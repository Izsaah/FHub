import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../Long/services/family_data_service.dart';
import '../models/family_jackpot_model.dart';
import '../models/user_bank_info.dart';
import 'jackpot_algorithm.dart';
import 'payment_service.dart';

/// Dịch vụ quản lý Hũ Niềm Vui Gia Đình (Realtime Jackpot & Shake)
/// Hỗ trợ cảm biến gia tốc ngoại vi (lắc điện thoại thật) + Realtime Firestore
class FamilyJackpotService extends ChangeNotifier {
  FamilyJackpotService._();
  static final FamilyJackpotService instance = FamilyJackpotService._();
  factory FamilyJackpotService() => instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<DocumentSnapshot>? _jackpotSub;
  StreamSubscription<AccelerometerEvent>? _sensorSub;
  Timer? _countdownTimer;

  DateTime? _lastShakeTime;
  String? _currentFamilyId;
  int _localMyShakeCount = 0;
  bool _isTransitioningPhase = false;
  String? _resolvedUserName;
  final Map<String, String> _cachedFamilyMembers = {};

  FamilyJackpotModel _jackpot = const FamilyJackpotModel(
    familyId: '',
    totalPoolAmount: 0,
    topContributorName: 'Chưa có',
    topContributorId: null,
    contributions: {},
    memberNames: {},
    shakeCounts: {},
    prizeResults: {},
    memberWallets: {},
    memberBanks: {},
  );

  FamilyJackpotModel get jackpot => _jackpot;
  int get myShakeCount => _localMyShakeCount;
  String get currentUserId => _auth.currentUser?.uid ?? FamilyDataService().currentUserId;
  String get currentUserName {
    if (_resolvedUserName != null && _resolvedUserName!.trim().isNotEmpty) {
      return _resolvedUserName!.trim();
    }
    final name = _auth.currentUser?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final email = _auth.currentUser?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return 'Bạn (Chủ gia đình)';
  }

  /// Lấy thông tin tài khoản ngân hàng cá nhân của User hiện tại để nhận thưởng
  UserBankInfo get myBankInfo {
    final uid = currentUserId;
    if (uid.isEmpty) {
      return const UserBankInfo(
        bankCode: 'MB',
        bankShortName: 'MBBank',
        accountNumber: '',
        accountHolder: '',
      );
    }
    return _jackpot.memberBanks[uid] ??
        const UserBankInfo(
          bankCode: 'MB',
          bankShortName: 'MBBank',
          accountNumber: '',
          accountHolder: '',
        );
  }

  /// Số dư ví tích lũy trong App của User hiện tại
  int get myWalletBalance {
    final uid = currentUserId;
    if (uid.isEmpty) return 0;
    return _jackpot.memberWallets[uid] ?? 0;
  }

  /// Điều kiện tiên quyết: Gia đình phải đang kích hoạt Gói Premium
  bool get canUseJackpot => PaymentService().isPremium;

  bool _isPaymentListenerBound = false;

  /// Khởi tạo và lắng nghe Hũ của gia đình
  void initForFamily(String? familyId) {
    if (!_isPaymentListenerBound) {
      _isPaymentListenerBound = true;
      PaymentService().addListener(_onPaymentStateChanged);
    }

    final rawFamilyId = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : PaymentService().currentFamilyId;
    final effectiveFamilyId = rawFamilyId.isNotEmpty ? rawFamilyId : 'f1';

    if (_currentFamilyId == effectiveFamilyId && _jackpotSub != null) {
      _loadFamilyMembers(effectiveFamilyId);
      return;
    }
    _currentFamilyId = effectiveFamilyId;

    _jackpotSub?.cancel();

    _loadFamilyMembers(effectiveFamilyId);

    final docRef = _firestore
        .collection('families')
        .doc(effectiveFamilyId)
        .collection('jackpot')
        .doc('current');

    _jackpotSub = docRef.snapshots().listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final prevStatus = _jackpot.status;

        var incoming = FamilyJackpotModel.fromMap(
          effectiveFamilyId,
          snapshot.data() as Map<String, dynamic>,
        );

        // Hợp nhất danh sách thành viên gia đình để không bao giờ bị mất thành viên khi đồng bộ
        final mergedMembers = <String, String>{
          ..._cachedFamilyMembers,
          ..._jackpot.memberNames,
          ...incoming.memberNames,
        };
        if (_auth.currentUser != null && _auth.currentUser!.uid != 'u1') {
          mergedMembers.remove('u1');
        }
        if (currentUserId.isNotEmpty) {
          mergedMembers[currentUserId] = currentUserName;
        }
        incoming = incoming.copyWith(memberNames: mergedMembers);

        // Nếu vừa bắt đầu hiệp lắc mới trên thiết bị khác -> reset bộ đếm local
        if (prevStatus != JackpotStatus.shaking && incoming.isShaking) {
          _localMyShakeCount = incoming.shakeCounts[currentUserId] ?? 0;
        } else if (incoming.isIdle) {
          _localMyShakeCount = 0;
        }

        // Trong lúc đang lắc, đảm bảo số lần lắc của bản thân không bao giờ bị giật lùi do độ trễ mạng
        if (incoming.isShaking && currentUserId.isNotEmpty) {
          final remoteMyShakes = incoming.shakeCounts[currentUserId] ?? 0;
          if (_localMyShakeCount > remoteMyShakes) {
            final syncedShakes = Map<String, int>.from(incoming.shakeCounts);
            syncedShakes[currentUserId] = _localMyShakeCount;
            incoming = incoming.copyWith(shakeCounts: syncedShakes);
          } else {
            _localMyShakeCount = remoteMyShakes;
          }
        }

        _jackpot = incoming;

        // Nếu nhận dữ liệu mà gia đình không còn Premium nhưng hũ có tiền -> lập tức tiêu hủy hũ
        if (!canUseJackpot && _jackpot.totalPoolAmount > 0 && !_jackpot.isFinished) {
          onPremiumLost();
        } else {
          _ensureCountdownTimerRunning();
          notifyListeners();
        }
      }
    }, onError: (e) {
      debugPrint('FamilyJackpotService stream error: $e');
    });

    _startSensorListener();
  }

  /// Tải danh sách thành viên thực tế của gia đình từ Firestore & dịch vụ gia đình hiện tại
  Future<void> _loadFamilyMembers(String familyId) async {
    try {
      final Map<String, String> loaded = {};

      // Lấy tên thật của user hiện tại từ hồ sơ
      try {
        final me = await FamilyDataService().getCurrentUser();
        if (me.name.trim().isNotEmpty && me.name != 'Người dùng') {
          _resolvedUserName = me.name.trim();
        }
      } catch (_) {}

      // 1. Đọc từ Firestore family_members (nếu có)
      final snap = await _firestore
          .collection('family_members')
          .where('familyId', isEqualTo: familyId)
          .where('status', isEqualTo: 'ACTIVE')
          .get();

      for (final doc in snap.docs) {
        final d = doc.data();
        final uid = d['userId'] as String? ?? '';
        final role = d['role'] as String? ?? 'Thành viên';
        final isOwner = d['isOwner'] as bool? ?? false;
        if (uid.isNotEmpty) {
          loaded[uid] = isOwner ? 'Chủ gia đình ($role)' : role;
        }
      }

      // 2. Đồng bộ thêm danh sách thành viên từ FamilyDataService (hiển thị ở tab Gia đình)
      try {
        final serviceMembers = await FamilyDataService().getFamilyMembers();
        for (final m in serviceMembers) {
          final uid = m.user.id;
          final name = m.user.name.trim();
          if (uid.isNotEmpty && name.isNotEmpty && !loaded.containsKey(uid)) {
            if (uid == 'u1' && _auth.currentUser != null && _auth.currentUser!.uid != 'u1') {
              continue;
            }
            loaded[uid] = name;
          }
        }
      } catch (_) {}

      // 3. Đảm bảo user hiện tại luôn có mặt với tên hiển thị chính xác
      final myUid = currentUserId;
      if (myUid.isNotEmpty) {
        loaded[myUid] = currentUserName;
      }

      if (loaded.isNotEmpty) {
        _cachedFamilyMembers
          ..clear()
          ..addAll(loaded);

        final merged = Map<String, String>.from(_jackpot.memberNames)..addAll(loaded);
        if (_auth.currentUser != null && _auth.currentUser!.uid != 'u1') {
          merged.remove('u1');
        }
        _jackpot = _jackpot.copyWith(
          familyId: familyId,
          memberNames: merged,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('FamilyJackpotService: load members error: $e');
    }
  }

  void _onPaymentStateChanged() {
    if (!canUseJackpot && _jackpot.totalPoolAmount > 0 && !_jackpot.isFinished) {
      onPremiumLost();
    } else {
      notifyListeners();
    }
  }

  /// QUY TẮC BẮT BUỘC: Nếu đang có hũ chưa lắc xong mà gia đình MẤT GÓI PREMIUM
  /// thì TOÀN BỘ TIỀN TRONG HŨ SẼ BỊ MẤT (HŨ BỊ TIÊU HỦY / RESET VỀ 0), nhưng giữ nguyên ví cá nhân đã trúng trước đó
  Future<void> onPremiumLost() async {
    final hadMoney = _jackpot.totalPoolAmount > 0;
    _localMyShakeCount = 0;
    _stopCountdownTimer();

    _jackpot = _jackpot.copyWith(
      totalPoolAmount: 0,
      status: JackpotStatus.idle,
      clearTopContributorId: true,
      topContributorName: 'Chưa có',
      contributions: const {},
      shakeCounts: const {},
      prizeResults: const {},
      clearTopShakerId: true,
      clearFirstPrizeWinnerId: true,
      clearShakeStartTime: true,
      clearSuspenseStartTime: true,
      lostDueToPremiumExpired: hadMoney,
    );

    notifyListeners();
    if (hadMoney) {
      debugPrint('FamilyJackpotService: MẤT GÓI PREMIUM -> HŨ VÀNG ĐÃ BỊ TIÊU HỦY, TOÀN BỘ TIỀN QUỸ BỊ MẤT!');
    }
    await _saveToFirestore();
  }

  /// Lắng nghe cảm biến chuyển động lắc của điện thoại (Accelerometer)
  void _startSensorListener() {
    _sensorSub?.cancel();
    try {
      _sensorSub = accelerometerEventStream().listen((event) {
        if (!_jackpot.isShaking) return;
        // Tính độ lớn gia tốc tổng hợp (Magnitude) và độ lệch so với trọng lực Trái Đất (9.81 m/s2)
        final g = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        final deltaG = (g - 9.81).abs();
        // Ngưỡng nhạy vừa tầm lắc cổ tay trên điện thoại thật: deltaG > 3.2 m/s2 hoặc g > 13.0 m/s2
        if (deltaG > 3.2 || g > 13.0) {
          final now = DateTime.now();
          if (_lastShakeTime == null || now.difference(_lastShakeTime!).inMilliseconds > 220) {
            _lastShakeTime = now;
            recordShake();
          }
        }
      }, onError: (e) {
        debugPrint('Accelerometer not available on this platform: $e');
      });
    } catch (e) {
      debugPrint('Sensor init skipped: $e');
    }
  }

  /// Ghi nhận 1 lần lắc (từ cảm biến hoặc từ nút bấm Lắc Ngay trên màn hình)
  void recordShake() {
    if (!canUseJackpot || !_jackpot.isShaking) return;
    final uid = currentUserId;
    if (uid.isEmpty) return;

    _localMyShakeCount++;

    final updatedShakes = Map<String, int>.from(_jackpot.shakeCounts);
    updatedShakes[uid] = _localMyShakeCount;

    final updatedNames = Map<String, String>.from(_jackpot.memberNames);
    updatedNames[uid] = currentUserName;

    _jackpot = _jackpot.copyWith(
      shakeCounts: updatedShakes,
      memberNames: updatedNames,
    );

    notifyListeners();
    _saveMyShakeCountOnly(uid, _localMyShakeCount);
  }

  /// Chỉ cập nhật đúng trường số lần lắc của user hiện tại lên Firestore để tránh ghi đè dữ liệu của thành viên khác
  Future<void> _saveMyShakeCountOnly(String uid, int count) async {
    if (_currentFamilyId == null || _currentFamilyId!.isEmpty) return;
    try {
      await _firestore
          .collection('families')
          .doc(_currentFamilyId)
          .collection('jackpot')
          .doc('current')
          .set({
        'shakeCounts': {uid: count},
        'memberNames': {uid: currentUserName},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Save shake count error: $e');
    }
  }

  /// Nạp thêm tiền vào Hũ Niềm Vui Gia Đình
  Future<void> contributeMoney({
    required int amount,
    String? memberName,
  }) async {
    if (!canUseJackpot) {
      throw Exception('Chỉ gia đình sở hữu Gói Premium mới được tham gia Hũ Niềm Vui!');
    }
    if (amount <= 0) return;

    final name = memberName ?? currentUserName;
    final uid = currentUserId;

    final updatedContribs = Map<String, int>.from(_jackpot.contributions);
    final currentVal = updatedContribs[uid] ?? 0;
    updatedContribs[uid] = currentVal + amount;

    final updatedNames = Map<String, String>.from(_jackpot.memberNames);
    updatedNames[uid] = name;

    // Tìm người nạp nhiều nhất (Realtime Đại Gia Đình)
    String? topUid;
    int maxAmount = 0;
    updatedContribs.forEach((k, v) {
      if (v > maxAmount) {
        maxAmount = v;
        topUid = k;
      }
    });

    final newTotal = _jackpot.totalPoolAmount + amount;

    _jackpot = _jackpot.copyWith(
      totalPoolAmount: newTotal,
      status: JackpotStatus.idle,
      topContributorId: topUid,
      topContributorName: updatedNames[topUid] ?? name,
      contributions: updatedContribs,
      memberNames: updatedNames,
      clearShakeStartTime: true,
      clearSuspenseStartTime: true,
      lostDueToPremiumExpired: false,
    );

    notifyListeners();
    await _saveToFirestore();
  }

  /// Bắt đầu 30s Nổ Hũ (Chỉ người nạp nhiều nhất mới được gọi)
  Future<void> startShakeBattle() async {
    if (!canUseJackpot) {
      throw Exception('Gói Premium không còn hiệu lực. Hũ đã bị tiêu hủy!');
    }
    if (_jackpot.totalPoolAmount <= 0) {
      throw Exception('Hũ hiện đang trống (0 đ). Hãy nạp tiền vào quỹ hũ trước khi bấm Nổ Hũ!');
    }

    if (_cachedFamilyMembers.isEmpty) {
      await _loadFamilyMembers(_currentFamilyId ?? 'f1');
    }

    _localMyShakeCount = 0;
    _isTransitioningPhase = false;
    final startTime = DateTime.now();

    final updatedNames = <String, String>{
      ..._cachedFamilyMembers,
      ..._jackpot.memberNames,
    };
    if (_auth.currentUser != null && _auth.currentUser!.uid != 'u1') {
      updatedNames.remove('u1');
    }
    if (currentUserId.isNotEmpty) {
      updatedNames[currentUserId] = currentUserName;
    }

    // Reset lại lượt lắc của tất cả thành viên về 0
    final resetShakes = <String, int>{
      for (final uid in updatedNames.keys) uid: 0,
    };

    _jackpot = _jackpot.copyWith(
      status: JackpotStatus.shaking,
      memberNames: updatedNames,
      shakeCounts: resetShakes,
      prizeResults: const {},
      clearTopShakerId: true,
      clearFirstPrizeWinnerId: true,
      shakeStartTime: startTime,
      clearSuspenseStartTime: true,
      lostDueToPremiumExpired: false,
    );

    _ensureCountdownTimerRunning();
    notifyListeners();
    await _saveToFirestore();
  }

  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  /// Đảm bảo bộ đếm giờ chạy mượt mà mà KHÔNG bị reset khi có snapshot Firestore mới gửi về
  void _ensureCountdownTimerRunning() {
    if (!_jackpot.isShaking && !_jackpot.isSuspense) {
      _stopCountdownTimer();
      return;
    }

    // Kiểm tra ngay tức thì nếu đã hết giờ
    _checkPhaseTransitions();

    if (_countdownTimer != null && _countdownTimer!.isActive) {
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_jackpot.isShaking && !_jackpot.isSuspense) {
        _stopCountdownTimer();
        return;
      }
      _checkPhaseTransitions();
      notifyListeners();
    });
  }

  void _checkPhaseTransitions() {
    if (_isTransitioningPhase) return;

    if (_jackpot.isShaking && _jackpot.remainingShakeSeconds <= 0) {
      _enterSuspensePhase();
    } else if (_jackpot.isSuspense && _jackpot.remainingSuspenseSeconds <= 0) {
      _finishShakeBattle();
    }
  }

  /// Vừa kết thúc 30s lắc: LẬP TỨC TÌM VÀ CÔNG BỐ NGƯỜI LẮC NHIỀU NHẤT!
  /// Đồng thời chuyển sang giai đoạn Hồi Hộp (Suspense) 10 giây trước khi Thần May Mắn chia thưởng.
  Future<void> _enterSuspensePhase() async {
    if (_isTransitioningPhase || !_jackpot.isShaking) return;
    _isTransitioningPhase = true;

    try {
      final finalShakes = Map<String, int>.from(_jackpot.shakeCounts);
      if (currentUserId.isNotEmpty && _localMyShakeCount > (finalShakes[currentUserId] ?? 0)) {
        finalShakes[currentUserId] = _localMyShakeCount;
      }

      // Tìm người lắc nhiều nhất ngay lập tức
      String? topShaker;
      int maxShakes = -1;
      finalShakes.forEach((uid, cnt) {
        if (cnt > maxShakes) {
          maxShakes = cnt;
          topShaker = uid;
        }
      });

      final suspenseTime = DateTime.now();

      _jackpot = _jackpot.copyWith(
        status: JackpotStatus.suspense,
        shakeCounts: finalShakes,
        prizeResults: const {},
        topShakerId: topShaker,
        clearFirstPrizeWinnerId: true,
        suspenseStartTime: suspenseTime,
      );

      notifyListeners();
      await _saveToFirestore();
    } finally {
      _isTransitioningPhase = false;
      _ensureCountdownTimerRunning();
    }
  }

  /// Sau 10 giây Hồi Hộp: Thần may mắn chính thức trao thưởng cho cả nhà bằng JackpotAlgorithm!
  Future<void> _finishShakeBattle() async {
    if (_isTransitioningPhase || !_jackpot.isSuspense) return;
    _isTransitioningPhase = true;
    _stopCountdownTimer();

    try {
      final participantIds = _jackpot.memberNames.keys.toList();
      if (currentUserId.isNotEmpty && !participantIds.contains(currentUserId)) {
        participantIds.add(currentUserId);
      }

      final finalShakes = Map<String, int>.from(_jackpot.shakeCounts);
      if (currentUserId.isNotEmpty && _localMyShakeCount > (finalShakes[currentUserId] ?? 0)) {
        finalShakes[currentUserId] = _localMyShakeCount;
      }

      final result = JackpotAlgorithm.calculate(
        totalAmount: _jackpot.totalPoolAmount,
        shakeCounts: finalShakes,
        participantIds: participantIds,
      );

      // Tiền trúng thưởng lập tức cộng dồn vào ví số dư trong App của từng thành viên
      final updatedWallets = Map<String, int>.from(_jackpot.memberWallets);
      result.prizes.forEach((uid, wonAmount) {
        updatedWallets[uid] = (updatedWallets[uid] ?? 0) + wonAmount;
      });

      _jackpot = _jackpot.copyWith(
        totalPoolAmount: 0, // Tiền đã nổ hũ chia hết 100% vào ví cá nhân các thành viên
        status: JackpotStatus.finished,
        shakeCounts: finalShakes,
        prizeResults: result.prizes,
        memberWallets: updatedWallets,
        topShakerId: result.topShakerId,
        firstPrizeWinnerId: result.firstPrizeWinnerId,
      );

      notifyListeners();
      await _saveToFirestore();
    } finally {
      _isTransitioningPhase = false;
    }
  }

  /// Cập nhật thông tin tài khoản ngân hàng của thành viên hiện tại
  Future<void> saveMyBankInfo(UserBankInfo bankInfo) async {
    final updatedBanks = Map<String, UserBankInfo>.from(_jackpot.memberBanks);
    updatedBanks[currentUserId] = bankInfo;

    _jackpot = _jackpot.copyWith(memberBanks: updatedBanks);

    notifyListeners();
    await _saveToFirestore();
  }

  /// Rút tiền từ Ví thành viên về Số tài khoản ngân hàng cá nhân
  Future<bool> withdrawToBank(int amount) async {
    final currentBal = myWalletBalance;
    if (amount <= 0 || amount > currentBal) return false;
    if (!myBankInfo.isValid) return false;

    final updatedWallets = Map<String, int>.from(_jackpot.memberWallets);
    updatedWallets[currentUserId] = currentBal - amount;

    _jackpot = _jackpot.copyWith(memberWallets: updatedWallets);

    notifyListeners();
    await _saveToFirestore();
    return true;
  }

  /// Đặt lại Hũ mới sau khi nổ hũ xong
  Future<void> resetJackpot() async {
    _localMyShakeCount = 0;
    _isTransitioningPhase = false;
    _stopCountdownTimer();

    _jackpot = _jackpot.copyWith(
      totalPoolAmount: 0,
      status: JackpotStatus.idle,
      clearTopContributorId: true,
      topContributorName: 'Chưa có',
      contributions: const {},
      shakeCounts: const {},
      prizeResults: const {},
      clearTopShakerId: true,
      clearFirstPrizeWinnerId: true,
      clearShakeStartTime: true,
      clearSuspenseStartTime: true,
      lostDueToPremiumExpired: false,
    );

    notifyListeners();
    await _saveToFirestore();
  }

  /// Ghi đè toàn bộ trạng thái Hũ hiện tại lên Firestore (không dùng merge: true để xóa sạch các Map rỗng khi reset)
  Future<void> _saveToFirestore() async {
    if (_currentFamilyId == null || _currentFamilyId!.isEmpty) return;
    try {
      await _firestore
          .collection('families')
          .doc(_currentFamilyId)
          .collection('jackpot')
          .doc('current')
          .set(_jackpot.toMap());
    } catch (e) {
      debugPrint('Save jackpot error: $e');
    }
  }

  @override
  void dispose() {
    _jackpotSub?.cancel();
    _sensorSub?.cancel();
    _stopCountdownTimer();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../Long/services/family_data_service.dart';
import '../../Long/models/family_member_model.dart';
import '../../Vinh/services/star_economy_service.dart';
import '../models/family_jackpot_model.dart';
import '../models/user_bank_info.dart';
import '../models/wallet_transaction_model.dart';
import 'jackpot_algorithm.dart';
import 'notification_service.dart';
import 'payment_service.dart';

/// Trạng thái vòng đời giải thưởng tiền mặt lì xì: WAITING_TRANSFER -> PAID -> RECEIVED
enum CashPrizeStatus {
  waitingTransfer,
  paid,
  received,
  cancelled;

  String get code {
    switch (this) {
      case CashPrizeStatus.waitingTransfer:
        return 'WAITING_TRANSFER';
      case CashPrizeStatus.paid:
        return 'PAID';
      case CashPrizeStatus.received:
        return 'RECEIVED';
      case CashPrizeStatus.cancelled:
        return 'CANCELLED';
    }
  }
}

/// Mô hình giải thưởng tiền mặt thật được trao từ Trưởng bối tới con cháu
class CashPrizeModel {
  final String id;
  final String childId;
  final String childName;
  final int amount;
  CashPrizeStatus status;
  String? paymentMethod; // 'CASH' or 'VIETQR'
  String? paidBy;
  String? paidByName;
  String? bankRef;
  DateTime? paidAt;
  DateTime? receivedAt;
  String? familyId;

  CashPrizeModel({
    required this.id,
    required this.childId,
    required this.childName,
    required this.amount,
    this.status = CashPrizeStatus.waitingTransfer,
    this.paymentMethod,
    this.paidBy,
    this.paidByName,
    this.bankRef,
    this.paidAt,
    this.receivedAt,
    this.familyId,
  });

  String get statusString => status.code;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'childId': childId,
      'childName': childName,
      'amount': amount,
      'status': status.name,
      'statusCode': status.code,
      'paymentMethod': paymentMethod,
      'paidBy': paidBy,
      'paidByName': paidByName,
      'bankRef': bankRef,
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      'receivedAt': receivedAt != null ? Timestamp.fromDate(receivedAt!) : null,
      'familyId': familyId,
    };
  }

  factory CashPrizeModel.fromMap(String id, Map<String, dynamic> data) {
    CashPrizeStatus parseStatus(String? val) {
      final upper = val?.toUpperCase();
      switch (upper) {
        case 'PAID':
          return CashPrizeStatus.paid;
        case 'RECEIVED':
          return CashPrizeStatus.received;
        case 'CANCELLED':
          return CashPrizeStatus.cancelled;
        case 'WAITING_TRANSFER':
        case 'WAITINGTRANSFER':
        default:
          return CashPrizeStatus.waitingTransfer;
      }
    }

    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is DateTime) return val;
      return null;
    }

    return CashPrizeModel(
      id: id,
      childId: data['childId'] as String? ?? '',
      childName: data['childName'] as String? ?? '',
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      status: parseStatus(data['status'] as String? ?? data['statusCode'] as String?),
      paymentMethod: data['paymentMethod'] as String?,
      paidBy: data['paidBy'] as String?,
      paidByName: data['paidByName'] as String?,
      bankRef: data['bankRef'] as String?,
      paidAt: parseDate(data['paidAt']),
      receivedAt: parseDate(data['receivedAt']),
      familyId: data['familyId'] as String?,
    );
  }

  CashPrizeModel copyWith({
    String? id,
    String? childId,
    String? childName,
    int? amount,
    CashPrizeStatus? status,
    String? paymentMethod,
    String? paidBy,
    String? paidByName,
    String? bankRef,
    DateTime? paidAt,
    DateTime? receivedAt,
    String? familyId,
  }) {
    return CashPrizeModel(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      childName: childName ?? this.childName,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidBy: paidBy ?? this.paidBy,
      paidByName: paidByName ?? this.paidByName,
      bankRef: bankRef ?? this.bankRef,
      paidAt: paidAt ?? this.paidAt,
      receivedAt: receivedAt ?? this.receivedAt,
      familyId: familyId ?? this.familyId,
    );
  }
}

/// Cơ chế Lì xì Thực tế 2-Way Handshake: WAITING_TRANSFER -> PAID -> RECEIVED
class CashGiftHandshakeEngine {
  final Map<String, CashPrizeModel> prizes = {};

  CashPrizeModel createPrize({
    required String prizeId,
    required String childId,
    required String childName,
    required int amount,
    String? familyId,
  }) {
    final prize = CashPrizeModel(
      id: prizeId,
      childId: childId,
      childName: childName,
      amount: amount,
      familyId: familyId,
    );
    prizes[prizeId] = prize;
    return prize;
  }

  void recordGuardianPayout({
    required String prizeId,
    required String guardianId,
    required String guardianName,
    String? bankRef,
    String? paymentMethod,
    bool isGuardian = true,
  }) {
    if (!isGuardian) {
      throw StateError('Chỉ Trưởng bối (Guardian) mới có quyền xác nhận trao tiền mặt!');
    }
    final prize = prizes[prizeId];
    if (prize == null) throw Exception('Giải thưởng không tồn tại');
    if (prize.status == CashPrizeStatus.cancelled) {
      throw StateError('Giải thưởng đã bị hủy bỏ');
    }

    prize.status = CashPrizeStatus.paid;
    prize.paymentMethod = paymentMethod ?? (bankRef != null ? 'VIETQR' : 'CASH');
    prize.paidBy = guardianId;
    prize.paidByName = guardianName;
    if (bankRef != null) prize.bankRef = bankRef;
    prize.paidAt = DateTime.now();
  }

  void guardianConfirmCashPayment({
    required String prizeId,
    required String guardianId,
    required String guardianName,
    required bool isGuardian,
  }) {
    recordGuardianPayout(
      prizeId: prizeId,
      guardianId: guardianId,
      guardianName: guardianName,
      paymentMethod: 'CASH',
      isGuardian: isGuardian,
    );
  }

  void guardianConfirmVietQrTransfer({
    required String prizeId,
    required String guardianId,
    required String guardianName,
    required String bankRef,
    required bool isGuardian,
  }) {
    recordGuardianPayout(
      prizeId: prizeId,
      guardianId: guardianId,
      guardianName: guardianName,
      bankRef: bankRef,
      paymentMethod: 'VIETQR',
      isGuardian: isGuardian,
    );
  }

  void confirmChildReceipt({
    required String prizeId,
    required String childId,
  }) {
    final prize = prizes[prizeId];
    if (prize == null) throw Exception('Giải thưởng không tồn tại');

    if (prize.childId != childId) {
      throw StateError('Chỉ người nhận giải thưởng mới có quyền bấm xác nhận nhận tiền!');
    }

    if (prize.status == CashPrizeStatus.waitingTransfer) {
      throw StateError('Không thể xác nhận nhận tiền khi Trưởng bối chưa thực hiện thanh toán!');
    }

    if (prize.status == CashPrizeStatus.received) {
      return;
    }

    prize.status = CashPrizeStatus.received;
    prize.receivedAt = DateTime.now();
  }

  void childConfirmReceipt({
    required String prizeId,
    required String childId,
  }) {
    confirmChildReceipt(prizeId: prizeId, childId: childId);
  }

  void reset() {
    prizes.clear();
  }
}

/// Accelerometer Sensor Debounce Engine with 3.0s cooldown & mutex lock
class AccelerometerShakeEngine {
  static const double minG = 15.0;
  static const double minDeltaG = 4.5;
  static const Duration cooldown = Duration(milliseconds: 3000);

  int shakeCount = 0;
  DateTime? lastShakeTime;
  bool _isProcessingShake = false;
  bool isShakingPhase = true;

  bool get isProcessingShake => _isProcessingShake;

  void reset() {
    shakeCount = 0;
    lastShakeTime = null;
    _isProcessingShake = false;
    isShakingPhase = true;
  }

  Future<bool> handleSensorEvent({
    required double x,
    required double y,
    required double z,
    DateTime? eventTime,
  }) async {
    if (!isShakingPhase) return false;

    final g = sqrt(x * x + y * y + z * z);
    final deltaG = (g - 9.81).abs();

    // Ngưỡng phát hiện gia tốc: g > 15.0 và deltaG > 4.5
    if (g <= minG || deltaG <= minDeltaG) {
      return false;
    }

    final now = eventTime ?? DateTime.now();

    // Kiểm tra cooldown 3.0 giây
    if (lastShakeTime != null && now.difference(lastShakeTime!) < cooldown) {
      return false;
    }

    // Mutex lock
    if (_isProcessingShake) {
      return false;
    }

    _isProcessingShake = true;
    try {
      lastShakeTime = now;
      shakeCount++;
      await Future.delayed(const Duration(milliseconds: 10));
      return true;
    } finally {
      _isProcessingShake = false;
    }
  }
}

/// Dịch vụ quản lý Hũ Niềm Vui Gia Đình (Realtime Jackpot & Shake)
/// Hỗ trợ cảm biến gia tốc ngoại vi (lắc điện thoại thật) + Realtime Firestore
class FamilyJackpotService extends ChangeNotifier {
  FamilyJackpotService._();
  static final FamilyJackpotService instance = FamilyJackpotService._();
  factory FamilyJackpotService() => instance;

  bool get _hasFirebase {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore? get _firestore => _hasFirebase ? FirebaseFirestore.instance : null;
  FirebaseAuth? get _auth => _hasFirebase ? FirebaseAuth.instance : null;

  StreamSubscription<DocumentSnapshot>? _jackpotSub;
  StreamSubscription<AccelerometerEvent>? _sensorSub;
  Timer? _countdownTimer;

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

  final AccelerometerShakeEngine shakeEngine = AccelerometerShakeEngine();
  final CashGiftHandshakeEngine handshakeEngine = CashGiftHandshakeEngine();

  bool get isProcessingShake => shakeEngine.isProcessingShake;
  int get shakeCount => shakeEngine.shakeCount;
  DateTime? get lastShakeTime => shakeEngine.lastShakeTime;
  bool get isShakingPhase => shakeEngine.isShakingPhase;
  set isShakingPhase(bool val) => shakeEngine.isShakingPhase = val;
  AccelerometerShakeEngine get accelerometerEngine => shakeEngine;
  CashGiftHandshakeEngine get cashGiftEngine => handshakeEngine;
  Map<String, CashPrizeModel> get cashPrizes => handshakeEngine.prizes;

  FamilyJackpotModel get jackpot => _jackpot;
  int get myShakeCount => _localMyShakeCount;
  String get currentUserId => _auth?.currentUser?.uid ?? FamilyDataService().currentUserId;
  String get currentUserName {
    if (_resolvedUserName != null && _resolvedUserName!.trim().isNotEmpty) {
      return _resolvedUserName!.trim();
    }
    final name = _auth?.currentUser?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final email = _auth?.currentUser?.email;
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
  bool? overrideCanUseJackpotForTest;

  /// Điều kiện tiên quyết: Gia đình phải đang kích hoạt Gói Premium
  bool get canUseJackpot => overrideCanUseJackpotForTest ?? PaymentService().isPremium;

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

    if (_firestore == null) return;
    final docRef = _firestore!
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

        // Hợp nhất danh sách thành viên: ưu tiên tên đã load từ profile thật
        final mergedMembers = <String, String>{
          ...incoming.memberNames,
          ..._jackpot.memberNames,
          ..._cachedFamilyMembers,
        };
        if (_auth?.currentUser != null && _auth?.currentUser?.uid != 'u1') {
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

        // Nếu nhận dữ liệu mà gia đình không còn Premium nhưng đang trong phiên lắc -> hủy phiên lắc
        if (!canUseJackpot && (_jackpot.isShaking || _jackpot.isSuspense)) {
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

      // 1. Ưu tiên lấy trực tiếp danh sách thành viên từ FamilyDataService (đã đọc từ collection users)
      try {
        final serviceMembers = await FamilyDataService().getFamilyMembers(familyId: familyId);
        for (final m in serviceMembers) {
          final uid = m.user.id;
          final name = m.user.name.trim();
          if (uid.isNotEmpty && name.isNotEmpty && name != 'Thành viên' && name != 'Người dùng') {
            if (uid == 'u1' && _auth?.currentUser != null && _auth?.currentUser?.uid != 'u1') {
              continue;
            }
            loaded[uid] = name;
          }
        }
      } catch (_) {}

      // 2. Đọc thêm từ collection family_members để tránh bỏ sót thành viên
      try {
        if (_firestore == null) return;
        final snap = await _firestore!
            .collection('family_members')
            .where('familyId', isEqualTo: familyId)
            .where('status', isEqualTo: 'ACTIVE')
            .get();

        for (final doc in snap.docs) {
          final d = doc.data();
          final uid = d['userId'] as String? ?? '';
          if (uid.isEmpty) continue;
          if (uid == 'u1' && _auth?.currentUser != null && _auth?.currentUser?.uid != 'u1') continue;

          // Nếu đã có tên thật từ FamilyDataService -> giữ nguyên
          if (loaded.containsKey(uid) && loaded[uid]!.isNotEmpty) continue;

          // Thử đọc tên từ users collection
          try {
            final userDoc = await _firestore!.collection('users').doc(uid).get();
            final rawName = userDoc.data()?['name']?.toString();
            final userName = rawName?.trim();
            if (userName != null && userName.isNotEmpty && userName != 'Người dùng') {
              loaded[uid] = userName;
              continue;
            }
          } catch (_) {}

          // Fallback tên vai trò tiếng Việt rõ ràng, tránh hiển thị thô "PARENT"
          final rawRole = (d['role'] as String? ?? 'PARENT').toUpperCase();
          final isOwner = d['isOwner'] as bool? ?? false;
          String fallbackRole;
          if (isOwner) {
            fallbackRole = 'Chủ gia đình';
          } else if (rawRole.contains('PARENT') || rawRole.contains('BỐ') || rawRole.contains('MẸ')) {
            fallbackRole = 'Bố / Mẹ';
          } else if (rawRole.contains('CHILD') || rawRole.contains('CON')) {
            fallbackRole = 'Con';
          } else if (rawRole.contains('GRAND') || rawRole.contains('ÔNG') || rawRole.contains('BÀ')) {
            fallbackRole = 'Ông / Bà';
          } else {
            fallbackRole = 'Thành viên';
          }
          loaded[uid] = fallbackRole;
        }
      } catch (_) {}

      // 3. Đảm bảo user hiện tại luôn có mặt với tên hiển thị chính xác
      final myUid = currentUserId;
      if (myUid.isNotEmpty) {
        loaded[myUid] = currentUserName;
      }

      // 4. Đánh số phân biệt nếu có thành viên bị trùng tên fallback (ví dụ 2 bố mẹ -> "Bố / Mẹ (1)", "Bố / Mẹ (2)")
      final nameCounts = <String, int>{};
      for (final n in loaded.values) {
        nameCounts[n] = (nameCounts[n] ?? 0) + 1;
      }
      final seenCount = <String, int>{};
      for (final uid in loaded.keys.toList()) {
        final rawName = loaded[uid]!;
        if ((nameCounts[rawName] ?? 0) > 1 && uid != myUid) {
          final idx = (seenCount[rawName] ?? 0) + 1;
          seenCount[rawName] = idx;
          loaded[uid] = '$rawName ($idx)';
        }
      }

      if (loaded.isNotEmpty) {
        _cachedFamilyMembers
          ..clear()
          ..addAll(loaded);

        final merged = Map<String, String>.from(_jackpot.memberNames)..addAll(loaded);
        if (_auth?.currentUser != null && _auth?.currentUser?.uid != 'u1') {
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
    if (!canUseJackpot && (_jackpot.isShaking || _jackpot.isSuspense)) {
      onPremiumLost();
    } else {
      notifyListeners();
    }
  }

  /// QUY TẮC CỐT LÕI: Khi gia đình MẤT GÓI PREMIUM:
  /// - Hũ VẪN GIỮ NGUYÊN SỐ SAO ĐÃ TÍCH TRỮ (Sao trong hũ không tự mất đi, chỉ tiêu khi lắc hũ)
  /// - Nếu đang trong phiên lắc hoặc hồi hộp, hủy phiên lắc đó (trở về idle)
  /// - Không thể bắt đầu Nổ Hũ mới cho đến khi gia hạn Premium.
  Future<void> onPremiumLost() async {
    _localMyShakeCount = 0;
    _stopCountdownTimer();

    if (_jackpot.isShaking || _jackpot.isSuspense) {
      _jackpot = _jackpot.copyWith(
        status: JackpotStatus.idle,
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
    } else {
      notifyListeners();
    }
  }

  /// Lắng nghe cảm biến chuyển động lắc của điện thoại (Accelerometer)
  void _startSensorListener() {
    _sensorSub?.cancel();
    try {
      _sensorSub = accelerometerEventStream().listen((event) async {
        if (!_jackpot.isShaking) return;
        shakeEngine.isShakingPhase = _jackpot.isShaking;
        final accepted = await shakeEngine.handleSensorEvent(
          x: event.x,
          y: event.y,
          z: event.z,
        );
        if (accepted) {
          recordShake();
        }
      }, onError: (e) {
        debugPrint('Accelerometer not available on this platform: $e');
      });
    } catch (e) {
      debugPrint('Sensor init skipped: $e');
    }
  }

  /// Xử lý sự kiện cảm biến gia tốc với debounce 3.0s, physics thresholds (g > 15.0 & deltaG > 4.5) và mutex lock
  Future<bool> handleSensorEvent({
    required double x,
    required double y,
    required double z,
    DateTime? eventTime,
  }) async {
    final accepted = await shakeEngine.handleSensorEvent(
      x: x,
      y: y,
      z: z,
      eventTime: eventTime,
    );
    if (accepted && canUseJackpot && _jackpot.isShaking) {
      recordShake();
    }
    return accepted;
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

  /// Chỉ cập nhật đúng trường số lần lắc của user hiện tại lên Firestore bằng Dot-Notation để tránh ghi đè dữ liệu của thành viên khác
  Future<void> _saveMyShakeCountOnly(String uid, int count) async {
    if (_currentFamilyId == null || _currentFamilyId!.isEmpty || _firestore == null) return;
    try {
      final docRef = _firestore!
          .collection('families')
          .doc(_currentFamilyId)
          .collection('jackpot')
          .doc('current');
      await docRef.update({
        'shakeCounts.$uid': count,
        'memberNames.$uid': currentUserName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Save shake count error: $e');
    }
  }

  /// Ghi lại giao dịch vào Sổ cái Biến động Ví của Gia đình (Family-scoped Ledger)
  Future<void> _recordTransaction({
    required WalletTransactionType type,
    required int amount,
    required String title,
    String? description,
    String? bankShortName,
    String? accountNumber,
    String? targetUserId,
    String? targetUserName,
  }) async {
    final fId = _currentFamilyId;
    if (fId == null || fId.isEmpty || amount <= 0 || _firestore == null) return;
    try {
      final txDoc = _firestore!
          .collection('families')
          .doc(fId)
          .collection('wallet_transactions')
          .doc();

      final tx = WalletTransactionModel(
        id: txDoc.id,
        familyId: fId,
        userId: targetUserId ?? currentUserId,
        userName: targetUserName ?? currentUserName,
        type: type,
        amount: amount,
        title: title,
        description: description,
        bankShortName: bankShortName,
        accountNumber: accountNumber,
        createdAt: DateTime.now(),
      );

      await txDoc.set(tx.toMap());
    } catch (e) {
      debugPrint('FamilyJackpotService._recordTransaction error: $e');
    }
  }

  /// Lắng nghe lịch sử biến động số dư ví của gia đình hiện tại theo thời gian thực (giới hạn 15 ngày)
  Stream<List<WalletTransactionModel>> watchWalletTransactions([String? familyId]) {
    final targetFamilyId = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : (_currentFamilyId ?? 'f1');
    final cutoffDate = DateTime.now().subtract(const Duration(days: 15));
    if (_firestore == null) return Stream.value(const []);
    return _firestore!
        .collection('families')
        .doc(targetFamilyId)
        .collection('wallet_transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          final txs = <WalletTransactionModel>[];
          final oldDocIds = <String>[];
          for (final doc in snap.docs) {
            final tx = WalletTransactionModel.fromMap(doc.id, doc.data());
            if (tx.createdAt.isAfter(cutoffDate)) {
              txs.add(tx);
            } else {
              oldDocIds.add(doc.id);
            }
          }
          // Dọn dẹp tự động các bản ghi cũ hơn 15 ngày để bảo vệ dung lượng database
          if (oldDocIds.isNotEmpty) {
            for (final oldId in oldDocIds) {
              _firestore!
                  .collection('families')
                  .doc(targetFamilyId)
                  .collection('wallet_transactions')
                  .doc(oldId)
                  .delete()
                  .catchError((_) {});
            }
          }
          return txs;
        });
  }

  /// Nạp thêm tiền vào Hũ Niềm Vui Gia Đình (Bảo toàn 100% ví thưởng tích lũy chưa rút của các thành viên)
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

    if (_firestore != null && _currentFamilyId != null && _currentFamilyId!.isNotEmpty) {
      final docRef = _firestore!
          .collection('families')
          .doc(_currentFamilyId)
          .collection('jackpot')
          .doc('current');

      await _firestore!.runTransaction((transaction) async {
        final snap = await transaction.get(docRef);
        int currentPool = 0;
        Map<String, int> contribs = {};
        Map<String, String> names = {};

        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          currentPool = (data['totalPoolAmount'] as num?)?.toInt() ?? 0;
          final rawContribs = (data['contributions'] as Map<String, dynamic>?) ?? {};
          contribs = rawContribs.map((k, v) => MapEntry(k, (v as num).toInt()));
          final rawNames = (data['memberNames'] as Map<String, dynamic>?) ?? {};
          names = rawNames.map((k, v) => MapEntry(k, v.toString()));
        }

        contribs[uid] = (contribs[uid] ?? 0) + amount;
        names[uid] = name;

        String? topUid;
        int maxAmount = 0;
        contribs.forEach((k, v) {
          if (v > maxAmount) {
            maxAmount = v;
            topUid = k;
          }
        });

        final newTotal = currentPool + amount;

        transaction.set(docRef, {
          'totalPoolAmount': newTotal,
          'status': JackpotStatus.idle.name,
          'topContributorId': topUid,
          'topContributorName': names[topUid] ?? name,
          'contributions': contribs,
          'memberNames': names,
          'shakeStartTime': null,
          'suspenseStartTime': null,
          'lostDueToPremiumExpired': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } else {
      final updatedContribs = Map<String, int>.from(_jackpot.contributions);
      final currentVal = updatedContribs[uid] ?? 0;
      updatedContribs[uid] = currentVal + amount;

      final updatedNames = Map<String, String>.from(_jackpot.memberNames);
      updatedNames[uid] = name;

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
    }

    // Ghi vào Sổ cái biến động ví gia đình
    await _recordTransaction(
      type: WalletTransactionType.contribute,
      amount: amount,
      title: 'Nạp quỹ Hũ Niềm Vui',
      description: 'Đóng góp bởi $name',
      targetUserId: uid,
      targetUserName: name,
    );

    final formattedDeposit = amount.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.");
    unawaited(NotificationService.instance.addNotification(
      familyId: _currentFamilyId ?? 'f1',
      title: 'Quỹ Hũ Niềm Vui được nạp thêm',
      titleEn: 'Family Pot Received a Deposit',
      body: '$name vừa đóng góp $formattedDeposit ⭐ vào Hũ Niềm Vui!',
      bodyEn: '$name just deposited $formattedDeposit ⭐ into the Family Pot!',
      type: 'jackpot_deposit',
    ));
  }

  // Theo dõi nhiệm vụ hằng ngày của Hũ: Cả nhà điểm danh (+10 ⭐ vào Hũ)
  final Map<String, Set<String>> _dailyCheckIns = {}; // dateKey (YYYY-MM-DD) -> Set<userId>
  final Set<String> _awardedCheckInDates = {}; // dateKey đã được cộng 10 sao

  bool hasUserCheckedInToday(String userId) {
    final todayKey = DateTime.now().toIso8601String().substring(0, 10);
    return _dailyCheckIns[todayKey]?.contains(userId) ?? false;
  }

  int getTodayCheckInCount() {
    final todayKey = DateTime.now().toIso8601String().substring(0, 10);
    return _dailyCheckIns[todayKey]?.length ?? 0;
  }

  /// Đồng bộ trạng thái điểm danh từ trang Home (FamilyDataService)
  Future<void> syncCheckInsFromMembers(List<FamilyMemberModel> members) async {
    if (members.isEmpty) return;
    final todayKey = DateTime.now().toIso8601String().substring(0, 10);
    final userSet = _dailyCheckIns.putIfAbsent(todayKey, () => <String>{});

    for (final m in members) {
      if (m.isCheckedInToday) {
        userSet.add(m.user.id);
      }
    }

    final threshold = members.length;
    if (userSet.length >= threshold && !_awardedCheckInDates.contains(todayKey)) {
      _awardedCheckInDates.add(todayKey);
      if (canUseJackpot) {
        await contributeStars(
          stars: 10,
          memberId: 'system_daily_mission',
          memberName: 'Cả nhà điểm danh',
          sourceTaskId: 'daily_checkin_$todayKey',
        );
        unawaited(NotificationService.instance.addNotification(
          familyId: _currentFamilyId ?? 'f1',
          title: '🎉 Hoàn thành nhiệm vụ Cả nhà Điểm Danh!',
          titleEn: '🎉 Daily Family Check-in Completed!',
          body: 'Gia đình đã điểm danh đầy đủ hôm nay, +10 ⭐ vừa được cộng vào Hũ Niềm Vui!',
          bodyEn: 'All family members checked in today, +10 ⭐ added to Family Jackpot!',
          type: 'daily_checkin_completed',
        ));
      } else {
        debugPrint('FamilyJackpotService: Cả nhà đã điểm danh nhưng chưa có Premium -> Không tăng sao vào hũ.');
      }
    }
    notifyListeners();
  }

  bool isDailyCheckInCompletedToday() {
    final todayKey = DateTime.now().toIso8601String().substring(0, 10);
    return _awardedCheckInDates.contains(todayKey);
  }

  /// Thành viên điểm danh hôm nay. Nếu toàn bộ thành viên gia đình đã điểm danh đủ,
  /// tự động thưởng +10 ⭐ vào Hũ Niềm Vui Gia Đình!
  Future<bool> checkInDaily({
    required String userId,
    required String userName,
    required int totalFamilyMembers,
  }) async {
    final todayKey = DateTime.now().toIso8601String().substring(0, 10);
    final userSet = _dailyCheckIns.putIfAbsent(todayKey, () => <String>{});
    userSet.add(userId);

    if (_awardedCheckInDates.contains(todayKey)) {
      notifyListeners();
      return false;
    }

    final threshold = totalFamilyMembers > 0 ? totalFamilyMembers : 1;
    if (userSet.length >= threshold) {
      _awardedCheckInDates.add(todayKey);
      // Chỉ tăng sao vào hũ nếu gia đình đang có Premium
      if (canUseJackpot) {
        await contributeStars(
          stars: 10,
          memberId: 'system_daily_mission',
          memberName: 'Cả nhà điểm danh',
          sourceTaskId: 'daily_checkin_$todayKey',
        );
        unawaited(NotificationService.instance.addNotification(
          familyId: _currentFamilyId ?? 'f1',
          title: '🎉 Hoàn thành nhiệm vụ Cả nhà Điểm Danh!',
          titleEn: '🎉 Daily Family Check-in Completed!',
          body: 'Gia đình đã điểm danh đầy đủ hôm nay, +10 ⭐ vừa được cộng vào Hũ Niềm Vui!',
          bodyEn: 'All family members checked in today, +10 ⭐ added to Family Jackpot!',
          type: 'daily_checkin_completed',
        ));
      } else {
        debugPrint('FamilyJackpotService: Cả nhà đã điểm danh nhưng gia đình chưa có Premium -> Đồng bộ thành công nhưng chưa tăng sao vào hũ cho đến khi mở Premium.');
      }
      notifyListeners();
      return true;
    }

    notifyListeners();
    return false;
  }

  /// Tích lũy Sao vào Hũ Sao Gia Đình (từ nhiệm vụ hoàn thành hoặc thành viên đóng góp sao)
  Future<void> contributeStars({
    required int stars,
    String? memberId,
    String? memberName,
    String? sourceTaskId,
  }) async {
    if (stars <= 0) return;
    final uid = memberId ?? currentUserId;
    final name = memberName ?? currentUserName;
    final updatedContribs = Map<String, int>.from(_jackpot.contributions);
    updatedContribs[uid] = (updatedContribs[uid] ?? 0) + stars;

    final updatedNames = Map<String, String>.from(_jackpot.memberNames);
    updatedNames[uid] = name;

    String? topUid;
    int maxStars = 0;
    updatedContribs.forEach((k, v) {
      if (v > maxStars) {
        maxStars = v;
        topUid = k;
      }
    });

    final newTotal = _jackpot.totalPoolAmount + stars;
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

    await StarEconomyService.instance.contributeStarsToJackpotPool(
      familyId: _currentFamilyId ?? 'f1',
      contributorId: uid.isNotEmpty ? uid : 'family_member',
      contributorName: name,
      stars: stars,
      sourceTaskId: sourceTaskId,
    );

    await _recordTransaction(
      type: WalletTransactionType.contribute,
      amount: stars,
      title: sourceTaskId != null
          ? (sourceTaskId.startsWith('cashback_')
              ? 'Tích điểm 10% đổi phúc lợi'
              : (sourceTaskId.startsWith('daily_checkin')
                  ? 'Nhiệm vụ: Cả nhà điểm danh'
                  : 'Tích lũy sao vào Hũ'))
          : 'Góp sao vào Hũ Sao Gia Đình',
      description: 'Đóng góp +$stars ⭐ bởi $name',
      targetUserId: uid,
      targetUserName: name,
    );
  }

  /// Thực thi chia sao Hũ Sao Gia Đình ngay lập tức và cộng vào StarEconomyService
  Future<JackpotDistributionResult> distributeStarPotNow({
    Map<String, int>? overrideShakeCounts,
    List<String>? overrideParticipantIds,
    String? roundId,
  }) async {
    final participants = overrideParticipantIds ??
        (_jackpot.memberNames.keys.isNotEmpty
            ? _jackpot.memberNames.keys.toList()
            : (overrideShakeCounts?.keys.toList() ?? <String>[]));
    final shakes = overrideShakeCounts ?? _jackpot.shakeCounts;
    final poolStars = _jackpot.totalPoolAmount;

    final result = JackpotAlgorithm.calculate(
      totalAmount: poolStars,
      shakeCounts: shakes,
      participantIds: participants,
    );

    if (result.prizes.isEmpty) {
      return result;
    }

    final effectiveRoundId =
        roundId ?? 'round_${DateTime.now().microsecondsSinceEpoch}';
    final famId = _currentFamilyId ?? 'f1';
    final updatedWallets = Map<String, int>.from(_jackpot.memberWallets);

    for (final entry in result.prizes.entries) {
      final uid = entry.key;
      final wonStars = entry.value;
      if (wonStars > 0) {
        updatedWallets[uid] = (updatedWallets[uid] ?? 0) + wonStars;
        await StarEconomyService.instance.creditJackpotStarWin(
          familyId: famId,
          winnerId: uid,
          winnerName: _jackpot.memberNames[uid] ?? 'Thành viên',
          wonStars: wonStars,
          roundId: effectiveRoundId,
          isFirstPrize: uid == result.firstPrizeWinnerId,
        );
      }
    }

    _jackpot = _jackpot.copyWith(
      totalPoolAmount: 0,
      status: JackpotStatus.finished,
      shakeCounts: shakes,
      prizeResults: result.prizes,
      memberWallets: updatedWallets,
      topShakerId: result.topShakerId,
      firstPrizeWinnerId: result.firstPrizeWinnerId,
    );
    notifyListeners();
    return result;
  }

  /// Bắt đầu 30s Nổ Hũ (Chỉ người nạp nhiều nhất mới được gọi)
  Future<void> startShakeBattle() async {
    if (!canUseJackpot) {
      throw Exception('Gia đình cần có gói Premium để bắt đầu Nổ Hũ! Số sao trong hũ vẫn được bảo toàn nguyên vẹn.');
    }
    if (_jackpot.totalPoolAmount <= 0) {
      throw Exception('Hũ hiện đang trống (0 đ). Hãy nạp tiền vào quỹ hũ trước khi bấm Nổ Hũ!');
    }

    if (_cachedFamilyMembers.isEmpty) {
      await _loadFamilyMembers(_currentFamilyId ?? 'f1');
    }

    _localMyShakeCount = 0;
    _isTransitioningPhase = false;
    shakeEngine.reset();
    shakeEngine.isShakingPhase = true;
    final startTime = DateTime.now();

    final updatedNames = <String, String>{
      ..._cachedFamilyMembers,
      ..._jackpot.memberNames,
    };
    if (_auth?.currentUser != null && _auth?.currentUser?.uid != 'u1') {
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

    final starterName = updatedNames[currentUserId] ?? currentUserName;
    unawaited(NotificationService.instance.addNotification(
      familyId: _currentFamilyId ?? 'f1',
      title: 'Trận chiến Nổ Hũ 30 giây bắt đầu!',
      titleEn: '30s Pot Shake Battle Has Started!',
      body: '$starterName vừa phát lệnh Nổ Hũ! Cả nhà cùng vào lắc điện thoại nhận thưởng!',
      bodyEn: '$starterName initiated the Pot Shake! Join now and shake to win prizes!',
      type: 'jackpot_shake',
    ));
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

  /// Vừa kết thúc 30s lắc: Chuyển sang giai đoạn Hồi Hộp (Suspense) qua Transaction chống Race Condition
  Future<void> _enterSuspensePhase() async {
    if (_isTransitioningPhase || !_jackpot.isShaking) return;
    _isTransitioningPhase = true;

    try {
      final docRef = _firestore
          ?.collection('families')
          .doc(_currentFamilyId)
          .collection('jackpot')
          .doc('current');

      if (docRef != null && _firestore != null) {
        await _firestore!.runTransaction((transaction) async {
          final snap = await transaction.get(docRef);
          if (!snap.exists) return;
          final data = snap.data()!;
          final currentStatus = data['status'] as String? ?? '';
          if (currentStatus != JackpotStatus.shaking.name) return;

          final rawShakes = (data['shakeCounts'] as Map<String, dynamic>?) ?? {};
          final finalShakes = rawShakes.map((k, v) => MapEntry(k, (v as num).toInt()));
          if (currentUserId.isNotEmpty && _localMyShakeCount > (finalShakes[currentUserId] ?? 0)) {
            finalShakes[currentUserId] = _localMyShakeCount;
          }

          String? topShaker;
          int maxShakes = 0;
          finalShakes.forEach((uid, cnt) {
            if (cnt > maxShakes) {
              maxShakes = cnt;
              topShaker = uid;
            }
          });

          transaction.update(docRef, {
            'status': JackpotStatus.suspense.name,
            'shakeCounts': finalShakes,
            'prizeResults': <String, int>{},
            'topShakerId': topShaker,
            'firstPrizeWinnerId': null,
            'suspenseStartTime': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      } else {
        final finalShakes = Map<String, int>.from(_jackpot.shakeCounts);
        if (currentUserId.isNotEmpty && _localMyShakeCount > (finalShakes[currentUserId] ?? 0)) {
          finalShakes[currentUserId] = _localMyShakeCount;
        }

        String? topShaker;
        int maxShakes = 0;
        finalShakes.forEach((uid, cnt) {
          if (cnt > maxShakes) {
            maxShakes = cnt;
            topShaker = uid;
          }
        });

        _jackpot = _jackpot.copyWith(
          status: JackpotStatus.suspense,
          shakeCounts: finalShakes,
          prizeResults: const {},
          topShakerId: topShaker,
          clearFirstPrizeWinnerId: true,
          suspenseStartTime: DateTime.now(),
        );

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Enter suspense phase error: $e');
    } finally {
      _isTransitioningPhase = false;
      _ensureCountdownTimerRunning();
    }
  }

  /// Sau 10 giây Hồi Hộp: Thần may mắn phân xử trao thưởng qua Atomic Transaction
  /// Tiền trúng giải CỘNG DỒN vào ví cá nhân, không bị ghi đè hay mất tiền của bất kỳ ai!
  Future<void> _finishShakeBattle() async {
    if (_isTransitioningPhase || !_jackpot.isSuspense) return;
    _isTransitioningPhase = true;
    _stopCountdownTimer();

    try {
      final docRef = _firestore
          ?.collection('families')
          .doc(_currentFamilyId)
          .collection('jackpot')
          .doc('current');

      if (docRef != null && _firestore != null) {
        JackpotDistributionResult? finalResult;
        String? winnerIdToNotify;
        int winnerPrizeToNotify = 0;

        await _firestore!.runTransaction((transaction) async {
          final snap = await transaction.get(docRef);
          if (!snap.exists) return;
          final data = snap.data()!;
          final currentStatus = data['status'] as String? ?? '';
          // Idempotency: Chỉ 1 thiết bị đầu tiên thực thi chia giải. Thiết bị sau nhận status == finished thì thoát ngay
          if (currentStatus != JackpotStatus.suspense.name) return;

          final poolAmount = (data['totalPoolAmount'] as num?)?.toInt() ?? 0;
          final rawShakes = (data['shakeCounts'] as Map<String, dynamic>?) ?? {};
          final finalShakes = rawShakes.map((k, v) => MapEntry(k, (v as num).toInt()));
          if (currentUserId.isNotEmpty && _localMyShakeCount > (finalShakes[currentUserId] ?? 0)) {
            finalShakes[currentUserId] = _localMyShakeCount;
          }

          final rawNames = (data['memberNames'] as Map<String, dynamic>?) ?? {};
          final names = rawNames.map((k, v) => MapEntry(k, v.toString()));
          final participantIds = names.keys.toList();
          if (currentUserId.isNotEmpty && !participantIds.contains(currentUserId)) {
            participantIds.add(currentUserId);
          }

          final result = JackpotAlgorithm.calculate(
            totalAmount: poolAmount,
            shakeCounts: finalShakes,
            participantIds: participantIds,
          );
          finalResult = result;

          // Nếu cả nhà không ai lắc (0 lượt lắc) -> Bảo toàn 100% quỹ hũ, trở về idle để chơi lại
          if (result.prizes.isEmpty) {
            transaction.update(docRef, {
              'status': JackpotStatus.idle.name,
              'shakeCounts': <String, dynamic>{},
              'prizeResults': <String, dynamic>{},
              'topShakerId': null,
              'firstPrizeWinnerId': null,
              'shakeStartTime': null,
              'suspenseStartTime': null,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            return;
          }

          // Tiền trúng thưởng lập tức CỘNG DỒN vào ví số dư trong App của từng thành viên
          final rawWallets = (data['memberWallets'] as Map<String, dynamic>?) ?? {};
          final updatedWallets = rawWallets.map((k, v) => MapEntry(k, (v as num).toInt()));
          result.prizes.forEach((uid, wonAmount) {
            updatedWallets[uid] = (updatedWallets[uid] ?? 0) + wonAmount;
          });

          transaction.update(docRef, {
            'totalPoolAmount': 0, // Tiền quỹ vòng này đã được phân bổ 100% vào ví cá nhân
            'status': JackpotStatus.finished.name,
            'shakeCounts': finalShakes,
            'prizeResults': result.prizes,
            'memberWallets': updatedWallets,
            'topShakerId': result.topShakerId,
            'firstPrizeWinnerId': result.firstPrizeWinnerId,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          winnerIdToNotify = result.firstPrizeWinnerId;
          winnerPrizeToNotify = winnerIdToNotify != null ? (result.prizes[winnerIdToNotify] ?? 0) : 0;
        });

        if (finalResult != null) {
          final roundId = 'round_${DateTime.now().microsecondsSinceEpoch}';
          final famId = _currentFamilyId ?? 'f1';
          finalResult!.prizes.forEach((uid, wonAmount) {
            if (wonAmount > 0) {
              final isTop1 = uid == finalResult!.firstPrizeWinnerId;
              final mName = _jackpot.memberNames[uid] ?? 'Thành viên';
              unawaited(
                StarEconomyService.instance.creditJackpotStarWin(
                  familyId: famId,
                  winnerId: uid,
                  winnerName: mName,
                  wonStars: wonAmount,
                  roundId: roundId,
                  isFirstPrize: isTop1,
                ),
              );
              _recordTransaction(
                type: WalletTransactionType.prize,
                amount: wonAmount,
                title: isTop1 ? 'Trúng Giải Nhất 👑' : 'Thưởng nổ hũ gia đình',
                description: 'Phần thưởng chia từ quỹ Hũ Sao',
                targetUserId: uid,
                targetUserName: mName,
              );
            }
          });

          if (winnerIdToNotify != null && winnerPrizeToNotify > 0) {
            final winnerName = _jackpot.memberNames[winnerIdToNotify] ?? 'Thành viên';
            final formattedPrize = winnerPrizeToNotify.toString().replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (Match m) => '${m[1]}.',
            );
            unawaited(NotificationService.instance.addNotification(
              familyId: _currentFamilyId ?? 'f1',
              title: 'Kết quả Nổ Hũ Gia Đình! 🎉',
              titleEn: 'Family Pot Battle Results! 🎉',
              body: '$winnerName đã xuất sắc giành Giải Nhất với phần thưởng $formattedPrize đ!',
              bodyEn: '$winnerName won 1st Prize with a reward of $formattedPrize đ!',
              type: 'jackpot_win',
            ));
          }
        }
      } else {
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

        if (result.prizes.isEmpty) {
          _jackpot = _jackpot.copyWith(
            status: JackpotStatus.idle,
            shakeCounts: const {},
            prizeResults: const {},
            clearTopShakerId: true,
            clearFirstPrizeWinnerId: true,
            clearShakeStartTime: true,
            clearSuspenseStartTime: true,
          );
          notifyListeners();
          return;
        }

        final updatedWallets = Map<String, int>.from(_jackpot.memberWallets);
        final roundId = 'round_${DateTime.now().microsecondsSinceEpoch}';
        final famId = _currentFamilyId ?? 'f1';
        result.prizes.forEach((uid, wonAmount) {
          updatedWallets[uid] = (updatedWallets[uid] ?? 0) + wonAmount;
          if (wonAmount > 0) {
            final isTop1 = uid == result.firstPrizeWinnerId;
            final mName = _jackpot.memberNames[uid] ?? 'Thành viên';
            unawaited(
              StarEconomyService.instance.creditJackpotStarWin(
                familyId: famId,
                winnerId: uid,
                winnerName: mName,
                wonStars: wonAmount,
                roundId: roundId,
                isFirstPrize: isTop1,
              ),
            );
            _recordTransaction(
              type: WalletTransactionType.prize,
              amount: wonAmount,
              title: isTop1 ? 'Trúng Giải Nhất 👑' : 'Thưởng nổ hũ gia đình',
              description: 'Phần thưởng chia từ quỹ Hũ Sao',
              targetUserId: uid,
              targetUserName: mName,
            );
          }
        });

        _jackpot = _jackpot.copyWith(
          totalPoolAmount: 0,
          status: JackpotStatus.finished,
          shakeCounts: finalShakes,
          prizeResults: result.prizes,
          memberWallets: updatedWallets,
          topShakerId: result.topShakerId,
          firstPrizeWinnerId: result.firstPrizeWinnerId,
        );

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Finish shake battle error: $e');
    } finally {
      _isTransitioningPhase = false;
    }
  }

  /// Cập nhật thông tin tài khoản ngân hàng của thành viên hiện tại (Dot-notation an toàn không đè ví)
  Future<void> saveMyBankInfo(UserBankInfo bankInfo) async {
    final updatedBanks = Map<String, UserBankInfo>.from(_jackpot.memberBanks);
    updatedBanks[currentUserId] = bankInfo;

    _jackpot = _jackpot.copyWith(memberBanks: updatedBanks);
    notifyListeners();

    if (_currentFamilyId == null || _currentFamilyId!.isEmpty || _firestore == null) return;
    try {
      final docRef = _firestore!
          .collection('families')
          .doc(_currentFamilyId)
          .collection('jackpot')
          .doc('current');
      await docRef.update({
        'memberBanks.$currentUserId': bankInfo.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Save bank info error: $e');
    }
  }

  /// Rút tiền từ Ví thành viên về Số tài khoản ngân hàng cá nhân
  /// Sử dụng Firestore Atomic Transaction để chống xung đột rút tiền đồng thời (Race Condition)
  Future<bool> withdrawToBank(int amount) async {
    final uid = currentUserId;
    if (uid.isEmpty || amount <= 0) return false;
    if (!myBankInfo.isValid) return false;
    final fId = _currentFamilyId;
    if (fId == null || fId.isEmpty) return false;

    if (_firestore == null) return true;
    try {
      final docRef = _firestore!
          .collection('families')
          .doc(fId)
          .collection('jackpot')
          .doc('current');

      // Atomic Transaction: Đảm bảo kiểm tra số dư và trừ ví không bao giờ bị xung đột đồng thời
      await _firestore!.runTransaction((transaction) async {
        final snap = await transaction.get(docRef);
        if (!snap.exists || snap.data() == null) {
          throw Exception('Hũ không tồn tại');
        }
        final data = snap.data()!;
        final rawWallets = (data['memberWallets'] as Map<String, dynamic>?) ?? {};
        final currentBal = (rawWallets[uid] as num?)?.toInt() ?? 0;
        if (amount > currentBal) {
          throw Exception('Số tiền rút ($amount đ) vượt quá số dư ví ($currentBal đ)');
        }

        final updated = Map<String, dynamic>.from(rawWallets);
        updated[uid] = currentBal - amount;

        transaction.update(docRef, {
          'memberWallets': updated,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      // Cập nhật state local ngay
      final localWallets = Map<String, int>.from(_jackpot.memberWallets);
      localWallets[uid] = (localWallets[uid] ?? 0) - amount;
      _jackpot = _jackpot.copyWith(memberWallets: localWallets);
      notifyListeners();

      // Ghi Sổ cái Lịch sử biến động ví gia đình (Family-scoped Ledger)
      await _recordTransaction(
        type: WalletTransactionType.withdraw,
        amount: amount,
        title: 'Rút tiền về ${myBankInfo.bankShortName}',
        description: 'Chuyển về STK: ${myBankInfo.accountNumber}',
        bankShortName: myBankInfo.bankShortName,
        accountNumber: myBankInfo.accountNumber,
      );

      final formattedWithdraw = amount.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.");
      unawaited(NotificationService.instance.addNotification(
        familyId: fId,
        targetUserId: uid,
        title: 'Yêu cầu rút tiền về ${myBankInfo.bankShortName}',
        titleEn: 'Bank Withdrawal to ${myBankInfo.bankShortName}',
        body: 'Bạn đã rút $formattedWithdraw đ về STK: ${myBankInfo.accountNumber}',
        bodyEn: 'You withdrew $formattedWithdraw đ to account: ${myBankInfo.accountNumber}',
        type: 'wallet_withdraw',
      ));

      return true;
    } catch (e) {
      debugPrint('FamilyJackpotService.withdrawToBank error: $e');
      return false;
    }
  }

  /// Đặt lại Hũ mới sau khi nổ hũ xong (Bảo toàn 100% ví tiền thưởng tích lũy chưa rút của thành viên)
  Future<void> resetJackpot() async {
    _dailyCheckIns.clear();
    _awardedCheckInDates.clear();
    _localMyShakeCount = 0;
    _isTransitioningPhase = false;
    _stopCountdownTimer();
    shakeEngine.reset();

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

    if (_currentFamilyId == null || _currentFamilyId!.isEmpty || _firestore == null) return;
    try {
      final docRef = _firestore!
          .collection('families')
          .doc(_currentFamilyId)
          .collection('jackpot')
          .doc('current');
      await docRef.update({
        'totalPoolAmount': 0,
        'status': JackpotStatus.idle.name,
        'topContributorId': null,
        'topContributorName': 'Chưa có',
        'contributions': <String, dynamic>{},
        'shakeCounts': <String, dynamic>{},
        'prizeResults': <String, dynamic>{},
        'topShakerId': null,
        'firstPrizeWinnerId': null,
        'shakeStartTime': null,
        'suspenseStartTime': null,
        'lostDueToPremiumExpired': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Reset jackpot error: $e');
    }
  }

  /// Ghi đè toàn bộ trạng thái Hũ hiện tại lên Firestore (không dùng merge: true để xóa sạch các Map rỗng khi reset)
  Future<void> _saveToFirestore() async {
    if (_currentFamilyId == null || _currentFamilyId!.isEmpty || _firestore == null) return;
    try {
      await _firestore!
          .collection('families')
          .doc(_currentFamilyId)
          .collection('jackpot')
          .doc('current')
          .set(_jackpot.toMap());
    } catch (e) {
      debugPrint('Save jackpot error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // REAL-WORLD CASH GIFT TWO-WAY HANDSHAKE (Lì xì thực tế ngoài đời)
  // ---------------------------------------------------------------------------

  /// Tạo bản ghi giải thưởng tiền mặt chờ trao: WAITING_TRANSFER
  CashPrizeModel createCashPrize({
    required String prizeId,
    required String childId,
    required String childName,
    required int amount,
    String? familyId,
  }) {
    final targetFamilyId = familyId ?? _currentFamilyId ?? 'f1';
    final prize = handshakeEngine.createPrize(
      prizeId: prizeId,
      childId: childId,
      childName: childName,
      amount: amount,
      familyId: targetFamilyId,
    );
    if (_firestore != null) {
      try {
        _firestore!
            .collection('families')
            .doc(targetFamilyId)
            .collection('cash_prizes')
            .doc(prizeId)
            .set(prize.toMap());
      } catch (e) {
        debugPrint('Create cash prize error: $e');
      }
    }
    notifyListeners();
    return prize;
  }

  /// Trưởng bối xác nhận đã trao lì xì tiền mặt tận tay hoặc chuyển khoản VietQR: -> PAID
  void recordGuardianPayout({
    required String prizeId,
    required String guardianId,
    required String guardianName,
    String? bankRef,
    String? paymentMethod,
    bool isGuardian = true,
  }) {
    handshakeEngine.recordGuardianPayout(
      prizeId: prizeId,
      guardianId: guardianId,
      guardianName: guardianName,
      bankRef: bankRef,
      paymentMethod: paymentMethod,
      isGuardian: isGuardian,
    );
    final prize = handshakeEngine.prizes[prizeId];
    final targetFamilyId = prize?.familyId ?? _currentFamilyId ?? 'f1';
    if (_firestore != null && prize != null) {
      try {
        _firestore!
            .collection('families')
            .doc(targetFamilyId)
            .collection('cash_prizes')
            .doc(prizeId)
            .set(prize.toMap(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('Guardian payout error: $e');
      }
    }
    notifyListeners();
  }

  /// Trưởng bối đưa tiền mặt tận tay
  void guardianConfirmCashPayment({
    required String prizeId,
    required String guardianId,
    required String guardianName,
    required bool isGuardian,
  }) {
    recordGuardianPayout(
      prizeId: prizeId,
      guardianId: guardianId,
      guardianName: guardianName,
      paymentMethod: 'CASH',
      isGuardian: isGuardian,
    );
  }

  /// Trưởng bối chuyển khoản qua VietQR
  void guardianConfirmVietQrTransfer({
    required String prizeId,
    required String guardianId,
    required String guardianName,
    required String bankRef,
    required bool isGuardian,
  }) {
    recordGuardianPayout(
      prizeId: prizeId,
      guardianId: guardianId,
      guardianName: guardianName,
      bankRef: bankRef,
      paymentMethod: 'VIETQR',
      isGuardian: isGuardian,
    );
  }

  /// Cháu bấm [Đã nhận tiền] xác nhận đã nhận lì xì: -> RECEIVED (Idempotent)
  void confirmChildReceipt({
    required String prizeId,
    required String childId,
  }) {
    handshakeEngine.confirmChildReceipt(
      prizeId: prizeId,
      childId: childId,
    );
    final prize = handshakeEngine.prizes[prizeId];
    final targetFamilyId = prize?.familyId ?? _currentFamilyId ?? 'f1';
    if (_firestore != null && prize != null) {
      try {
        _firestore!
            .collection('families')
            .doc(targetFamilyId)
            .collection('cash_prizes')
            .doc(prizeId)
            .set(prize.toMap(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('Child confirm receipt error: $e');
      }
    }
    notifyListeners();
  }

  /// Alias tương thích childConfirmReceipt
  void childConfirmReceipt({
    required String prizeId,
    required String childId,
  }) {
    confirmChildReceipt(prizeId: prizeId, childId: childId);
  }

  @override
  void dispose() {
    _jackpotSub?.cancel();
    _sensorSub?.cancel();
    _stopCountdownTimer();
    super.dispose();
  }
}

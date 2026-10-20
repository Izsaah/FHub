import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/subscription_plan_model.dart';
import '../models/family_subscription_model.dart';

/// Service quản lý toàn bộ nghiệp vụ Gói cước, Đồng bộ Firestore Realtime & Thanh toán
class PaymentService extends ChangeNotifier {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal() {
    _currentSubscription = FamilySubscriptionModel.freeDefault(_currentFamilyId);
    _autoResolveFamilyId();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _firestoreSub;

  String _currentFamilyId = '';
  String get currentFamilyId => _currentFamilyId;

  late FamilySubscriptionModel _currentSubscription;
  FamilySubscriptionModel get currentSubscription => _currentSubscription;

  /// Gói Premium lưu tạm nếu user mua trước khi chọn gia đình
  FamilySubscriptionModel? _pendingSubscription;
  bool get hasPendingSubscription => _pendingSubscription != null;

  bool get isPremium => _currentSubscription.isPremium;
  int get memberLimit => _currentSubscription.maxMembers;

  /// Tự động tìm familyId của user đang đăng nhập nếu chưa được gán thủ công
  Future<void> _autoResolveFamilyId() async {
    if (_currentFamilyId.isNotEmpty) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final snap = await _firestore
            .collection('family_members')
            .where('userId', isEqualTo: uid)
            .where('status', isEqualTo: 'ACTIVE')
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final fId = snap.docs.first.data()['familyId'] as String? ?? '';
          if (fId.isNotEmpty && _currentFamilyId.isEmpty) {
            setFamilyId(fId);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('PaymentService: autoResolveFamilyId error: $e');
    }
    if (_currentFamilyId.isEmpty) {
      setFamilyId('f1');
    }
  }

  /// Đặt familyId và kích hoạt lắng nghe Firestore Realtime
  void setFamilyId(String familyId) {
    if (familyId.isEmpty) return;
    if (_currentFamilyId == familyId && _firestoreSub != null) return;

    _currentFamilyId = familyId;
    _currentSubscription = _currentSubscription.copyWith(familyId: familyId);

    // Hủy stream cũ nếu có
    _firestoreSub?.cancel();

    // Nếu có gói pending từ trước -> áp dụng lên Firestore ngay trước khi lắng nghe
    if (_pendingSubscription != null) {
      final pending = _pendingSubscription!;
      _pendingSubscription = null;
      activatePremium(
        planName: pending.planName,
        maxMembers: pending.maxMembers,
      );
    }

    // Lắng nghe thay đổi gói cước theo thời gian thực từ Firestore
    try {
      _firestoreSub = _firestore
          .collection('families')
          .doc(familyId)
          .snapshots()
          .listen(
        (snapshot) {
          if (!snapshot.exists || snapshot.data() == null) return;
          final data = snapshot.data()!;

          final bool isPrem = data['isPremium'] as bool? ?? false;
          final String plan = data['planName'] as String? ?? (isPrem ? 'Family Hub Premium' : 'Gói Cơ Bản (Free)');
          final int maxMem = data['maxMembers'] as int? ?? (isPrem ? 10 : 4);
          final dynamic endAt = data['subscriptionEndDate'] ?? data['endDate'];

          DateTime? parsedEnd;
          if (endAt is Timestamp) parsedEnd = endAt.toDate();
          if (endAt is String) parsedEnd = DateTime.tryParse(endAt);

          _currentSubscription = FamilySubscriptionModel(
            familyId: familyId,
            isPremium: isPrem,
            planName: plan,
            maxMembers: maxMem,
            endDate: parsedEnd,
          );
          notifyListeners();
        },
        onError: (e) {
          debugPrint('PaymentService: Firestore listen error: $e');
        },
      );
    } catch (e) {
      debugPrint('PaymentService: Init stream error: $e');
    }

    notifyListeners();
  }

  void applyPendingSubscriptionIfNeeded(String familyId) {
    setFamilyId(familyId);
  }

  // ─── Kiểm tra hạn mức thành viên ──────────────────────────────────────────

  bool canAddMember(int currentMemberCount) {
    return currentMemberCount < _currentSubscription.maxMembers;
  }

  int remainingSlots(int currentMemberCount) {
    final remaining = _currentSubscription.maxMembers - currentMemberCount;
    return remaining > 0 ? remaining : 0;
  }

  String getMemberLimitMessage(int currentMemberCount) {
    if (!canAddMember(currentMemberCount)) {
      final limit = _currentSubscription.maxMembers;
      if (isPremium) {
        return 'Gia đình đã đạt tối đa $limit thành viên của gói Premium.';
      }
      return 'Gói Cơ Bản chỉ cho phép tối đa $limit thành viên. '
          'Vui lòng nâng cấp lên Family Hub Premium để mời thêm tối đa 10 người!';
    }
    return '';
  }

  // ─── Kích hoạt gói Premium (Đồng bộ Firestore) ──────────────────────────

  Future<void> activatePremium({
    String? planName,
    int? maxMembers,
    Duration duration = const Duration(days: 30),
  }) async {
    final name = planName ?? SubscriptionPlanModel.premiumPlan.name;
    final limit = maxMembers ?? SubscriptionPlanModel.premiumPlan.maxMembers;
    final now = DateTime.now();
    final expiry = now.add(duration);

    final newSub = FamilySubscriptionModel(
      familyId: _currentFamilyId,
      isPremium: true,
      planName: name,
      maxMembers: limit,
      startDate: now,
      endDate: expiry,
    );

    _currentSubscription = newSub;
    if (_currentFamilyId.isEmpty) {
      _pendingSubscription = newSub;
    }
    notifyListeners();

    // Ghi trực tiếp lên Cloud Firestore nếu đã gắn familyId
    if (_currentFamilyId.isNotEmpty) {
      try {
        await _firestore.collection('families').doc(_currentFamilyId).set({
          'isPremium': true,
          'planName': name,
          'maxMembers': limit,
          'subscriptionStartDate': FieldValue.serverTimestamp(),
          'subscriptionEndDate': Timestamp.fromDate(expiry),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('PaymentService: Synced Premium to Firestore for family $_currentFamilyId');
      } catch (e) {
        debugPrint('PaymentService: Error updating Firestore: $e');
      }
    }
  }

  // ─── Đặt lại về Free (Reset Test) ────────────────────────────────────────

  Future<void> resetToFreeForDemo() async {
    _currentSubscription = FamilySubscriptionModel.freeDefault(_currentFamilyId);
    _pendingSubscription = null;
    notifyListeners();

    if (_currentFamilyId.isNotEmpty) {
      try {
        await _firestore.collection('families').doc(_currentFamilyId).set({
          'isPremium': false,
          'planName': 'Gói Cơ Bản (Free)',
          'maxMembers': 4,
          'subscriptionStartDate': null,
          'subscriptionEndDate': null,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('PaymentService: Reset family $_currentFamilyId to Free on Firestore');
      } catch (e) {
        debugPrint('PaymentService: Error resetting Firestore: $e');
      }
    }
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    super.dispose();
  }
}

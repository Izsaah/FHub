import 'package:flutter/foundation.dart';
import '../models/subscription_plan_model.dart';
import '../models/family_subscription_model.dart';

/// Service quản lý toàn bộ nghiệp vụ Gói cước & Giả lập Thanh toán
///
/// Nguyên lý thiết kế:
/// 1. Gói gắn theo Family: Mọi thành viên trong tổ ấm đều hưởng quyền lợi.
/// 2. Hạn mức: Free tối đa 4 người, Premium tối đa 10 người.
/// 3. Hỗ trợ Pending: Nếu mua trước khi tạo gia đình -> tự động áp dụng khi tạo.
/// 4. Giả lập thanh toán (Mock Payment): Delay 1.8s mô phỏng xử lý ngân hàng -> Kích hoạt Premium.
class PaymentService extends ChangeNotifier {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal() {
    _currentSubscription = FamilySubscriptionModel.freeDefault(_currentFamilyId);
  }

  String _currentFamilyId = 'f1';
  String get currentFamilyId => _currentFamilyId;

  late FamilySubscriptionModel _currentSubscription;
  FamilySubscriptionModel get currentSubscription => _currentSubscription;

  /// Gói Premium lưu tạm nếu user mua trước khi tạo gia đình
  FamilySubscriptionModel? _pendingSubscription;
  bool get hasPendingSubscription => _pendingSubscription != null;

  bool get isPremium => _currentSubscription.isPremium;
  int get memberLimit => _currentSubscription.maxMembers;

  /// Cập nhật familyId và áp dụng ngay gói Premium nếu có gói đang chờ (Pending)
  void setFamilyId(String familyId) {
    if (_currentFamilyId == familyId && _currentSubscription.familyId == familyId) {
      return;
    }
    _currentFamilyId = familyId;
    _currentSubscription = _currentSubscription.copyWith(familyId: familyId);

    if (_pendingSubscription != null) {
      _currentSubscription = _pendingSubscription!.copyWith(familyId: familyId);
      _pendingSubscription = null;
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

  // ─── Giả lập Thanh toán (Mock Payment) ────────────────────────────────────

  /// Giả lập thanh toán: Chờ 1.8s mô phỏng cổng thanh toán -> Kích hoạt gói Premium
  Future<bool> processMockPayment() async {
    // Giả lập độ trễ xử lý ngân hàng (1.8 giây)
    await Future.delayed(const Duration(milliseconds: 1800));

    final now = DateTime.now();
    final newSub = FamilySubscriptionModel(
      familyId: _currentFamilyId,
      isPremium: true,
      planName: SubscriptionPlanModel.premiumPlan.name,
      maxMembers: SubscriptionPlanModel.premiumPlan.maxMembers, // 10 người
      startDate: now,
      endDate: now.add(const Duration(days: 30)),
    );

    if (_currentFamilyId.isEmpty) {
      _pendingSubscription = newSub;
    } else {
      _currentSubscription = newSub;
    }

    notifyListeners();
    return true;
  }

  /// Đặt lại về Free để dễ dàng demo lại cho giảng viên
  void resetToFreeForDemo() {
    _currentSubscription = FamilySubscriptionModel.freeDefault(_currentFamilyId);
    _pendingSubscription = null;
    notifyListeners();
  }
}

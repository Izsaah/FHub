import 'package:flutter/material.dart';
import 'screens/premium_plan_screen.dart';
import 'screens/manage_subscription_screen.dart';
import 'screens/family_jackpot_screen.dart';
import 'services/payment_service.dart';
import 'theme/danh_colors.dart';
import 'theme/danh_svgs.dart';
import 'widgets/premium_badge_widget.dart';
import 'widgets/family_premium_status_widget.dart';
import '../Thinh/theme/app_language.dart';

/// Điểm truy cập trung tâm (Entry Point) của Module Danh
///
/// Thiết kế chuẩn Clean Architecture:
/// - Toàn bộ logic, screen, model nằm gọn gàng bên trong `lib/Danh`.
/// - Các màn hình khác của ứng dụng (ProfileScreen, FamilyScreen...) chỉ cần gọi
///   các hàm tĩnh này để sử dụng hoặc nhúng UI thanh toán.
/// - Khi bạn copy thư mục `lib/Danh` sang repo chính, toàn bộ hoạt động trơn tru 100%.
class DanhPaymentEntry {
  DanhPaymentEntry._();

  static final PaymentService service = PaymentService();

  /// Điều hướng tới màn hình Xem & Chọn gói Premium
  static Future<bool?> openPremiumPlans(BuildContext context) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PremiumPlanScreen()),
    );
  }

  /// Điều hướng tới màn hình Quản lý Thuê bao
  static Future<void> openManageSubscription(
    BuildContext context, {
    int? memberCount,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManageSubscriptionScreen(initialMemberCount: memberCount),
      ),
    );
  }

  /// Điều hướng tới Hũ Niềm Vui Gia Đình (Shopee Shake) - Tính năng độc quyền Premium
  static Future<void> openFamilyJackpot(BuildContext context) {
    if (!service.isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              '🌟 Vui lòng nâng cấp lên Gói Premium để mở khóa Hũ Niềm Vui Gia Đình!',
              '🌟 Please upgrade to Premium to unlock Family Jackpot!',
            ),
          ),
          backgroundColor: DanhColors.brand800,
        ),
      );
      return openPremiumPlans(context);
    }
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FamilyJackpotScreen()),
    );
  }

  /// Kiểm tra xem gia đình có thể mời thêm thành viên không
  static bool canAddMember(int currentMemberCount) {
    return service.canAddMember(currentMemberCount);
  }

  /// Lấy thông báo lỗi/hướng dẫn khi đạt giới hạn thành viên
  static String getMemberLimitMessage(int currentMemberCount) {
    return service.getMemberLimitMessage(currentMemberCount);
  }

  /// Gọi khi User tạo gia đình mới hoặc tham gia một gia đình
  /// để tự động áp dụng gói Premium đã mua trước (Pending Subscription)
  static void onFamilyCreatedOrJoined(String familyId) {
    service.applyPendingSubscriptionIfNeeded(familyId);
  }

  /// Widget hiển thị tiến trình hạn mức và trạng thái gói cho TOÀN BỘ thành viên trong Family
  static Widget buildFamilyPremiumStatus(int currentMemberCount) {
    return FamilyPremiumStatusWidget(currentMemberCount: currentMemberCount);
  }

  /// Widget Banner quảng bá / kích hoạt Premium nhúng nhẹ nhàng vào ProfileScreen
  static Widget buildPremiumBanner(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final isPremium = service.isPremium;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isPremium
                  ? [DanhColors.goldLight, const Color(0xFFFFF9E6)]
                  : [const Color(0xFFE8F6F3), const Color(0xFFF3FBF8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isPremium
                  ? DanhColors.gold.withValues(alpha: 0.6)
                  : DanhColors.brand200,
            ),
            boxShadow: isPremium
                ? DanhColors.premiumGlowShadow
                : DanhColors.fhubCardShadow,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isPremium ? DanhColors.gold.withValues(alpha: 0.2) : DanhColors.brand700.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: isPremium
                          ? DanhSvgs.crown(size: 28)
                          : DanhSvgs.vipBadge(size: 26),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              isPremium
                                  ? AppLanguage.text('Tổ Ấm Premium', 'Family Hub Premium')
                                  : AppLanguage.text('Nâng cấp Tổ Ấm Plus', 'Upgrade to Family Hub Plus'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isPremium ? DanhColors.brand900 : DanhColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            PremiumBadgeWidget(isPremium: isPremium, compact: true),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isPremium
                              ? AppLanguage.text(
                                  'Đã mở rộng tối đa 10 thành viên & mở khóa Hũ Niềm Vui',
                                  'Expanded up to 10 members & Family Jackpot unlocked',
                                )
                              : AppLanguage.text(
                                  'Mở rộng tối đa lên 10 thành viên & Hũ Niềm Vui Gia Đình',
                                  'Expand up to 10 members & Family Jackpot',
                                ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: DanhColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPremium ? DanhColors.goldDark : DanhColors.brand800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      if (isPremium) {
                        openManageSubscription(context);
                      } else {
                        openPremiumPlans(context);
                      }
                    },
                    child: Text(
                      isPremium
                          ? AppLanguage.text('Quản lý', 'Manage')
                          : AppLanguage.text('Nâng cấp', 'Upgrade'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => openFamilyJackpot(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: isPremium ? const Color(0xFFFFF3E0) : Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPremium ? const Color(0xFFFFB74D) : DanhColors.brand200,
                    ),
                  ),
                  child: Row(
                    children: [
                      DanhSvgs.goldenPot(size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isPremium
                              ? AppLanguage.text(
                                  'Hũ Niềm Vui Gia Đình • Vào nạp quỹ & Lắc 30s nổ hũ!',
                                  'Family Jackpot • Deposit & Shake 30s to win!',
                                )
                              : AppLanguage.text(
                                  'Hũ Niềm Vui Gia Đình (Đặc quyền gói Premium)',
                                  'Family Jackpot (Exclusive to Premium plan)',
                                ),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isPremium ? const Color(0xFFE65100) : DanhColors.brand800,
                          ),
                        ),
                      ),
                      Icon(
                        isPremium ? Icons.arrow_forward_ios_rounded : Icons.lock_outline_rounded,
                        size: 14,
                        color: isPremium ? const Color(0xFFE65100) : DanhColors.brand800,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../screens/premium_plan_screen.dart';
import '../screens/manage_subscription_screen.dart';
import '../services/payment_service.dart';
import '../theme/danh_colors.dart';
import 'premium_badge_widget.dart';

/// Widget hiển thị Trạng thái Gói & Hạn mức Thành viên của Gia đình
/// - Dành cho TOÀN BỘ thành viên trong tổ ấm (không chỉ riêng Owner)
/// - Reactive Realtime: Tự động cập nhật tức thì khi bất kỳ ai trong gia đình mua gói
/// - Hiển thị tiến trình hạn mức (VD: 2/4 người gói Free hoặc 2/10 người gói Premium)
/// - Cảnh báo rõ ràng khi gia đình đã đầy để nhắc nâng cấp
class FamilyPremiumStatusWidget extends StatelessWidget {
  final int currentMemberCount;

  const FamilyPremiumStatusWidget({
    super.key,
    required this.currentMemberCount,
  });

  @override
  Widget build(BuildContext context) {
    final paymentService = PaymentService();

    return ListenableBuilder(
      listenable: paymentService,
      builder: (context, _) {
        final sub = paymentService.currentSubscription;
        final isPremium = paymentService.isPremium;
        final maxMembers = sub.maxMembers;
        final isFull = currentMemberCount >= maxMembers;
        final progress = (currentMemberCount / maxMembers).clamp(0.0, 1.0);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFull
                  ? DanhColors.warning
                  : (isPremium ? DanhColors.gold.withValues(alpha: 0.6) : const Color(0xFFBDC9C4).withValues(alpha: 0.6)),
              width: isPremium || isFull ? 1.5 : 1.0,
            ),
            boxShadow: isPremium
                ? DanhColors.premiumGlowShadow
                : DanhColors.fhubCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hàng trên: Badge + Tên gói + Nút Quản lý/Nâng cấp
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      PremiumBadgeWidget(
                        isPremium: isPremium,
                        compact: true,
                        customText: isPremium ? 'TỔ ẤM PREMIUM' : 'GÓI CƠ BẢN',
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sub.planName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: DanhColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      if (isPremium) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ManageSubscriptionScreen()),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PremiumPlanScreen()),
                        );
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isPremium ? 'Chi tiết' : 'Nâng cấp 10 người',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isPremium ? DanhColors.brand800 : DanhColors.goldDark,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: isPremium ? DanhColors.brand800 : DanhColors.goldDark,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Thanh tiến trình hạn mức thành viên (VD: 2/4 hoặc 3/10)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Số lượng thành viên',
                    style: TextStyle(fontSize: 12, color: DanhColors.textMuted),
                  ),
                  Text(
                    '$currentMemberCount / $maxMembers người',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isFull ? DanhColors.error : DanhColors.brand800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: DanhColors.borderLight,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isFull
                        ? DanhColors.error
                        : (isPremium ? DanhColors.gold : DanhColors.brand700),
                  ),
                ),
              ),

              // Thông báo hướng dẫn hoặc cảnh báo khi đầy
              const SizedBox(height: 8),
              if (isFull)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: DanhColors.errorBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: DanhColors.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isPremium
                              ? 'Đã đạt hạn mức tối đa của gói ($maxMembers thành viên).'
                              : 'Đã đạt giới hạn 4 người. Nâng cấp Premium để mời thêm tối đa 10 người!',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: DanhColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'Còn trống ${maxMembers - currentMemberCount} vị trí mời thêm vào gia đình.',
                  style: const TextStyle(fontSize: 11, color: DanhColors.textMuted),
                ),
            ],
          ),
        );
      },
    );
  }
}

import '../Long/services/family_data_service.dart';
import '../Long/models/family_member_model.dart';
import '../Vinh/screens/wishlist_and_ledger_screen.dart';
import '../Vinh/models/family_member.dart';
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

  static bool _ensureHasFamily(BuildContext context) {
    if (service.currentFamilyId.trim().isNotEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLanguage.text(
            'Vui lòng tạo hoặc tham gia gia đình trước khi sử dụng tính năng này!',
            'Please create or join a family before using this feature!',
          ),
        ),
        backgroundColor: DanhColors.brand800,
      ),
    );
    return false;
  }

  /// Điều hướng tới màn hình Xem & Chọn gói Premium
  static Future<bool?> openPremiumPlans(BuildContext context) {
    if (!_ensureHasFamily(context)) return Future.value(false);
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
    if (!_ensureHasFamily(context)) return Future.value();
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManageSubscriptionScreen(initialMemberCount: memberCount),
      ),
    );
  }

  /// Điều hướng tới Heo Đất Gia Đình (Piggy Bank) - Tính năng độc quyền Premium
  static Future<void> openFamilyJackpot(BuildContext context) {
    if (!_ensureHasFamily(context)) return Future.value();
    if (!service.isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              '🌟 Vui lòng nâng cấp lên Gói Premium để mở khóa Heo Đất Gia Đình!',
              '🌟 Please upgrade to Premium to unlock Family Piggy Bank!',
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

  /// Xóa ngữ cảnh gia đình khi User chưa có hoặc đã rời hết tất cả gia đình
  static void clearFamilyContext() {
    service.clearFamily();
  }

  /// Điều hướng tới Cửa Hàng Đổi Sao & Sổ Cái Phúc Lợi Thực Tế
  static Future<void> openWishlistAndLedger(BuildContext context) async {
    final familyDataService = FamilyDataService();
    final family = await familyDataService.getCurrentFamily();
    final familyId = (family != null && family.id.trim().isNotEmpty)
        ? family.id
        : service.currentFamilyId;

    if (familyId.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                'Vui lòng chọn hoặc tham gia một gia đình trước!',
                'Please select or join a family first!',
              ),
            ),
          ),
        );
      }
      return;
    }

    final user = await familyDataService.getCurrentUser();
    final members = await familyDataService.getFamilyMembers(familyId: familyId);
    FamilyMemberModel? me;
    for (final m in members) {
      if (m.user.id == user.id) {
        me = m;
        break;
      }
    }
    final roleCode = me?.hierarchyRole.code ?? 'PARENT';

    final convertedMembers = members.map((m) {
      return FamilyMember(
        id: m.user.id,
        name: m.user.name,
        role: m.hierarchyRole.code,
        familyId: familyId,
        rewardStarsTotal: m.rewardStarsTotal,
      );
    }).toList();

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WishlistAndLedgerScreen(
          familyId: familyId,
          familyName: family?.name,
          currentUserId: user.id,
          currentUserName: user.name,
          currentUserRole: roleCode,
          familyMembers: convertedMembers,
        ),
      ),
    );
  }

  /// Widget hiển thị tiến trình hạn mức và trạng thái gói cho TOÀN BỘ thành viên trong Family
  /// Kiểm tra xem gia đình có đang bị đóng băng vượt ghế sau 7 ngày ân hạn hay không
  static bool get isOverCapacityFrozen => service.isOverCapacityFrozen;
  static bool get isGracePeriod => service.isGracePeriod;

  /// Hiển thị thông báo khi tính năng bị tạm khóa do vượt ghế
  /// Điều hướng tới Cửa Hàng Đổi Sao (Alias cho openWishlistAndLedger)
  static Future<void> openWishlistShop(BuildContext context) => openWishlistAndLedger(context);

  static Future<void> showOverCapacityFrozenDialog(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.lock_clock_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(AppLanguage.text('Tạm Khóa Tính Năng', 'Feature Frozen')),
          ],
        ),
        content: Text(
          AppLanguage.text(
            'Gia đình đã vượt quá hạn mức 4 người của gói Miễn phí và hết thời gian ân hạn.\n\nTính năng tạo lời nhắc mới và điểm danh tạm thời bị khóa. Vui lòng nâng cấp gói Premium (10 người) hoặc chuyển bớt thành viên sang Tạm ngưng để tiếp tục sử dụng miễn phí!',
            'Family has exceeded 4-member limit and grace period expired.\n\nCreating new tasks and check-ins are temporarily frozen. Please upgrade to Premium (10 members) or set members to inactive to continue for free!',
          ),
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLanguage.text('Đóng', 'Close')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005F50),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              openPremiumPlans(context);
            },
            child: Text(AppLanguage.text('Nâng cấp 10 người', 'Upgrade to 10')),
          ),
        ],
      ),
    );
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
        if (service.currentFamilyId.trim().isEmpty) {
          return const SizedBox.shrink();
        }
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
                            Flexible(
                              child: Text(
                                isPremium
                                    ? AppLanguage.text('Tổ Ấm Premium', 'Family Hub Premium')
                                    : AppLanguage.text('Nâng cấp Tổ Ấm Plus', 'Upgrade to Family Hub Plus'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isPremium ? DanhColors.brand900 : DanhColors.textPrimary,
                                ),
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
                                  'Đã mở rộng tối đa 10 thành viên & mở khóa Heo Đất Gia Đình',
                                  'Expanded up to 10 members & Family Piggy Bank unlocked',
                                )
                              : AppLanguage.text(
                                  'Mở rộng tối đa lên 10 thành viên & Heo Đất Gia Đình',
                                  'Expand up to 10 members & Family Piggy Bank',
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
                                  'Heo Đất Gia Đình • Nuôi heo chăm ngoan & Mở thưởng',
                                  'Family Piggy Bank • Feed with chores & Open rewards',
                                )
                              : AppLanguage.text(
                                  'Heo Đất Gia Đình (Đặc quyền gói Premium)',
                                  'Family Piggy Bank (Exclusive to Premium plan)',
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
              const SizedBox(height: 8),
              InkWell(
                key: const Key('btn_profile_open_wishlist'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => openWishlistAndLedger(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF81C784),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.card_giftcard_rounded, color: Color(0xFF2E7D32), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLanguage.text(
                                'Cửa Hàng Đổi Sao & Phúc Lợi Thực Tế ⭐',
                                'Star Reward Shop & Real Wishlist ⭐',
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                            Text(
                              AppLanguage.text(
                                'Đổi sao lấy quà thực tế • Sổ cái minh bạch',
                                'Redeem stars for real rewards • Transparent ledger',
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF388E3C),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF1B5E20),
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

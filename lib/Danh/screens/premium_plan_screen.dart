import 'package:flutter/material.dart';
import '../../Long/services/family_data_service.dart';
import '../models/subscription_plan_model.dart';
import '../services/payment_service.dart';
import '../theme/danh_colors.dart';
import '../widgets/premium_badge_widget.dart';
import 'manage_subscription_screen.dart';
import 'payment_checkout_screen.dart';

class PremiumPlanScreen extends StatefulWidget {
  const PremiumPlanScreen({super.key});

  @override
  State<PremiumPlanScreen> createState() => _PremiumPlanScreenState();
}

class _PremiumPlanScreenState extends State<PremiumPlanScreen> {
  final PaymentService _paymentService = PaymentService();
  String _familyName = 'Gia đình';

  @override
  void initState() {
    super.initState();
    _loadFamilyName();
  }

  Future<void> _loadFamilyName() async {
    try {
      final fam = await FamilyDataService().getCurrentFamily();
      if (fam != null && fam.name.trim().isNotEmpty && mounted) {
        setState(() => _familyName = fam.name.trim());
      }
    } catch (_) {}
  }

  Future<void> _onPressPay() async {
    final success = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaymentCheckoutScreen()),
    );
    if (success == true && mounted) {
      // Khi thanh toán xong thành công, tự động đóng màn hình này
      // và truyền kết quả true về màn hình trước đó (KhoaTestHomeScreen/Profile)
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const plan = SubscriptionPlanModel.premiumPlan;

    return ListenableBuilder(
      listenable: _paymentService,
      builder: (context, _) {
        final isPremium = _paymentService.isPremium;
        final sub = _paymentService.currentSubscription;

        return Scaffold(
          backgroundColor: DanhColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: DanhColors.brand50,
            elevation: 1,
            shadowColor: Colors.black12.withValues(alpha: 0.05),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: DanhColors.brand800),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _familyName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: DanhColors.brand800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  isPremium ? 'Đã là gói Premium' : 'Nâng cấp gói dịch vụ',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DanhColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero Card Banner
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isPremium
                          ? [const Color(0xFF1B4D3E), const Color(0xFF0F362A)]
                          : [DanhColors.brand900, DanhColors.brand700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: DanhColors.fhubCardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isPremium ? Icons.verified_rounded : Icons.workspace_premium,
                            color: DanhColors.gold,
                            size: 30,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isPremium ? 'Tổ Ấm Premium 👑' : 'Family Hub Premium',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isPremium
                            ? 'Gia đình bạn đã mở rộng thành công lên tới 10 thành viên. Toàn bộ người thân trong gia đình cùng hưởng trọn đặc quyền VIP!'
                            : 'Mở rộng không gian tổ ấm lên tới 10 thành viên. Một người mua – Toàn bộ gia đình cùng hưởng trọn quyền lợi!',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Card chi tiết gói cước
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: DanhColors.gold.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    boxShadow: DanhColors.premiumGlowShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          PremiumBadgeWidget(
                            isPremium: true,
                            customText: isPremium ? 'GÓI ĐANG DÙNG' : 'GÓI ĐỀ XUẤT',
                          ),
                          Text(
                            plan.priceFormatted,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: DanhColors.brand800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        plan.name,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: DanhColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.description,
                        style: const TextStyle(fontSize: 13, color: DanhColors.textMuted),
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: DanhColors.borderLight, height: 1),
                      const SizedBox(height: 14),
                      ...plan.benefits.map(
                        (benefit) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: DanhColors.brand50,
                                  shape: BoxShape.circle,
                                ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: DanhColors.brand800,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                benefit,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: DanhColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Nút bấm hành động
              if (isPremium)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DanhColors.brand800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shadowColor: DanhColors.brand800.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.verified_rounded, color: DanhColors.gold, size: 22),
                  label: const Text(
                    '✓ Đang Là Premium • Quản Lý Gói Cước',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const ManageSubscriptionScreen()),
                    );
                  },
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DanhColors.brand800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shadowColor: DanhColors.brand800.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _onPressPay,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_2_rounded, color: DanhColors.gold, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Thanh Toán VietQR (49.000 đ)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  isPremium
                      ? 'Gói đang hoạt động: ${sub.planName} (Hạn dùng: ${sub.formattedExpiry})'
                      : 'Quét mã VietQR bằng ứng dụng ngân hàng bất kỳ để kích hoạt',
                  style: const TextStyle(fontSize: 11.5, color: DanhColors.textMuted),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    },
  );
}
}

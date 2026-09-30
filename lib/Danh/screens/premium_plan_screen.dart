import 'package:flutter/material.dart';
import '../models/subscription_plan_model.dart';
import '../services/payment_service.dart';
import '../theme/danh_colors.dart';
import '../widgets/premium_badge_widget.dart';
// ignore: unused_import
import 'payment_checkout_screen.dart';

class PremiumPlanScreen extends StatefulWidget {
  const PremiumPlanScreen({super.key});

  @override
  State<PremiumPlanScreen> createState() => _PremiumPlanScreenState();
}

class _PremiumPlanScreenState extends State<PremiumPlanScreen> {
  final PaymentService _paymentService = PaymentService();
  bool _isProcessing = false;

  void _onPressPay() {
    // =========================================================================
    // 👉 CHẾ ĐỘ 1: MOCK PAYMENT (ĐANG BẬT MẶC ĐỊNH)
    // Bấm thanh toán -> load giả lập 1.8s -> thông báo thành công & kích hoạt ngay.
    // =========================================================================
    _handleMockPayment();

    // =========================================================================
    // 👉 CHẾ ĐỘ 2: VIETQR CHECKOUT (KHI CẦN DEMO QUÉT MÃ NGÂN HÀNG THẬT)
    // Khi cần demo: Chỉ cần comment dòng `_handleMockPayment();` ở trên
    // và bỏ comment 4 dòng code bên dưới:
    // =========================================================================
    /*
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaymentCheckoutScreen()),
    );
    */
  }

  /// Xử lý thanh toán giả lập (Mock Payment) với UI/UX chuẩn mực
  Future<void> _handleMockPayment() async {
    setState(() => _isProcessing = true);

    // 1. Hiển thị popup loading giả lập quá trình kết nối ngân hàng
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: DanhColors.brand50,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: DanhColors.brand800,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Đang xử lý giao dịch...',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: DanhColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Đang kết nối cổng thanh toán an toàn',
                  style: TextStyle(color: DanhColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 2. Chờ 1.8s giả lập
    await _paymentService.processMockPayment();

    if (!mounted) return;
    setState(() => _isProcessing = false);
    Navigator.pop(context); // Đóng popup loading

    // 3. Hiển thị popup Thành công tuyệt đẹp
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: DanhColors.successBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: DanhColors.brand200, width: 2),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: DanhColors.brand700,
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Thanh Toán Thành Công!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: DanhColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tổ ấm của bạn đã được nâng cấp lên Family Hub Premium! '
                'Hạn mức gia đình đã mở rộng lên 10 thành viên cho tất cả mọi người.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: DanhColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DanhColors.brand800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx); // Đóng dialog
                    Navigator.pop(context); // Quay về màn hình trước
                  },
                  child: const Text(
                    'Bắt đầu trải nghiệm ngay',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const plan = SubscriptionPlanModel.premiumPlan;

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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tổ Ấm Yêu Thương',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: DanhColors.brand800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Nâng cấp gói dịch vụ',
              style: TextStyle(
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
                gradient: const LinearGradient(
                  colors: [DanhColors.brand900, DanhColors.brand700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: DanhColors.fhubCardShadow,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium, color: DanhColors.gold, size: 30),
                      SizedBox(width: 10),
                      Text(
                        'Family Hub Premium',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Mở rộng không gian tổ ấm lên tới 10 thành viên. '
                    'Một người mua – Toàn bộ gia đình cùng hưởng trọn quyền lợi!',
                    style: TextStyle(
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
                      const PremiumBadgeWidget(isPremium: true, customText: 'GÓI ĐỀ XUẤT'),
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

            // Nút bấm thanh toán
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
              onPressed: _isProcessing ? null : _onPressPay,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flash_on, color: DanhColors.gold, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Thanh Toán Ngay (49.000 đ)',
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
            const Center(
              child: Text(
                'Mô phỏng thanh toán sandbox (delay 1.8s → kích hoạt ngay)',
                style: TextStyle(fontSize: 11.5, color: DanhColors.textMuted),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/payment_service.dart';
import '../theme/danh_colors.dart';

/// Màn hình Thanh toán Mã QR VietQR chuẩn Napas 247
/// Đã được thiết lập sẵn sàng:
/// - Hiển thị mã QR tự động điền STK, Số tiền, Nội dung
/// - Có nút Copy tiện lợi
/// - Có nút Giả lập ngân hàng xác nhận nhận tiền thành công
class PaymentCheckoutScreen extends StatefulWidget {
  const PaymentCheckoutScreen({super.key});

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  final PaymentService _paymentService = PaymentService();

  // Thông tin tài khoản nhận tiền (có thể cấu hình)
  final String _bankName = 'MB Bank (Quân Đội)';
  final String _bankId = 'MB';
  final String _accountNo = '0388889999';
  final String _accountName = 'FAMILY HUB PREMIUM';
  final int _amount = 49000;
  final String _orderCode = 'FHUB-PREMIUM';

  bool _isProcessing = false;

  String get _qrUrl =>
      'https://img.vietqr.io/image/$_bankId-$_accountNo-compact2.png'
      '?amount=$_amount&addInfo=$_orderCode&accountName=${Uri.encodeComponent(_accountName)}';

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép $label: $text'),
        backgroundColor: DanhColors.brand800,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleConfirmPayment() async {
    setState(() => _isProcessing = true);
    await _paymentService.processMockPayment();
    if (!mounted) return;
    setState(() => _isProcessing = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: DanhColors.successBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: DanhColors.success,
                  size: 44,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Thanh Toán Thành Công!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ngân hàng đã ghi nhận chuyển khoản. Tổ ấm của bạn đã được nâng cấp lên 10 thành viên!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: DanhColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DanhColors.brand800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx); // Đóng dialog
                    Navigator.pop(context); // Quay về trang trước
                    Navigator.pop(context); // Quay về màn hình chính
                  },
                  child: const Text('Hoàn tất', style: TextStyle(fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: DanhColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: DanhColors.brand50,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: DanhColors.brand900),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Thanh Toán VietQR',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: DanhColors.brand900),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card QR
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: DanhColors.borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: DanhColors.brand200, width: 2),
                    ),
                    child: Image.network(
                      _qrUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(Icons.qr_code_2_rounded, size: 100, color: DanhColors.brand800),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Mở app ngân hàng quét mã QR để thanh toán',
                    style: TextStyle(fontSize: 12, color: DanhColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: DanhColors.borderLight),
                  const SizedBox(height: 12),
                  _buildRow('Ngân hàng:', _bankName),
                  _buildRow('Số tài khoản:', _accountNo, canCopy: true),
                  _buildRow('Chủ tài khoản:', _accountName),
                  _buildRow('Số tiền:', '49.000 đ', isAmount: true),
                  _buildRow('Nội dung CK:', _orderCode, canCopy: true, isHighlight: true),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Nút mô phỏng xác nhận
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: DanhColors.brand800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isProcessing ? null : _handleConfirmPayment,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: Text(
                _isProcessing ? 'Đang xác nhận...' : 'Tôi đã chuyển khoản thành công',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    String label,
    String value, {
    bool canCopy = false,
    bool isHighlight = false,
    bool isAmount = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: DanhColors.textMuted)),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: isAmount ? 15 : 13,
                  fontWeight: isHighlight || isAmount ? FontWeight.bold : FontWeight.w600,
                  color: isHighlight
                      ? DanhColors.brand800
                      : (isAmount ? DanhColors.goldDark : DanhColors.textPrimary),
                ),
              ),
              if (canCopy) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _copy(value, label),
                  child: const Icon(Icons.copy_rounded, size: 16, color: DanhColors.brand700),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/payment_config.dart';
import '../services/payment_service.dart';
import '../services/sepay_service.dart';
import '../theme/danh_colors.dart';
import '../theme/danh_svgs.dart';
import 'family_jackpot_screen.dart';
import 'manage_subscription_screen.dart';

/// Màn hình Thanh toán Mã QR VietQR Napas 247 kết nối SePay Sandbox
class PaymentCheckoutScreen extends StatefulWidget {
  const PaymentCheckoutScreen({super.key});

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  final PaymentService _paymentService = PaymentService();
  final SepayService _sepayService = SepayService.instance;

  late final String _orderCode;
  Timer? _pollingTimer;
  bool _isSuccess = false;
  bool _isCheckingNow = false;
  String? _underpaidWarning;
  BuildContext? _zoomDialogCtx;

  @override
  void initState() {
    super.initState();
    // Sinh mã đơn hàng ngẫu nhiên duy nhất cho phiên thanh toán
    final randNum = Random().nextInt(899999) + 100000;
    _orderCode = 'FHUB$randNum';

    // Bắt đầu tự động kiểm tra giao dịch từ SePay Sandbox mỗi 2 giây
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) async {
      await _checkSepayNow(silent: true);
    });
  }

  Future<void> _checkSepayNow({bool silent = false}) async {
    if (!mounted || _isSuccess || _isCheckingNow) return;
    if (!silent) {
      setState(() => _isCheckingNow = true);
    }

    try {
      final result = await _sepayService.checkPayment(
        orderCode: _orderCode,
        expectedAmount: PaymentConfig.defaultAmount,
      );

      if (result.isSuccess && mounted && !_isSuccess) {
        _isSuccess = true;
        _pollingTimer?.cancel();
        await _onPaymentSuccess();
      } else if (result.isUnderpaid && mounted) {
        setState(() {
          _underpaidWarning =
              'Phát hiện chuyển thiếu tiền: Đã nhận ${result.amountIn} đ (Yêu cầu ${result.expectedAmount} đ). Vui lòng chuyển đủ!';
        });
      } else if (!silent && mounted) {
        final msg = kIsWeb
            ? 'Trên Web (Chrome), chính sách CORS của trình duyệt có thể hạn chế đọc tự động từ SePay. Bạn hãy bấm "Mô phỏng thanh toán thành công" ngay bên dưới để kích hoạt gói tức thì!'
            : 'Chưa nhận được giao dịch cho mã $_orderCode. Hãy bấm "Mô phỏng giao dịch" trên SePay với đúng mã $_orderCode!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: DanhColors.warning,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (!silent && mounted) {
        setState(() => _isCheckingNow = false);
      }
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _onPaymentSuccess() async {
    // Nếu đang mở popup phóng to QR thì tự động đóng lại ngay để hiện màn hình thành công
    if (_zoomDialogCtx != null && _zoomDialogCtx!.mounted) {
      Navigator.of(_zoomDialogCtx!).pop();
      _zoomDialogCtx = null;
    }

    if (mounted) {
      setState(() => _isSuccess = true);
    }
    await _paymentService.activatePremium();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 Thanh toán thành công! Gói Premium đã được kích hoạt.'),
        backgroundColor: DanhColors.brand800,
        duration: Duration(seconds: 3),
      ),
    );
  }

  bool _isSimulating = false;

  /// Phóng to mã QR khi người dùng nhấp vào
  void _zoomQrCode(String qrUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        _zoomDialogCtx = ctx;
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, color: DanhColors.brand800, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Mã VietQR Napas 247',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: DanhColors.brand800),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 3.5,
                        child: Image.network(
                          qrUrl,
                          width: 280,
                          height: 280,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.qr_code_2_rounded, size: 180, color: DanhColors.brand800),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DanhColors.brand50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Số tiền: ${PaymentConfig.defaultAmount} đ',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: DanhColors.goldDark),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Nội dung CK: $_orderCode',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: DanhColors.brand800),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _copy(_orderCode, 'Nội dung CK'),
                              child: const Icon(Icons.copy_rounded, size: 16, color: DanhColors.brand800),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: DanhColors.brand800),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Đang tự động lắng nghe SePay (tự đóng khi hoàn tất)...',
                        style: TextStyle(fontSize: 11.5, color: DanhColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DanhColors.brand800,
                        side: const BorderSide(color: DanhColors.brand800),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Đóng'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      _zoomDialogCtx = null;
    });
  }

  /// Nút riêng biệt để mô phỏng thanh toán thành công (Không cần xác nhận rườm rà)
  Future<void> _handleManualSimulate() async {
    if (_isSuccess || _isSimulating) return;
    setState(() => _isSimulating = true);

    _pollingTimer?.cancel();
    await Future.delayed(const Duration(milliseconds: 300));
    await _onPaymentSuccess();
    if (mounted) {
      setState(() => _isSimulating = false);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        backgroundColor: DanhColors.scaffoldBg,
        appBar: AppBar(
          backgroundColor: DanhColors.brand50,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: DanhColors.brand900),
            onPressed: () => Navigator.pop(context, _isSuccess),
          ),
          title: Text(
            _isSuccess ? 'Kết Quả Thanh Toán' : 'Thanh Toán VietQR',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: DanhColors.brand900),
          ),
        ),
        body: _isSuccess ? _buildSuccessView() : _buildCheckoutView(),
      ),
    );
  }

  // ─── GIAO DIỆN THANH TOÁN ────────────────────────────────────────────────
  Widget _buildCheckoutView() {
    final qrUrl = PaymentConfig.buildVietQrUrl(orderCode: _orderCode);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thẻ chứa mã QR & Thông tin chuyển khoản
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DanhColors.borderLight),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 15,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                // Bấm vào mã QR để phóng to
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _zoomQrCode(qrUrl),
                    child: Container(
                      width: 220,
                      height: 220,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: DanhColors.brand200, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Image.network(
                        qrUrl,
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
                  ),
                ),
                const SizedBox(height: 10),

                // Gợi ý bấm phóng to
                InkWell(
                  onTap: () => _zoomQrCode(qrUrl),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in_rounded, size: 16, color: DanhColors.brand800),
                        SizedBox(width: 4),
                        Text(
                          'Nhấp vào mã QR để phóng to',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DanhColors.brand800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_underpaidWarning != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DanhColors.errorBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: DanhColors.error),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 18, color: DanhColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _underpaidWarning!,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: DanhColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(color: DanhColors.borderLight),
                const SizedBox(height: 12),
                _buildRow('Ngân hàng:', PaymentConfig.bankShortName),
                _buildRow('Số tài khoản:', PaymentConfig.accountNo, canCopy: true),
                _buildRow('Chủ tài khoản:', PaymentConfig.accountName),
                _buildRow('Số tiền:', '${PaymentConfig.defaultAmount} đ', isAmount: true),
                _buildRow('Nội dung CK:', _orderCode, canCopy: true, isHighlight: true),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: DanhColors.brand50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: DanhColors.brand800),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Đang tự động lắng nghe SePay (mỗi 2s)...',
                          style: TextStyle(fontSize: 12, color: DanhColors.brand800, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _isCheckingNow ? null : () => _checkSepayNow(silent: false),
                        child: Text(
                          _isCheckingNow ? 'Đang kiểm tra...' : 'Kiểm tra ngay',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Nút mô phỏng thanh toán riêng biệt
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: DanhColors.brand800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: _isSimulating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 20, color: Colors.white),
            label: Text(
              _isSimulating
                  ? 'Đang kích hoạt gói...'
                  : 'Mô phỏng thanh toán thành công (Thử nghiệm)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            onPressed: _isSimulating ? null : _handleManualSimulate,
          ),

          const SizedBox(height: 10),

          // Nút Hủy / Quay lại
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: DanhColors.textSecondary,
              side: const BorderSide(color: DanhColors.borderLight),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy giao dịch', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ─── GIAO DIỆN KẾT QUẢ THÀNH CÔNG RÕ RÀNG ──────────────────────────────
  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: DanhColors.brand200),
            boxShadow: DanhColors.premiumGlowShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DanhSvgs.checkSuccess(size: 76),
              const SizedBox(height: 18),
              const Text(
                'Thanh Toán Thành Công!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: DanhColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Hệ thống đã ghi nhận giao dịch.\nTổ ấm của bạn đã được nâng cấp lên 10 thành viên!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: DanhColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DanhColors.brand50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildRow('Mã đơn:', _orderCode),
                    _buildRow('Số tiền:', '${PaymentConfig.defaultAmount} đ', isAmount: true),
                    _buildRow('Trạng thái:', 'ĐÃ KÍCH HOẠT PREMIUM', isHighlight: true),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: DanhSvgs.goldenPot(size: 20),
                  label: const Text('Mở Hũ Niềm Vui Gia Đình Ngay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const FamilyJackpotScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DanhColors.brand800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  child: const Text('✓ Hoàn tất & Quay về', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DanhColors.brand800,
                    side: const BorderSide(color: DanhColors.brand800),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const ManageSubscriptionScreen()),
                    );
                  },
                  child: const Text('Quản Lý Gói Cước Gia Đình', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 4.0),
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

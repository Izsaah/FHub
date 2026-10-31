import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Cấu hình ngân hàng nhận tiền và Cổng thanh toán SePay Sandbox
class PaymentConfig {
  PaymentConfig._();

  // Thông tin ngân hàng thử nghiệm SePay (Ưu tiên đọc linh hoạt từ .env, có fallback an toàn)
  static const String bankCode = 'MB';
  static String get bankShortName => _getEnv('SEPAY_BANK_NAME', 'MBBank');
  static const String bankFullName = 'Ngân hàng TMCP Quân Đội';
  static const String bankBin = '970422';
  static String get accountNo => _getEnv('SEPAY_ACCOUNT_NO', '0000000001');
  static String get accountName => _getEnv('SEPAY_ACCOUNT_NAME', 'Family Hub');

  // Số tiền gói Premium mặc định (Tháng)
  static const int defaultAmount = 49000;

  // Cấu hình SePay Sandbox API Key (Ưu tiên đọc từ .env, fallback khi test)
  static const String _fallbackApiKey =
      'ZMSQWHDK3RPRBDC08DX9FVJ8TG9UEJYYS2M5A4VGWH7EOLOE6BXPXL1QNWTVMNOK';

  static String get apiKey => _getEnv('SEPAY_API_KEY', _fallbackApiKey);

  static const String sepaySandboxEndpoint =
      'https://userapi-sandbox.sepay.vn/v2/transactions';

  static String _getEnv(String key, String fallback) {
    try {
      if (dotenv.isInitialized) {
        final val = dotenv.env[key]?.trim();
        if (val != null && val.isNotEmpty) return val;
      }
    } catch (_) {}
    return fallback;
  }

  /// Sinh đường dẫn ảnh mã VietQR Napas chuẩn SePay (trả về ảnh PNG trực tiếp, không bị lỗi SVG hay CORS)
  static String buildVietQrUrl({
    required String orderCode,
    int amount = defaultAmount,
  }) {
    return 'https://qr.sepay.vn/img?bank=$bankShortName&acc=$accountNo&amount=$amount&des=$orderCode&template=qronly';
  }
}

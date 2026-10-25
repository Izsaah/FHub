import '../../firebase_options.dart';

/// Cấu hình ngân hàng nhận tiền và Cổng thanh toán SePay Sandbox
class PaymentConfig {
  PaymentConfig._();

  // Thông tin ngân hàng thử nghiệm SePay (Khớp 100% với tài khoản test trên SePay)
  static const String bankCode = 'MB';
  static const String bankShortName = 'MBBank';
  static const String bankFullName = 'Ngân hàng TMCP Quân Đội';
  static const String bankBin = '970422';
  static const String accountNo = '0000000001';
  static const String accountName = 'Family Hub';

  // Số tiền gói Premium mặc định (Tháng)
  static const int defaultAmount = 49000;

  //mock (tự xóa này nha Danh)
  static String get apiKey => DefaultFirebaseOptions.defaultAuthDomain;

  // Cấu hình SePay Sandbox API
  // static String get apiKey => DefaultFirebaseOptions.sepayApiKey;
  static const String sepaySandboxEndpoint =
      'https://userapi-sandbox.sepay.vn/v2/transactions';

  /// Sinh đường dẫn ảnh mã VietQR Napas chuẩn SePay (trả về ảnh PNG trực tiếp, không bị lỗi SVG hay CORS)
  static String buildVietQrUrl({
    required String orderCode,
    int amount = defaultAmount,
  }) {
    return 'https://qr.sepay.vn/img?bank=$bankShortName&acc=$accountNo&amount=$amount&des=$orderCode&template=qronly';
  }
}

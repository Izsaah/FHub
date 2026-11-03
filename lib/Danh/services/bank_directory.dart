import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'payment_config.dart';

/// Đại diện một ngân hàng trong hệ thống thanh toán & rút tiền NAPAS / VietQR
class BankItem {
  final String code;
  final String shortName;
  final String bin;
  final String name;

  const BankItem({
    required this.code,
    required this.shortName,
    required this.bin,
    required this.name,
  });
}

/// Danh bạ ngân hàng Việt Nam hỗ trợ rút tiền và VietQR
class BankDirectory {
  BankDirectory._();

  static const List<BankItem> supportedBanks = [
    BankItem(code: 'MB', shortName: 'MBBank', bin: '970422', name: 'MBBank - Ngân hàng Quân Đội'),
    BankItem(code: 'TPB', shortName: 'TPBank', bin: '970423', name: 'TPBank - Ngân hàng Tiên Phong'),
    BankItem(code: 'VCB', shortName: 'Vietcombank', bin: '970436', name: 'Vietcombank - Ngoại Thương'),
    BankItem(code: 'TCB', shortName: 'Techcombank', bin: '970407', name: 'Techcombank - Kỹ Thương'),
    BankItem(code: 'ACB', shortName: 'ACB', bin: '970416', name: 'ACB - Á Châu'),
    BankItem(code: 'VPB', shortName: 'VPBank', bin: '970432', name: 'VPBank - VN Thịnh Vượng'),
    BankItem(code: 'ICB', shortName: 'VietinBank', bin: '970415', name: 'VietinBank - Công Thương'),
    BankItem(code: 'BIDV', shortName: 'BIDV', bin: '970418', name: 'BIDV - Đầu tư & Phát triển'),
    BankItem(code: 'STB', shortName: 'Sacombank', bin: '970403', name: 'Sacombank - Sài Gòn Thương Tín'),
    BankItem(code: 'HDB', shortName: 'HDBank', bin: '970437', name: 'HDBank - Phát triển TP.HCM'),
    BankItem(code: 'VIB', shortName: 'VIB', bin: '970441', name: 'VIB - Quốc Tế'),
    BankItem(code: 'SHB', shortName: 'SHB', bin: '970443', name: 'SHB - Sài Gòn - Hà Nội'),
    BankItem(code: 'VBA', shortName: 'Agribank', bin: '970405', name: 'Agribank - Nông nghiệp & PTNT'),
    BankItem(code: 'MSB', shortName: 'MSB', bin: '970426', name: 'MSB - Hàng Hải'),
    BankItem(code: 'OCB', shortName: 'OCB', bin: '970448', name: 'OCB - Phương Đông'),
    BankItem(code: 'SEAB', shortName: 'SeABank', bin: '970440', name: 'SeABank - Đông Nam Á'),
    BankItem(code: 'LPB', shortName: 'LPBank', bin: '970449', name: 'LPBank - Lộc Phát'),
    BankItem(code: 'EIB', shortName: 'Eximbank', bin: '970431', name: 'Eximbank - Xuất Nhập Khẩu'),
    BankItem(code: 'NAB', shortName: 'NamABank', bin: '970428', name: 'Nam A Bank - Nam Á'),
    BankItem(code: 'BVB', shortName: 'BaoVietBank', bin: '970438', name: 'Bảo Việt Bank'),
    BankItem(code: 'TIMO', shortName: 'Timo', bin: '963388', name: 'Timo by BVBank'),
    BankItem(code: 'CAKE', shortName: 'CAKE', bin: '546034', name: 'CAKE by VPBank'),
  ];

  static BankItem? findByCode(String code) {
    try {
      return supportedBanks.firstWhere(
        (b) => b.code.toUpperCase() == code.toUpperCase(),
      );
    } catch (_) {
      return null;
    }
  }

  static BankItem? findByShortName(String shortName) {
    try {
      return supportedBanks.firstWhere(
        (b) => b.shortName.toUpperCase() == shortName.toUpperCase(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Dịch vụ tra cứu tên chủ tài khoản ngân hàng tự động
class BankLookupService {
  BankLookupService._();

  /// Tra cứu tên chủ tài khoản theo mã ngân hàng và số tài khoản
  static Future<String?> lookupAccountName({
    required String bankCode,
    required String accountNumber,
    String? fallbackName,
  }) async {
    final cleanAcc = accountNumber.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanAcc.length < 6) return null;

    // 1. Kiểm tra khớp tài khoản SePay đã cấu hình trong .env
    final envAcc = PaymentConfig.accountNo.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanAcc == envAcc && PaymentConfig.accountName.isNotEmpty) {
      return PaymentConfig.accountName.toUpperCase();
    }

    // 2. Tra cứu qua SePay Bank Accounts API nếu có API key
    final sepayToken = PaymentConfig.apiKey.trim();
    if (sepayToken.isNotEmpty) {
      try {
        final res = await http.get(
          Uri.parse('https://userapi.sepay.vn/v2/bank-accounts'),
          headers: {'Authorization': 'Bearer $sepayToken'},
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>?;
          final list = json?['data'] as List<dynamic>? ?? [];
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final acc = (item['account_number'] ?? '')
                  .toString()
                  .trim()
                  .replaceAll(RegExp(r'[^0-9]'), '');
              if (acc == cleanAcc) {
                final holder = (item['account_holder_name'] ?? '').toString().trim();
                if (holder.isNotEmpty) return holder.toUpperCase();
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Tra cứu qua VietQR Open API nếu người dùng có cấu hình API credentials
    final vietqrClientId = dotenv.isInitialized ? dotenv.env['VIETQR_CLIENT_ID']?.trim() : null;
    final vietqrApiKey = dotenv.isInitialized ? dotenv.env['VIETQR_API_KEY']?.trim() : null;
    final bankItem = BankDirectory.findByCode(bankCode);
    if (vietqrClientId != null &&
        vietqrClientId.isNotEmpty &&
        vietqrApiKey != null &&
        vietqrApiKey.isNotEmpty &&
        bankItem != null) {
      try {
        final res = await http.post(
          Uri.parse('https://api.vietqr.io/v2/lookup'),
          headers: {
            'x-client-id': vietqrClientId,
            'x-api-key': vietqrApiKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'bin': bankItem.bin,
            'accountNumber': cleanAcc,
          }),
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>?;
          final data = json?['data'] as Map<String, dynamic>?;
          final name = data?['accountName'] as String?;
          if (name != null && name.trim().isNotEmpty) {
            return name.trim().toUpperCase();
          }
        }
      } catch (_) {}
    }

    return null;
  }
}

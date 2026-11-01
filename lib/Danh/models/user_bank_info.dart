/// Thông tin tài khoản ngân hàng của thành viên để nhận tiền thưởng nổ hũ
class UserBankInfo {
  final String bankCode;       // MB, VCB, TCB, ACB, ICB, VPB...
  final String bankShortName;  // MBBank, Vietcombank, Techcombank...
  final String accountNumber;  // Số tài khoản ngân hàng
  final String accountHolder;  // Tên chủ tài khoản (in hoa không dấu)

  const UserBankInfo({
    required this.bankCode,
    required this.bankShortName,
    required this.accountNumber,
    required this.accountHolder,
  });

  bool get isValid =>
      accountNumber.trim().isNotEmpty && accountHolder.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'bankCode': bankCode,
      'bankShortName': bankShortName,
      'accountNumber': accountNumber,
      'accountHolder': accountHolder,
    };
  }

  factory UserBankInfo.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const UserBankInfo(
        bankCode: 'MB',
        bankShortName: 'MBBank',
        accountNumber: '',
        accountHolder: '',
      );
    }
    return UserBankInfo(
      bankCode: map['bankCode'] as String? ?? 'MB',
      bankShortName: map['bankShortName'] as String? ?? 'MBBank',
      accountNumber: map['accountNumber'] as String? ?? '',
      accountHolder: map['accountHolder'] as String? ?? '',
    );
  }

  /// Tạo link VietQR nhận tiền chuyển khoản về tài khoản này
  String buildReceiveQrUrl({required int amount, String description = 'Thuong no hu Family Hub'}) {
    final cleanDesc = Uri.encodeComponent(description);
    return 'https://qr.sepay.vn/img?bank=$bankShortName&acc=$accountNumber&amount=$amount&des=$cleanDesc&template=qronly';
  }
}

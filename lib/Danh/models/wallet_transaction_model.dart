import 'package:cloud_firestore/cloud_firestore.dart';

enum WalletTransactionType {
  contribute, // Nạp tiền vào quỹ hũ (+)
  prize,      // Trúng thưởng nổ hũ (+)
  withdraw,   // Rút tiền thưởng về ngân hàng (-)
}

/// Model lưu lịch sử biến động số dư Quỹ Hũ & Ví gia đình
/// Phân vùng độc lập theo từng gia đình (Family Scoping)
class WalletTransactionModel {
  final String id;
  final String familyId;
  final String userId;
  final String userName;
  final WalletTransactionType type;
  final int amount; // Số tiền (luôn là số nguyên dương)
  final String title;
  final String? description;
  final String? bankShortName;
  final String? accountNumber;
  final DateTime createdAt;

  const WalletTransactionModel({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.userName,
    required this.type,
    required this.amount,
    required this.title,
    this.description,
    this.bankShortName,
    this.accountNumber,
    required this.createdAt,
  });

  bool get isPositive =>
      type == WalletTransactionType.contribute || type == WalletTransactionType.prize;

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'userId': userId,
      'userName': userName,
      'type': type.name,
      'amount': amount,
      'title': title,
      if (description != null) 'description': description,
      if (bankShortName != null) 'bankShortName': bankShortName,
      if (accountNumber != null) 'accountNumber': accountNumber,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory WalletTransactionModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime parsedTime = DateTime.now();
    final rawCreated = map['createdAt'];
    if (rawCreated is Timestamp) {
      parsedTime = rawCreated.toDate();
    } else if (rawCreated is String) {
      parsedTime = DateTime.tryParse(rawCreated) ?? DateTime.now();
    }

    final rawType = map['type']?.toString() ?? 'contribute';
    WalletTransactionType txType = WalletTransactionType.contribute;
    if (rawType == 'withdraw') {
      txType = WalletTransactionType.withdraw;
    } else if (rawType == 'prize') {
      txType = WalletTransactionType.prize;
    }

    return WalletTransactionModel(
      id: id,
      familyId: map['familyId']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      userName: map['userName']?.toString() ?? 'Thành viên',
      type: txType,
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      title: map['title']?.toString() ?? 'Giao dịch ví',
      description: map['description']?.toString(),
      bankShortName: map['bankShortName']?.toString(),
      accountNumber: map['accountNumber']?.toString(),
      createdAt: parsedTime,
    );
  }
}

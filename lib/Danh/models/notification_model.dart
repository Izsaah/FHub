import 'package:cloud_firestore/cloud_firestore.dart';

/// Loại thông báo trong hệ thống gia đình
enum NotificationType {
  jackpotDeposit,
  jackpotShake,
  jackpotWin,
  walletWithdraw,
  system,
}

/// Model Thông báo trong In-app Notification Hub của Gia đình (Module 6 & Module 7)
/// Hỗ trợ song ngữ (Tiếng Việt & Tiếng Anh) và lưu trữ tự động 15 ngày trên Firestore (families/{familyId}/notifications)
class NotificationModel {
  final String id;
  final String familyId;
  final String targetUserId; // 'ALL' hoặc userId cụ thể
  final String title;
  final String? titleEn;
  final String body;
  final String? bodyEn;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const NotificationModel({
    required this.id,
    required this.familyId,
    this.targetUserId = 'ALL',
    required this.title,
    this.titleEn,
    required this.body,
    this.bodyEn,
    required this.type,
    this.isRead = false,
    required this.createdAt,
    this.metadata,
  });

  /// Trả về Tiêu đề hiển thị theo ngôn ngữ hiện tại (Tiếng Anh hoặc Tiếng Việt)
  String localizedTitle(bool isEnglish) {
    if (isEnglish) {
      if (titleEn != null && titleEn!.isNotEmpty) return titleEn!;
      // Fallback Tiếng Anh tự động theo loại thông báo nếu chưa có bản dịch
      switch (type) {
        case 'jackpotDeposit':
        case 'jackpot_deposit':
          return 'New Family Pot Deposit';
        case 'jackpotShake':
        case 'jackpot_shake':
          return '30s Pot Shake Battle Has Started!';
        case 'jackpotWin':
        case 'jackpot_win':
          return 'Congratulations on Winning Pot Prize!';
        case 'walletWithdraw':
        case 'wallet_withdraw':
          return 'Bank Withdrawal Request';
        default:
          return title;
      }
    }
    return title;
  }

  /// Trả về Nội dung hiển thị theo ngôn ngữ hiện tại (Tiếng Anh hoặc Tiếng Việt)
  String localizedBody(bool isEnglish) {
    if (isEnglish && bodyEn != null && bodyEn!.isNotEmpty) {
      return bodyEn!;
    }
    return body;
  }

  NotificationModel copyWith({
    String? id,
    String? familyId,
    String? targetUserId,
    String? title,
    String? titleEn,
    String? body,
    String? bodyEn,
    String? type,
    bool? isRead,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      targetUserId: targetUserId ?? this.targetUserId,
      title: title ?? this.title,
      titleEn: titleEn ?? this.titleEn,
      body: body ?? this.body,
      bodyEn: bodyEn ?? this.bodyEn,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'familyId': familyId,
      'targetUserId': targetUserId,
      'title': title,
      if (titleEn != null) 'titleEn': titleEn,
      'body': body,
      if (bodyEn != null) 'bodyEn': bodyEn,
      'type': type,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory NotificationModel.fromMap(String docId, Map<String, dynamic> map) {
    DateTime created;
    final rawCreated = map['createdAt'];
    if (rawCreated is Timestamp) {
      created = rawCreated.toDate();
    } else if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else {
      created = DateTime.now();
    }

    return NotificationModel(
      id: docId,
      familyId: (map['familyId'] ?? map['family_id'] ?? '').toString(),
      targetUserId: (map['targetUserId'] ?? map['target_user_id'] ?? 'ALL').toString(),
      title: (map['title'] ?? 'Thông báo mới').toString(),
      titleEn: map['titleEn']?.toString(),
      body: (map['body'] ?? '').toString(),
      bodyEn: map['bodyEn']?.toString(),
      type: (map['type'] ?? 'system').toString(),
      isRead: map['isRead'] == true,
      createdAt: created,
      metadata: map['metadata'] is Map ? Map<String, dynamic>.from(map['metadata'] as Map) : null,
    );
  }
}

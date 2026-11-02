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
/// Lưu trữ tự động 15 ngày trên Firestore (families/{familyId}/notifications)
class NotificationModel {
  final String id;
  final String familyId;
  final String targetUserId; // 'ALL' hoặc userId cụ thể
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const NotificationModel({
    required this.id,
    required this.familyId,
    this.targetUserId = 'ALL',
    required this.title,
    required this.body,
    required this.type,
    this.isRead = false,
    required this.createdAt,
    this.metadata,
  });

  NotificationModel copyWith({
    String? id,
    String? familyId,
    String? targetUserId,
    String? title,
    String? body,
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
      body: body ?? this.body,
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
      'body': body,
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
      body: (map['body'] ?? '').toString(),
      type: (map['type'] ?? 'system').toString(),
      isRead: map['isRead'] == true,
      createdAt: created,
      metadata: map['metadata'] is Map ? Map<String, dynamic>.from(map['metadata'] as Map) : null,
    );
  }
}

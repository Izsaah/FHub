import 'package:cloud_firestore/cloud_firestore.dart';

/// Đại diện cho một phiên trò chuyện (Cuộc trò chuyện) với Trợ lý AI Gia đình
/// Hỗ trợ quản lý đa phiên (như ChatGPT / Claude / Gemini trên Web)
/// Tự động dọn dẹp sau 15 ngày để tối ưu cơ sở dữ liệu.
class AiChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastMessage;

  const AiChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage = '',
  });

  AiChatSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastMessage,
  }) {
    return AiChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'lastMessage': lastMessage,
    };
  }

  factory AiChatSession.fromMap(String docId, Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return AiChatSession(
      id: docId,
      title: (map['title'] ?? 'Cuộc trò chuyện mới').toString(),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      lastMessage: (map['lastMessage'] ?? '').toString(),
    );
  }
}

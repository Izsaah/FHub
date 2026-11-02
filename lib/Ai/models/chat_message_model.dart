import 'package:cloud_firestore/cloud_firestore.dart';
import '../../Vinh/models/reminder_model.dart';

enum ChatSender { user, ai, system }

/// Đại diện cho một tin nhắn trong khung Chatbot AI Gia đình
/// Hỗ trợ lưu trữ tự động trong 15 ngày trên Firestore (private per user per family)
class ChatMessageModel {
  final String id;
  final String text;
  final ChatSender sender;
  final DateTime timestamp;
  final ReminderModel? createdTask;
  final String? savedMemorySummary;
  final bool isError;

  const ChatMessageModel({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.createdTask,
    this.savedMemorySummary,
    this.isError = false,
  });

  bool get isUser => sender == ChatSender.user;
  bool get hasTaskCard => createdTask != null;
  bool get hasMemoryBadge => savedMemorySummary != null && savedMemorySummary!.isNotEmpty;

  ChatMessageModel copyWith({
    String? id,
    String? text,
    ChatSender? sender,
    DateTime? timestamp,
    ReminderModel? createdTask,
    String? savedMemorySummary,
    bool? isError,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      text: text ?? this.text,
      sender: sender ?? this.sender,
      timestamp: timestamp ?? this.timestamp,
      createdTask: createdTask ?? this.createdTask,
      savedMemorySummary: savedMemorySummary ?? this.savedMemorySummary,
      isError: isError ?? this.isError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'sender': sender.name,
      'timestamp': Timestamp.fromDate(timestamp),
      if (createdTask != null) 'createdTask': createdTask!.toMap(),
      if (savedMemorySummary != null) 'savedMemorySummary': savedMemorySummary,
      'isError': isError,
    };
  }

  factory ChatMessageModel.fromMap(String docId, Map<String, dynamic> map) {
    DateTime ts;
    final rawTs = map['timestamp'];
    if (rawTs is Timestamp) {
      ts = rawTs.toDate();
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    ChatSender s = ChatSender.ai;
    final rawSender = map['sender']?.toString();
    if (rawSender == 'user') {
      s = ChatSender.user;
    } else if (rawSender == 'system') {
      s = ChatSender.system;
    }

    ReminderModel? task;
    if (map['createdTask'] is Map) {
      final tMap = Map<String, dynamic>.from(map['createdTask'] as Map);
      task = ReminderModel.fromMap(tMap['id']?.toString() ?? '', tMap);
    }

    return ChatMessageModel(
      id: docId,
      text: (map['text'] ?? '').toString(),
      sender: s,
      timestamp: ts,
      createdTask: task,
      savedMemorySummary: map['savedMemorySummary']?.toString(),
      isError: map['isError'] == true,
    );
  }
}

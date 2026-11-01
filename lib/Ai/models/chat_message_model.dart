import '../../Vinh/models/reminder_model.dart';

enum ChatSender { user, ai, system }

/// Đại diện cho một tin nhắn trong khung Chatbot AI Gia đình
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
}

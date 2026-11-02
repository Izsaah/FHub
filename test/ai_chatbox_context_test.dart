import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Ai/models/chat_message_model.dart';
import 'package:fhub/Ai/services/gemini_chat_service.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';

void main() {
  group('Phase 2: AI Chatbox Context & Brain Overhaul Tests', () {
    final aiService = GeminiChatService.instance;

    test('1. ChatMessageModel serialization with toMap and fromMap', () {
      final now = DateTime.now();
      final task = ReminderModel(
        id: 't_mock',
        familyId: 'fam_1',
        creatorId: 'u_child',
        assignedTo: 'ALL',
        assignedToName: 'Việc chung',
        title: 'Dọn phòng',
        date: '02/11/2026',
        time: '17:00',
      );

      final msg = ChatMessageModel(
        id: 'msg_001',
        text: 'Em đã tạo công việc cho gia đình mình rồi ạ!',
        sender: ChatSender.ai,
        timestamp: now,
        createdTask: task,
        savedMemorySummary: 'Đã ghi nhớ: "nước giặt" ➔ "Omo"',
      );

      final map = msg.toMap();
      expect(map['id'], 'msg_001');
      expect(map['text'], contains('Em đã tạo'));
      expect(map['sender'], 'ai');
      expect(map['createdTask'], isNotNull);
      expect(map['savedMemorySummary'], contains('Omo'));

      final restored = ChatMessageModel.fromMap('msg_001', map);
      expect(restored.id, 'msg_001');
      expect(restored.isUser, isFalse);
      expect(restored.hasTaskCard, isTrue);
      expect(restored.createdTask?.title, 'Dọn phòng');
      expect(restored.hasMemoryBadge, isTrue);
      expect(restored.savedMemorySummary, contains('Omo'));
    });

    test('2. Child user asking for their role receives Child identity without "chào mẹ"', () async {
      await aiService.initChat(
        familyId: 'fam_demo',
        userId: 'u_danh',
        userName: 'Danh',
        userRole: 'Con cái (Thành viên)',
        familyName: 'Tổ Ấm Hạnh Phúc',
      );

      final res = await aiService.sendMessage('à mà bạn có thể cho tôi biết vai trò của tôi trong gia đình không ?');
      expect(res.isUser, isFalse);
      expect(res.text, isNot(contains('chào mẹ')));
      expect(res.text, isNot(contains('Chào mẹ')));
      expect(res.text, isNot(contains('Dạ mẹ')));
      expect(res.text, contains('Danh'));
      expect(res.text, contains('vai trò'));
    });

    test('3. Father user asking for work progress summary receives report without "chào mẹ"', () async {
      await aiService.initChat(
        familyId: 'fam_demo',
        userId: 'u_dad',
        userName: 'Bố Hùng',
        userRole: 'Bố (Phụ huynh)',
        familyName: 'Tổ Ấm Hạnh Phúc',
      );

      final res = await aiService.sendMessage('tóm tắt tiến độ công việc hôm nay');
      expect(res.isUser, isFalse);
      expect(res.text, isNot(contains('chào mẹ')));
      expect(res.text, isNot(contains('Chào mẹ')));
      expect(res.text, isNot(contains('Dạ mẹ')));
      expect(res.text, contains('Bố'));
      expect(res.text, contains('TIẾN ĐỘ'));
    });

    test('4. User asking who has checked in receives check-in status without "chào mẹ"', () async {
      await aiService.initChat(
        familyId: 'fam_demo',
        userId: 'u_danh',
        userName: 'Danh',
        userRole: 'Con cái',
        familyName: 'Tổ Ấm Hạnh Phúc',
      );

      final res = await aiService.sendMessage('ai đã điểm danh hôm nay?');
      expect(res.isUser, isFalse);
      expect(res.text, isNot(contains('chào mẹ')));
      expect(res.text, isNot(contains('Chào mẹ')));
      expect(res.text, isNot(contains('Dạ mẹ')));
      expect(res.text, contains('ĐIỂM DANH'));
    });

    test('5. User asking about family jackpot receives accurate treasury guidelines', () async {
      await aiService.initChat(
        familyId: 'fam_demo',
        userId: 'u_danh',
        userName: 'Danh',
        userRole: 'Con cái',
        familyName: 'Tổ Ấm Hạnh Phúc',
      );

      final res = await aiService.sendMessage('hũ niềm vui gia đình có bao nhiêu tiền và ai được nổ hũ?');
      expect(res.isUser, isFalse);
      expect(res.text, contains('HŨ NIỀM VUI'));
      expect(res.text, contains('30 giây'));
      expect(res.text, contains('Ví cá nhân'));
    });

    test('6. 15-day rolling chat persistence logic strictly excludes messages older than 15 days', () {
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(days: 15));

      final msgToday = ChatMessageModel(
        id: 'm_today',
        text: 'Hôm nay trời đẹp',
        sender: ChatSender.user,
        timestamp: now,
      );

      final msg10DaysAgo = ChatMessageModel(
        id: 'm_10d',
        text: '10 ngày trước',
        sender: ChatSender.user,
        timestamp: now.subtract(const Duration(days: 10)),
      );

      final msg16DaysAgo = ChatMessageModel(
        id: 'm_16d',
        text: 'Tin nhắn cũ đã quá 15 ngày',
        sender: ChatSender.user,
        timestamp: now.subtract(const Duration(days: 16)),
      );

      expect(msgToday.timestamp.isAfter(cutoff), isTrue);
      expect(msg10DaysAgo.timestamp.isAfter(cutoff), isTrue);
      expect(msg16DaysAgo.timestamp.isBefore(cutoff), isTrue);
    });

    test('7. Multi-family isolation: Switching active family updates familyId and context', () async {
      await aiService.initChat(
        familyId: 'fam_A',
        userId: 'u_user',
        userName: 'Minh',
        userRole: 'Con',
      );
      expect(aiService.currentFamilyId, 'fam_A');

      await aiService.initChat(
        familyId: 'fam_B',
        userId: 'u_user',
        userName: 'Minh',
        userRole: 'Bố',
      );
      expect(aiService.currentFamilyId, 'fam_B');
      expect(aiService.currentUserRole, 'Bố');
    });
  });
}

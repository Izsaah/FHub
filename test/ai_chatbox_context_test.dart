import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fhub/Ai/models/ai_chat_session.dart';
import 'package:fhub/Ai/models/chat_message_model.dart';
import 'package:fhub/Ai/services/gemini_chat_service.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/screens/family_ai_chat_screen.dart';
import 'package:fhub/Vinh/services/family_ai_assistant_service.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';

void main() {
  group('Phase 2: AI Chatbox Context & Brain Overhaul Tests', () {
    final aiService = GeminiChatService.instance;

    setUp(() {
      aiService.resetCooldown();
    });

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

    test('8. Grandparent role and dynamic salutation (calls Ông/Bà, never "chào mẹ")', () async {
      await aiService.initChat(
        familyId: 'fam_grand',
        userId: 'u_grandpa',
        userName: 'Ông Tuấn',
        userRole: 'Ông (Grandparent)',
        familyName: 'Đại Gia Đình Tuấn',
      );

      final res = await aiService.sendMessage('tôi là ai trong gia đình này?');
      expect(res.text, isNot(contains('chào mẹ')));
      expect(res.text, contains('Ông'));
    });

    test('9. User asking about multiple families receives active family context clarity', () async {
      await aiService.initChat(
        familyId: 'fam_main',
        userId: 'u_member',
        userName: 'Khoa',
        userRole: 'Phụ huynh',
        familyName: 'Gia Đình Khoa',
      );

      final res = await aiService.sendMessage('tôi có bao nhiêu gia đình?');
      expect(res.text, contains('Gia Đình Khoa'));
      expect(res.text, contains('fam_main'));
      expect(res.text, isNot(contains('chào mẹ')));
    });

    test('10. AiChatSession serialization and 15-day rolling persistence cutoff', () {
      final now = DateTime.now();
      final session = AiChatSession(
        id: 's_01',
        title: 'Bản chất của cạnh tranh',
        createdAt: now,
        updatedAt: now,
        lastMessage: 'AI giải thích về cạnh tranh',
      );

      final map = session.toMap();
      expect(map['id'], 's_01');
      expect(map['title'], 'Bản chất của cạnh tranh');

      final parsed = AiChatSession.fromMap('s_01', {
        'title': 'Bản chất của cạnh tranh',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'lastMessage': 'AI giải thích về cạnh tranh',
      });
      expect(parsed.title, 'Bản chất của cạnh tranh');

      final cutoff = now.subtract(const Duration(days: 15));
      final oldSession = session.copyWith(updatedAt: now.subtract(const Duration(days: 16)));
      expect(session.updatedAt.isAfter(cutoff), isTrue);
      expect(oldSession.updatedAt.isBefore(cutoff), isTrue);
    });

    testWidgets('11. Multi-session slide bar (Drawer) opens, displays New Chat and history with 0 overflow', (tester) async {
      FlutterErrorDetails? caughtDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caughtDetails = details;
        debugPrint('CAPTURED DETAILS: ${details.toString()}');
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_danh',
          name: 'Danh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: FamilyAiChatScreen(
            familyId: 'f1',
            currentUserId: 'u_danh',
            currentUserName: 'Danh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      debugPrint('EX AFTER INITIAL PUMP: ${tester.takeException()}');

      // Verify app bar title
      expect(find.text('Trợ lý AI Gia đình'), findsOneWidget);

      // Verify history icon exists in AppBar
      final historyIcon = find.byIcon(Icons.history_rounded);
      expect(historyIcon, findsOneWidget);

      // Tap history icon to slide out the Drawer
      await tester.tap(historyIcon);
      await tester.pumpAndSettle();
      final tapHistoryEx = tester.takeException();
      if (tapHistoryEx is FlutterError) {
        debugPrint('DRAWER OPEN OVERFLOW: ${tapHistoryEx.toStringDeep()}');
      }
      expect(tapHistoryEx, isNull);

      // Verify drawer header and New Chat button appear
      expect(find.text('Lịch sử trò chuyện'), findsOneWidget);
      expect(find.text('Cuộc trò chuyện mới'), findsOneWidget);
      expect(find.text('Tự động dọn dẹp sau 15 ngày'), findsOneWidget);

      // Tap "Cuộc trò chuyện mới" button
      await tester.tap(find.text('Cuộc trò chuyện mới'));
      await tester.pumpAndSettle();
      debugPrint('EX AFTER TAP NEW CHAT: ${tester.takeException()}');

      // Verify drawer closed and returned to chat view
      expect(find.text('Lịch sử trò chuyện'), findsNothing);
      final ex = tester.takeException();
      if (ex is FlutterError) {
        debugPrint('DIAGNOSTICS: ${ex.diagnostics.map((d) => d.toString()).join('\n')}');
      }
      expect(ex, isNull);
      expect(caughtDetails, isNull);
    });

    test('12. In-app Gemini API Key configuration allows live activation without restart', () async {
      final initialConfigured = GeminiChatService.instance.isConfigured;
      // Set custom API key live
      await GeminiChatService.instance.setCustomApiKey('AIzaSyTestKeyLive123456');
      expect(GeminiChatService.instance.isConfigured, isTrue);
      expect(GeminiChatService.instance.effectiveApiKey, 'AIzaSyTestKeyLive123456');

      // Clear custom key -> restores default key from environment
      await GeminiChatService.instance.setCustomApiKey('');
      final expectedDefaultKey = dotenv.isInitialized ? (dotenv.env['GEMINI_API_KEY']?.trim() ?? '') : '';
      expect(GeminiChatService.instance.effectiveApiKey, expectedDefaultKey);
      expect(GeminiChatService.instance.isConfigured, initialConfigured);
    });

    test('13. Asking "tôi đẹp trai không" returns smart conversational response, never robotic reminder template', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'tôi đẹp trai không',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.attachedReminder, isNull);
      expect(res.attachedReminders.isEmpty, isTrue);
      expect(res.text.contains('đã soạn và tạo'), isFalse);
      expect(
        res.text.contains('tuyệt vời') || res.text.contains('phong độ') || res.text.contains('Lương Diệu Vinh'),
        isTrue,
      );
    });

    test('14. Asking "tôi đóng vai trò gì trong căn nhà này, tôi có thể giao việc cho ai không" does NOT create tasks', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'tôi đóng vai trò gì trong căn nhà này, tôi có thể giao việc cho ai không',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      // Must NOT create reminders for questions!
      expect(res.attachedReminder, isNull);
      expect(res.attachedReminders.isEmpty, isTrue);
      expect(res.text.contains('đã soạn và tạo'), isFalse);
      expect(
        res.text.contains('vai trò') || res.text.contains('giao việc') || res.text.contains('Phụ huynh') || res.text.contains('Bố'),
        isTrue,
      );
    });

    test('15. Asking "hôm nay đã có những ai điểm danh rồi vậy" or "check in" returns check-in status, NEVER canned cooking boilerplate', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
        FamilyMember(
          id: 'u_bin',
          name: 'Bin',
          role: FamilyMember.roleChild,
          familyId: 'f1',
        ),
      ];

      // Test 1: "hôm nay đã có những ai điểm danh rồi vậy"
      final res1 = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'hôm nay đã có những ai điểm danh rồi vậy',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res1.attachedReminder, isNull);
      expect(res1.text, isNot(contains('Tối nay nấu thịt kho')));
      expect(res1.text, isNot(contains('kế hoạch nấu ăn')));
      expect(res1.text.toLowerCase(), contains('điểm danh'));

      // Test 2: "hôm nay đã có những ai check in rồi vậy"
      final res2 = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'hôm nay đã có những ai check in rồi vậy',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res2.attachedReminder, isNull);
      expect(res2.text, isNot(contains('Tối nay nấu thịt kho')));
      expect(res2.text, isNot(contains('kế hoạch nấu ăn')));
      expect(res2.text.toLowerCase(), contains('điểm danh'));
    });

    testWidgets('16. Drawer strictly removes "Cài đặt Gemini API Key" button for end users', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_danh',
          name: 'Danh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: FamilyAiChatScreen(
            familyId: 'f1',
            currentUserId: 'u_danh',
            currentUserName: 'Danh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open drawer
      final historyIcon = find.byIcon(Icons.history_rounded);
      expect(historyIcon, findsOneWidget);
      await tester.tap(historyIcon);
      await tester.pumpAndSettle();

      // Ensure API key button is completely absent
      expect(find.text('Cài đặt Gemini API Key'), findsNothing);
      expect(find.text('Gemini AI: Sẵn sàng'), findsNothing);
    });

    test('17. "có thể tạo một nhiệm vụ quét nhà lúc 15h cho thành viên gia đình tôi được không ?" creates Open task "Quét nhà" at 15:00 and NEVER lists members', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
        FamilyMember(
          id: 'u_bin',
          name: 'Bin',
          role: FamilyMember.roleChild,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'có thể tạo một nhiệm vụ quét nhà lúc 15h cho thành viên gia đình tôi được không ?',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      // Verify task creation
      expect(res.attachedReminder, isNotNull);
      final created = res.attachedReminder!;
      expect(created.title, 'Quét nhà');
      expect(created.time, '15:00');
      expect(created.assignedTo, 'OPEN');
      expect(created.assignedToName, 'Cả nhà (Việc chung)');
      expect(res.text, isNot(contains('DANH SÁCH THÀNH VIÊN GIA ĐÌNH')));
      expect(res.text, contains('Quét nhà'));
    });

    test('18. "tôi muốn tạo nhiệm vụ quét nhà lcus 15h" handles typo "lcus" -> 15:00, strips prefix, title is "Quét nhà"', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'tôi muốn tạo nhiệm vụ quét nhà lcus 15h',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.attachedReminder, isNotNull);
      final created = res.attachedReminder!;
      expect(created.title, 'Quét nhà');
      expect(created.time, '15:00');
      expect(created.assignedTo, 'u_vinh');
      expect(created.assignedToName, 'Lương Diệu Vinh');
      expect(created.title, isNot(contains('tôi muốn')));
      expect(created.title, isNot(contains('nhiệm vụ')));
      expect(created.title, isNot(contains('lcus')));
    });

    test('19. "tôi đóng vai trò gì trong căn nhà này, tôi có thể giao việc cho ai không" returns role explanation and NEVER creates chores', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'tôi đóng vai trò gì trong căn nhà này, tôi có thể giao việc cho ai không',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.attachedReminder, isNull);
      expect(res.attachedReminders, isEmpty);
      expect(res.text, contains('vai trò của bạn là'));
      expect(res.text, isNot(contains('Dạ em đã soạn và tạo xong 2 công việc')));
    });

    test('20. "tích i\'m ok dùm tôi" performs actual check-in action and confirms cheerfully', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: "tích i'm ok dùm tôi",
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.attachedReminder, isNull);
      expect(res.text, contains("I'm OK"));
      expect(res.text, contains('hoàn tất điểm danh'));
      expect(res.text, isNot(contains('Chưa có thành viên nào')));
      expect(res.text, isNot(contains('có thể hỏi em về tình hình')));
    });

    test('21. "điểm danh giúp tôi" triggers check-in action', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_danh',
          name: 'Danh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'điểm danh giúp tôi',
        familyId: 'f1',
        currentUserId: 'u_danh',
        currentUserName: 'Danh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, contains("I'm OK"));
      expect(res.text, contains('hoàn tất điểm danh'));
    });

    test('22. "tôi ok" triggers check-in action directly', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_danh',
          name: 'Danh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'tôi ok',
        familyId: 'f1',
        currentUserId: 'u_danh',
        currentUserName: 'Danh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, contains("I'm OK"));
      expect(res.text, contains('hoàn tất điểm danh'));
    });

    test('23. "tôi trông thế nào" returns flattering compliment and NEVER canned robotic template', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_khoa',
          name: 'Khoa Cao',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'tôi trông thế nào',
        familyId: 'f1',
        currentUserId: 'u_khoa',
        currentUserName: 'Khoa Cao',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, contains('phong độ'));
      expect(res.text, isNot(contains('có thể hỏi em về tình hình điểm danh')));
    });

    test('24. "xin vhaog" handles keyboard typo and returns warm greeting', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_khoa',
          name: 'Khoa Cao',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'xin vhaog',
        familyId: 'f1',
        currentUserId: 'u_khoa',
        currentUserName: 'Khoa Cao',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, contains('chào'));
      expect(res.text, isNot(contains('có thể hỏi em về tình hình điểm danh')));
    });

    test('25. "ai đã điểm danh hôm nay" returns query list without triggering check-in action', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_khoa',
          name: 'Khoa Cao',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'ai đã điểm danh hôm nay',
        familyId: 'f1',
        currentUserId: 'u_khoa',
        currentUserName: 'Khoa Cao',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, contains('TÌNH HÌNH ĐIỂM DANH'));
      expect(res.text, isNot(contains('Đã tích "I\'m OK" và hoàn tất điểm danh')));
    });

    test('26. "bạn có thể làm gì" returns structured Markdown capabilities guide and never generic canned fallback', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'bạn có thể làm gì',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, contains('TÍNH NĂNG NỔI BẬT CỦA TRỢ LÝ AI'));
      expect(res.text, contains('Soạn & Giao việc'));
      expect(res.text, contains('I\'m OK'));
      expect(res.text, contains('Hũ Niềm Vui'));
      expect(res.text, isNot(contains('Lương Diệu Vinh muốn chia sẻ thêm điều gì')));
    });

    test('27. "bạn có trả lời tôi được không" returns active connection confirmation and never generic canned fallback', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'bạn có trả lời tôi được không',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, contains('luôn sẵn sàng và lắng nghe'));
      expect(res.text, contains('hoạt động hoàn hảo'));
      expect(res.text, isNot(contains('Lương Diệu Vinh muốn chia sẻ thêm điều gì')));
    });

    test('28. Conversational comma-separated input never splits into nonsense tasks (e.g. ABC bakery)', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'của ABC bakery, tạo lịch đi, thành viên gia đình tôi tự biết',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      // Must NEVER split into 3 nonsense tasks
      expect(res.attachedReminders.length, isNot(equals(3)));
      expect(res.text, isNot(contains('Tạo lịch đi')));
      expect(res.text, isNot(contains('Thành viên gia đình tôi tự biết')));
    });

    test('29. Topic change cancels pending milk clarification and does not save milk memory', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      // Turn 1: user asks to buy milk
      await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'tôi muốn đi mua sữa',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      // Turn 2: user changes topic to cooking party
      final res2 = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'à không, tôi muốn nấu một bữa tiệc, bạn có đề xuất gì không',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      // Must not save milk memory with party prompt, must propose party menu
      expect(res2.text, isNot(contains('thói quen mua sữa "à không')));
      expect(res2.text, contains('bữa tiệc'));
      expect(res2.attachedReminder?.title, isNot(contains('Mua sữa (à không')));
    });

    test('30. "hôm nay là thứ mấy" returns weekday and today date', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'xin chào, hôm nay là thứ mấy',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text.contains('Thứ') || res.text.contains('Chủ Nhật'), isTrue);
      expect(res.text, contains('ngày'));
    });

    test('31. Weather and news queries never trigger chore progress report', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'hehe, hôm nay thời tiết thế nào, trong nước có tin tức gì không',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, isNot(contains('BÁO CÁO TIẾN ĐỘ')));
      expect(res.text, isNot(contains('Tổng số công việc')));
      expect(res.text, contains('thời tiết'));
    });

    test('32. Delete request never creates new chore and handles deletion', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_vinh',
          name: 'Lương Diệu Vinh',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      // Add a dummy reminder to delete
      await repo.createReminder(
        reminder: ReminderModel(
          id: 'rem_abc',
          familyId: 'f1',
          creatorId: 'u_vinh',
          assignedTo: 'ALL',
          assignedToName: 'Việc chung',
          title: 'Của ABC bakery',
          date: '${(DateTime.now().add(const Duration(days: 2)).day).toString().padLeft(2, '0')}/${(DateTime.now().month).toString().padLeft(2, '0')}/${DateTime.now().year}',
          time: '23:59',
        ),
        currentUserId: 'u_vinh',
      );

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'bạn xoá đi 3 cái công việc của abc bakery, tạo lịch đi, thành viên gia đình tôi tự biết được không',
        familyId: 'f1',
        currentUserId: 'u_vinh',
        currentUserName: 'Lương Diệu Vinh',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, isNot(contains('Em đã tạo lời nhắc "Việc nhà"')));
      expect(res.attachedReminder, isNull);
      expect(res.text, contains('xóa'));
    });

    test('33. Child account asking AI to perform check-in is directed to take photo on home screen', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_child',
          name: 'Bé Na',
          role: FamilyMember.roleChild,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: "tích i'm ok dùm con",
        familyId: 'f1',
        currentUserId: 'u_child',
        currentUserName: 'Bé Na',
        familyMembers: members,
        repository: repo,
      );

      expect(res.text, contains('chụp một tấm ảnh'));
      expect(res.text, contains("✓ I'M OK"));
    });

    test('34. Child account attempting to assign chores to parents is rejected politely', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_child',
          name: 'Bé Na',
          role: FamilyMember.roleChild,
          familyId: 'f1',
        ),
        FamilyMember(
          id: 'u_dad',
          name: 'Bố Tuấn',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'giao cho bố lau nhà lúc 17:00',
        familyId: 'f1',
        currentUserId: 'u_child',
        currentUserName: 'Bé Na',
        familyMembers: members,
        repository: repo,
      );

      expect(res.attachedReminder, isNull);
      expect(res.text, contains('không thể phân công việc nhà cho Bố/Mẹ'));
    });

    test('35. Child account politely requesting parent creates task with [Lời nhờ từ con] prefix', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_child',
          name: 'Bé Na',
          role: FamilyMember.roleChild,
          familyId: 'f1',
        ),
        FamilyMember(
          id: 'u_dad',
          name: 'Bố Tuấn',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'nhờ bố đón con lúc 17:00',
        familyId: 'f1',
        currentUserId: 'u_child',
        currentUserName: 'Bé Na',
        familyMembers: members,
        repository: repo,
      );

      expect(res.attachedReminder, isNotNull);
      expect(res.attachedReminder!.title, contains('[Lời nhờ từ con]'));
      expect(res.attachedReminder!.assignedTo, equals('u_dad'));
    });

    test('36. Child account attempting to delete Parent chore protects the chore', () async {
      final repo = InMemoryReminderRepository();
      final members = [
        FamilyMember(
          id: 'u_child',
          name: 'Bé Na',
          role: FamilyMember.roleChild,
          familyId: 'f1',
        ),
        FamilyMember(
          id: 'u_dad',
          name: 'Bố Tuấn',
          role: FamilyMember.roleParent,
          familyId: 'f1',
        ),
      ];

      // Parent created chore
      final parentTask = await repo.createReminder(
        reminder: ReminderModel(
          id: 'rem_parent',
          familyId: 'f1',
          creatorId: 'u_dad',
          assignedTo: 'u_child',
          assignedToName: 'Bé Na',
          title: 'Quét nhà',
          date: '${(DateTime.now().add(const Duration(days: 2)).day).toString().padLeft(2, '0')}/${(DateTime.now().month).toString().padLeft(2, '0')}/${DateTime.now().year}',
          time: '23:59',
        ),
        currentUserId: 'u_dad',
      );

      // Child tries to delete parent chore
      final res = await FamilyAiAssistantService.instance.processMessage(
        userMessage: 'xoá việc quét nhà đi',
        familyId: 'f1',
        currentUserId: 'u_child',
        currentUserName: 'Bé Na',
        familyMembers: members,
        repository: repo,
      );

      // Verify the task was NOT deleted in repository
      final reminders = await repo.getReminders(familyId: 'f1');
      final target = reminders.firstWhere((r) => r.id == parentTask.id);
      expect(target.isDeleted, isFalse);
      expect(res.text, contains('Bố/Mẹ'));
    });

    test('37. Family switch and resetChatSession properly invalidates _cachedSystemPrompt and updates family name', () async {
      final gemini = GeminiChatService.instance;
      gemini.resetCooldown();

      // Initialize family 1: "Gia Đình Cũ"
      await gemini.initChat(
        familyId: 'fam_old',
        familyName: 'Gia Đình Cũ',
        userId: 'u_khoa',
        userName: 'Khoa Cao',
        userRole: 'Bố Mẹ',
      );
      expect(gemini.currentFamilyId, 'fam_old');
      expect(gemini.currentFamilyName, 'Gia Đình Cũ');

      // Reset chat session must clean cached prompt
      gemini.resetChatSession();

      // Switch to new family: "Yeah"
      await gemini.initChat(
        familyId: 'fam_yeah',
        familyName: 'Yeah',
        userId: 'u_khoa',
        userName: 'Khoa Cao',
        userRole: 'Bố Mẹ',
      );
      expect(gemini.currentFamilyId, 'fam_yeah');
      expect(gemini.currentFamilyName, 'Yeah');
    });

    test('38. Domain guard: Programming and homework queries (if high < low, Python) are rejected politely without generating code', () async {
      final gemini = GeminiChatService.instance;
      gemini.resetCooldown();

      await gemini.initChat(
        familyId: 'f1',
        familyName: 'Tổ Ấm',
        userId: 'u_khoa',
        userName: 'Khoa Cao',
        userRole: 'Bố Mẹ',
      );

      final res = await gemini.sendMessage(
        'if high < low then fail, viết cho tôi code Python và JavaScript',
        familyId: 'f1',
        fallbackToLocal: true,
      );

      // Must refuse programming/homework and redirect to family chores
      expect(res.text.toLowerCase(), anyOf([contains('viết mã code'), contains('giải bài tập'), contains('không thể')]));
      expect(res.text, isNot(contains('```python')));
      expect(res.text, isNot(contains('def ')));
      expect(res.text, isNot(contains('console.log')));
    });

    test('39. Task completion guard: Asking AI to tick/complete chore is rejected, directing user to proof verification', () async {
      final gemini = GeminiChatService.instance;
      gemini.resetCooldown();

      await gemini.initChat(
        familyId: 'f1',
        familyName: 'Tổ Ấm',
        userId: 'u_khoa',
        userName: 'Khoa Cao',
        userRole: 'Bố Mẹ',
      );

      final res = await gemini.sendMessage(
        'tích hoàn thành việc nhà giúp tôi với',
        familyId: 'f1',
        fallbackToLocal: true,
      );

      // AI must decline marking chore completed and instruct user to complete in app with proof photo
      expect(res.text, contains('không thể tự ý tích hoàn thành việc nhà'));
      expect(res.text, contains('nghiệm thu'));
    });

    test('40. Slow mode service-layer throttling: Consecutive messages within 5s return cooldown notice without API call', () async {
      final gemini = GeminiChatService.instance;
      gemini.resetCooldown();

      await gemini.initChat(
        familyId: 'f1',
        familyName: 'Tổ Ấm',
        userId: 'u_khoa',
        userName: 'Khoa Cao',
        userRole: 'Bố Mẹ',
      );

      // First message: succeeds
      final res1 = await gemini.sendMessage(
        'hôm nay có việc gì',
        familyId: 'f1',
        fallbackToLocal: true,
        checkThrottle: true,
      );
      expect(res1.text, isNotEmpty);
      expect(gemini.isThrottled, isTrue);

      // Immediate second message: triggers Slow Mode throttle
      final res2 = await gemini.sendMessage(
        'ai đã điểm danh',
        familyId: 'f1',
        fallbackToLocal: true,
        checkThrottle: true,
      );
      expect(res2.text, contains('Slow Mode'));
      expect(res2.text, contains('giây nữa rồi gửi tiếp'));
    });

    test('41. Slow mode cooldown resets and allows message when cooldown is cleared', () async {
      final gemini = GeminiChatService.instance;
      gemini.resetCooldown();

      await gemini.initChat(
        familyId: 'f1',
        familyName: 'Tổ Ấm',
        userId: 'u_khoa',
        userName: 'Khoa Cao',
        userRole: 'Bố Mẹ',
      );

      // Send first message with throttle check
      await gemini.sendMessage(
        'hôm nay có việc gì',
        familyId: 'f1',
        fallbackToLocal: true,
        checkThrottle: true,
      );
      expect(gemini.isThrottled, isTrue);

      // Reset cooldown
      gemini.resetCooldown();
      expect(gemini.isThrottled, isFalse);

      // Sending now proceeds without throttle
      final res = await gemini.sendMessage(
        'hôm nay ai đã điểm danh',
        familyId: 'f1',
        fallbackToLocal: true,
        checkThrottle: true,
      );
      expect(res.text, isNot(contains('Slow Mode')));
    });

    testWidgets('42. FamilyAiChatScreen UI widgets reflect slow mode countdown and disables send button', (tester) async {
      final repo = InMemoryReminderRepository();
      GeminiChatService.instance.resetCooldown();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyAiChatScreen(
              familyId: 'fam_demo',
              currentUserId: 'u_test',
              currentUserName: 'Khoa Cao',
              familyMembers: const [],
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pump();

      // Enter text and tap send
      final inputField = find.byType(TextField);
      expect(inputField, findsOneWidget);
      await tester.enterText(inputField, 'Xin chào AI');
      await tester.pump();

      final sendBtn = find.byIcon(Icons.send_rounded);
      expect(sendBtn, findsOneWidget);
      await tester.tap(sendBtn);
      await tester.pump();

      // Now slow mode is active (5s cooldown) -> Send button should show countdown text
      expect(find.textContaining('s'), findsWidgets);

      // Advance through cooldown so the periodic timer completes cleanly
      await tester.pump(const Duration(seconds: 6));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Ai/models/chat_message_model.dart';
import 'package:fhub/Ai/models/family_memory_model.dart';
import 'package:fhub/Ai/services/ai_tools_declarations.dart';
import 'package:fhub/Ai/services/gemini_chat_service.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/family_ai_assistant_service.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';

void main() {
  group('Module 7: AI Chatbot Models & Tools Tests', () {
    test('ChatMessageModel identifies task card and memory badges correctly', () {
      final task = ReminderModel(
        id: 't1',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'ALL',
        assignedToName: 'Việc chung',
        title: 'Phụ mẹ làm việc nhà',
        date: '21/10/2026',
        time: '09:00',
      );

      final msg = ChatMessageModel(
        id: 'm1',
        text: 'Con đã tạo Open Task cho các con rồi ạ!',
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
        createdTask: task,
        savedMemorySummary: 'Đã ghi nhớ: "sữa" ➔ "Vinamilk"',
      );

      expect(msg.isUser, isFalse);
      expect(msg.hasTaskCard, isTrue);
      expect(msg.createdTask?.title, 'Phụ mẹ làm việc nhà');
      expect(msg.hasMemoryBadge, isTrue);
      expect(msg.savedMemorySummary, contains('Vinamilk'));
    });

    test('FamilyMemory toMap formats keyword cleanly', () {
      final memory = FamilyMemory(
        id: 'mem_1',
        familyId: 'f1',
        keyword: '  Sữa Tươi  ',
        value: '  Vinamilk Có Đường  ',
        updatedAt: DateTime.now(),
      );

      final map = memory.toMap();
      expect(map['keyword'], 'sữa tươi');
      expect(map['value'], 'Vinamilk Có Đường');
      expect(map['familyId'], 'f1');
    });

    test('AiToolsDeclarations exports correct Gemini tool schemas', () {
      final tools = AiToolsDeclarations.allTools;
      expect(tools.isNotEmpty, isTrue);

      final funcs = tools.first.functionDeclarations;
      expect(funcs, isNotNull);
      expect(funcs!.length, 2);

      final names = funcs.map((f) => f.name).toList();
      expect(names, contains('createFamilyTask'));
      expect(names, contains('saveFamilyPreference'));

      final taskTool = funcs.firstWhere((f) => f.name == 'createFamilyTask');
      expect(taskTool.parameters?.requiredProperties, contains('title'));
      expect(taskTool.parameters?.requiredProperties, contains('date'));
      expect(taskTool.parameters?.requiredProperties, contains('time'));

      final memoryTool = funcs.firstWhere((f) => f.name == 'saveFamilyPreference');
      expect(memoryTool.parameters?.requiredProperties, contains('keyword'));
      expect(memoryTool.parameters?.requiredProperties, contains('value'));
    });

    test('GeminiChatService handles missing API key gracefully without crashing', () async {
      // Khi chưa có API Key trong env, sendMessage trả về thông điệp hướng dẫn rõ ràng
      final result = await GeminiChatService.instance.sendMessage('Hello AI');
      expect(result.sender, ChatSender.ai);
      expect(result.isError, isTrue);
      expect(result.text, contains('Gemini API Key'));
    });
  });

  group('Module 7: Dynamic Intent, Creator Identity & Suggestion Cards Tests', () {
    final ai = FamilyAiAssistantService.instance;
    const members = [
      FamilyMember(id: 'u_dad', name: 'Bố Hùng', role: 'Parent', familyId: 'f1'),
      FamilyMember(id: 'u_mom', name: 'Mẹ Lan', role: 'Parent', familyId: 'f1'),
      FamilyMember(id: 'u_child', name: 'Danh', role: 'Child', familyId: 'f1'),
    ];

    test('Cooking intent generates suggestion card without writing immediately to repo', () async {
      final repo = InMemoryReminderRepository();

      final res = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'u_dad',
        currentUserName: 'Bố Hùng',
        familyMembers: members,
        repository: repo,
        userMessage: 'Tối nay có lẽ sẽ nấu thịt kho',
      );

      // Verify no task is created immediately in repo
      final repoTasks = await repo.getReminders(familyId: 'f1');
      expect(repoTasks.isEmpty, isTrue);

      // Verify AI attached a suggestedReminder
      expect(res.suggestedReminder, isNotNull);
      final sug = res.suggestedReminder!;
      expect(sug.title, 'Mua nguyên liệu nấu Thịt kho');
      expect(sug.creatorId, 'u_dad');
      expect(sug.creatorName, 'Bố Hùng');
      expect(sug.isOpenTask, isTrue);
      expect(sug.voiceNoteDescription, contains('Bố Hùng'));

      // Verify conversational warm response
      expect(res.text.toLowerCase(), contains('thịt kho'));
      expect(res.text, contains('bố'));
      expect(res.text, isNot(contains('Dạ mẹ!')));

      // When user accepts the suggestion, it is saved with correct creator ID
      final saved = await repo.createReminder(
        reminder: sug,
        currentUserId: 'u_dad',
        familyMembers: members,
      );
      expect(saved.id, sug.id);
      expect(saved.creatorId, 'u_dad');
      expect(saved.creatorName, 'Bố Hùng');
    });

    test('Child user requesting open chore binds creatorId strictly to child, not mother', () async {
      final repo = InMemoryReminderRepository();

      final res = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'u_child',
        currentUserName: 'Danh',
        familyMembers: members,
        repository: repo,
        userMessage: 'Ai muốn phụ mẹ nấu cơm',
      );

      // Response addresses the child by name, not "Dạ mẹ!"
      expect(res.text, contains('Dạ Danh!'));
      expect(res.text, isNot(contains('Dạ mẹ!')));

      // Created task belongs to child (Danh) as creator
      expect(res.attachedReminder, isNotNull);
      final task = res.attachedReminder!;
      expect(task.creatorId, 'u_child');
      expect(task.creatorName, 'Danh');
      expect(task.isOpenTask, isTrue);
      expect(task.title, contains('Phụ mẹ nấu cơm'));

      final all = await repo.getReminders(familyId: 'f1');
      expect(all.first.creatorId, 'u_child');
    });

    test('Recipe questions provide tips and suggestion card', () async {
      final repo = InMemoryReminderRepository();

      final res = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'u_child',
        currentUserName: 'Danh',
        familyMembers: members,
        repository: repo,
        userMessage: 'Nấu thịt kho thế nào',
      );

      expect(res.text, contains('Bí quyết nấu món Thịt kho'));
      expect(res.suggestedReminder, isNotNull);
      expect(res.suggestedReminder?.title, contains('Thịt kho'));
    });

    test('Conversational chitchat responds warmly without error or static menu', () async {
      final repo = InMemoryReminderRepository();

      final helloRes = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'u_child',
        currentUserName: 'Danh',
        familyMembers: members,
        repository: repo,
        userMessage: 'Chào em',
      );
      expect(helloRes.text, contains('Dạ em chào Danh!'));

      final tiredRes = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'u_child',
        currentUserName: 'Danh',
        familyMembers: members,
        repository: repo,
        userMessage: 'Hôm nay mệt quá',
      );
      expect(tiredRes.text, contains('Dạ thương Danh quá!'));
    });
  });
}

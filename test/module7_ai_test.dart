import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Ai/models/chat_message_model.dart';
import 'package:fhub/Ai/models/family_memory_model.dart';
import 'package:fhub/Ai/services/ai_tools_declarations.dart';
import 'package:fhub/Ai/services/gemini_chat_service.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';

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
}

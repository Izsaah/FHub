import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../Vinh/models/reminder_model.dart';
import '../models/chat_message_model.dart';
import 'ai_tools_declarations.dart';
import 'family_memory_service.dart';

/// Dịch vụ Trợ lý AI Gia đình sử dụng Gemini API và Function Calling chính chủ (Module 7)
/// Thiết kế chuẩn Senior: Tự động nhận diện model, tự fallback, không bắt người dùng điền model thủ công
class GeminiChatService {
  GeminiChatService._();
  static final GeminiChatService instance = GeminiChatService._();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  GenerativeModel? _model;
  ChatSession? _chat;

  String _currentFamilyId = 'f1';
  String _currentUserId = '';
  String _currentUserName = 'Bạn';

  String get currentFamilyId => _currentFamilyId;
  String get currentUserName => _currentUserName;

  /// Danh sách các model Gemini tối ưu, tự động thử lần lượt nếu một model bị thay đổi version
  static const List<String> _candidateModels = [
    'gemini-1.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash-latest',
    'gemini-1.5-pro',
  ];

  bool get isConfigured {
    if (!dotenv.isInitialized) return false;
    final key = dotenv.env['GEMINI_API_KEY']?.trim();
    return key != null && key.isNotEmpty;
  }

  /// Khởi tạo phiên trò chuyện với Gemini kèm System Instruction động từ Firestore
  Future<void> initChat({String? familyId}) async {
    if (!dotenv.isInitialized) {
      try {
        await dotenv.load(fileName: ".env");
      } catch (_) {
        try {
          await dotenv.load(fileName: "assets/.env");
        } catch (_) {}
      }
    }
    final apiKey = (dotenv.isInitialized ? dotenv.env['GEMINI_API_KEY'] : null)?.trim() ?? '';
    // Người dùng chỉ cần nhét API Key. Nếu không cấu hình model, tự động chọn gemini-1.5-flash
    final configuredModel = (dotenv.isInitialized ? dotenv.env['GEMINI_MODEL'] : null)?.trim();

    if (apiKey.isEmpty) {
      debugPrint('GeminiChatService: GEMINI_API_KEY is not set in .env');
      return;
    }

    // Xác định thông tin người dùng hiện tại
    final user = _auth.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      _currentUserName = (user.displayName != null && user.displayName!.isNotEmpty)
          ? user.displayName!
          : (user.email?.split('@').first ?? 'Thành viên');

      // Tra cứu tên chuẩn từ collection `users` nếu có
      try {
        final uDoc = await _firestore.collection('users').doc(user.uid).get();
        if (uDoc.exists) {
          final uName = uDoc.data()?['name']?.toString();
          if (uName != null && uName.isNotEmpty) {
            _currentUserName = uName;
          }
        }
      } catch (_) {}
    }

    // Tự động giải quyết familyId nếu chưa có
    if (familyId != null && familyId.isNotEmpty) {
      _currentFamilyId = familyId;
    } else {
      await _autoResolveFamilyId();
    }

    // Xây dựng System Instruction động theo thời gian thực (AC1, AC2, AC3)
    final systemPrompt = await _buildDynamicSystemPrompt();

    // Thử model được cấu hình trước, hoặc tự động lấy từ danh sách candidate
    final modelsToTry = [
      if (configuredModel != null && configuredModel.isNotEmpty) configuredModel,
      ..._candidateModels.where((m) => m != configuredModel),
    ];

    for (final candidate in modelsToTry) {
      try {
        _model = GenerativeModel(
          model: candidate,
          apiKey: apiKey,
          tools: AiToolsDeclarations.allTools,
          systemInstruction: Content.system(systemPrompt),
        );
        _chat = _model!.startChat();
        debugPrint('GeminiChatService: Initialized successfully with model $candidate');
        return;
      } catch (e) {
        debugPrint('GeminiChatService: Model $candidate init failed: $e, trying next...');
      }
    }
  }

  /// Gửi tin nhắn đến Gemini và tự động xử lý Function Calling ghi Firestore
  Future<ChatMessageModel> sendMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return ChatMessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: 'Vui lòng nhập nội dung tin nhắn.',
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
      );
    }

    if (!isConfigured) {
      return ChatMessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '⚠️ **Chưa tìm thấy Gemini API Key**\n\n'
            'Để kích hoạt Trợ lý AI Gia đình, bạn chỉ cần làm 1 bước duy nhất:\n'
            '1. Lấy API key miễn phí tại: [Google AI Studio](https://aistudio.google.com/app/apikey)\n'
            '2. Mở file `.env` ở thư mục gốc và dán vào: `GEMINI_API_KEY=AIzaSy...`\n'
            '*(Không cần điền model hay cấu hình phức tạp nào khác, AI sẽ tự động kích hoạt!)*',
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
        isError: true,
      );
    }

    if (_chat == null) {
      await initChat();
    }

    if (_chat == null) {
      return ChatMessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: 'Không thể khởi tạo phiên trò chuyện với AI. Vui lòng kiểm tra lại API Key hoặc kết nối mạng.',
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
        isError: true,
      );
    }

    try {
      var response = await _chat!.sendMessage(Content.text(cleanText));

      ReminderModel? createdTaskResult;
      String? savedMemorySummary;

      // Xử lý Function Calling (nếu AI kích hoạt Tool)
      int loopLimit = 0;
      while (response.functionCalls.isNotEmpty && loopLimit < 3) {
        loopLimit++;
        final List<FunctionResponse> toolResponses = [];

        for (final call in response.functionCalls) {
          debugPrint('Gemini wants to call tool: ${call.name} with args: ${call.args}');

          if (call.name == 'createFamilyTask') {
            final task = await _handleCreateFamilyTask(call.args);
            createdTaskResult = task;
            toolResponses.add(
              FunctionResponse(
                call.name,
                {
                  'success': true,
                  'taskId': task.id,
                  'title': task.title,
                  'message': 'Đã tạo công việc thành công vào hệ thống nhắc việc gia đình.',
                },
              ),
            );
          } else if (call.name == 'saveFamilyPreference') {
            final keyword = call.args['keyword']?.toString() ?? '';
            final val = call.args['value']?.toString() ?? '';
            final category = call.args['category']?.toString() ?? 'general';

            if (keyword.isNotEmpty && val.isNotEmpty) {
              await FamilyMemoryService.instance.savePreference(
                familyId: _currentFamilyId,
                keyword: keyword,
                value: val,
                category: category,
              );
              savedMemorySummary = 'Đã ghi nhớ: "$keyword" ➔ "$val"';
            }

            toolResponses.add(
              FunctionResponse(
                call.name,
                {
                  'success': true,
                  'keyword': keyword,
                  'value': val,
                  'message': 'Đã ghi nhớ thói quen vào bộ nhớ dài hạn của gia đình.',
                },
              ),
            );
          } else {
            toolResponses.add(
              FunctionResponse(
                call.name,
                {'error': 'Tool ${call.name} không tồn tại.'},
              ),
            );
          }
        }

        // Gửi kết quả thực thi Tool ngược lại cho Gemini để AI trả về câu hội thoại cuối
        response = await _chat!.sendMessage(
          Content.functionResponses(toolResponses),
        );
      }

      // Trích xuất an toàn nội dung text (tránh lỗi StateError nếu SDK không có text part)
      var aiText = _extractTextSafely(response);
      if (aiText.isEmpty) {
        if (createdTaskResult != null) {
          aiText = 'Dạ em đã tạo công việc "${createdTaskResult.title}" và lưu vào hệ thống cho gia đình mình rồi ạ!';
        } else {
          aiText = 'Dạ em đã ghi nhận thông tin rồi ạ!';
        }
      }

      return ChatMessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: aiText,
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
        createdTask: createdTaskResult,
        savedMemorySummary: savedMemorySummary,
      );
    } catch (e) {
      debugPrint('GeminiChatService error: $e');
      return ChatMessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: 'Dạ em tạm thời gặp sự cố kết nối với Gemini ($e). Bạn vui lòng thử lại nhé!',
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
        isError: true,
      );
    }
  }

  /// Trích xuất text phản hồi an toàn, phòng ngừa trường hợp SDK quăng exception khi rỗng
  String _extractTextSafely(GenerateContentResponse res) {
    try {
      final t = res.text;
      if (t != null && t.trim().isNotEmpty) return t.trim();
    } catch (_) {}

    final buffer = StringBuffer();
    for (final candidate in res.candidates) {
      for (final part in candidate.content.parts) {
        if (part is TextPart && part.text.isNotEmpty) {
          buffer.write(part.text);
        }
      }
    }
    return buffer.toString().trim();
  }

  /// Tự động dò familyId của user hiện tại
  Future<void> _autoResolveFamilyId() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        final snap = await _firestore
            .collection('family_members')
            .where('userId', isEqualTo: uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final fId = snap.docs.first.data()['familyId']?.toString() ?? '';
          if (fId.isNotEmpty) {
            _currentFamilyId = fId;
            return;
          }
        }
      } catch (_) {}
    }
    _currentFamilyId = 'f1';
  }

  /// Xây dựng ngữ cảnh dữ liệu động cho System Instruction
  Future<String> _buildDynamicSystemPrompt() async {
    final now = DateTime.now();
    final todayStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    // 1. Đọc danh sách thành viên gia đình + trạng thái check-in (AC3)
    final membersInfo = StringBuffer();
    try {
      final membersSnap = await _firestore
          .collection('family_members')
          .where('familyId', isEqualTo: _currentFamilyId)
          .get();

      if (membersSnap.docs.isEmpty) {
        membersInfo.writeln('- $_currentUserName (Bạn, Thành viên)');
      } else {
        for (final doc in membersSnap.docs) {
          final data = doc.data();
          final name = data['displayName'] ?? data['name'] ?? 'Thành viên';
          final role = data['role'] ?? 'Thành viên';
          final lastCheckIn = data['lastCheckInAt'];

          String checkInStatus = 'Chưa check-in hôm nay';
          if (lastCheckIn is Timestamp) {
            final checkInDate = lastCheckIn.toDate();
            if (checkInDate.year == now.year &&
                checkInDate.month == now.month &&
                checkInDate.day == now.day) {
              checkInStatus =
                  'ĐÃ CHECK-IN lúc ${checkInDate.hour.toString().padLeft(2, '0')}:${checkInDate.minute.toString().padLeft(2, '0')}';
            }
          }
          membersInfo.writeln('- $name (Vai trò: $role): $checkInStatus');
        }
      }
    } catch (_) {
      membersInfo.writeln('- $_currentUserName (Bạn, Thành viên)');
    }

    // 2. Đọc danh sách công việc/lời nhắc hôm nay từ collection `reminders` (AC3)
    final tasksInfo = StringBuffer();
    try {
      final remindersSnap = await _firestore
          .collection('reminders')
          .where('familyId', isEqualTo: _currentFamilyId)
          .get();

      for (final doc in remindersSnap.docs) {
        final data = doc.data();
        final status = data['status']?.toString() ?? 'PENDING';
        if (status == 'DELETED') continue;

        final title = data['title'] ?? 'Công việc';
        final assigned = data['assignedToName'] ?? 'Chưa rõ';
        final isDone = status == 'COMPLETED';

        tasksInfo.writeln(
          '- [${isDone ? "ĐÃ XONG" : "CHƯA XONG"}] $title (Người làm: $assigned)',
        );
      }
      if (tasksInfo.isEmpty) {
        tasksInfo.writeln('- Chưa có việc nhà nào được tạo hôm nay.');
      }
    } catch (_) {
      tasksInfo.writeln('- Chưa có dữ liệu việc nhà hôm nay.');
    }

    // 3. Đọc trí nhớ thói quen gia đình từ `family_memories` (AC2)
    final memoriesInfo = StringBuffer();
    try {
      final memories =
          await FamilyMemoryService.instance.getMemories(_currentFamilyId);
      if (memories.isEmpty) {
        memoriesInfo.writeln('- Chưa lưu thói quen nào.');
      } else {
        for (final m in memories) {
          memoriesInfo.writeln('- Từ khóa "${m.keyword}": ${m.value}');
        }
      }
    } catch (_) {
      memoriesInfo.writeln('- Chưa có bộ nhớ thói quen.');
    }

    return '''
Bạn là Trợ lý AI Gia đình thông minh, ấm áp và chu đáo của ứng dụng Family Hub (FHub).
Hôm nay là ngày: $todayStr.
Người đang trò chuyện với bạn: $_currentUserName (ID: $_currentUserId).
Mã gia đình: $_currentFamilyId.

=== DANH SÁCH THÀNH VIÊN VÀ TRẠNG THÁI CHECK-IN HÔM NAY ===
$membersInfo

=== DANH SÁCH VIỆC NHÀ TRONG GIA ĐÌNH HÔM NAY ===
$tasksInfo

=== BỘ NHỚ THÓI QUEN & SỞ THÍCH GIA ĐÌNH ĐÃ GHI NHỚ (FAMILY MEMORY) ===
$memoriesInfo

=== CÁC QUY TẮC BẮT BUỘC KHI XỬ LÝ ===
1. [GIAO VIỆC MỞ CHO CÁC CON - AC1]:
   - Khi phụ huynh (Mẹ, Bố) nói những câu nhờ con phụ việc nhà (ví dụ: "Hôm nay mẹ muốn làm việc nhà, có đứa nào phụ không?"):
   - BẮT BUỘC gọi tool `createFamilyTask`:
     * title: "Phụ mẹ làm việc nhà" (hoặc tên việc phù hợp ngữ cảnh).
     * assignedTo: "ALL"
     * assignedToName: "Việc chung"
     * date: "$todayStr"
     * time: "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}"
     * isOpenTask: true
   - Sau đó thông báo rằng bạn đã tạo một Open Task gửi đến các con để các con bấm nhận việc.

2. [CÁ NHÂN HÓA & NHỚ THÓI QUEN - AC2]:
   - Khi có yêu cầu mua sắm hoặc làm việc liên quan đến một đồ vật / thói quen (ví dụ "sữa", "nước giặt", "gạo"):
     * TRƯỜNG HỢP A: Nếu từ khóa ĐÃ CÓ trong Bộ nhớ (ví dụ "sữa" đã lưu là "Vinamilk"):
       TỰ ĐỘNG điền luôn chi tiết vào tiêu đề công việc (ví dụ: "Mua sữa (Vinamilk)"), gọi tool `createFamilyTask` NGAY LẬP TỨC mà KHÔNG ĐƯỢC hỏi lại người dùng!
     * TRƯỜNG HỢP B: Nếu từ khóa CHƯA CÓ trong Bộ nhớ:
       Hãy hỏi lại một câu ngắn gọn, tự nhiên và thân thiện. Ví dụ: "Dạ Mẹ muốn mua sữa loại gì ạ?".
       Khi người dùng trả lời (ví dụ: "Vinamilk"), BẮT BUỘC gọi ĐỒNG THỜI 2 tool:
       1) `saveFamilyPreference(keyword: "sữa", value: "Vinamilk")`
       2) `createFamilyTask(title: "Mua sữa (Vinamilk)", ...)` để tạo việc ngay.

3. [BÁO CÁO NHANH TÌNH HÌNH TRONG NGÀY - AC3]:
   - Khi Bố/Mẹ hỏi "Tình hình ở nhà hôm nay sao rồi?" (hoặc bấm nút Báo cáo hôm nay):
   - Đọc kỹ dữ liệu thành viên và việc nhà ở trên để tổng hợp:
     * Ai đã check-in (lúc mấy giờ), ai chưa check-in.
     * Việc nhà nào đã hoàn thành, việc nào còn tồn đọng chưa ai làm.
   - Trả lời bằng giọng điệu gia đình ấm áp, ngắn gọn, súc tích (dưới 4 câu).

4. Luôn trả lời bằng Tiếng Việt lễ phép, tôn trọng, xưng hô "Em/Con" với người lớn hoặc gọi tên người dùng.
''';
  }

  /// Chuẩn hóa định dạng ngày từ LLM về đúng chuẩn dd/MM/yyyy của hệ thống
  String _normalizeDate(String? raw) {
    final now = DateTime.now();
    final fallback =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    if (raw == null || raw.trim().isEmpty) return fallback;

    final trimmed = raw.trim();
    // Khớp chuẩn ISO: YYYY-MM-DD hoặc YYYY/MM/DD
    final isoMatch = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(trimmed);
    if (isoMatch != null) {
      final y = isoMatch.group(1)!;
      final m = isoMatch.group(2)!.padLeft(2, '0');
      final d = isoMatch.group(3)!.padLeft(2, '0');
      return '$d/$m/$y';
    }

    // Khớp chuẩn dd/MM/yyyy hoặc dd-MM-yyyy
    final dmyMatch = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(trimmed);
    if (dmyMatch != null) {
      final d = dmyMatch.group(1)!.padLeft(2, '0');
      final m = dmyMatch.group(2)!.padLeft(2, '0');
      final y = dmyMatch.group(3)!;
      return '$d/$m/$y';
    }

    return fallback;
  }

  /// Chuẩn hóa định dạng giờ từ LLM về đúng chuẩn HH:mm
  String _normalizeTime(String? raw) {
    final now = DateTime.now();
    final fallback =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (raw == null || raw.trim().isEmpty) return fallback;

    final trimmed = raw.trim().toLowerCase().replaceAll('h', ':');
    final timeMatch = RegExp(r'^(\d{1,2}):(\d{1,2})').firstMatch(trimmed);
    if (timeMatch != null) {
      final h = timeMatch.group(1)!.padLeft(2, '0');
      final m = timeMatch.group(2)!.padLeft(2, '0');
      return '$h:$m';
    }

    return fallback;
  }

  /// Xử lý tạo ReminderModel thật và ghi vào Firestore collection `reminders` (AC1 & AC2)
  Future<ReminderModel> _handleCreateFamilyTask(Map<String, dynamic> args) async {
    final title = args['title']?.toString() ?? 'Việc nhà';
    final assignedTo = args['assignedTo']?.toString() ?? 'ALL';
    final assignedToName = args['assignedToName']?.toString() ?? 'Việc chung';

    final date = _normalizeDate(args['date']?.toString());
    final time = _normalizeTime(args['time']?.toString());
    final now = DateTime.now();

    final docRef = _firestore.collection('reminders').doc();

    final reminder = ReminderModel(
      id: docRef.id,
      familyId: _currentFamilyId,
      creatorId: _currentUserId.isNotEmpty ? _currentUserId : 'user_mom',
      creatorName: _currentUserName,
      assignedTo: assignedTo,
      assignedToName: assignedToName,
      title: title,
      date: date,
      time: time,
      status: ReminderStatus.pending,
      createdAt: now,
    );

    // Ghi trực tiếp vào Firestore collection `reminders` (Tương thích 100% với Vinh và Long)
    await docRef.set({
      ...reminder.toJson(),
      'family_id': _currentFamilyId,
      'creator_id': reminder.creatorId,
      'assigned_to': reminder.assignedTo,
      'assigned_to_name': reminder.assignedToName,
      'isOpenTask': assignedTo == 'ALL' || (args['isOpenTask'] == true),
    });

    debugPrint('GeminiChatService: Created Firestore Reminder ${docRef.id} - $title at $date $time');
    return reminder;
  }
}

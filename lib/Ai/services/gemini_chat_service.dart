import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../Vinh/models/family_member.dart';
import '../../Vinh/models/reminder_model.dart';
import '../models/chat_message_model.dart';
import 'ai_tools_declarations.dart';
import 'family_memory_service.dart';
import '../../Long/services/family_state_manager.dart';

/// Dịch vụ Trí tuệ AI Gia đình (Module 7 EPIC)
/// - Kết nối trực tiếp Gemini LLM API chính chủ với Function Calling & Dynamic Realtime System Instruction
/// - Bơm ngữ cảnh thời gian thực: Danh tính người dùng & vai trò chuẩn xác, trạng thái điểm danh hôm nay,
///   tiến độ việc nhà, quỹ hũ niềm vui, trí nhớ thói quen gia đình.
/// - Tuyệt đối không mặc định "chào mẹ", cách ly dữ liệu gia đình nghiêm ngặt (Zero Data Leakage).
/// - Lưu trữ hội thoại riêng tư theo từng người dùng trong gia đình trong 15 ngày tự động cuốn chiếu.
/// - Tự động dự phòng thông minh (Senior Intelligent Fallback) khi ngoại tuyến hoặc chưa cấu hình API Key.
class GeminiChatService {
  GeminiChatService._();
  static final GeminiChatService instance = GeminiChatService._();

  bool get _hasFirebase => Firebase.apps.isNotEmpty;
  FirebaseFirestore? get _firestore => _hasFirebase ? FirebaseFirestore.instance : null;
  FirebaseAuth? get _auth => _hasFirebase ? FirebaseAuth.instance : null;

  GenerativeModel? _model;
  ChatSession? _chat;

  String _currentFamilyId = 'f1';
  String _currentFamilyName = 'Gia Đình';
  String _currentUserId = '';
  String _currentUserName = 'Bạn';
  String _currentUserRole = 'Thành viên';

  String get currentFamilyId => _currentFamilyId;
  String get currentUserName => _currentUserName;
  String get currentUserRole => _currentUserRole;

  static const List<String> _candidateModels = [
    'gemini-2.0-flash',
    'gemini-1.5-pro',
    'gemini-1.5-flash',
    'gemini-2.0-flash-exp',
  ];

  String? _customApiKey;
  List<FamilyMember>? _cachedFamilyMembers;

  /// Lấy API Key hiệu lực (Ưu tiên Key người dùng lưu trong SharedPreferences -> sau đó đến .env)
  String get effectiveApiKey {
    if (_customApiKey != null && _customApiKey!.trim().isNotEmpty) {
      return _customApiKey!.trim();
    }
    if (dotenv.isInitialized) {
      return dotenv.env['GEMINI_API_KEY']?.trim() ?? '';
    }
    return '';
  }

  bool get isConfigured => effectiveApiKey.isNotEmpty;

  /// Cài đặt API Key tuỳ chỉnh trong ứng dụng (lưu đồng bộ vào Firestore user profile)
  Future<void> setCustomApiKey(String key) async {
    _customApiKey = key.trim();
    if (_firestore != null && _currentUserId.isNotEmpty) {
      try {
        await _firestore!.collection('users').doc(_currentUserId).set(
          {'customGeminiApiKey': _customApiKey},
          SetOptions(merge: true),
        );
      } catch (_) {}
    }
    await initChat();
  }

  /// Tải API Key đã lưu từ Firestore user profile
  Future<void> loadSavedApiKey() async {
    if (_firestore != null && _currentUserId.isNotEmpty) {
      try {
        final doc = await _firestore!.collection('users').doc(_currentUserId).get();
        final saved = doc.data()?['customGeminiApiKey']?.toString().trim();
        if (saved != null && saved.isNotEmpty) {
          _customApiKey = saved;
        }
      } catch (_) {}
    }
  }

  /// Đặt lại phiên trò chuyện hiện tại (Bắt đầu cuộc trò chuyện mới)
  void resetChatSession() {
    _chat = null;
  }

  /// Khởi tạo hoặc làm mới ngữ cảnh gia đình cho AI Chatbot
  Future<void> initChat({
    String? familyId,
    String? userId,
    String? userName,
    String? userRole,
    String? familyName,
  }) async {
    if (_customApiKey == null) {
      await loadSavedApiKey();
    }

    if (!dotenv.isInitialized) {
      try {
        await dotenv.load(fileName: ".env");
      } catch (_) {
        try {
          await dotenv.load(fileName: "assets/.env");
        } catch (_) {}
      }
    }

    final apiKey = effectiveApiKey;
    final configuredModel = (dotenv.isInitialized ? dotenv.env['GEMINI_MODEL'] : null)?.trim();

    // Cập nhật thông tin định danh
    if (familyId != null && familyId.isNotEmpty) {
      _currentFamilyId = familyId;
    } else {
      await _autoResolveFamilyId();
    }

    if (familyName != null && familyName.isNotEmpty) {
      _currentFamilyName = familyName;
    }

    final user = _auth?.currentUser;
    if (userId != null && userId.isNotEmpty) {
      _currentUserId = userId;
    } else if (user != null) {
      _currentUserId = user.uid;
    }

    if (userName != null && userName.isNotEmpty) {
      _currentUserName = userName;
    } else if (user != null) {
      _currentUserName = (user.displayName != null && user.displayName!.isNotEmpty)
          ? user.displayName!
          : (user.email?.split('@').first ?? 'Bạn');
    }

    if (userRole != null && userRole.isNotEmpty) {
      _currentUserRole = userRole;
    } else {
      await _autoResolveUserRole();
    }

    if (apiKey.isEmpty) {
      debugPrint('GeminiChatService: GEMINI_API_KEY is not set in .env');
      return;
    }

    // Xây dựng System Instruction động theo thời gian thực
    final systemPrompt = await _buildDynamicSystemPrompt();

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
        debugPrint('GeminiChatService: Initialized successfully with model $candidate for family $_currentFamilyId');
        return;
      } catch (e) {
        debugPrint('GeminiChatService: Model $candidate init failed: $e, trying next...');
      }
    }
  }

  /// Kiểm tra xem câu hỏi có thuộc nghiệp vụ / ngữ cảnh gia đình không
  bool isFamilyContextQuery(String text) => _isFamilyContextQuery(text);

  bool _isFamilyContextQuery(String text) {
    final lower = text.toLowerCase();
    return lower.contains('điểm danh') ||
        lower.contains('diem danh') ||
        lower.contains('check in') ||
        lower.contains('check-in') ||
        lower.contains('checkin') ||
        lower.contains('ai có mặt') ||
        lower.contains('ai đã đến') ||
        lower.contains('attendance') ||
        lower.contains('who checked') ||
        lower.contains('tiến độ') ||
        lower.contains('tien do') ||
        lower.contains('tóm tắt') ||
        lower.contains('tom tat') ||
        lower.contains('progress') ||
        lower.contains('vai trò') ||
        lower.contains('vai tro') ||
        lower.contains('tôi là ai') ||
        lower.contains('quyền của tôi') ||
        lower.contains('đóng vai trò gì') ||
        lower.contains('chức vụ') ||
        lower.contains('có thể giao việc') ||
        lower.contains('giao việc cho ai không') ||
        lower.contains('role') ||
        lower.contains('who am i') ||
        lower.contains('mấy gia đình') ||
        lower.contains('bao nhiêu gia đình') ||
        lower.contains('các gia đình') ||
        lower.contains('danh sách gia đình') ||
        lower.contains('hũ niềm vui') ||
        lower.contains('quỹ hũ') ||
        lower.contains('nổ hũ') ||
        lower.contains('lắc hũ') ||
        lower.contains('đẹp trai') ||
        lower.contains('xinh gái') ||
        lower.contains('đẹp gái') ||
        lower.contains('dễ thương') ||
        lower.contains('thông minh') ||
        lower.contains('phong độ') ||
        lower.contains('tôi đẹp không') ||
        lower.contains('tôi thế nào') ||
        lower.contains('trông thế nào') ||
        lower.contains('trông như thế nào') ||
        lower.contains('thấy tôi') ||
        lower.contains('tôi ra sao') ||
        lower.contains('chào') ||
        lower.contains('xin vhaog') ||
        lower.contains('xinchao') ||
        lower.contains('tích') ||
        lower.contains('tick') ||
        lower.contains("i'm ok") ||
        lower.contains('im ok');
  }

  /// Nhận diện xem người dùng có đang yêu cầu AI thực hiện hành động điểm danh / tích "I'm OK" cho mình không
  bool _isPerformCheckInIntent(String lower) {
    final isQueryOther = lower.contains('ai đã') ||
        lower.contains('ai chưa') ||
        lower.contains('tình hình') ||
        lower.contains('bao nhiêu người') ||
        lower.contains('danh sách') ||
        lower.contains('ai có mặt') ||
        lower.contains('ai check in') ||
        lower.contains('ai điểm danh');
    if (isQueryOther) return false;

    final hasActionVerb = lower.contains('tích') ||
        lower.contains('tick') ||
        lower.contains('bấm') ||
        lower.contains('ấn') ||
        lower.contains('giúp') ||
        lower.contains('hộ') ||
        lower.contains('dùm') ||
        lower.contains('giùm') ||
        lower.contains('cho tôi') ||
        lower.contains('cho mình') ||
        lower.contains('báo');

    final hasCheckInTarget = lower.contains("i'm ok") ||
        lower.contains('im ok') ||
        lower.contains("i m ok") ||
        lower.contains('điểm danh') ||
        lower.contains('diem danh') ||
        lower.contains('check in') ||
        lower.contains('check-in') ||
        lower.contains('checkin') ||
        lower.contains('an toàn');

    if (hasActionVerb && hasCheckInTarget) return true;

    if (lower == 'tôi ok' ||
        lower == 'tôi ổn' ||
        lower == 'mình ok' ||
        lower == 'mình ổn' ||
        lower == "i'm ok" ||
        lower == 'im ok' ||
        lower.contains('hôm nay tôi ok') ||
        lower.contains('tôi đã an toàn') ||
        lower.contains('báo tôi ổn')) {
      return true;
    }

    return false;
  }

  /// Gửi tin nhắn và xử lý phản hồi thông minh
  Future<ChatMessageModel> sendMessage(
    String text, {
    String? familyId,
    String? userId,
    String? userName,
    String? userRole,
    List<FamilyMember>? familyMembers,
    bool fallbackToLocal = true,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return ChatMessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Vui lòng nhập nội dung tin nhắn.',
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
      );
    }

    if (familyMembers != null && familyMembers.isNotEmpty) {
      _cachedFamilyMembers = familyMembers;
    }

    // Cập nhật ngữ cảnh nếu truyền vào
    if (familyId != null && familyId != _currentFamilyId) {
      _currentFamilyId = familyId;
      _chat = null; // Reset chat session để nạp lại system prompt của gia đình mới
    }
    if (userId != null && userId.isNotEmpty) _currentUserId = userId;
    if (userName != null && userName.isNotEmpty) _currentUserName = userName;
    if (userRole != null && userRole.isNotEmpty) _currentUserRole = userRole;

    // Nếu chưa cấu hình API Key:
    if (!isConfigured) {
      if (fallbackToLocal && _isFamilyContextQuery(cleanText)) {
        return _generateContextualResponse(cleanText);
      }
      return ChatMessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        text: '⚠️ **Chưa tìm thấy Gemini API Key**\n\n'
            'Để kích hoạt Trợ lý AI Gia đình, bạn chỉ cần làm 1 bước duy nhất:\n'
            '1. Lấy API key miễn phí tại: [Google AI Studio](https://aistudio.google.com/app/apikey)\n'
            '2. Mở file `.env` ở thư mục gốc và dán vào: `GEMINI_API_KEY=AQ...` (hoặc `AIzaSy...`)\n'
            '*(Không cần điền model hay cấu hình phức tạp nào khác, AI sẽ tự động kích hoạt!)*',
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
        isError: true,
      );
    }

    if (_chat == null) {
      await initChat(
        familyId: _currentFamilyId,
        userId: _currentUserId,
        userName: _currentUserName,
        userRole: _currentUserRole,
      );
    }

    if (_chat == null) {
      // Nếu khởi tạo Gemini thất bại (ví dụ lỗi mạng), tự động fallback về engine nội bộ
      if (fallbackToLocal) {
        return _generateContextualResponse(cleanText);
      }
      return ChatMessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Không thể khởi tạo phiên trò chuyện Gemini.',
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
          } else if (call.name == 'performFamilyCheckIn') {
            final caption = call.args['caption']?.toString();
            await _handlePerformCheckIn(caption);
            toolResponses.add(
              FunctionResponse(
                call.name,
                {
                  'success': true,
                  'message': 'Đã thực hiện tích "I\'m OK" và hoàn tất điểm danh thành công cho $_currentUserName hôm nay.',
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

        response = await _chat!.sendMessage(
          Content.functionResponses(toolResponses),
        );
      }

      var aiText = _extractTextSafely(response);
      if (aiText.isEmpty) {
        if (createdTaskResult != null) {
          aiText = 'Dạ em đã tạo công việc "${createdTaskResult.title}" và lưu vào hệ thống cho gia đình mình rồi ạ!';
        } else {
          aiText = 'Dạ em đã ghi nhận thông tin rồi ạ!';
        }
      }

      return ChatMessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        text: aiText,
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
        createdTask: createdTaskResult,
        savedMemorySummary: savedMemorySummary,
      );
    } catch (e) {
      debugPrint('GeminiChatService sendMessage error: $e');
      final err = e.toString().toLowerCase();
      if (err.contains('api_key_invalid') ||
          err.contains('api key not valid') ||
          err.contains('unauthenticated') ||
          err.contains('access_token_type_unsupported') ||
          err.contains('api_key_service_blocked') ||
          err.contains('401')) {
        final prefix = effectiveApiKey.length > 8 ? effectiveApiKey.substring(0, 10) : effectiveApiKey;
        return ChatMessageModel(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          text: '⚠️ **Dịch vụ Gemini API bị chặn hoặc chưa kích hoạt (Google báo lỗi 401 / API_KEY_SERVICE_BLOCKED)**\n\n'
              'Khóa API hiện tại: `$prefix...`\n'
              '• **Nguyên nhân**: Khóa này được liên kết với một Google Cloud Project nhưng dịch vụ **Generative Language API** chưa được bật (Enable) trong project đó.\n\n'
              '👉 **Cách xử lý nhanh nhất (10 giây)**:\n'
              '1. Vào lại [Google AI Studio](https://aistudio.google.com/app/apikey).\n'
              '2. Bấm **Create API key** ➔ Chọn **"Create API key in new project"** (Tạo trong project mới của AI Studio để Google tự động bật sẵn dịch vụ).\n'
              '3. Dán khóa mới vào file `.env` là Gemini 2.0 Flash hoạt động ngay lập tức nhé!',
          sender: ChatSender.ai,
          timestamp: DateTime.now(),
          isError: true,
        );
      }
      if (fallbackToLocal) {
        return _generateContextualResponse(cleanText);
      }
      return ChatMessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Lỗi gọi Gemini: $e',
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
        isError: true,
      );
    }
  }

  /// Trích xuất text phản hồi an toàn
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

  /// Tự động xác định familyId nếu chưa có
  Future<void> _autoResolveFamilyId() async {
    final uid = _auth?.currentUser?.uid;
    if (uid != null && uid.isNotEmpty && _firestore != null) {
      try {
        final snap = await _firestore!
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

  /// Tự động xác định vai trò của người dùng hiện tại trong gia đình
  Future<void> _autoResolveUserRole() async {
    final uid = _currentUserId.isNotEmpty ? _currentUserId : _auth?.currentUser?.uid;
    if (uid != null && uid.isNotEmpty && _firestore != null) {
      try {
        final snap = await _firestore!
            .collection('family_members')
            .where('familyId', isEqualTo: _currentFamilyId)
            .where('userId', isEqualTo: uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final r = snap.docs.first.data()['role']?.toString();
          if (r != null && r.isNotEmpty) {
            _currentUserRole = r;
            return;
          }
        }
      } catch (_) {}
    }

    final nameLower = _currentUserName.toLowerCase();
    if (nameLower.contains('mẹ') || nameLower.contains('mom') || nameLower.contains('má')) {
      _currentUserRole = 'Mẹ (Phụ huynh)';
    } else if (nameLower.contains('bố') || nameLower.contains('ba') || nameLower.contains('dad') || nameLower.contains('cha')) {
      _currentUserRole = 'Bố (Phụ huynh)';
    } else {
      _currentUserRole = 'Thành viên';
    }
  }

  /// Xây dựng ngữ cảnh thời gian thực (Dynamic System Prompt)
  Future<String> _buildDynamicSystemPrompt() async {
    final now = DateTime.now();
    final todayStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    // 1. Đọc danh sách thành viên gia đình và trạng thái điểm danh hôm nay
    final membersInfo = StringBuffer();
    if (_firestore != null) {
      try {
        final membersSnap = await _firestore!
            .collection('family_members')
            .where('familyId', isEqualTo: _currentFamilyId)
            .get();

        if (membersSnap.docs.isEmpty) {
          membersInfo.writeln('- $_currentUserName (Vai trò: $_currentUserRole)');
        } else {
          for (final doc in membersSnap.docs) {
            final data = doc.data();
            final name = (data['displayName'] ?? data['name'] ?? data['userName'] ?? 'Thành viên').toString().trim();
            final role = (data['role'] ?? 'Thành viên').toString().trim();
            final lastCheckIn = data['lastCheckInAt'] ?? data['last_check_in_at'];

            String checkInStatus = 'Chưa điểm danh hôm nay';
            if (lastCheckIn is Timestamp) {
              final checkInDate = lastCheckIn.toDate();
              if (checkInDate.year == now.year &&
                  checkInDate.month == now.month &&
                  checkInDate.day == now.day) {
                checkInStatus =
                    'ĐÃ ĐIỂM DANH lúc ${checkInDate.hour.toString().padLeft(2, '0')}:${checkInDate.minute.toString().padLeft(2, '0')}';
              }
            }
            membersInfo.writeln('- $name (Vai trò: $role): $checkInStatus');
          }
        }
      } catch (_) {
        membersInfo.writeln('- $_currentUserName (Vai trò: $_currentUserRole)');
      }
    } else {
      membersInfo.writeln('- $_currentUserName (Vai trò: $_currentUserRole)');
    }

    // 2. Đọc danh sách công việc gia đình hôm nay
    final tasksInfo = StringBuffer();
    if (_firestore != null) {
      try {
        final remindersSnap = await _firestore!
            .collection('reminders')
            .where('familyId', isEqualTo: _currentFamilyId)
            .get();

        for (final doc in remindersSnap.docs) {
          final data = doc.data();
          final status = (data['status'] ?? 'PENDING').toString();
          if (status == 'DELETED') continue;

          final title = data['title'] ?? 'Công việc';
          final assigned = data['assignedToName'] ?? 'Việc chung';
          final isDone = status == 'COMPLETED';

          tasksInfo.writeln(
            '- [${isDone ? "ĐÃ XONG" : "CHƯA XONG"}] $title (Người làm: $assigned)',
          );
        }
        if (tasksInfo.isEmpty) {
          tasksInfo.writeln('- Chưa có việc nhà nào được tạo hôm nay.');
        }
      } catch (_) {
        tasksInfo.writeln('- Chưa có dữ liệu việc nhà.');
      }
    } else {
      tasksInfo.writeln('- Chưa có dữ liệu việc nhà.');
    }

    // 3. Đọc thông tin Hũ Niềm Vui gia đình
    final jackpotInfo = StringBuffer();
    if (_firestore != null) {
      try {
        final jDoc = await _firestore!
            .collection('families')
            .doc(_currentFamilyId)
            .collection('jackpot')
            .doc('current')
            .get();

        if (jDoc.exists && jDoc.data() != null) {
          final data = jDoc.data()!;
          final pool = data['totalPoolAmount'] ?? 0;
          final topName = data['topContributorName'] ?? 'Chưa có';
          jackpotInfo.writeln('- Tổng quỹ Hũ hiện tại: $pool đ');
          jackpotInfo.writeln('- Người đóng góp nhiều nhất: $topName (Nắm giữ quyền phát lệnh nổ hũ 30 giây)');
        } else {
          jackpotInfo.writeln('- Hũ Niềm Vui hiện tại: 0 đ');
        }
      } catch (_) {
        jackpotInfo.writeln('- Hũ Niềm Vui đang được cập nhật.');
      }
    } else {
      jackpotInfo.writeln('- Hũ Niềm Vui hiện tại: 0 đ');
    }

    // 4. Đọc thói quen sở thích
    final memoriesInfo = StringBuffer();
    try {
      final memories = await FamilyMemoryService.instance.getMemories(_currentFamilyId);
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
Vai trò của người dùng trong gia đình: $_currentUserRole.
Gia đình hiện tại: $_currentFamilyName (Mã: $_currentFamilyId).

=== QUY TẮC XƯNG HÔ BẮT BUỘC (TUYỆT ĐỐI ĐỘNG THEO PROFILE - CẤM HARDCODE) ===
- KHÔNG ĐƯỢC mặc định gọi "Mẹ" hoặc xưng "Chào mẹ" nếu người dùng không phải là Mẹ!
- Đọc chính xác tên thật của người dùng: "$_currentUserName" và vai trò thật: "$_currentUserRole".
- Nếu người dùng có vai trò là Con cái (Child/Con): Xưng em/mình và gọi tên "$_currentUserName", TUYỆT ĐỐI KHÔNG xưng "chào mẹ"!
- Nếu người dùng là Bố/Ba (Parent - Bố): Xưng con/em, gọi "Bố".
- Nếu người dùng là Mẹ (Parent - Mẹ): Xưng con/em, gọi "Mẹ".
- Nếu người dùng là Ông/Bà (Grandparent): Xưng cháu/con, gọi "Ông/Bà".

=== NGUYÊN TẮC ĐA GIA ĐÌNH & PHÂN LẬP DỮ LIỆU (MULTI-FAMILY SCOPING) ===
- Người dùng có thể tham gia nhiều gia đình trong ứng dụng FHub.
- Phiên trò chuyện này ĐANG HOẠT ĐỘNG TRONG GIA ĐÌNH: "$_currentFamilyName" (Mã: $_currentFamilyId).
- Khi người dùng hỏi chung chung ("tiến độ", "ai điểm danh", "việc nhà", "quỹ hũ"):
  + Báo cáo chính xác theo không gian của gia đình "$_currentFamilyName".
  + Luôn nêu rõ tên gia đình ở câu trả lời (VD: "Dạ trong gia đình $_currentFamilyName, tiến độ hôm nay là...").
  + Nếu người dùng hỏi tổng thể về các gia đình (VD: "tôi có mấy gia đình?"), giải thích rõ người dùng đang ở không gian gia đình "$_currentFamilyName", và nhắc người dùng có thể đổi gia đình trên thanh chọn (Family Selector).

=== HỖ TRỢ ĐA NGÔN NGỮ (VIETNAMESE / ENGLISH) ===
- Nếu người dùng hỏi bằng Tiếng Anh (English): Trả lời hoàn toàn bằng Tiếng Anh tự nhiên, ấm áp.
- Nếu người dùng hỏi bằng Tiếng Việt: Trả lời bằng Tiếng Việt chuẩn mực, đúng văn hóa gia đình.

=== DANH SÁCH THÀNH VIÊN VÀ TRẠNG THÁI ĐIỂM DANH HÔM NAY ===
$membersInfo

=== DANH SÁCH VIỆC NHÀ TRONG GIA ĐÌNH HÔM NAY ===
$tasksInfo

=== THÔNG TIN HŨ NIỀM VUI GIA ĐÌNH ===
$jackpotInfo

=== BỘ NHỚ THÓI QUEN & SỞ THÍCH GIA ĐÌNH (FAMILY MEMORY) ===
$memoriesInfo

=== NGUYÊN TẮC GỌI TOOL TẠO VIỆC (createFamilyTask) ===
- CHỈ ĐƯỢC PHÉP gọi tool "createFamilyTask" khi người dùng THỰC SỰ RA LỆNH tạo việc nhà cụ thể (VD: "Tạo việc rửa chén lúc 19h", "Giao Bin quét nhà").
- CẤM TUYỆT ĐỐI gọi "createFamilyTask" khi người dùng đang ĐẶT CÂU HỎI, THẮC MẮC, TÂM SỰ hoặc HỎI VỀ QUYỀN HẠN/VAI TRÒ (VD: "tôi đóng vai trò gì trong căn nhà này?", "tôi có thể giao việc cho ai không?", "vai trò của tôi là gì?", "hôm nay ai làm việc nhà?").
- Khi người dùng hỏi thắc mắc quyền hạn/vai trò: Trả lời giải thích trực tiếp bằng ngôn từ tự nhiên, hướng dẫn rõ ràng quyền của họ, TUYỆT ĐỐI KHÔNG TỰ Ý TẠO VIỆC NHÀ.

=== QUYỀN HẠN HỆ THỐNG VÀ BẢN CHẤT CỦA BẠN ===
- Bạn là Trợ lý AI Gia đình có TOÀN QUYỀN HỆ THỐNG ĐỌC DỮ LIỆU: Bạn nắm rõ danh tính của người dùng ($_currentUserName), vai trò ($_currentUserRole), ai đã điểm danh hôm nay, ai chưa, danh sách mọi công việc nhà, và số dư hũ.
- Bạn kết nối trực tiếp với hệ thống để TẠO CÔNG VIỆC / LỜI NHẮC (Reminder) tự động thông qua công cụ (Tool Calling: createFamilyTask).
- BẢN CHẤT TRÒ CHUYỆN: Bạn là một AI thế hệ mới (LLM) thông minh, ấm áp và uyên bác như khi người dùng chat trên web, có thể trả lời mọi câu hỏi, đưa ra lời khuyên, chia sẻ kinh nghiệm, đùa vui hóm hỉnh, hỗ trợ việc nhà một cách tự nhiên và chân thành nhất, KHÔNG BỊ GÒ BÓ bởi bất kỳ mẫu câu cứng nhắc nào.
- GIỚI HẠN DUY NHẤT VỀ HŨ NIỀM VUI (JACKPOT): Bạn nắm rõ thông tin Hũ, nhưng bạn KHÔNG THỂ VÀ KHÔNG ĐƯỢC PHÉP tự bấm lắc hũ giùm người dùng! Lắc hũ là tính năng tương tác thực tế giữa các thành viên: mỗi người phải tự cầm điện thoại thật của mình lên và lắc cơ học trong 30 giây (hoặc bấm nút Lắc trên màn hình Hũ) để tranh giải. Nếu người dùng bảo bạn "lắc hũ đi", "nổ hũ hộ tôi", hãy giải thích vui vẻ rằng bạn không có tay để lắc điện thoại hộ được, và mời họ vào tab Hũ Niềm Vui để cùng cả nhà lắc!

=== CÁC CHỈ DẪN TRẢ LỜI NGHIỆP VỤ ===
1. Khi người dùng hỏi "ai đã điểm danh", "hôm nay ai chưa check-in", "tình hình điểm danh":
   Đọc chính xác danh sách thành viên ở trên để trả lời rõ ràng ai đã điểm danh lúc mấy giờ, ai chưa điểm danh.
2. Khi người dùng hỏi "tóm tắt tiến độ công việc", "tình hình việc nhà hôm nay", "hôm nay có việc gì":
   Báo cáo tổng kết súc tích: việc nào đã xong, việc nào chưa xong, ai phụ trách.
3. Khi người dùng hỏi về vai trò hoặc quyền hạn của mình trong gia đình:
   Trả lời chính xác theo vai trò thực tế của họ (quyền giao việc, quyền nổ hũ, nhận sao thưởng).
4. Khi người dùng hỏi về Hũ Niềm Vui:
   Cung cấp số dư hũ, ai nạp nhiều nhất và quy tắc lắc 30s (nhắc rõ AI không lắc hũ hộ được).
5. Khi người dùng muốn giao việc mở cho các con: Gọi tool createFamilyTask với assignedTo: "ALL".
6. Luôn giao tiếp lịch sự, ngắn gọn, tự nhiên và giàu cảm xúc gia đình.
''';
  }

  /// Senior Intelligent Fallback Engine: Trả lời tự nhiên, chính xác theo ngữ cảnh động khi không có API Key
  Future<ChatMessageModel> _generateContextualResponse(String query) async {
    final lower = query.toLowerCase().trim();
    final salutation = _resolveSalutation();
    final now = DateTime.now();
    final todayStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    // 0. HÀNH ĐỘNG: YÊU CẦU ĐIỂM DANH / TÍCH I'M OK CHO BẢN THÂN
    if (_isPerformCheckInIntent(lower)) {
      await _handlePerformCheckIn('Đã điểm danh I\'m OK qua Trợ lý AI');
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ em đã tích "I\'m OK" và hoàn tất điểm danh hôm nay cho $salutation rồi nhé! 💚✨\n'
            'Trạng thái an tâm của $salutation đã được cập nhật cho cả gia đình cùng thấy. Chúc $salutation một ngày thật vui vẻ và tràn đầy năng lượng! 🌟',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 1. HỎI VỀ ĐIỂM DANH / CHECK-IN HÔM NAY
    if (lower.contains('điểm danh') ||
        lower.contains('diem danh') ||
        lower.contains('check in') ||
        lower.contains('check-in') ||
        lower.contains('checkin') ||
        lower.contains('attendance') ||
        lower.contains('who checked') ||
        (lower.contains('ai') && (lower.contains('đã đến') || lower.contains('có mặt') || lower.contains('điểm danh') || lower.contains('check in')))) {
      if (_firestore != null) {
        try {
          final membersSnap = await _firestore!
              .collection('family_members')
              .where('familyId', isEqualTo: _currentFamilyId)
              .get();

          final checkedInList = <String>[];
          final notCheckedInList = <String>[];

          for (final doc in membersSnap.docs) {
            final data = doc.data();
            final name = (data['displayName'] ?? data['name'] ?? data['userName'] ?? 'Thành viên').toString().trim();
            final lastCheckIn = data['lastCheckInAt'] ?? data['last_check_in_at'];

            bool isToday = false;
            String timeStr = '';
            if (lastCheckIn is Timestamp) {
              final dt = lastCheckIn.toDate();
              if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
                isToday = true;
                timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              }
            } else if (lastCheckIn is String) {
              final dt = DateTime.tryParse(lastCheckIn);
              if (dt != null && dt.year == now.year && dt.month == now.month && dt.day == now.day) {
                isToday = true;
                timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              }
            }

            if (isToday) {
              checkedInList.add('$name (lúc $timeStr)');
            } else {
              notCheckedInList.add(name);
            }
          }

          if (checkedInList.isNotEmpty || notCheckedInList.isNotEmpty) {
            final buffer = StringBuffer();
            buffer.writeln('📋 TÌNH HÌNH ĐIỂM DANH GIA ĐÌNH HÔM NAY ($todayStr):');
            if (checkedInList.isNotEmpty) {
              buffer.writeln('✅ Đã điểm danh (${checkedInList.length} người):');
              for (final c in checkedInList) {
                buffer.writeln('  • $c');
              }
            } else {
              buffer.writeln('• Chưa có thành viên nào điểm danh hôm nay.');
            }

            if (notCheckedInList.isNotEmpty) {
              buffer.writeln('\n⏳ Chưa điểm danh (${notCheckedInList.length} người):');
              for (final nc in notCheckedInList) {
                buffer.writeln('  • $nc');
              }
            }

            return ChatMessageModel(
              id: 'msg_${now.millisecondsSinceEpoch}',
              text: buffer.toString().trim(),
              sender: ChatSender.ai,
              timestamp: now,
            );
          }
        } catch (_) {}
      }

      if (_cachedFamilyMembers != null && _cachedFamilyMembers!.isNotEmpty) {
        final notChecked = _cachedFamilyMembers!.map((m) => '${m.name} (${m.roleDisplayName})').toList();
        final buffer = StringBuffer();
        buffer.writeln('📋 TÌNH HÌNH ĐIỂM DANH GIA ĐÌNH HÔM NAY ($todayStr):');
        buffer.writeln('• Chưa có thành viên nào ghi nhận điểm danh hôm nay.');
        buffer.writeln('\n⏳ Danh sách thành viên gia đình:');
        for (final nc in notChecked) {
          buffer.writeln('  • $nc');
        }
        buffer.write('\nDạ $salutation, cả nhà nhớ mở app bấm Điểm danh hôm nay để nhận sao thưởng nhé! ❤️');
        return ChatMessageModel(
          id: 'msg_${now.millisecondsSinceEpoch}',
          text: buffer.toString().trim(),
          sender: ChatSender.ai,
          timestamp: now,
        );
      }

      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: '📋 TÌNH HÌNH ĐIỂM DANH GIA ĐÌNH HÔM NAY ($todayStr):\n'
            '• $_currentUserName (Vai trò: $_currentUserRole): Sẵn sàng hoạt động!\n'
            'Dạ $salutation, cả nhà mình hôm nay ai có mặt nhớ mở app bấm điểm danh để nhận sao thưởng nhé! ❤️',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 2. HỎI VỀ TIẾN ĐỘ CÔNG VIỆC / TÓM TẮT TIẾN ĐỘ
    if (lower.contains('tiến độ') ||
        lower.contains('tien do') ||
        lower.contains('tóm tắt') ||
        lower.contains('tom tat') ||
        lower.contains('công việc hôm nay') ||
        lower.contains('việc nhà hôm nay') ||
        lower.contains('báo cáo')) {
      if (_firestore != null) {
        try {
          final remindersSnap = await _firestore!
              .collection('reminders')
              .where('familyId', isEqualTo: _currentFamilyId)
              .get();

          int total = 0;
          int completed = 0;
          final pendingList = <String>[];

          for (final doc in remindersSnap.docs) {
            final data = doc.data();
            final status = (data['status'] ?? 'PENDING').toString();
            if (status == 'DELETED') continue;

            total++;
            final title = data['title'] ?? 'Công việc';
            final assigned = data['assignedToName'] ?? 'Việc chung';

            if (status == 'COMPLETED') {
              completed++;
            } else {
              pendingList.add('$title ($assigned)');
            }
          }

          final percent = total > 0 ? ((completed / total) * 100).toInt() : 100;
          final buffer = StringBuffer();
          buffer.writeln('📊 BÁO CÁO TIẾN ĐỘ GIA ĐÌNH HÔM NAY ($todayStr):');
          buffer.writeln('• Tổng công việc: $total việc');
          buffer.writeln('• Đã hoàn thành: $completed việc ($percent%)');
          buffer.writeln('• Đang chờ thực hiện: ${pendingList.length} việc');

          if (pendingList.isNotEmpty) {
            buffer.writeln('\n📌 Việc cần làm:');
            for (final p in pendingList.take(5)) {
              buffer.writeln('  - $p');
            }
          } else {
            buffer.writeln('\n🎉 Tuyệt vời! Tất cả việc nhà hôm nay đã được hoàn tất!');
          }

          return ChatMessageModel(
            id: 'msg_${now.millisecondsSinceEpoch}',
            text: buffer.toString().trim(),
            sender: ChatSender.ai,
            timestamp: now,
          );
        } catch (_) {}
      }

      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: '📊 BÁO CÁO TIẾN ĐỘ GIA ĐÌNH HÔM NAY ($todayStr):\n'
            '• Các thành viên đang hoàn thành tốt kế hoạch sinh hoạt.\n'
            'Dạ $salutation, nếu có việc gì cần giao thêm cho các con, $salutation cứ bảo em nhé! ❤️',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 2.5 HỎI VỀ ĐA GIA ĐÌNH CỦA NGƯỜI DÙNG
    if (lower.contains('mấy gia đình') ||
        lower.contains('bao nhiêu gia đình') ||
        lower.contains('danh sách gia đình') ||
        lower.contains('các gia đình')) {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: '🏡 **KHÔNG GIAN GIA ĐÌNH CỦA BẠN**:\n'
            '• Gia đình đang hoạt động: **$_currentFamilyName** (Mã: $_currentFamilyId)\n'
            '• Vai trò của bạn tại gia đình này: **$_currentUserRole**\n'
            '• Phạm vi dữ liệu: Toàn bộ việc nhà, điểm danh và hũ niềm vui được tách bạch an toàn theo từng gia đình.\n\n'
            '💡 *Mẹo: Nếu bạn tham gia nhiều gia đình, bạn có thể dễ dàng chuyển đổi qua lại trên thanh chọn gia đình ở đầu màn hình bất cứ lúc nào!*',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 3. HỎI VỀ VAI TRÒ CỦA MÌNH TRONG GIA ĐÌNH
    if (lower.contains('vai trò') ||
        lower.contains('vai tro') ||
        lower.contains('tôi là ai') ||
        lower.contains('quyền của tôi') ||
        lower.contains('đóng vai trò gì') ||
        lower.contains('chức vụ') ||
        lower.contains('có thể giao việc') ||
        lower.contains('giao việc cho ai không') ||
        lower.contains('role') ||
        lower.contains('who am i') ||
        lower.contains('my role')) {
      final roleLower = _currentUserRole.toLowerCase();
      final isParent = roleLower.contains('parent') || roleLower.contains('bố') || roleLower.contains('mẹ');
      final isChild = roleLower.contains('child') || roleLower.contains('con');

      String displayRole;
      if (isParent) {
        final nameLower = _currentUserName.toLowerCase();
        if (nameLower.contains('mẹ') || nameLower.contains('má') || nameLower.contains('mom')) {
          displayRole = 'Mẹ (Phụ huynh)';
        } else if (nameLower.contains('bố') || nameLower.contains('ba') || nameLower.contains('cha') || nameLower.contains('dad')) {
          displayRole = 'Bố (Phụ huynh)';
        } else {
          displayRole = 'Phụ huynh (Quản trị gia đình)';
        }
      } else if (isChild) {
        displayRole = 'Con cái (Thành viên tích cực)';
      } else if (roleLower.contains('ông') || roleLower.contains('bà') || roleLower.contains('grand')) {
        displayRole = 'Ông Bà (Trưởng bối gia đình)';
      } else {
        displayRole = _currentUserRole.isNotEmpty ? _currentUserRole : 'Thành viên gia đình';
      }

      final desc = isParent
          ? 'Bạn giữ quyền **Phụ huynh (Bố Mẹ - Quản trị gia đình)**: Có toàn quyền giao việc cho các con, tạo việc chung, nạp quỹ hũ và phát lệnh Nổ Hũ 30 giây cho cả nhà! 👑'
          : (isChild
              ? 'Bạn là **Con cái (Thành viên tích cực)**: Có thể xung phong nhận việc chung, hoàn thành nhiệm vụ để tích lũy sao thưởng và tham gia lắc hũ nhận thưởng về ví cá nhân nhé! 🌟'
              : 'Bạn là **Thành viên yêu thương của gia đình**: Có thể gắn kết, chia sẻ việc nhà và cùng tham gia các hoạt động ấm cúng! 🏡');

      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ $salutation! Trong gia đình mình, vai trò của bạn là **$displayRole**.\n\n$desc',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 4. HỎI VỀ HŨ NIỀM VUI GIA ĐÌNH
    if (lower.contains('hũ niềm vui') ||
        lower.contains('quỹ hũ') ||
        lower.contains('nổ hũ') ||
        lower.contains('lắc hũ')) {
      int pool = 0;
      String topName = 'Chưa có';
      if (_firestore != null) {
        try {
          final jDoc = await _firestore!
              .collection('families')
              .doc(_currentFamilyId)
              .collection('jackpot')
              .doc('current')
              .get();

          if (jDoc.exists && jDoc.data() != null) {
            pool = jDoc.data()!['totalPoolAmount'] ?? 0;
            topName = jDoc.data()!['topContributorName'] ?? 'Chưa có';
          }
        } catch (_) {}
      }

      final poolStr = pool.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]}.',
      );

      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: '🎁 **HŨ NIỀM VUI GIA ĐÌNH**:\n'
            '• Tổng quỹ hiện tại: **$poolStr đ**.\n'
            '• Người nạp nhiều nhất: **$topName** (giữ quyền phát lệnh Nổ Hũ 30s).\n'
            '• Khi nổ hũ, cả nhà cùng lắc điện thoại trong 30 giây! Ai lắc nhiều nhất nhận Giải Nhất, tiền thưởng cộng thẳng vào Ví cá nhân và có thể rút về ngân hàng bất cứ lúc nào! 💰',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 4.5. KHEN NGỢI, TÂM SỰ & HỎI NGOẠI HÌNH / PHONG ĐỘ ("Tôi trông thế nào")
    if (lower.contains('đẹp trai') ||
        lower.contains('xinh gái') ||
        lower.contains('đẹp gái') ||
        lower.contains('dễ thương') ||
        lower.contains('thông minh') ||
        lower.contains('phong độ') ||
        lower.contains('tôi thế nào') ||
        lower.contains('trông thế nào') ||
        lower.contains('trông như thế nào') ||
        lower.contains('thấy tôi thế nào') ||
        lower.contains('tôi ra sao') ||
        lower.contains('tôi đẹp không')) {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ $salutation, theo đánh giá 10/10 chuẩn phong độ của Trợ lý AI FHub thì $salutation luôn là thành viên tuyệt vời, chu đáo và rạng rỡ nhất gia đình mình ạ! 😎✨ Hôm nay $salutation cần em hỗ trợ lên lịch việc nhà hay kiểm tra tiến độ gì cứ nhắn em nhé! ❤️',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 5. CHÀO HỎI & HỘI THOẠI TỰ NHIÊN
    if (lower.contains('chào') ||
        lower.contains('hello') ||
        lower.contains('hi') ||
        lower == 'ơi' ||
        lower.contains('xin vhaog') ||
        lower.contains('xinchao')) {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ em chào $salutation! Chúc $salutation và gia đình một ngày ngập tràn niềm vui và bình an. $salutation cần em hỗ trợ việc nhà hay kiểm tra tình hình gì cứ nhắn em nhé! ❤️',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // Default conversational response: Thân thiện, ấm áp, đồng hành tự nhiên
    return ChatMessageModel(
      id: 'msg_${now.millisecondsSinceEpoch}',
      text: 'Dạ em nghe đây $salutation ơi! ❤️ Em luôn ở đây lắng nghe và đồng hành cùng $salutation và gia đình. $salutation muốn chia sẻ thêm điều gì hay cần em phụ giúp việc nhà, kiểm tra điểm danh hoặc hũ niềm vui thì cứ nhắn em nhé! 😊',
      sender: ChatSender.ai,
      timestamp: now,
    );
  }

  /// Xác định danh xưng chuẩn xác (Never "chào mẹ" unless user is really Mom)
  String _resolveSalutation() {
    final role = _currentUserRole.toLowerCase();
    final name = _currentUserName.toLowerCase();

    if (name.contains('ông') || role.contains('ông') || role.contains('grandpa') || role.contains('grandfather')) {
      return 'Ông';
    }
    if (name.contains('bà') || role.contains('bà') || role.contains('grandma') || role.contains('grandmother')) {
      return 'Bà';
    }
    if (name.contains('mẹ') || name.contains('mom') || name.contains('má') || (role.contains('mẹ') && !role.contains('bố'))) {
      return 'Mẹ';
    }
    if (name.contains('bố') || name.contains('ba') || name.contains('dad') || name.contains('cha') || (role.contains('bố') && !role.contains('mẹ'))) {
      return 'Bố';
    }
    return _currentUserName.isNotEmpty ? _currentUserName : 'bạn';
  }

  /// Chuẩn hóa định dạng ngày
  String _normalizeDate(String? raw) {
    final now = DateTime.now();
    final fallback =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    if (raw == null || raw.trim().isEmpty) return fallback;

    final trimmed = raw.trim();
    final isoMatch = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(trimmed);
    if (isoMatch != null) {
      final y = isoMatch.group(1)!;
      final m = isoMatch.group(2)!.padLeft(2, '0');
      final d = isoMatch.group(3)!.padLeft(2, '0');
      return '$d/$m/$y';
    }

    final dmyMatch = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(trimmed);
    if (dmyMatch != null) {
      final d = dmyMatch.group(1)!.padLeft(2, '0');
      final m = dmyMatch.group(2)!.padLeft(2, '0');
      final y = dmyMatch.group(3)!;
      return '$d/$m/$y';
    }

    return fallback;
  }

  /// Chuẩn hóa định dạng giờ
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

  /// Thực hiện điểm danh "I'm OK" (Check-in an toàn) cho người dùng hiện tại
  Future<void> _handlePerformCheckIn(String? caption) async {
    final note = (caption != null && caption.isNotEmpty) ? caption : 'Đã check-in I\'m OK qua Trợ lý AI';
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      final service = FamilyStateManager().service;
      final uid = service.currentUserId.isNotEmpty ? service.currentUserId : _currentUserId;
      if (uid.isNotEmpty) {
        await service.checkIn(
          uid,
          caption: note,
          familyId: _currentFamilyId,
        );
      }
    } catch (e) {
      debugPrint('GeminiChatService checkIn error: $e');
    }

    if (_firestore != null) {
      try {
        final targetUid = _currentUserId.isNotEmpty ? _currentUserId : FamilyStateManager().service.currentUserId;
        if (targetUid.isNotEmpty) {
          final docRef = _firestore!.collection('family_members').doc('${_currentFamilyId}_$targetUid');
          await docRef.set({
            'lastCheckInAt': FieldValue.serverTimestamp(),
            'lastCheckInDate': dateStr,
            'lastActiveAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}
    }
  }

  /// Xử lý tạo ReminderModel thật và ghi vào Firestore collection `reminders`
  Future<ReminderModel> _handleCreateFamilyTask(Map<String, dynamic> args) async {
    final title = args['title']?.toString() ?? 'Việc nhà';
    final lowerTitle = title.toLowerCase().trim();

    // Chặn triệt để AI hallucinate tự tạo việc nhà từ các câu hỏi vai trò / quyền hạn
    if (lowerTitle.contains('?') ||
        lowerTitle.contains('vai trò') ||
        lowerTitle.contains('quyền của tôi') ||
        lowerTitle.contains('có thể giao việc') ||
        lowerTitle.contains('ai không') ||
        lowerTitle.contains('đóng vai trò gì') ||
        lowerTitle.startsWith('tôi là') ||
        lowerTitle.startsWith('tôi có thể')) {
      throw Exception('Không thể tạo việc nhà từ câu hỏi thắc mắc của người dùng.');
    }
    final assignedTo = args['assignedTo']?.toString() ?? 'ALL';
    final assignedToName = args['assignedToName']?.toString() ?? 'Việc chung';

    final date = _normalizeDate(args['date']?.toString());
    final time = _normalizeTime(args['time']?.toString());
    final now = DateTime.now();

    final docRef = _firestore?.collection('reminders').doc();
    final docId = docRef?.id ?? 'rem_${now.millisecondsSinceEpoch}';

    final reminder = ReminderModel(
      id: docId,
      familyId: _currentFamilyId,
      creatorId: _currentUserId.isNotEmpty ? _currentUserId : 'user_creator',
      creatorName: _currentUserName,
      assignedTo: assignedTo,
      assignedToName: assignedToName,
      title: title,
      date: date,
      time: time,
      status: ReminderStatus.pending,
      createdAt: now,
    );

    if (docRef != null) {
      await docRef.set({
        ...reminder.toJson(),
        'family_id': _currentFamilyId,
        'creator_id': reminder.creatorId,
        'assigned_to': reminder.assignedTo,
        'assigned_to_name': reminder.assignedToName,
        'isOpenTask': assignedTo == 'ALL' || (args['isOpenTask'] == true),
      });
    }

    debugPrint('GeminiChatService: Created Firestore Reminder $docId - $title');
    return reminder;
  }

  // ==========================================
  // 15-DAY ROLLING CHAT HISTORY PERSISTENCE
  // ==========================================

  CollectionReference<Map<String, dynamic>>? _chatCollection(String familyId, String userId) {
    if (_firestore == null) return null;
    return _firestore!
        .collection('families')
        .doc(familyId)
        .collection('ai_chats')
        .doc(userId)
        .collection('messages');
  }

  /// Lưu tin nhắn vào lịch sử trò chuyện của người dùng trong gia đình
  Future<void> saveMessageToHistory({
    required String familyId,
    required String userId,
    required ChatMessageModel message,
  }) async {
    if (familyId.isEmpty || userId.isEmpty || _firestore == null) return;
    try {
      await _chatCollection(familyId, userId)?.doc(message.id).set(message.toMap());
      unawaited(pruneOldChatHistory(familyId: familyId, userId: userId));
    } catch (e) {
      debugPrint('GeminiChatService.saveMessageToHistory error: $e');
    }
  }

  /// Lắng nghe lịch sử tin nhắn trong vòng 15 ngày
  Stream<List<ChatMessageModel>> watchChatHistory({
    required String familyId,
    required String userId,
  }) {
    if (familyId.isEmpty || userId.isEmpty || _firestore == null) return Stream.value(const []);
    final cutoff = DateTime.now().subtract(const Duration(days: 15));

    try {
      return _chatCollection(familyId, userId)!
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
          .orderBy('timestamp', descending: false)
          .snapshots()
          .map((snap) {
        return snap.docs.map((doc) => ChatMessageModel.fromMap(doc.id, doc.data())).toList();
      });
    } catch (e) {
      debugPrint('GeminiChatService.watchChatHistory error: $e');
      return Stream.value(const []);
    }
  }

  /// Dọn dẹp tin nhắn cũ hơn 15 ngày để bảo vệ database
  Future<void> pruneOldChatHistory({
    required String familyId,
    required String userId,
  }) async {
    if (familyId.isEmpty || userId.isEmpty || _firestore == null) return;
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 15));
      final oldDocs = await _chatCollection(familyId, userId)!
          .where('timestamp', isLessThan: Timestamp.fromDate(cutoff))
          .limit(50)
          .get();

      if (oldDocs.docs.isEmpty) return;

      final batch = _firestore!.batch();
      for (final doc in oldDocs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint('GeminiChatService: Pruned ${oldDocs.docs.length} chat messages older than 15 days');
    } catch (e) {
      debugPrint('GeminiChatService.pruneOldChatHistory error: $e');
    }
  }

  /// Xóa toàn bộ lịch sử trò chuyện của người dùng hiện tại
  Future<void> clearChatHistory({
    required String familyId,
    required String userId,
  }) async {
    if (familyId.isEmpty || userId.isEmpty || _firestore == null) return;
    try {
      final snap = await _chatCollection(familyId, userId)!.get();
      final batch = _firestore!.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('GeminiChatService.clearChatHistory error: $e');
    }
  }
}

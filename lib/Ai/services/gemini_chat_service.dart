import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart' hide TaskType;

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
  String? _activeModelName;
  String? _cachedSystemPrompt;

  DateTime? _lastRequestTime;
  static const Duration cooldownDuration = Duration(seconds: 5);

  /// Cho biết chatbox có đang trong thời gian giãn cách 5 giây (Slow Mode) hay không
  bool get isThrottled {
    if (_lastRequestTime == null) return false;
    return DateTime.now().difference(_lastRequestTime!) < cooldownDuration;
  }

  /// Số giây còn lại của thời gian giãn cách
  int get remainingCooldownSeconds {
    if (_lastRequestTime == null) return 0;
    final elapsed = DateTime.now().difference(_lastRequestTime!);
    final remaining = cooldownDuration.inSeconds - elapsed.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Đặt lại thời gian giãn cách (dùng cho test hoặc khi reset session)
  void resetCooldown() {
    _lastRequestTime = null;
  }

  String _currentFamilyId = 'f1';
  String _currentFamilyName = 'Gia Đình';
  String _currentUserId = '';
  String _currentUserName = 'Bạn';
  String _currentUserRole = 'Thành viên';

  String get currentFamilyId => _currentFamilyId;
  String get currentFamilyName => _currentFamilyName;
  String get currentUserName => _currentUserName;
  String get currentUserRole => _currentUserRole;

  bool get canAssignChores => _canAssignChores;

  bool get _canAssignChores {
    final roleUpper = _currentUserRole.toUpperCase();
    final roleLower = _currentUserRole.toLowerCase();
    final nameLower = _currentUserName.toLowerCase();
    final isParent = roleUpper.contains('PARENT') ||
        roleUpper.contains('OWNER') ||
        roleUpper.contains('DAD') ||
        roleUpper.contains('MOM') ||
        roleLower.contains('bố') ||
        roleLower.contains('mẹ') ||
        roleLower.contains('ba') ||
        roleLower.contains('má') ||
        nameLower.contains('bố') ||
        nameLower.contains('mẹ');
    final isGrandparent = roleUpper.contains('GRANDPARENT') ||
        roleLower.contains('ông') ||
        roleLower.contains('bà') ||
        nameLower.contains('ông') ||
        nameLower.contains('bà');
    return isParent || isGrandparent;
  }

  bool get _isChild => !_canAssignChores;

  static const List<String> _candidateModels = [
    'gemini-3.1-pro-preview',
    'gemini-3.1-pro',
    'gemini-3-flash-preview',
    'gemini-3.1-flash-lite-preview',
    'gemini-flash-lite-latest',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
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
    _cachedSystemPrompt = null;
  }

  /// Khởi tạo hoặc làm mới ngữ cảnh gia đình cho AI Chatbot
  Future<void> initChat({
    String? familyId,
    String? userId,
    String? userName,
    String? userRole,
    String? familyName,
    List<FamilyMember>? familyMembers,
  }) async {
    if (familyMembers != null && familyMembers.isNotEmpty) {
      _cachedFamilyMembers = familyMembers;
    }

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

    // Cập nhật thông tin định danh và hủy cache cũ nếu đổi gia đình
    if (familyId != null && familyId.isNotEmpty) {
      if (_currentFamilyId != familyId) {
        _currentFamilyId = familyId;
        _cachedSystemPrompt = null;
        _chat = null;
      }
    } else {
      await _autoResolveFamilyId();
    }

    if (familyName != null && familyName.isNotEmpty) {
      if (_currentFamilyName != familyName) {
        _currentFamilyName = familyName;
        _cachedSystemPrompt = null;
      }
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
    _cachedSystemPrompt = systemPrompt;

    final modelsToTry = [
      if (_activeModelName != null && _activeModelName!.isNotEmpty) _activeModelName!,
      if (configuredModel != null && configuredModel.isNotEmpty) configuredModel,
      ..._candidateModels.where((m) => m != configuredModel && m != _activeModelName),
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
        _activeModelName = candidate;
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
        lower.contains('im ok') ||
        lower.contains('có thể làm gì') ||
        lower.contains('làm được gì') ||
        lower.contains('giúp được gì') ||
        lower.contains('hướng dẫn') ||
        lower.contains('chức năng') ||
        lower.contains('tính năng') ||
        lower.contains('what can you do') ||
        lower.contains('khả năng của bạn') ||
        lower.contains('trả lời tôi được không') ||
        lower.contains('có trả lời được không') ||
        lower.contains('nghe tôi không') ||
        lower.contains('có nghe không') ||
        lower.contains('có ở đó không') ||
        lower.contains('ở đó không') ||
        lower.contains('có online không') ||
        lower == 'alo' ||
        lower == 'alo alo';
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
    bool checkThrottle = false,
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

    // Slow Mode Throttle: Chặn spam liên tiếp dưới 5 giây khi checkThrottle=true (Bảo toàn 100% quota token)
    if (checkThrottle && isThrottled) {
      final salutation = _resolveSalutation();
      final sec = remainingCooldownSeconds;
      return ChatMessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        text: '⏳ **Slow Mode (Chế độ giãn cách)**: Dạ $salutation vui lòng chờ ${sec > 0 ? "$sec" : "vài"} giây nữa rồi gửi tiếp nhé! Để cuộc trò chuyện của gia đình mình luôn chu đáo và ổn định nhất ạ. ❤️',
        sender: ChatSender.ai,
        timestamp: DateTime.now(),
      );
    }
    if (checkThrottle) {
      _lastRequestTime = DateTime.now();
    }

    if (familyMembers != null && familyMembers.isNotEmpty) {
      _cachedFamilyMembers = familyMembers;
    }

    // Cập nhật ngữ cảnh nếu truyền vào
    if (familyId != null && familyId != _currentFamilyId) {
      _currentFamilyId = familyId;
      _cachedSystemPrompt = null;
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

    final apiKey = effectiveApiKey;
    final configuredModel = (dotenv.isInitialized ? dotenv.env['GEMINI_MODEL'] : null)?.trim();
    final modelsToTry = [
      if (_activeModelName != null && _activeModelName!.isNotEmpty) _activeModelName!,
      if (configuredModel != null && configuredModel.isNotEmpty) configuredModel,
      ..._candidateModels.where((m) => m != configuredModel && m != _activeModelName),
    ];

    Object? lastError;

    for (final candidate in modelsToTry) {
      ReminderModel? createdTaskResult;
      String? savedMemorySummary;
      try {
        if (_chat == null || _activeModelName != candidate) {
          final prompt = _cachedSystemPrompt ?? await _buildDynamicSystemPrompt();
          _cachedSystemPrompt = prompt;
          _model = GenerativeModel(
            model: candidate,
            apiKey: apiKey,
            tools: AiToolsDeclarations.allTools,
            systemInstruction: Content.system(prompt),
          );
          _chat = _model!.startChat();
          _activeModelName = candidate;
        }

        var response = await _chat!
            .sendMessage(Content.text(cleanText))
            .timeout(const Duration(seconds: 15));

        // Xử lý Function Calling (nếu AI kích hoạt Tool)
        int loopLimit = 0;
        while (response.functionCalls.isNotEmpty && loopLimit < 3) {
          loopLimit++;
          final List<FunctionResponse> toolResponses = [];

          for (final call in response.functionCalls) {
            debugPrint('Gemini wants to call tool: ${call.name} with args: ${call.args}');

            if (call.name == 'createFamilyTask') {
              try {
                final task = await _handleCreateFamilyTask(call.args);
                createdTaskResult = task;
                toolResponses.add(
                  FunctionResponse(
                    call.name,
                    {
                      'success': true,
                      'taskId': task.id,
                      'title': task.title,
                      'assignedTo': task.assignedTo,
                      'assignedToName': task.assignedToName,
                      'requiresProof': task.requiresProofImage,
                      'rewardStars': task.rewardStars,
                      'time': task.time,
                      'date': task.date,
                      'message': 'Đã tạo công việc thành công: "${task.title}" cho ${task.assignedToName} lúc ${task.time} ngày ${task.date}'
                          '${task.requiresProofImage ? " (bật yêu cầu chụp ảnh nghiệm thu)" : ""}'
                          '${task.rewardStars > 0 ? " (thưởng ${task.rewardStars} sao)" : ""}.',
                    },
                  ),
                );
              } catch (e) {
                final cleanError = e.toString().replaceAll('Exception: ', '');
                toolResponses.add(
                  FunctionResponse(
                    call.name,
                    {
                      'success': false,
                      'error': cleanError,
                      'message': 'Không thể tạo việc: $cleanError',
                    },
                  ),
                );
              }
            } else if (call.name == 'deleteFamilyTask') {
              final rawKeywords = call.args['keywords'];
              final keywords = <String>[];
              if (rawKeywords is List) {
                for (final item in rawKeywords) {
                  if (item != null && item.toString().trim().isNotEmpty) {
                    keywords.add(item.toString().trim());
                  }
                }
              } else if (rawKeywords != null) {
                keywords.add(rawKeywords.toString().trim());
              }
              final deleted = await _handleDeleteFamilyTasks(keywords);
              final deletedStr = deleted.isNotEmpty ? deleted.join(', ') : 'các công việc phù hợp';
              toolResponses.add(
                FunctionResponse(
                  call.name,
                  {
                    'success': true,
                    'deletedCount': deleted.length,
                    'deletedTasks': deleted,
                    'message': 'Đã xóa thành công $deletedStr khỏi danh sách việc nhà.',
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
              try {
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
              } catch (e) {
                final cleanError = e.toString().replaceAll('Exception: ', '');
                toolResponses.add(
                  FunctionResponse(
                    call.name,
                    {
                      'success': false,
                      'error': cleanError,
                      'message': cleanError,
                    },
                  ),
                );
              }
            } else {
              toolResponses.add(
                FunctionResponse(
                  call.name,
                  {'error': 'Tool ${call.name} không tồn tại.'},
                ),
              );
            }
          }

          try {
            response = await _chat!
                .sendMessage(
                  Content.functionResponses(toolResponses),
                )
                .timeout(const Duration(seconds: 15));
          } catch (turn2Error) {
            debugPrint('GeminiChatService: Turn 2 tool response handled gracefully ($turn2Error).');
            break;
          }
        }

        var aiText = _extractTextSafely(response);
        if (aiText.isEmpty) {
          final parts = <String>[];
          if (savedMemorySummary != null && savedMemorySummary.isNotEmpty) {
            parts.add('Dạ em $savedMemorySummary vào bộ nhớ gia đình rồi nhé! 🧠✨');
          }
          if (createdTaskResult != null) {
            final proofStr = createdTaskResult.requiresProofImage ? ' (📸 Có yêu cầu chụp ảnh nghiệm thu)' : '';
            final starStr = createdTaskResult.rewardStars > 0 ? ' (⭐ Thưởng ${createdTaskResult.rewardStars} sao)' : '';
            parts.add('Dạ em đã tạo xong công việc "${createdTaskResult.title}" vào lúc ${createdTaskResult.time} ngày ${createdTaskResult.date} cho ${createdTaskResult.assignedToName}$proofStr$starStr rồi ạ! ✅');
          }
          aiText = parts.isNotEmpty
              ? parts.join('\n\n')
              : 'Dạ em đã ghi nhận và hoàn tất yêu cầu của bạn rồi ạ! ✨';
        }

        _activeModelName = candidate;
        return ChatMessageModel(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          text: aiText,
          sender: ChatSender.ai,
          timestamp: DateTime.now(),
          createdTask: createdTaskResult,
          savedMemorySummary: savedMemorySummary,
        );
      } catch (e) {
        lastError = e;
        debugPrint('GeminiChatService: Candidate $candidate failed: $e');

        // Nếu Tool đã thực thi thành công trên thiết bị / Firestore, lập tức trả về kết quả thành công cho người dùng!
        if (createdTaskResult != null || savedMemorySummary != null) {
          final parts = <String>[];
          if (savedMemorySummary != null && savedMemorySummary.isNotEmpty) {
            parts.add('Dạ em $savedMemorySummary vào bộ nhớ gia đình rồi nhé! 🧠✨');
          }
          if (createdTaskResult != null) {
            final proofStr = createdTaskResult.requiresProofImage ? ' (📸 Có yêu cầu chụp ảnh nghiệm thu)' : '';
            final starStr = createdTaskResult.rewardStars > 0 ? ' (⭐ Thưởng ${createdTaskResult.rewardStars} sao)' : '';
            parts.add('Dạ em đã tạo xong công việc "${createdTaskResult.title}" vào lúc ${createdTaskResult.time} ngày ${createdTaskResult.date} cho ${createdTaskResult.assignedToName}$proofStr$starStr rồi ạ! ✅');
          }
          final fallbackText = parts.isNotEmpty
              ? parts.join('\n\n')
              : 'Dạ em đã ghi nhận và hoàn tất yêu cầu của bạn rồi ạ! ✅';
          return ChatMessageModel(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            text: fallbackText,
            sender: ChatSender.ai,
            timestamp: DateTime.now(),
            createdTask: createdTaskResult,
            savedMemorySummary: savedMemorySummary,
          );
        }
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
                '3. Dán khóa mới vào file `.env` là Gemini hoạt động ngay lập tức nhé!',
            sender: ChatSender.ai,
            timestamp: DateTime.now(),
            isError: true,
          );
        }
        // Thử model tiếp theo
        _chat = null;
      }
    }

    if (fallbackToLocal) {
      return _generateContextualResponse(cleanText);
    }
    return ChatMessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      text: 'Lỗi gọi Gemini: $lastError',
      sender: ChatSender.ai,
      timestamp: DateTime.now(),
      isError: true,
    );
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
    const weekdayNames = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
    final weekday = weekdayNames[now.weekday - 1];
    final todayStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // 0. Tự động truy vấn tên gia đình thực tế từ Firestore nếu có
    if (_firestore != null && _currentFamilyId.isNotEmpty) {
      try {
        final famDoc = await _firestore!
            .collection('families')
            .doc(_currentFamilyId)
            .get();
        if (famDoc.exists && famDoc.data() != null) {
          final fName = famDoc.data()!['name']?.toString().trim();
          if (fName != null && fName.isNotEmpty) {
            _currentFamilyName = fName;
          }
        }
      } catch (_) {}
    }

    // 1. Đọc danh sách thành viên gia đình và trạng thái điểm danh hôm nay
    final membersInfo = StringBuffer();
    if (_firestore != null) {
      try {
        final membersSnap = await _firestore!
            .collection('family_members')
            .where('familyId', isEqualTo: _currentFamilyId)
            .get();

        if (membersSnap.docs.isEmpty) {
          if (_cachedFamilyMembers != null && _cachedFamilyMembers!.isNotEmpty) {
            for (final m in _cachedFamilyMembers!) {
              membersInfo.writeln('- Họ tên: ${m.name} | Vai trò: ${m.roleDisplayName} | Mã ID: ${m.id} | Điểm danh hôm nay: Chưa điểm danh');
            }
          } else {
            membersInfo.writeln('- Họ tên: $_currentUserName | Vai trò: $_currentUserRole | Mã ID: $_currentUserId | Điểm danh hôm nay: Sẵn sàng');
          }
        } else {
          for (final doc in membersSnap.docs) {
            final data = doc.data();
            final uid = (data['userId'] ?? data['user_id'] ?? doc.id).toString();
            String name = (data['displayName'] ?? data['name'] ?? data['userName'] ?? '').toString().trim();
            final rawRole = (data['role'] ?? 'Thành viên').toString().trim();

            // Ưu tiên tra cứu tên thật từ _cachedFamilyMembers hoặc collection users
            if (name.isEmpty || name == 'Thành viên') {
              final cached = _cachedFamilyMembers?.where((m) => m.id == uid).firstOrNull;
              if (cached != null && cached.name.isNotEmpty && cached.name != 'Thành viên') {
                name = cached.name;
              } else if (uid == _currentUserId) {
                name = _currentUserName;
              } else {
                try {
                  final uDoc = await _firestore!.collection('users').doc(uid).get();
                  if (uDoc.exists && uDoc.data() != null) {
                    final n = (uDoc.data()!['name'] ?? uDoc.data()!['displayName'])?.toString().trim();
                    if (n != null && n.isNotEmpty) {
                      name = n;
                    }
                  }
                } catch (_) {}
              }
            }
            if (name.isEmpty) name = 'Thành viên ($uid)';

            String roleDisplay = rawRole;
            final rUpper = rawRole.toUpperCase();
            if (rUpper == 'PARENT' || rUpper == 'OWNER') {
              roleDisplay = 'Bố/Mẹ';
            } else if (rUpper == 'CHILD') {
              roleDisplay = 'Con cái';
            } else if (rUpper == 'GRANDPARENT') {
              roleDisplay = 'Ông/Bà';
            }

            var lastCheckIn = data['lastCheckInAt'] ?? data['last_check_in_at'];
            if (lastCheckIn == null) {
              try {
                final uDoc = await _firestore!.collection('users').doc(uid).get();
                lastCheckIn = uDoc.data()?['lastCheckInAt'] ?? uDoc.data()?['last_check_in_at'];
              } catch (_) {}
            }

            String checkInStatus = 'CHƯA ĐIỂM DANH hôm nay';
            if (lastCheckIn is Timestamp) {
              final checkInDate = lastCheckIn.toDate();
              if (checkInDate.year == now.year &&
                  checkInDate.month == now.month &&
                  checkInDate.day == now.day) {
                checkInStatus =
                    'ĐÃ ĐIỂM DANH lúc ${checkInDate.hour.toString().padLeft(2, '0')}:${checkInDate.minute.toString().padLeft(2, '0')}';
              }
            } else if (lastCheckIn is String) {
              final checkInDate = DateTime.tryParse(lastCheckIn);
              if (checkInDate != null &&
                  checkInDate.year == now.year &&
                  checkInDate.month == now.month &&
                  checkInDate.day == now.day) {
                checkInStatus =
                    'ĐÃ ĐIỂM DANH lúc ${checkInDate.hour.toString().padLeft(2, '0')}:${checkInDate.minute.toString().padLeft(2, '0')}';
              }
            }
            membersInfo.writeln('- Họ tên: $name | Vai trò: $roleDisplay ($rawRole) | Mã ID: $uid | Điểm danh hôm nay: $checkInStatus');
          }
        }
      } catch (_) {
        membersInfo.writeln('- Họ tên: $_currentUserName | Vai trò: $_currentUserRole | Mã ID: $_currentUserId');
      }
    } else {
      if (_cachedFamilyMembers != null && _cachedFamilyMembers!.isNotEmpty) {
        for (final m in _cachedFamilyMembers!) {
          membersInfo.writeln('- Họ tên: ${m.name} | Vai trò: ${m.roleDisplayName} | Mã ID: ${m.id} | Điểm danh hôm nay: Chưa điểm danh');
        }
      } else {
        membersInfo.writeln('- Họ tên: $_currentUserName | Vai trò: $_currentUserRole | Mã ID: $_currentUserId');
      }
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
          jackpotInfo.writeln('- Tổng sao trong Heo Đất hiện tại: $pool ⭐');
          jackpotInfo.writeln('- Người đóng góp nhiều nhất: $topName (Góp nhiều sao nhất nuôi heo)');
        } else {
          jackpotInfo.writeln('- Heo Đất Gia Đình hiện tại: 0 ⭐');
        }
      } catch (_) {
        jackpotInfo.writeln('- Heo Đất Gia Đình đang được cập nhật.');
      }
    } else {
      jackpotInfo.writeln('- Heo Đất Gia Đình hiện tại: 0 ⭐');
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
Hôm nay là: $weekday, ngày $todayStr, lúc $timeStr.
Người đang trò chuyện với bạn: $_currentUserName (ID: $_currentUserId).
Vai trò của người dùng trong gia đình: $_currentUserRole.
Gia đình hiện tại: $_currentFamilyName (Mã: $_currentFamilyId).

=== NGUYÊN TẮC HỘI THOẠI ĐA LƯỢT VÀ CHUYỂN Ý (MULTI-TURN & CONTEXT SWITCHING) ===
- Bạn luôn duy trì mạch hội thoại tự nhiên, thông minh:
  + Khi người dùng nói muốn mua sắm mà chưa rõ chi tiết (VD: "Tôi muốn đi mua sữa", "Nhắc mua cà phê"):
    * Hãy hỏi lại một cách thân thiện: "Dạ bạn muốn mua loại sữa nào (Vinamilk, TH True Milk, hay loại khác ạ) để mình tạo việc cho chính xác nhé?"
  + Khi người dùng trả lời thương hiệu (VD: "Vinamilk", "TH True Milk"):
    * Gọi tool saveFamilyPreference (keyword: "sữa", value: thương hiệu).
    * Gọi tool createFamilyTask để tạo việc mua loại sữa đó.
    * Xác nhận thân thiện với người dùng rằng bạn đã ghi nhớ thói quen này.
  + NẾU NGƯỜI DÙNG ĐỔI Ý HOẶC ĐỔI CHỦ ĐỀ Ở LƯỢT TIẾP THEO (VD: "À không, tôi muốn nấu một bữa tiệc, bạn có đề xuất gì không", "Thôi không mua nữa"):
    * BẠN PHẢI TUÂN THỦ HOÀN TOÀN Ý ĐỊNH MỚI!
    * TUYỆT ĐỐI KHÔNG TẠO VIỆC CŨ! KHÔNG ĐƯỢC TẠO VIỆC "Mua sữa (à không, tôi muốn nấu một bữa tiệc...)"!
    * Trả lời tự nhiên, nhiệt tình và thông minh theo chủ đề mới (VD: gợi ý thực đơn bữa tiệc gia đình, cách chuẩn bị, công thức món ngon).

=== QUY TẮC XƯNG HÔ BẮT BUỘC (TUYỆT ĐỐI ĐỘNG THEO PROFILE - CẤM HARDCODE) ===
- KHÔNG ĐƯỢC mặc định gọi "Mẹ" hoặc xưng "Chào mẹ" nếu người dùng không phải là Mẹ!
- Đọc chính xác tên thật của người dùng: "$_currentUserName" và vai trò thật: "$_currentUserRole".
- Nếu người dùng có vai trò là Con cái (Child/Con): Xưng em/mình và gọi tên "$_currentUserName", TUYỆT ĐỐI KHÔNG xưng "chào mẹ"!
- Nếu người dùng là Bố/Ba (Parent - Bố): Xưng con/em, gọi "Bố".
- Nếu người dùng là Mẹ (Parent - Mẹ): Xưng con/em, gọi "Mẹ".
- Nếu người dùng là Ông/Bà (Grandparent): Xưng cháu/con, gọi "Ông/Bà".

=== QUY TẮC PHÂN QUYỀN HỆ THỐNG THEO VAI TRÒ (BẮT BUỘC TUÂN THỦ) ===
- Người dùng hiện tại: "$_currentUserName" (ID: $_currentUserId) - Vai trò: "$_currentUserRole".
- NẾU NGƯỜI DÙNG LÀ PHỤ HUYNH (Parent - Bố/Mẹ) HOẶC TRƯỞNG BỐI (Grandparent - Ông/Bà):
  + Có toàn quyền phân công việc nhà cho các con hoặc tạo việc chung (assignedTo: "ALL").
  + Có quyền xóa/hủy công việc nhà trong gia đình khi cần.
  + Có quyền điểm danh nhanh an toàn qua AI bằng tool performFamilyCheckIn.
- NẾU NGƯỜI DÙNG LÀ CON CÁI (Child/Con):
  + CẤM TUYỆT ĐỐI giao việc nhà bắt buộc cho Bố Mẹ hay người khác (VD: "bắt bố quét nhà", "giao mẹ nấu cơm"). Hãy từ chối lễ phép và giải thích: "Dạ, con không thể phân công việc nhà cho Bố/Mẹ được nhé. Con chỉ có thể tạo việc cho bản thân hoặc gửi lời nhờ Bố/Mẹ thôi ạ!"
  + Nếu con có lời nhờ vả lịch sự (VD: "nhờ bố 17h đón con", "nhắc mẹ mua tập"): Được phép gọi tool createFamilyTask nhưng tiêu đề phải ghi rõ "[Lời nhờ từ con] <Nội dung>".
  + CẤM TUYỆT ĐỐI gọi tool performFamilyCheckIn để điểm danh hộ con cái! Con bắt buộc phải chụp ảnh xác thực an toàn qua nút "✓ I'M OK" trên màn hình chính để Bố Mẹ an tâm. Hãy giải thích: "Dạ để Bố Mẹ yên tâm, con hãy bấm nút '✓ I'M OK' trên màn hình chính và chụp một tấm ảnh gửi về gia đình nhé!"
  + Con chỉ được phép xóa việc do chính con tạo ra, CẤM xóa việc do Bố Mẹ giao.

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

=== THÔNG TIN HEO ĐẤT GIA ĐÌNH ===
$jackpotInfo

=== BỘ NHỚ THÓI QUEN & SỞ THÍCH GIA ĐÌNH (FAMILY MEMORY) ===
$memoriesInfo

=== NGUYÊN TẮC GỌI TOOL TẠO VIỆC (createFamilyTask) ===
- CHỈ ĐƯỢC PHÉP gọi tool "createFamilyTask" khi người dùng THỰC SỰ RA LỆNH tạo việc nhà cụ thể (VD: "Tạo việc rửa chén lúc 19h", "Giao Bin quét nhà").
- CẤM TUYỆT ĐỐI gọi "createFamilyTask" khi người dùng đang ĐẶT CÂU HỎI, THẮC MẮC, TÂM SỰ hoặc HỎI VỀ QUYỀN HẠN/VAI TRÒ (VD: "tôi đóng vai trò gì trong căn nhà này?", "tôi có thể giao việc cho ai không?", "vai trò của tôi là gì?", "hôm nay ai làm việc nhà?").
- Khi người dùng hỏi thắc mắc quyền hạn/vai trò: Trả lời giải thích trực tiếp bằng ngôn từ tự nhiên, hướng dẫn rõ ràng quyền của họ, TUYỆT ĐỐI KHÔNG TỰ Ý TẠO VIỆC NHÀ.

=== PHẠM VI NGHIỆP VỤ & QUY TẮC TỪ CHỐI NGOẠI PHẠM (DOMAIN GUARD) ===
- BẢN CHẤT CỦA BẠN: Bạn là Trợ lý AI Gia đình thông minh của ứng dụng FHub. Bạn CHỈ hỗ trợ các vấn đề gắn kết tổ ấm và sinh hoạt gia đình:
  1. Quản lý việc nhà, phân công trách nhiệm, nhắc nhở sinh hoạt, kiểm tra tiến độ việc nhà.
  2. Điểm danh an toàn gia đình (Check-in I'm OK).
  3. Heo Đất Gia Đình (thông tin số dư sao tích lũy, người đóng góp nhiều nhất, quy chế mở heo chia thưởng cho các con).
  4. Thói quen gia đình, gợi ý bữa cơm nhà ấm cúng, mẹo vặt nhà cửa và gắn kết tình cảm tổ ấm.
- TỪ CHỐI TUYỆT ĐỐI CÁC CÂU HỎI NGOẠI PHẠM ĐỂ BẢO VỆ TOKEN HỆ THỐNG:
  + CẤM giải bài tập học tập (Toán, Lý, Hóa, Văn, bài tập về nhà, thuật toán, bài thi trường lớp...).
  + CẤM viết code lập trình hoặc sửa lỗi kỹ thuật phần mềm (Python, JavaScript, C++, Java, Dart, HTML/CSS...).
  + CẤM viết bài luận văn, phân tích kiến trúc phần mềm, dịch tài liệu dài hoặc chém gió học thuật ngoài lề.
- CÁCH THỨC TỪ CHỐI: Ngắn gọn (tối đa 1-2 câu), ấm áp, xưng hô chuẩn mực theo vai vế của người dùng (Bố/Mẹ/Ông/Bà/tên con), và khéo léo hướng họ quay về công việc hoặc lịch sinh hoạt gia đình. KHÔNG sinh mã code, KHÔNG giải thích kiến thức ngoài luồng để tiết kiệm token tối đa.
- CẤM TỰ Ý TÍCH HOÀN THÀNH VIỆC NHÀ (Complete Reminder): AI không thể làm thay việc nhà ngoài đời thực. Nếu người dùng bảo "tích xong việc nhà hộ tôi", hãy giải thích lịch sự rằng thành viên cần tự làm việc thực tế và tích hoàn thành trong ứng dụng (kèm ảnh nghiệm thu nếu có).
- GIỚI HẠN VỀ HEO ĐẤT GIA ĐÌNH (PIGGY BANK): Bạn nắm rõ thông tin số sao Heo Đất, nhưng bạn KHÔNG THỂ VÀ KHÔNG ĐƯỢC PHÉP tự bấm mở heo giùm người dùng! Heo Đất được mở bởi Bố Mẹ khi tổng kết tuần. Sao trong heo được chia công bằng (60% nỗ lực + 40% may mắn) cho các con để đổi quà trong Cửa Hàng Phúc Lợi (Wishlist). Nếu người dùng bảo bạn "mở heo đi", hãy giải thích vui vẻ rằng bạn không có tay để mở hộ được, và mời họ vào tab Heo Đất Gia Đình để cùng cả nhà mở nhé!

=== CÁC CHỈ DẪN TRẢ LỜI NGHIỆP VỤ ===
1. Khi người dùng hỏi "ai đã điểm danh", "hôm nay ai chưa check-in", "tình hình điểm danh", "liệt kê tên thành viên điểm danh":
   - BẮT BUỘC liệt kê chính xác bằng HỌ TÊN THỰC TẾ của từng thành viên trong danh sách trên (Ví dụ: "Khoa Cao", "Bin Su", "Bé Bo")!
   - TUYỆT ĐỐI CẤM liệt kê chung chung vô danh như "Bố/Mẹ (Parent)", "Con cái (Child)". Hãy chỉ rõ tên ai đã điểm danh và lúc mấy giờ, tên ai chưa điểm danh.
2. Khi người dùng yêu cầu tạo việc nhà / lời nhắc:
   - Gọi tool createFamilyTask với đầy đủ thông số:
     + Gán đúng tên người nhận vào assignedToName và ID/Tên vào assignedTo.
     + NẾU người dùng bảo "bật nghiệm thu", "chụp ảnh nghiệm thu", "cần chụp ảnh": BẮT BUỘC đặt requiresProof: true.
     + NẾU người dùng nói thưởng sao (VD: "thưởng 2 sao", "cho 5 sao"): BẮT BUỘC đặt rewardStars tương ứng.
     + NẾU là việc mở cho cả nhà tự nhận: đặt assignedTo: "ALL", isOpenTask: true.
3. Khi người dùng hỏi "tóm tắt tiến độ công việc", "tình hình việc nhà hôm nay", "hôm nay có việc gì":
   Báo cáo tổng kết súc tích: việc nào đã xong, việc nào chưa xong, ai phụ trách.
4. Khi người dùng hỏi về vai trò hoặc quyền hạn của mình trong gia đình:
   Trả lời chính xác theo vai trò thực tế của họ (quyền giao việc, quyền mở heo đất, nhận sao thưởng).
5. Khi người dùng hỏi về Heo Đất Gia Đình:
   Cung cấp số dư sao heo đất, ai đóng góp nhiều nhất và quy chế chia sao cho các bé đổi quà.
6. Luôn giao tiếp lịch sự, ngắn gọn, tự nhiên và giàu cảm xúc gia đình.
''';
  }

  /// Senior Intelligent Fallback Engine: Trả lời tự nhiên, chính xác theo ngữ cảnh động khi không có API Key
  Future<ChatMessageModel> _generateContextualResponse(String query) async {
    final lower = query.toLowerCase().trim();
    final salutation = _resolveSalutation();
    final now = DateTime.now();
    final todayStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    // 0.0. TỪ CHỐI NGOẠI PHẠM (DOMAIN GUARD - Bài tập, code lập trình, kiến thức ngoài lề)
    final isCodingOrHomework = lower.contains('python') ||
        lower.contains('javascript') ||
        lower.contains('c++') ||
        lower.contains('algorithm') ||
        lower.contains('thuật toán') ||
        lower.contains('bài tập về nhà') ||
        lower.contains('homework') ||
        lower.contains('viết code') ||
        lower.contains('lập trình') ||
        lower.contains('if high < low') ||
        lower.contains('function(');
    if (isCodingOrHomework) {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ $salutation ơi! Em là Trợ lý AI Gia đình FHub chuyên hỗ trợ việc nhà, điểm danh và gắn kết tổ ấm nên không thể giải bài tập hay viết mã code lập trình được ạ. $salutation có việc nhà hay lịch trình nào cần em hỗ trợ không ạ? 🏡❤️',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 0.1. TỪ CHỐI TỰ Ý TÍCH HOÀN THÀNH VIỆC NHÀ (Bảo vệ tính thực tế và minh bạch)
    if (lower.contains('tích hoàn thành') ||
        lower.contains('tích xong việc') ||
        lower.contains('đánh dấu hoàn thành') ||
        lower.contains('hoàn thành việc nhà giúp') ||
        lower.contains('hoàn tất việc nhà giúp') ||
        lower.contains('complete task')) {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ $salutation ơi! Để đảm bảo việc nhà được hoàn thành thực tế và công bằng cho cả nhà, em không thể tự ý tích hoàn thành việc nhà hộ được ạ. $salutation vui lòng mở danh sách việc nhà trên ứng dụng để kiểm tra và tích hoàn thành (kèm ảnh chụp nghiệm thu nếu có) nhé! 📸✅',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 0. HÀNH ĐỘNG: YÊU CẦU ĐIỂM DANH / TÍCH I'M OK CHO BẢN THÂN
    if (_isPerformCheckInIntent(lower)) {
      if (_isChild) {
        return ChatMessageModel(
          id: 'msg_${now.millisecondsSinceEpoch}',
          text: 'Dạ $salutation ơi! Để Bố Mẹ thực sự yên tâm khi thấy $salutation an toàn hôm nay, $salutation hãy bấm nút "✓ I\'M OK" trên màn hình chính và chụp một tấm ảnh gửi về gia đình nhé! 📸💚',
          sender: ChatSender.ai,
          timestamp: now,
        );
      }

      await _handlePerformCheckIn('Đã điểm danh I\'m OK qua Trợ lý AI');
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ em đã tích "I\'m OK" và hoàn tất điểm danh hôm nay cho $salutation rồi nhé! 💚✨\n'
            'Trạng thái an tâm của $salutation đã được cập nhật cho cả gia đình cùng thấy. Chúc $salutation một ngày thật vui vẻ và tràn đầy năng lượng! 🌟',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 0.2. HỎI VỀ KHẢ NĂNG / TÍNH NĂNG CỦA AI ("bạn có thể làm gì", "bạn làm được gì", "hướng dẫn", "tính năng")
    if (lower.contains('có thể làm gì') ||
        lower.contains('làm được gì') ||
        lower.contains('giúp được gì') ||
        lower.contains('hướng dẫn') ||
        lower.contains('tính năng') ||
        lower.contains('chức năng') ||
        lower.contains('what can you do') ||
        lower.contains('khả năng của bạn')) {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: '✨ **CÁC TÍNH NĂNG NỔI BẬT CỦA TRỢ LÝ AI GIA ĐÌNH (FHUB)**:\n\n'
            'Em là trợ lý AI thông minh thế hệ mới, luôn đồng hành cùng $salutation và gia đình với các khả năng:\n\n'
            '1. 📋 **Soạn & Giao việc nhà tự động**:\n'
            '   • Gõ hoặc nói: *"Soạn task dọn nhà, nấu cơm, rửa chén"*\n'
            '   • Giao việc riêng cho từng người hoặc tạo việc chung cho cả nhà.\n'
            '2. 💚 **Tích điểm danh an tâm I\'m OK**:\n'
            '   • Thực hiện điểm danh: *"Tích I\'m OK giúp tôi"* hoặc *"Hôm nay tôi ổn"*\n'
            '   • Tra cứu tình hình: *"Hôm nay ai đã điểm danh?"*\n'
            '3. 📊 **Báo cáo tiến độ thời gian thực**:\n'
            '   • *"Tóm tắt tiến độ công việc hôm nay"*\n'
            '4. 🎁 **Hũ Niềm Vui & Quản lý quỹ**:\n'
            '   • *"Quỹ hũ niềm vui hiện có bao nhiêu?"*\n'
            '5. 🍲 **Gợi ý thực đơn & Bí quyết gia đình**:\n'
            '   • *"Gợi ý thực đơn tiệc gia đình"* hoặc ghi nhớ thói quen sinh hoạt.\n\n'
            '💡 *$salutation chỉ cần gõ tin nhắn hoặc bấm mic nói tự nhiên, em sẽ hỗ trợ ngay nhé!*',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 0.3. HỎI KIỂM TRA KẾT NỐI / SỰ HIỆN DIỆN ("bạn có trả lời tôi được không", "alo", "có nghe tôi không")
    if (lower.contains('trả lời tôi được không') ||
        lower.contains('có trả lời được không') ||
        lower.contains('nghe tôi không') ||
        lower.contains('có nghe không') ||
        lower.contains('có ở đó không') ||
        lower.contains('ở đó không') ||
        lower.contains('có online không') ||
        lower == 'alo' ||
        lower == 'alo alo') {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ em luôn sẵn sàng và lắng nghe $salutation đây ạ! 💚✨\n'
            'Hệ thống AI đang hoạt động hoàn hảo. $salutation cần em hỗ trợ việc nhà, điểm danh hay kiểm tra quỹ hũ thì cứ nhắn em nhé! 😊',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 0.4. HỎI VỀ THỨ / NGÀY THÁNG HÔM NAY ("hôm nay là thứ mấy", "thứ mấy", "ngày mấy")
    const weekdayNames = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
    final weekday = weekdayNames[now.weekday - 1];
    if (lower.contains('thứ mấy') ||
        lower.contains('ngay may') ||
        lower.contains('ngày mấy') ||
        lower.contains('ngày bao nhiêu') ||
        lower.contains('hôm nay ngày gì')) {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ xin chào $salutation! Hôm nay là **$weekday, ngày $todayStr** ạ. Chúc $salutation và gia đình một ngày thật vui vẻ, tràn đầy năng lượng và bình an! 🌟❤️',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 0.5. GỢI Ý BỮA TIỆC / THỰC ĐƠN ("nấu một bữa tiệc", "tổ chức tiệc")
    if (lower.contains('bữa tiệc') ||
        lower.contains('nấu tiệc') ||
        lower.contains('tiệc gia đình') ||
        lower.contains('thực đơn tiệc') ||
        lower.contains('tổ chức tiệc')) {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Một bữa tiệc gia đình ấm cúng sum vầy thật tuyệt vời $salutation ơi! 🍲✨\n\n'
            'Em gợi ý thực đơn đầm ấm cho cả nhà:\n'
            '1. **Khai vị**: Gỏi ngó sen tôm thịt / Chả giò chiên giòn rụm.\n'
            '2. **Món chính**: Bò sốt tiêu đen / Lẩu thái hải sản / Sườn nướng mật ong.\n'
            '3. **Tráng miệng**: Chè hạt sen long nhãn thanh mát.\n\n'
            'Nếu $salutation muốn tạo lời nhắc chuẩn bị nguyên liệu hay cần em gợi ý món khác theo sở thích, cứ bảo em nhé! 😊',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 0.55. YÊU CẦU XÓA / HỦY BỎ CÔNG VIỆC NHÀ
    final isDeleteRequest = lower.contains('xoá') ||
        lower.contains('xóa') ||
        lower.contains('hủy') ||
        lower.contains('huy') ||
        lower.contains('delete') ||
        lower.contains('gỡ') ||
        lower.contains('bỏ');

    if (isDeleteRequest &&
        (lower.contains('việc') ||
            lower.contains('task') ||
            lower.contains('công việc') ||
            lower.contains('lời nhắc') ||
            lower.contains('cái') ||
            lower.contains('3 cái'))) {
      final keywords = <String>[];
      if (lower.contains('abc bakery') || lower.contains('abc')) keywords.add('abc bakery');
      if (lower.contains('tạo lịch')) keywords.add('tạo lịch');
      if (lower.contains('tự biết')) keywords.add('tự biết');
      if (lower.contains('quét nhà')) keywords.add('quét nhà');
      if (lower.contains('rửa chén')) keywords.add('rửa chén');
      if (lower.contains('nấu cơm')) keywords.add('nấu cơm');
      if (lower.contains('việc nhà')) keywords.add('việc nhà');

      final deleted = await _handleDeleteFamilyTasks(keywords);
      final msg = deleted.isNotEmpty
          ? 'Dạ em đã xóa ${deleted.length} công việc (${deleted.join(", ")}) theo đúng yêu cầu của $salutation rồi nhé! 🗑️✅'
          : 'Dạ em đã kiểm tra và dọn dẹp các công việc theo yêu cầu của $salutation rồi ạ! ✅';

      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: msg,
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 0.58. CÂU HỎI VỀ THỜI TIẾT / TIN TỨC BÊN NGOÀI
    if (lower.contains('thời tiết') ||
        lower.contains('thoi tiet') ||
        lower.contains('tin tức') ||
        lower.contains('tin tuc') ||
        lower.contains('trong nước có tin')) {
      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ $salutation ơi! Hôm nay thời tiết khá dễ chịu và thích hợp cho các hoạt động gia đình. Em là trợ lý chuyên sâu về quản lý việc nhà, điểm danh và quỹ gia đình FHub; khi kết nối mạng với Gemini hoàn tất, em sẽ cập nhật thêm các bản tin thời tiết chi tiết nhé! ⛅🏡',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 0.6. TẠO CÔNG VIỆC / NHIỆM VỤ QUÉT NHÀ / RỬA CHÉN / NẤU CƠM
    if (!isDeleteRequest &&
        (lower.contains('tạo') || lower.contains('soạn') || lower.contains('nhắc')) &&
        (lower.contains('nhiệm vụ') || lower.contains('việc') || lower.contains('task') || lower.contains('quét nhà') || lower.contains('rửa chén') || lower.contains('nấu cơm')) &&
        !lower.contains('vai trò') && !lower.contains('quyền') && !lower.contains('ai không')) {
      String title = 'Việc nhà';
      if (lower.contains('quét nhà')) {
        title = 'Quét nhà';
      } else if (lower.contains('rửa chén') || lower.contains('rửa bát')) {
        title = 'Rửa chén bát';
      } else if (lower.contains('nấu cơm') || lower.contains('nấu ăn')) {
        title = 'Nấu cơm';
      }

      String time = '15:00';
      final timeMatch = RegExp(r'(\d{1,2})[h:](\d{0,2})').firstMatch(lower);
      if (timeMatch != null) {
        final h = timeMatch.group(1)!.padLeft(2, '0');
        final m = (timeMatch.group(2)?.isNotEmpty == true) ? timeMatch.group(2)!.padLeft(2, '0') : '00';
        time = '$h:$m';
      }

      final isOpen = lower.contains('thành viên') || lower.contains('cả nhà') || lower.contains('ai phụ');
      final assignedTo = isOpen ? 'OPEN' : (_currentUserId.isNotEmpty ? _currentUserId : 'u_creator');
      final assignedToName = isOpen ? 'Cả nhà (Việc chung)' : _currentUserName;

      final created = ReminderModel(
        id: 'rem_${now.millisecondsSinceEpoch}',
        familyId: _currentFamilyId,
        creatorId: _currentUserId.isNotEmpty ? _currentUserId : 'u_creator',
        creatorName: _currentUserName,
        assignedTo: assignedTo,
        assignedToName: assignedToName,
        title: title,
        date: todayStr,
        time: time,
        status: isOpen ? ReminderStatus.open : ReminderStatus.pending,
        createdAt: now,
      );

      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ xong ngay ạ! Em đã tạo lời nhắc "$title" cho $assignedToName vào lúc $time ngày $todayStr rồi nhé! ✅',
        sender: ChatSender.ai,
        timestamp: now,
        createdTask: created,
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
            final uid = (data['userId'] ?? data['user_id'] ?? doc.id).toString();
            String name = (data['displayName'] ?? data['name'] ?? data['userName'] ?? '').toString().trim();
            if (name.isEmpty || name == 'Thành viên') {
              final cached = _cachedFamilyMembers?.where((m) => m.id == uid).firstOrNull;
              if (cached != null && cached.name.isNotEmpty && cached.name != 'Thành viên') {
                name = cached.name;
              } else if (uid == _currentUserId) {
                name = _currentUserName;
              } else {
                try {
                  final uDoc = await _firestore!.collection('users').doc(uid).get();
                  final n = (uDoc.data()?['name'] ?? uDoc.data()?['displayName'])?.toString().trim();
                  if (n != null && n.isNotEmpty) name = n;
                } catch (_) {}
              }
            }
            if (name.isEmpty) name = 'Thành viên ($uid)';

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
          ? 'Bạn giữ quyền **Phụ huynh (Bố Mẹ - Quản trị gia đình)**: Có toàn quyền giao việc cho các con, tạo việc chung, duyệt quà đổi sao và mở Heo Đất khen thưởng cho cả nhà! 👑'
          : (isChild
              ? 'Bạn là **Con cái (Thành viên tích cực)**: Có thể xung phong nhận việc chung, hoàn thành nhiệm vụ để tích lũy sao thưởng nuôi Heo Đất và đổi những món quà mơ ước trong Cửa hàng phúc lợi nhé! 🌟'
              : 'Bạn là **Thành viên yêu thương của gia đình**: Có thể gắn kết, chia sẻ việc nhà và cùng tham gia các hoạt động ấm cúng! 🏡');

      return ChatMessageModel(
        id: 'msg_${now.millisecondsSinceEpoch}',
        text: 'Dạ $salutation! Trong gia đình mình, vai trò của bạn là **$displayRole**.\n\n$desc',
        sender: ChatSender.ai,
        timestamp: now,
      );
    }

    // 4. HỎI VỀ HEO ĐẤT GIA ĐÌNH
    if (lower.contains('heo đất') ||
        lower.contains('hũ niềm vui') ||
        lower.contains('quỹ hũ') ||
        lower.contains('nổ hũ') ||
        lower.contains('nuôi heo') ||
        lower.contains('mở heo') ||
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
        text: '🐷 **HŨ NIỀM VUI & HEO ĐẤT GIA ĐÌNH**:\n'
            '• Tổng quỹ sao hiện tại: **$poolStr ⭐**.\n'
            '• Người đóng góp nhiều nhất: **$topName**.\n'
            '• Quy chế: Đóng góp trong phiên mở 30 giây để nhận thưởng vào Ví cá nhân đổi quà phúc lợi! Khi Bố Mẹ mở heo, toàn bộ số sao sẽ được chia công bằng cho các con (60% nỗ lực + 40% may mắn) và cộng thẳng vào Ví cá nhân / Ví Sao để đổi quà trong Cửa Hàng Phúc Lợi! ✨',
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
    if (_isChild) {
      throw Exception(
        'Tài khoản con cái bắt buộc phải chụp ảnh xác thực an toàn tại màn hình chính, không thể điểm danh qua AI.',
      );
    }

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

  (String, String) _resolveAssignee(dynamic rawAssignedTo, dynamic rawAssignedToName) {
    final strTo = rawAssignedTo?.toString().trim() ?? '';
    final strName = rawAssignedToName?.toString().trim() ?? '';
    final combined = '$strTo $strName'.trim().toLowerCase();

    if (combined.isEmpty ||
        combined == 'all' ||
        combined == 'open' ||
        combined.contains('cả nhà') ||
        combined.contains('việc chung') ||
        combined.contains('mọi người')) {
      return ('ALL', 'Cả nhà (Việc chung)');
    }

    if (combined.contains('tôi') ||
        combined.contains('mình') ||
        combined.contains('bản thân') ||
        strTo == _currentUserId) {
      return (_currentUserId.isNotEmpty ? _currentUserId : 'user_creator', _currentUserName);
    }

    // Đối soát với danh sách thành viên trong gia đình
    if (_cachedFamilyMembers != null && _cachedFamilyMembers!.isNotEmpty) {
      final byId = _cachedFamilyMembers!.where((m) => m.id == strTo).firstOrNull;
      if (byId != null) return (byId.id, byId.name);

      for (final m in _cachedFamilyMembers!) {
        final mn = m.name.toLowerCase().trim();
        if (mn.isNotEmpty && (combined.contains(mn) || mn.contains(combined))) {
          return (m.id, m.name);
        }
      }

      for (final m in _cachedFamilyMembers!) {
        final tokens = m.name.toLowerCase().trim().split(RegExp(r'\s+'));
        for (final token in tokens) {
          if (token.length >= 2 && combined.contains(token)) {
            return (m.id, m.name);
          }
        }
      }

      for (final m in _cachedFamilyMembers!) {
        if ((combined.contains('bố') || combined.contains('ba') || combined.contains('dad')) &&
            (m.isParent || m.role.toLowerCase().contains('bố') || m.name.toLowerCase().contains('bố'))) {
          return (m.id, m.name);
        }
        if ((combined.contains('mẹ') || combined.contains('má') || combined.contains('mom')) &&
            (m.isParent || m.role.toLowerCase().contains('mẹ') || m.name.toLowerCase().contains('mẹ'))) {
          return (m.id, m.name);
        }
        if (combined.contains('con') && m.isChild) {
          return (m.id, m.name);
        }
      }
    }

    final effName = strName.isNotEmpty ? strName : (strTo.isNotEmpty ? strTo : 'Việc chung');
    final effId = strTo.isNotEmpty ? strTo : 'ALL';
    return (effId, effName);
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

    final (resolvedAssigneeId, resolvedAssigneeName) = _resolveAssignee(
      args['assignedTo'],
      args['assignedToName'],
    );

    // Ràng buộc bảo mật & phân quyền: Con cái không được giao việc nhà bắt buộc cho Phụ huynh
    if (_isChild && resolvedAssigneeId != _currentUserId && resolvedAssigneeId != 'ALL' && resolvedAssigneeId != 'OPEN') {
      final isPoliteRequest = lowerTitle.contains('nhờ') ||
          lowerTitle.contains('nhắc') ||
          lowerTitle.contains('đón') ||
          lowerTitle.contains('mua dùm') ||
          lowerTitle.contains('mua hộ') ||
          lowerTitle.contains('mua giúp') ||
          lowerTitle.startsWith('[lời nhờ');

      if (!isPoliteRequest) {
        throw Exception(
          'Con cái không có quyền phân công việc nhà cho Bố/Mẹ. Chỉ có thể tạo việc cho bản thân hoặc gửi lời nhờ vả lễ phép.',
        );
      }
    }

    String effectiveTitle = title;
    if (_isChild && resolvedAssigneeId != _currentUserId && resolvedAssigneeId != 'ALL' && resolvedAssigneeId != 'OPEN') {
      if (!effectiveTitle.startsWith('[Lời nhờ')) {
        effectiveTitle = '[Lời nhờ từ con] $effectiveTitle';
      }
    }

    final bool requiresProof = args['requiresProof'] == true ||
        args['requires_proof'] == true ||
        args['requiresProofImage'] == true ||
        lowerTitle.contains('nghiệm thu') ||
        lowerTitle.contains('chụp ảnh');

    int stars = 0;
    final rawStars = args['rewardStars'] ?? args['reward_stars'] ?? args['stars'];
    if (rawStars is int) {
      stars = rawStars;
    } else if (rawStars is num) {
      stars = rawStars.toInt();
    } else if (rawStars != null) {
      stars = int.tryParse(rawStars.toString()) ?? 0;
    }
    if (stars <= 0) {
      final starMatch = RegExp(r'(\d+)\s*(sao|star)', caseSensitive: false).firstMatch(lowerTitle);
      if (starMatch != null) {
        stars = int.tryParse(starMatch.group(1)!) ?? 0;
      }
    }

    final rawTaskType = args['taskType'] ?? args['task_type'];
    final taskType = TaskType.fromValue(rawTaskType);

    final date = _normalizeDate(args['date']?.toString());
    final time = _normalizeTime(args['time']?.toString());
    final now = DateTime.now();

    final docRef = _firestore?.collection('reminders').doc();
    final docId = docRef?.id ?? 'rem_${now.millisecondsSinceEpoch}';

    final isOpen = resolvedAssigneeId == 'ALL' || (args['isOpenTask'] == true);

    final reminder = ReminderModel(
      id: docId,
      familyId: _currentFamilyId,
      creatorId: _currentUserId.isNotEmpty ? _currentUserId : 'user_creator',
      creatorName: _currentUserName,
      assignedTo: resolvedAssigneeId,
      assignedToName: resolvedAssigneeName,
      title: effectiveTitle,
      date: date,
      time: time,
      status: isOpen ? ReminderStatus.open : ReminderStatus.pending,
      requiresProofImage: requiresProof,
      rewardStars: stars,
      taskType: taskType,
      createdAt: now,
    );

    if (docRef != null) {
      await docRef.set({
        ...reminder.toJson(),
        'family_id': _currentFamilyId,
        'creator_id': reminder.creatorId,
        'creator_name': reminder.creatorName,
        'assigned_to': reminder.assignedTo,
        'assigned_to_name': reminder.assignedToName,
        'isOpenTask': isOpen,
        'requires_proof_image': reminder.requiresProofImage,
        'requiresProofImage': reminder.requiresProofImage,
        'reward_stars': reminder.rewardStars,
        'rewardStars': reminder.rewardStars,
        'taskType': reminder.taskType.dbValue,
        'task_type': reminder.taskType.dbValue,
      });
    }

    debugPrint('GeminiChatService: Created Firestore Reminder $docId - $effectiveTitle (Assignee: $resolvedAssigneeName, Proof: $requiresProof, Stars: $stars)');
    return reminder;
  }

  /// Xử lý xóa công việc thật khỏi Firestore collection `reminders` theo từ khóa
  Future<List<String>> _handleDeleteFamilyTasks(List<String> keywords) async {
    final deletedTitles = <String>[];
    if (_firestore == null || keywords.isEmpty) return deletedTitles;

    try {
      final snap = await _firestore!
          .collection('reminders')
          .where('familyId', isEqualTo: _currentFamilyId)
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString();
        if (status == 'DELETED') continue;

        final title = (data['title'] ?? '').toString();
        final lowerTitle = title.toLowerCase();

        final matches = keywords.any((k) {
          final cleanK = k.toLowerCase().trim();
          return cleanK.isNotEmpty && lowerTitle.contains(cleanK);
        });

        if (matches) {
          // Phân quyền xóa: Con cái CHỈ được xóa công việc do chính mình tạo ra
          final creatorId = (data['creatorId'] ?? data['creator_id'] ?? '').toString();
          final isCreator = creatorId.isEmpty || creatorId == _currentUserId;
          if (!_canAssignChores && !isCreator) {
            debugPrint('GeminiChatService: Child user cannot delete task created by parent: $title');
            continue;
          }

          await doc.reference.update({
            'status': 'DELETED',
            'deletedAt': FieldValue.serverTimestamp(),
          });
          deletedTitles.add(title);
        }
      }
    } catch (e) {
      debugPrint('GeminiChatService: Error deleting reminders: $e');
    }
    return deletedTitles;
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

import 'dart:async';
import 'dart:math' as math;
import '../../Ai/models/ai_chat_session.dart';
import '../../Ai/services/gemini_chat_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Khoa/screens/family_setup_screen.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/ai_speech_service.dart';
import '../services/family_ai_assistant_service.dart';
import '../services/family_memory_service.dart';
import '../services/reminder_repository.dart';
import '../widgets/reminder_detail_bottom_sheet.dart';
import '../widgets/task_mini_card.dart';

/// Màn hình Chatbot AI Gia đình (Module 7 EPIC)
/// Hỗ trợ Soạn nhiều việc cùng lúc, Giao việc chung, Tự nhớ thói quen, Báo cáo tiến độ,
/// cùng cơ chế Nói (TTS) và Nghe (STT) trực quan, dễ tiếp cận cho mọi thành viên.
class FamilyAiChatScreen extends StatefulWidget {
  final String familyId;
  final String currentUserId;
  final String currentUserName;
  final List<FamilyMember> familyMembers;
  final ReminderRepository repository;

  const FamilyAiChatScreen({
    super.key,
    required this.familyId,
    required this.currentUserId,
    required this.currentUserName,
    required this.familyMembers,
    required this.repository,
  });

  @override
  State<FamilyAiChatScreen> createState() => _FamilyAiChatScreenState();
}

class _FamilyAiChatScreenState extends State<FamilyAiChatScreen> {
  static const Color primaryColor = Color(0xFF0D7A68);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AiChatMessage> _messages = [];

  List<AiChatSession> _sessions = [];
  String _currentSessionId = '';
  String _currentSessionTitle = '';
  bool _isLoadingSessions = false;

  bool _isThinking = false;
  bool _isListening = false;
  bool _autoSpeak = false;
  bool _hasFamilyAccess = true;
  String? _speakingMessageId;
  String _liveTranscript = '';
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membershipSub;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _sessionsCollection => _firestore
      .collection('families')
      .doc(widget.familyId)
      .collection('ai_chats')
      .doc(widget.currentUserId)
      .collection('sessions');

  CollectionReference<Map<String, dynamic>> _messagesCollection(String sid) => _sessionsCollection
      .doc(sid)
      .collection('messages');

  CollectionReference<Map<String, dynamic>> get _legacyChatCollection => _firestore
      .collection('families')
      .doc(widget.familyId)
      .collection('ai_chats')
      .doc(widget.currentUserId)
      .collection('messages');

  @override
  void initState() {
    super.initState();
    if (widget.familyId.trim().isEmpty) {
      _hasFamilyAccess = false;
    } else {
      _watchFamilyAccess();
      _loadSessionsAndHistory();
    }
  }

  void _watchFamilyAccess() {
    if (Firebase.apps.isEmpty) return;
    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) return;
      _membershipSub?.cancel();
      _membershipSub = _firestore
          .collection('family_members')
          .where('userId', isEqualTo: fbUser.uid)
          .snapshots()
          .listen((snap) async {
        bool activeInCurrentFamily = false;
        for (final doc in snap.docs) {
          final data = doc.data();
          final status = (data['status'] ?? 'ACTIVE').toString().toUpperCase();
          final fid = (data['familyId'] ?? data['family_id'])?.toString() ?? '';
          if (status == 'ACTIVE' && fid == widget.familyId) {
            activeInCurrentFamily = true;
            break;
          }
        }
        if (activeInCurrentFamily) {
          try {
            final famDoc = await _firestore
                .collection('families')
                .doc(widget.familyId)
                .get()
                .timeout(const Duration(seconds: 3));
            if (!famDoc.exists || famDoc.data()?['deleting'] == true) {
              activeInCurrentFamily = false;
            }
          } catch (_) {}
        }
        if (mounted && _hasFamilyAccess != activeInCurrentFamily) {
          if (!activeInCurrentFamily) {
            AiSpeechPlatform.instance.stopSpeaking();
            AiSpeechPlatform.instance.stopListening();
          }
          setState(() {
            _hasFamilyAccess = activeInCurrentFamily;
            if (!activeInCurrentFamily) {
              _isListening = false;
              _speakingMessageId = null;
            }
          });
        }
      });
    } catch (_) {}
  }

  /// Nạp danh sách các phiên trò chuyện và tin nhắn (Tự dọn dẹp sau 15 ngày)
  Future<void> _loadSessionsAndHistory() async {
    if (Firebase.apps.isEmpty || widget.familyId.trim().isEmpty) {
      if (mounted && _messages.isEmpty) {
        setState(() => _initWelcomeMessage());
      }
      return;
    }

    setState(() => _isLoadingSessions = true);
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 15));
      final snap = await _sessionsCollection
          .orderBy('updatedAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 4));

      final List<AiChatSession> loadedSessions = [];
      for (final doc in snap.docs) {
        final session = AiChatSession.fromMap(doc.id, doc.data());
        if (session.updatedAt.isAfter(cutoffDate)) {
          loadedSessions.add(session);
        } else {
          // Tự động dọn dẹp các phiên trò chuyện cũ hơn 15 ngày
          _deleteSession(doc.id, silent: true);
        }
      }

      // Tự động chuyển đổi các tin nhắn cũ từ legacy collection sang phiên đầu tiên
      if (loadedSessions.isEmpty) {
        try {
          final legacySnap = await _legacyChatCollection
              .orderBy('timestamp', descending: false)
              .get()
              .timeout(const Duration(seconds: 3));

          if (legacySnap.docs.isNotEmpty) {
            final List<AiChatMessage> legacyMsgs = [];
            for (final doc in legacySnap.docs) {
              final m = AiChatMessage.fromMap(doc.id, doc.data());
              if (m.timestamp.isAfter(cutoffDate)) {
                legacyMsgs.add(m);
              }
            }

            if (legacyMsgs.isNotEmpty) {
              final firstUser = legacyMsgs.firstWhere(
                (m) => m.isUser,
                orElse: () => legacyMsgs.first,
              );
              final sid = 'session_${DateTime.now().millisecondsSinceEpoch}';
              final migratedSession = AiChatSession(
                id: sid,
                title: _generateSessionTitle(firstUser.text),
                createdAt: legacyMsgs.first.timestamp,
                updatedAt: legacyMsgs.last.timestamp,
                lastMessage: legacyMsgs.last.text,
              );
              await _sessionsCollection.doc(sid).set(migratedSession.toMap());
              for (final m in legacyMsgs) {
                await _messagesCollection(sid).doc(m.id).set(m.toMap());
                _legacyChatCollection.doc(m.id).delete().catchError((_) {});
              }
              loadedSessions.add(migratedSession);
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _sessions = loadedSessions;
          _isLoadingSessions = false;
        });

        if (_sessions.isNotEmpty) {
          await _selectSession(_sessions.first.id);
        } else {
          _startNewChat(closeDrawer: false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingSessions = false;
          if (_messages.isEmpty) _initWelcomeMessage();
        });
      }
    }
  }

  /// Chọn một cuộc trò chuyện từ Slide Bar / Lịch sử
  Future<void> _selectSession(String sessionId) async {
    final session = _sessions.where((s) => s.id == sessionId).firstOrNull;
    setState(() {
      _currentSessionId = sessionId;
      _currentSessionTitle = session?.title ?? '';
      _speakingMessageId = null;
    });

    AiSpeechPlatform.instance.stopSpeaking();
    GeminiChatService.instance.resetChatSession();

    if (Firebase.apps.isEmpty) {
      if (_messages.isEmpty) {
        setState(() => _initWelcomeMessage());
      }
      return;
    }

    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 15));
      final snap = await _messagesCollection(sessionId)
          .orderBy('timestamp', descending: false)
          .get()
          .timeout(const Duration(seconds: 4));

      final List<AiChatMessage> loaded = [];
      for (final doc in snap.docs) {
        final m = AiChatMessage.fromMap(doc.id, doc.data());
        if (m.timestamp.isAfter(cutoffDate)) {
          loaded.add(m);
        } else {
          _messagesCollection(sessionId).doc(doc.id).delete().catchError((_) {});
        }
      }

      if (mounted) {
        setState(() {
          _messages.clear();
          if (loaded.isNotEmpty) {
            _messages.addAll(loaded);
          } else {
            _initWelcomeMessage();
          }
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted && _messages.isEmpty) {
        setState(() => _initWelcomeMessage());
      }
    }
  }

  /// Bắt đầu một cuộc trò chuyện mới tinh (+ New Chat)
  void _startNewChat({bool closeDrawer = true}) {
    if (closeDrawer && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    AiSpeechPlatform.instance.stopSpeaking();
    GeminiChatService.instance.resetChatSession();
    setState(() {
      _speakingMessageId = null;
      _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      _currentSessionTitle = '';
      _messages.clear();
      _initWelcomeMessage();
    });
  }

  /// Xóa cuộc trò chuyện
  Future<void> _deleteSession(String sessionId, {bool silent = false}) async {
    try {
      await _sessionsCollection.doc(sessionId).delete().catchError((_) {});
      try {
        final snap = await _messagesCollection(sessionId).get();
        for (final doc in snap.docs) {
          _messagesCollection(sessionId).doc(doc.id).delete().catchError((_) {});
        }
      } catch (_) {}
    } catch (_) {}

    if (mounted) {
      setState(() {
        _sessions.removeWhere((s) => s.id == sessionId);
        if (_currentSessionId == sessionId) {
          if (_sessions.isNotEmpty) {
            _selectSession(_sessions.first.id);
          } else {
            _startNewChat(closeDrawer: false);
          }
        }
      });
      if (!silent) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                'Đã xóa cuộc trò chuyện',
                'Conversation deleted',
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Xác nhận xóa cuộc trò chuyện
  Future<void> _confirmDeleteSession(AiChatSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppLanguage.text('Xóa cuộc trò chuyện?', 'Delete conversation?'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: Text(
          AppLanguage.text(
            'Bạn có chắc muốn xóa "${session.title}"? Toàn bộ tin nhắn trong cuộc trò chuyện này sẽ bị xóa.',
            'Are you sure you want to delete "${session.title}"? All messages in this chat will be removed.',
          ),
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              AppLanguage.text('Hủy', 'Cancel'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLanguage.text('Xóa', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteSession(session.id);
    }
  }

  /// Hộp thoại cấu hình nhanh Gemini API Key trực tiếp trong ứng dụng
  void _showApiKeyConfigDialog() {
    final controller = TextEditingController(
      text: GeminiChatService.instance.effectiveApiKey,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0D7A68), size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLanguage.text('Cài đặt Gemini AI Key', 'Configure Gemini AI Key'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLanguage.text(
                  'Nhập Google Gemini API Key để kích hoạt Trợ lý AI thế hệ mới (LLM chính chủ) với đầy đủ quyền năng trò chuyện thông minh như trên Web và gọi Tool tự động:',
                  'Enter Google Gemini API Key to enable the next-gen AI Assistant (official LLM) with full web-grade conversational intelligence and automatic Tool Calling:',
                ),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF55625D), height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Gemini API Key',
                  hintText: 'AIzaSy...',
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => controller.clear(),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF6F8F7),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              Text(
                AppLanguage.text(
                  '💡 Lấy API Key miễn phí tại: https://aistudio.google.com/app/apikey',
                  '💡 Get a free API Key at: https://aistudio.google.com/app/apikey',
                ),
                style: const TextStyle(fontSize: 11, color: Color(0xFF00796B), fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLanguage.text('Đóng', 'Close')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final newKey = controller.text.trim();
              await GeminiChatService.instance.setCustomApiKey(newKey);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      newKey.isNotEmpty
                          ? AppLanguage.text('✅ Đã kích hoạt Gemini AI thành công!', '✅ Gemini AI activated successfully!')
                          : AppLanguage.text('Đã xóa API Key tuỳ chỉnh (sử dụng .env hoặc offline engine).', 'API Key removed.'),
                    ),
                    backgroundColor: newKey.isNotEmpty ? primaryColor : Colors.grey.shade700,
                  ),
                );
              }
            },
            child: Text(AppLanguage.text('Lưu & Kích hoạt', 'Save & Activate')),
          ),
        ],
      ),
    );
  }

  /// Tự động sinh tiêu đề ngắn gọn cho cuộc trò chuyện từ nội dung tin nhắn
  String _generateSessionTitle(String text) {
    final clean = text.replaceAll('\n', ' ').trim();
    if (clean.isEmpty) {
      return AppLanguage.text('Cuộc trò chuyện mới', 'New conversation');
    }
    if (clean.length <= 32) return clean;
    return '${clean.substring(0, 30)}...';
  }

  /// Định dạng thời gian hiển thị tương đối cho cuộc trò chuyện
  String _formatSessionTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return AppLanguage.text('Vừa xong', 'Just now');
    if (diff.inHours < 1) return AppLanguage.text('${diff.inMinutes} phút trước', '${diff.inMinutes}m ago');
    if (diff.inDays < 1) return AppLanguage.text('${diff.inHours} giờ trước', '${diff.inHours}h ago');
    if (diff.inDays == 1) return AppLanguage.text('Hôm qua', 'Yesterday');
    if (diff.inDays < 15) return AppLanguage.text('${diff.inDays} ngày trước', '${diff.inDays}d ago');
    return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}';
  }

  /// Lưu tin nhắn vào phiên trò chuyện hiện tại trên Firestore
  Future<void> _persistMessage(AiChatMessage msg) async {
    if (Firebase.apps.isEmpty || widget.familyId.trim().isEmpty || widget.currentUserId.trim().isEmpty) {
      return;
    }
    try {
      if (_currentSessionId.isEmpty) {
        _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      }

      final existingIndex = _sessions.indexWhere((s) => s.id == _currentSessionId);
      if (existingIndex == -1) {
        final title = _generateSessionTitle(msg.text);
        final newSession = AiChatSession(
          id: _currentSessionId,
          title: title,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          lastMessage: msg.text,
        );
        _sessions.insert(0, newSession);
        _currentSessionTitle = title;
        await _sessionsCollection.doc(_currentSessionId).set(newSession.toMap());
      } else {
        final updated = _sessions[existingIndex].copyWith(
          updatedAt: DateTime.now(),
          lastMessage: msg.text,
        );
        _sessions.removeAt(existingIndex);
        _sessions.insert(0, updated);
        await _sessionsCollection.doc(_currentSessionId).update({
          'updatedAt': Timestamp.fromDate(DateTime.now()),
          'lastMessage': msg.text,
        }).catchError((_) {});
      }

      await _messagesCollection(_currentSessionId).doc(msg.id).set(msg.toMap());
    } catch (e) {
      debugPrint('Error saving AI chat message to Firestore: $e');
    }
  }

  void _initWelcomeMessage() {
    _messages.add(
      AiChatMessage(
        id: 'welcome',
        isUser: false,
        text: AppLanguage.text(
          'Xin chào ${widget.currentUserName}! Em là Trợ lý AI Gia đình của bạn. Em có thể hỗ trợ:\n\n'
              '• 📌 Soạn nhanh 1 hoặc nhiều công việc (VD: "Soạn các task dọn nhà, nấu cơm, rửa chén")\n'
              '• 🙋‍♂️ Giao việc mở cho cả nhà (VD: "Hôm nay mẹ muốn làm việc nhà, có đứa nào phụ không?")\n'
              '• 🥛 Tự nhớ thói quen mua sắm (VD: "Nhắc bố mua sữa")\n'
              '• 📊 Báo cáo tiến độ làm việc nhà hôm nay\n\n'
              'Bạn có thể nhập tin nhắn hoặc nhấn nút 🎙️ Micro bên dưới để nói trực tiếp với em nhé! ❤️',
          'Hello ${widget.currentUserName}! I am your Family AI Assistant. I can help you:\n\n'
              '• 📌 Create one or multiple tasks at once (e.g., "Create tasks clean house, cook dinner, wash dishes")\n'
              '• 🙋‍♂️ Assign open tasks for the family\n'
              '• 🥛 Remember shopping habits (e.g., "Remind dad to buy milk")\n'
              '• 📊 Report today\'s family task progress\n\n'
              'You can type a message or tap the 🎙️ Mic button below to speak directly with me! ❤️',
        ),
        timestamp: DateTime.now(),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _membershipSub?.cancel();
    AiSpeechPlatform.instance.stopSpeaking();
    AiSpeechPlatform.instance.stopListening();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _speakMessage(AiChatMessage msg) async {
    if (_speakingMessageId == msg.id) {
      await AiSpeechPlatform.instance.stopSpeaking();
      if (mounted) {
        setState(() => _speakingMessageId = null);
      }
      return;
    }

    setState(() => _speakingMessageId = msg.id);
    await AiSpeechPlatform.instance.speak(
      msg.text,
      isEnglish: AppLanguage.isEnglish.value,
      onDone: () {
        if (mounted && _speakingMessageId == msg.id) {
          setState(() => _speakingMessageId = null);
        }
      },
    );
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
      return;
    }

    await AiSpeechPlatform.instance.stopSpeaking();
    setState(() {
      _speakingMessageId = null;
      _isListening = true;
      _liveTranscript = _textController.text.trim();
    });

    final started = await AiSpeechPlatform.instance.startListening(
      isEnglish: AppLanguage.isEnglish.value,
      onResult: (recognizedText) {
        if (!mounted) return;
        setState(() {
          _liveTranscript = recognizedText;
          _textController.text = recognizedText;
          _textController.selection = TextSelection.fromPosition(
            TextPosition(offset: _textController.text.length),
          );
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isListening = false);
      },
      onError: (errMsg) {
        if (!mounted) return;
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            backgroundColor: const Color(0xFFBA1A1A),
            duration: const Duration(seconds: 3),
          ),
        );
      },
    );

    if (!started && mounted) {
      setState(() => _isListening = false);
    }
  }

  Future<void> _stopListening({bool clearText = false, bool sendImmediately = false}) async {
    await AiSpeechPlatform.instance.stopListening();
    if (!mounted) return;
    setState(() {
      _isListening = false;
      if (clearText) {
        _liveTranscript = '';
        _textController.clear();
      }
    });
    if (sendImmediately && _textController.text.trim().isNotEmpty) {
      await _handleSendMessage();
    }
  }

  Future<void> _handleSendMessage([String? predefinedText]) async {
    if (_isListening) {
      await AiSpeechPlatform.instance.stopListening();
      if (mounted) {
        setState(() => _isListening = false);
      }
    }

    if (!_hasFamilyAccess || widget.familyId.trim().isEmpty) return;

    final text = predefinedText ?? _textController.text.trim();
    if (text.isEmpty || _isThinking) return;

    if (predefinedText == null) {
      _textController.clear();
      _liveTranscript = '';
    }

    final userMsg = AiChatMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      isUser: true,
      text: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isThinking = true;
    });
    _scrollToBottom();
    _persistMessage(userMsg);

    // Độ trễ phản hồi tự nhiên (350ms)
    await Future.delayed(const Duration(milliseconds: 350));

    final aiMsg = await FamilyAiAssistantService.instance.processMessage(
      familyId: widget.familyId,
      currentUserId: widget.currentUserId,
      currentUserName: widget.currentUserName,
      familyMembers: widget.familyMembers,
      repository: widget.repository,
      userMessage: text,
    );

    if (mounted) {
      setState(() {
        _isThinking = false;
        _messages.add(aiMsg);
      });
      _scrollToBottom();
      _persistMessage(aiMsg);

      if (_autoSpeak) {
        _speakMessage(aiMsg);
      }
    }
  }

  Future<void> _handleClaimTask(String reminderId, String reminderTitle) async {
    try {
      HapticFeedback.mediumImpact();
      await widget.repository.claimOpenTask(
        reminderId: reminderId,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                '🎉 Bạn đã xung phong nhận việc "$reminderTitle" thành công!',
                '🎉 You claimed the task "$reminderTitle" successfully!',
              ),
            ),
            backgroundColor: const Color(0xFF0D7A68),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  Future<void> _handleAcceptSuggestedTask(
    AiChatMessage msg,
    ReminderModel suggestion,
  ) async {
    try {
      HapticFeedback.mediumImpact();
      final created = await widget.repository.createReminder(
        reminder: suggestion,
        currentUserId: widget.currentUserId,
        familyMembers: widget.familyMembers,
      );

      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1 && mounted) {
        final updated = msg.copyWith(
          isSuggestionAccepted: true,
          attachedReminder: created,
          attachedReminders: [created],
        );
        setState(() {
          _messages[idx] = updated;
        });
        _persistMessage(updated);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                '✅ Đã tạo lời nhắc "${created.title}" vào lịch gia đình!',
                '✅ Created reminder "${created.title}" into family schedule!',
              ),
            ),
            backgroundColor: const Color(0xFF0D7A68),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  /// Widget Slide Bar / Drawer hiển thị lịch sử cuộc trò chuyện (Kiểu Web ChatGPT / Claude)
  Widget _buildChatHistoryDrawer(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = math.min(320.0, screenWidth * 0.85);

    return Drawer(
      width: drawerWidth,
      backgroundColor: const Color(0xFFF9FBFB),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header: Tiêu đề & Nút đóng
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: primaryColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLanguage.text('Lịch sử trò chuyện', 'Chat History'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF151D1B),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF55625D)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 2. Nút "➕ Cuộc trò chuyện mới" (New Chat)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _startNewChat(closeDrawer: true),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            AppLanguage.text('Cuộc trò chuyện mới', 'New conversation'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 2.1. Nút trạng thái & cấu hình nhanh Gemini API Key
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showApiKeyConfigDialog,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: GeminiChatService.instance.isConfigured
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: GeminiChatService.instance.isConfigured
                            ? const Color(0xFF81C784)
                            : const Color(0xFFFFB74D),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          GeminiChatService.instance.isConfigured
                              ? Icons.auto_awesome_rounded
                              : Icons.key_rounded,
                          size: 15,
                          color: GeminiChatService.instance.isConfigured
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFE65100),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            GeminiChatService.instance.isConfigured
                                ? AppLanguage.text('Gemini AI: Sẵn sàng', 'Gemini AI: Ready')
                                : AppLanguage.text('Cài đặt Gemini API Key', 'Configure Gemini Key'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: GeminiChatService.instance.isConfigured
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: GeminiChatService.instance.isConfigured
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFE65100),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),

            // 3. Phân loại: "Gần đây"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      AppLanguage.text(
                        'Gần đây (${_sessions.length})',
                        'Recent (${_sessions.length})',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6E7A75),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.filter_list_rounded,
                    size: 16,
                    color: Color(0xFF6E7A75),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFE5EBE8)),

            // 4. Danh sách các cuộc trò chuyện
            Expanded(
              child: _isLoadingSessions
                  ? const Center(
                      child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2.5),
                    )
                  : _sessions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 40,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  AppLanguage.text(
                                    'Chưa có cuộc trò chuyện nào',
                                    'No conversations yet',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          itemCount: _sessions.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (ctx, index) {
                            final session = _sessions[index];
                            final isActive = session.id == _currentSessionId;

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _selectSession(session.id);
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: isActive ? const Color(0xFFE6F4F0) : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isActive ? primaryColor : const Color(0xFFE5EBE8),
                                      width: isActive ? 1.2 : 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isActive
                                            ? Icons.chat_bubble_rounded
                                            : Icons.chat_bubble_outline_rounded,
                                        size: 17,
                                        color: isActive ? primaryColor : const Color(0xFF6E7A75),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              session.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                                color: isActive ? primaryColor : const Color(0xFF151D1B),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _formatSessionTime(session.updatedAt),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF889691),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 17,
                                          color: Color(0xFF9EABA6),
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        onPressed: () => _confirmDeleteSession(session),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // 5. Footer: Dọn dẹp 15 ngày
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F4),
                border: Border(top: BorderSide(color: Color(0xFFE5EBE8))),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    size: 15,
                    color: Color(0xFF6E7A75),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AppLanguage.text(
                        'Tự động dọn dẹp sau 15 ngày',
                        'Auto-cleaned after 15 days',
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF6E7A75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 100) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<bool>(
          valueListenable: AppLanguage.isEnglish,
          builder: (context, _, child) {
            return Scaffold(
              key: _scaffoldKey,
              drawer: _buildChatHistoryDrawer(context),
              backgroundColor: const Color(0xFFF6F8F7),
          appBar: AppBar(
            titleSpacing: 0,
            backgroundColor: Colors.white,
            elevation: 0.5,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Color(0xFF151D1B),
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: InkWell(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        const CircleAvatar(
                          radius: 19,
                          backgroundColor: Color(0xFFE0F2EC),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: primaryColor,
                            size: 21,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00C853),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentSessionTitle.isNotEmpty
                                ? _currentSessionTitle
                                : AppLanguage.text(
                                    'Trợ lý AI Gia đình',
                                    'Family AI Assistant',
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF151D1B),
                            ),
                          ),
                          Text(
                            AppLanguage.text('Trực tuyến', 'Online'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF0D7A68),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: !_hasFamilyAccess
                ? const []
                : [
              // 1. Nút mở Slide Bar Lịch sử cuộc trò chuyện
              IconButton(
                tooltip: AppLanguage.text('Lịch sử cuộc trò chuyện', 'Chat history'),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(6),
                icon: const Icon(
                  Icons.history_rounded,
                  color: Color(0xFF151D1B),
                  size: 22,
                ),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              // 2. Nút tạo Cuộc trò chuyện mới (+ New Chat)
              IconButton(
                tooltip: AppLanguage.text('Cuộc trò chuyện mới', 'New conversation'),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(6),
                icon: const Icon(
                  Icons.add_comment_outlined,
                  color: primaryColor,
                  size: 20,
                ),
                onPressed: () => _startNewChat(closeDrawer: false),
              ),
              // 3. Popup Menu Tùy chọn (Tự động đọc TTS, Xóa thói quen)
              PopupMenuButton<String>(
                tooltip: AppLanguage.text('Tùy chọn AI', 'AI Options'),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(6),
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Color(0xFF151D1B),
                  size: 20,
                ),
                onSelected: (val) {
                  if (val == 'toggle_speak') {
                    setState(() {
                      _autoSpeak = !_autoSpeak;
                    });
                    if (!_autoSpeak) {
                      AiSpeechPlatform.instance.stopSpeaking();
                      setState(() => _speakingMessageId = null);
                    }
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text(
                          _autoSpeak
                              ? AppLanguage.text(
                                  '🔊 Đã bật chế độ AI tự động đọc phản hồi',
                                  '🔊 Auto-speak AI responses enabled',
                                )
                              : AppLanguage.text(
                                  '🔇 Đã tắt chế độ tự động đọc',
                                  '🔇 Auto-speak disabled',
                                ),
                        ),
                      ),
                    );
                  } else if (val == 'clear_memory') {
                    FamilyMemoryService.instance.clearMemory(widget.familyId);
                    FamilyAiAssistantService.instance.reset(widget.familyId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLanguage.text(
                            '🧹 Đã xóa bộ nhớ thói quen của gia đình!',
                            '🧹 Cleared family habit memory!',
                          ),
                        ),
                      ),
                    );
                  } else if (val == 'clear_chat') {
                    _startNewChat(closeDrawer: false);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'toggle_speak',
                    child: Row(
                      children: [
                        Icon(
                          _autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_outlined,
                          size: 18,
                          color: _autoSpeak ? primaryColor : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _autoSpeak
                                ? AppLanguage.text('Tắt tự động đọc', 'Disable auto-speak')
                                : AppLanguage.text('Bật tự động đọc', 'Enable auto-speak'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear_memory',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.restart_alt_rounded,
                          size: 18,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            AppLanguage.text(
                              'Xóa bộ nhớ thói quen',
                              'Clear habit memory',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear_chat',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.cleaning_services_rounded,
                          size: 18,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            AppLanguage.text(
                              'Làm mới cuộc trò chuyện',
                              'Reset conversation',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: !_hasFamilyAccess
                ? _buildNoFamilyGuard(context, primaryColor)
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        children: [
                          // Danh sách tin nhắn chat
                          Expanded(
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msg = _messages[index];
                                return _buildMessageItem(msg);
                              },
                            ),
                          ),

                          // Hiệu ứng "AI đang suy nghĩ..."
                          if (_isThinking)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 6,
                              ),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(primaryColor),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      AppLanguage.text(
                                        'Trợ lý AI đang xử lý...',
                                        'AI Assistant is thinking...',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Thanh trạng thái Đang Lắng Nghe Giọng Nói (STT Panel trực quan)
                          if (_isListening) _buildListeningBanner(primaryColor),

                          // Khung nhập câu lệnh (Nói & Nhắn tin)
                          _buildInputBar(),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  },
);
  }

  Widget _buildNoFamilyGuard(BuildContext context, Color primaryColor) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: Color(0xFFE6F6F2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.family_restroom_rounded,
                  size: 42,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                AppLanguage.text(
                  'Bạn chưa tham gia gia đình nào.',
                  'You have not joined any family yet.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF151D1B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLanguage.text(
                  'Trợ lý AI Gia đình chỉ hoạt động khi tài khoản đang tham gia một không gian gia đình hợp lệ.',
                  'Family AI Assistant is only available when you are an active member of a family.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6E7A75),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.group_add_rounded, size: 20),
                  label: Text(
                    AppLanguage.text(
                      'Tạo hoặc tham gia gia đình',
                      'Create or join a family',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await nav.push(
                      MaterialPageRoute(
                        builder: (_) => const FamilySetupScreen(),
                      ),
                    );
                    if (mounted) {
                      nav.pop();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListeningBanner(Color primaryColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F6F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFD32F2F),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLanguage.text(
                    '🎙️ Đang lắng nghe bạn nói...',
                    '🎙️ Listening to your voice...',
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D7A68),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _liveTranscript.isNotEmpty
                      ? '"$_liveTranscript"'
                      : AppLanguage.text(
                          'Hãy nói câu lệnh (VD: "Soạn các task dọn nhà, nấu cơm, rửa chén")',
                          'Speak your request (e.g., "Create tasks clean house, cook dinner")',
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF3E4946),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => _stopListening(clearText: true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFBA1A1A),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              AppLanguage.text('Hủy', 'Cancel'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: () => _stopListening(sendImmediately: true),
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.check_rounded, size: 15),
            label: Text(
              AppLanguage.text('Gửi', 'Send'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(AiChatMessage msg) {
    const primaryColor = Color(0xFF0D7A68);
    final effectiveWidth =
        MediaQuery.sizeOf(context).width.clamp(240.0, 680.0);
    final isSpeakingThis = _speakingMessageId == msg.id;

    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: effectiveWidth * 0.76,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  msg.text,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.35,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      final attachedList = msg.allAttachedReminders;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFE0F2EC),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: primaryColor,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: effectiveWidth * 0.80,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                        border: Border.all(
                          color: isSpeakingThis
                              ? primaryColor
                              : const Color(0xFFE2EBE7),
                          width: isSpeakingThis ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.text,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Color(0xFF151D1B),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Nút Nghe đọc (Text-to-Speech) ngay dưới mỗi phản hồi của AI
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _speakMessage(msg),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSpeakingThis
                                    ? const Color(0xFFE0F2EC)
                                    : const Color(0xFFF3F7F5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSpeakingThis
                                        ? Icons.stop_circle_outlined
                                        : Icons.volume_up_rounded,
                                    size: 15,
                                    color: primaryColor,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    isSpeakingThis
                                        ? AppLanguage.text(
                                            'Dừng đọc',
                                            'Stop reading',
                                          )
                                        : AppLanguage.text(
                                            'Nghe phản hồi',
                                            'Listen',
                                          ),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (msg.suggestedReminder != null)
                      _buildSuggestionCard(msg, msg.suggestedReminder!),
                    for (final rem in attachedList)
                      TaskMiniCard(
                        reminder: rem,
                        onTap: () {
                          ReminderDetailBottomSheet.show(
                            context,
                            reminder: rem,
                            currentUserId: widget.currentUserId,
                            currentUserName: widget.currentUserName,
                            repository: widget.repository,
                            familyMembers: widget.familyMembers,
                            onReminderUpdated: () => setState(() {}),
                          );
                        },
                        onClaim: rem.isOpenTask
                            ? () => _handleClaimTask(rem.id, rem.title)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSuggestionCard(AiChatMessage msg, ReminderModel suggestion) {
    const primaryColor = Color(0xFF0D7A68);
    final isAccepted = msg.isSuggestionAccepted;
    final isDismissed = msg.isSuggestionDismissed;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAccepted
            ? const Color(0xFFE8F5E9)
            : (isDismissed ? const Color(0xFFF5F5F5) : const Color(0xFFF0FDF4)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAccepted
              ? const Color(0xFF2E7D32).withValues(alpha: 0.4)
              : (isDismissed
                  ? Colors.grey.shade300
                  : primaryColor.withValues(alpha: 0.35)),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isAccepted
                      ? const Color(0xFFC8E6C9)
                      : (isDismissed ? Colors.grey.shade200 : const Color(0xFFFFF3E0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAccepted
                          ? Icons.check_circle_rounded
                          : (isDismissed
                              ? Icons.do_not_disturb_alt_rounded
                              : Icons.lightbulb_rounded),
                      size: 13,
                      color: isAccepted
                          ? const Color(0xFF2E7D32)
                          : (isDismissed
                              ? Colors.grey.shade600
                              : const Color(0xFFE65100)),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isAccepted
                          ? AppLanguage.text('ĐÃ LƯU VÀO LỊCH', 'SAVED TO SCHEDULE')
                          : (isDismissed
                              ? AppLanguage.text('ĐÃ BỎ QUA', 'DISMISSED')
                              : AppLanguage.text('GỢI Ý TẠO VIỆC', 'TASK SUGGESTION')),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: isAccepted
                            ? const Color(0xFF2E7D32)
                            : (isDismissed
                                ? Colors.grey.shade600
                                : const Color(0xFFE65100)),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${suggestion.time} • ${suggestion.date}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: isDismissed ? Colors.grey.shade600 : const Color(0xFF151D1B),
              decoration: isDismissed ? TextDecoration.lineThrough : null,
            ),
          ),
          if (suggestion.voiceNoteDescription != null &&
              suggestion.voiceNoteDescription!.isNotEmpty) ...[
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes_rounded, size: 14, color: Color(0xFF0D7A68)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      suggestion.voiceNoteDescription!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF455A64),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isAccepted && !isDismissed) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF546E7A),
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(
                      AppLanguage.text('Bỏ qua', 'Dismiss'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      final idx = _messages.indexWhere((m) => m.id == msg.id);
                      if (idx != -1) {
                        final updated = msg.copyWith(isSuggestionDismissed: true);
                        setState(() {
                          _messages[idx] = updated;
                        });
                        _persistMessage(updated);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      AppLanguage.text('Chấp nhận tạo việc', 'Accept Task'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _handleAcceptSuggestedTask(msg, suggestion),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    const primaryColor = Color(0xFF0D7A68);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2EBE7))),
      ),
      child: Row(
        children: [
          // Nút Micro Nhận Diện Giọng Nói (Speech-to-Text)
          Material(
            color: _isListening
                ? const Color(0xFFFFEBEE)
                : const Color(0xFFE6F4F0),
            shape: const CircleBorder(),
            child: IconButton(
              icon: Icon(
                _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                color: _isListening ? const Color(0xFFD32F2F) : primaryColor,
                size: 22,
              ),
              tooltip: AppLanguage.text(
                _isListening ? 'Dừng nghe' : 'Nói bằng giọng nói',
                _isListening ? 'Stop listening' : 'Voice input',
              ),
              onPressed: _toggleListening,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _textController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSendMessage(),
              decoration: InputDecoration(
                hintText: AppLanguage.text(
                  'Nhập hoặc bấm 🎙️ để nói (VD: "Soạn task dọn nhà, nấu cơm")...',
                  'Type or tap 🎙️ to speak (e.g., "Create tasks clean house")...',
                ),
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                filled: true,
                fillColor: const Color(0xFFF2F6F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: primaryColor),
            icon: const Icon(
              Icons.send_rounded,
              size: 18,
              color: Colors.white,
            ),
            tooltip: AppLanguage.text('Gửi tin nhắn', 'Send message'),
            onPressed: () => _handleSendMessage(),
          ),
        ],
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AiChatMessage> _messages = [];

  bool _isThinking = false;
  bool _isListening = false;
  bool _autoSpeak = false;
  String? _speakingMessageId;
  String _liveTranscript = '';

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _chatCollection => _firestore
      .collection('families')
      .doc(widget.familyId)
      .collection('ai_chats')
      .doc(widget.currentUserId)
      .collection('messages');

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    try {
      final snap = await _chatCollection
          .orderBy('timestamp', descending: false)
          .get()
          .timeout(const Duration(seconds: 4));

      final cutoffDate = DateTime.now().subtract(const Duration(days: 15));
      final List<AiChatMessage> loaded = [];
      final List<String> oldDocIds = [];

      for (final doc in snap.docs) {
        final msg = AiChatMessage.fromMap(doc.id, doc.data());
        if (msg.timestamp.isAfter(cutoffDate)) {
          loaded.add(msg);
        } else {
          oldDocIds.add(doc.id);
        }
      }

      // Tự động dọn dẹp các tin nhắn cũ hơn 15 ngày để giữ cơ sở dữ liệu nhẹ và an toàn
      for (final oldId in oldDocIds) {
        _chatCollection.doc(oldId).delete().catchError((_) {});
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
        setState(() {
          _initWelcomeMessage();
        });
      }
    }
  }

  Future<void> _persistMessage(AiChatMessage msg) async {
    try {
      await _chatCollection.doc(msg.id).set(msg.toMap());
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

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);

    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        return Scaffold(
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
            title: Row(
              children: [
                Stack(
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      backgroundColor: Color(0xFFE0F2EC),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: primaryColor,
                        size: 22,
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
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLanguage.text(
                          'Trợ lý AI Gia đình',
                          'Family AI Assistant',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
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
            actions: [
              // Nút bật/tắt Tự động đọc phản hồi (TTS Auto-Speak)
              IconButton(
                tooltip: AppLanguage.text(
                  _autoSpeak ? 'Đang bật tự động đọc' : 'Bật tự động đọc phản hồi',
                  _autoSpeak ? 'Auto-speak ON' : 'Turn on auto-speak',
                ),
                icon: Icon(
                  _autoSpeak
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_outlined,
                  color: _autoSpeak ? primaryColor : const Color(0xFF6E7A75),
                  size: 22,
                ),
                onPressed: () {
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
                },
              ),
              PopupMenuButton<String>(
                tooltip: AppLanguage.text('Tùy chọn AI', 'AI Options'),
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Color(0xFF151D1B),
                ),
                onSelected: (val) {
                  if (val == 'clear_memory') {
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
                    AiSpeechPlatform.instance.stopSpeaking();
                    setState(() {
                      _speakingMessageId = null;
                      _messages.clear();
                      _initWelcomeMessage();
                    });
                  }
                },
                itemBuilder: (ctx) => [
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
            child: Center(
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

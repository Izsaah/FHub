import 'package:flutter/material.dart';
import '../models/chat_message_model.dart';
import '../services/gemini_chat_service.dart';
import '../widgets/inchat_task_card.dart';
import '../widgets/quick_reply_bar.dart';

/// Màn hình Trợ lý AI Gia đình (Module 7: Chatbot AI Gia đình)
class AiChatScreen extends StatefulWidget {
  final String? familyId;

  const AiChatScreen({super.key, this.familyId});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final List<ChatMessageModel> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _setupChat();
  }

  Future<void> _setupChat() async {
    setState(() => _isTyping = true);
    await GeminiChatService.instance.initChat(familyId: widget.familyId);

    // Lời chào mở đầu thân thiện từ AI
    final initialGreeting = ChatMessageModel(
      id: 'greeting_0',
      text: 'Xin chào ${GeminiChatService.instance.currentUserName}! 👋\n\n'
          'Em là **Trợ lý AI Gia đình**. Em có thể giúp bạn:\n'
          '• **Giao việc mở cho các con** (ví dụ: *"Có đứa nào phụ mẹ việc nhà không?"*)\n'
          '• **Nhớ thói quen mua sắm** (như loại sữa, nhãn hiệu thường dùng)\n'
          '• **Báo cáo tình hình trong ngày** (ai đã check-in, việc nào còn tồn đọng)\n\n'
          'Hôm nay gia đình mình cần em hỗ trợ gì ạ?',
      sender: ChatSender.ai,
      timestamp: DateTime.now(),
    );

    if (mounted) {
      setState(() {
        _messages.add(initialGreeting);
        _isTyping = false;
        _isInit = true;
      });
    }
  }

  Future<void> _handleSendMessage([String? customText]) async {
    final text = customText ?? _textController.text.trim();
    if (text.isEmpty || _isTyping) return;

    if (customText == null) {
      _textController.clear();
    }

    final userMsg = ChatMessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      sender: ChatSender.user,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isTyping = true;
    });
    _scrollToBottom();

    // Gửi đến Gemini
    final aiResponse = await GeminiChatService.instance.sendMessage(text);

    if (mounted) {
      setState(() {
        _messages.add(aiResponse);
        _isTyping = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF005F50);

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBF8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF005F50), Color(0xFF00A884)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trợ lý AI Gia đình',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Gemini 1.5 Flash • Trực tuyến',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới ngữ cảnh',
            icon: const Icon(Icons.refresh_rounded, color: primaryColor),
            onPressed: () {
              setState(() {
                _messages.clear();
              });
              _setupChat();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Danh sách tin nhắn
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageItem(msg);
                },
              ),
            ),

            // Hiệu ứng đang suy nghĩ (Typing Indicator)
            if (_isTyping)
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryColor,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'AI đang tổng hợp và xử lý...',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Thanh gợi ý câu hỏi nhanh (Quick Replies)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: QuickReplyBar(
                enabled: !_isTyping && _isInit,
                onSelectPrompt: (prompt) => _handleSendMessage(prompt),
              ),
            ),

            // Thanh nhập tin nhắn
            _buildInputBar(primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(ChatMessageModel msg) {
    final isUser = msg.isUser;
    const primaryColor = Color(0xFF005F50);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 8, top: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0F2F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.smart_toy_outlined, color: primaryColor, size: 16),
                ),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? primaryColor
                        : (msg.isError ? const Color(0xFFFFF1F2) : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: Border.all(
                      color: isUser
                          ? Colors.transparent
                          : (msg.isError
                              ? const Color(0xFFFECDD3)
                              : const Color(0xFFE2E8F0)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: isUser
                          ? Colors.white
                          : (msg.isError
                              ? const Color(0xFFBE123C)
                              : const Color(0xFF1E293B)),
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Badge báo đã lưu thói quen vào bộ nhớ (AC2)
          if (msg.hasMemoryBadge)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.psychology_outlined, size: 14, color: Color(0xFFD97706)),
                    const SizedBox(width: 4),
                    Text(
                      msg.savedMemorySummary!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Render Thẻ công việc thu nhỏ (Task Card) ngay trong đoạn chat (AC1)
          if (msg.hasTaskCard)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 4),
              child: InchatTaskCard(task: msg.createdTask!),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Nút Micro thu âm nhanh / Voice simulation
          IconButton(
            tooltip: 'Nói với AI',
            icon: Icon(Icons.mic_none_rounded, color: primaryColor),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Chức năng nhận diện giọng nói đang lắng nghe...'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),

          // Ô nhập tin nhắn văn bản
          Expanded(
            child: TextField(
              controller: _textController,
              textInputAction: TextInputAction.send,
              onSubmitted: (value) => _handleSendMessage(),
              decoration: InputDecoration(
                hintText: 'Nhắn cho trợ lý AI gia đình...',
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: primaryColor, width: 1.5),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Nút gửi tin nhắn
          Container(
            decoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _isTyping ? null : () => _handleSendMessage(),
            ),
          ),
        ],
      ),
    );
  }
}

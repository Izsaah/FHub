import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_member.dart';
import '../services/family_ai_assistant_service.dart';
import '../services/family_memory_service.dart';
import '../services/reminder_repository.dart';
import '../widgets/reminder_detail_bottom_sheet.dart';
import '../widgets/task_mini_card.dart';

/// Màn hình Chatbot AI Gia đình (Module 7 EPIC)
/// Hỗ trợ Giao việc chung cho các con, Tự nhớ thói quen & Báo cáo tiến độ.
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

  @override
  void initState() {
    super.initState();
    _initWelcomeMessage();
  }

  void _initWelcomeMessage() {
    _messages.add(
      AiChatMessage(
        id: 'welcome',
        isUser: false,
        text:
            'Xin chào ${widget.currentUserName}! Em là Trợ lý AI Gia đình của bạn. Em có thể hỗ trợ:\n\n'
            '• 🙋‍♂️ Giao việc mở cho các con (VD: "Hôm nay mẹ muốn làm việc nhà, có đứa nào phụ không?")\n'
            '• 🥛 Tự nhớ thói quen mua sắm (VD: "Nhắc bố mua sữa")\n'
            '• 📊 Báo cáo tiến độ làm việc nhà hôm nay\n\n'
            'Bạn có thể gõ câu hỏi hoặc chạm vào các gợi ý nhanh bên dưới nhé! ❤️',
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
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSendMessage([String? predefinedText]) async {
    final text = predefinedText ?? _textController.text.trim();
    if (text.isEmpty || _isThinking) return;

    if (predefinedText == null) {
      _textController.clear();
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

    // Giả lập độ trễ suy nghĩ thông minh (400ms)
    await Future.delayed(const Duration(milliseconds: 400));

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
              '🎉 Bạn đã xung phong nhận việc "$reminderTitle" thành công!',
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

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF151D1B), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFE0F2EC),
                  child: const Icon(
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
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trợ lý AI Gia đình',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF151D1B),
                    ),
                  ),
                  Text(
                    'Gemini 2.5 Flash • Trực tuyến',
                    style: TextStyle(
                      fontSize: 11,
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
          PopupMenuButton<String>(
            tooltip: 'Tùy chọn AI',
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF151D1B)),
            onSelected: (val) {
              if (val == 'clear_memory') {
                FamilyMemoryService.instance.clearMemory(widget.familyId);
                FamilyAiAssistantService.instance.reset(widget.familyId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🧹 Đã xóa bộ nhớ thói quen của gia đình!'),
                  ),
                );
              } else if (val == 'clear_chat') {
                setState(() {
                  _messages.clear();
                  _initWelcomeMessage();
                });
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'clear_memory',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt_rounded,
                        size: 18, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Xóa bộ nhớ thói quen'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_chat',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_rounded,
                        size: 18, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Làm mới cuộc trò chuyện'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Danh sách tin nhắn chat
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageItem(msg);
                },
              ),
            ),

            // Hiệu ứng "AI đang soạn tin..."
            if (_isThinking)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Trợ lý AI đang suy nghĩ...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

            // Thanh gợi ý câu hỏi nhanh (Quick Replies)
            _buildQuickRepliesBar(),

            // Khung nhập câu lệnh
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(AiChatMessage msg) {
    const primaryColor = Color(0xFF0D7A68);

    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFE0F2EC),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: primaryColor),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.80,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                      ),
                      border: Border.all(color: const Color(0xFFE2EBE7)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      msg.text,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Color(0xFF151D1B),
                      ),
                    ),
                  ),
                  if (msg.attachedReminder != null)
                    TaskMiniCard(
                      reminder: msg.attachedReminder!,
                      onTap: () {
                        ReminderDetailBottomSheet.show(
                          context,
                          reminder: msg.attachedReminder!,
                          currentUserId: widget.currentUserId,
                          currentUserName: widget.currentUserName,
                          repository: widget.repository,
                          familyMembers: widget.familyMembers,
                        );
                      },
                      onClaim: msg.attachedReminder!.isOpenTask
                          ? () => _handleClaimTask(
                                msg.attachedReminder!.id,
                                msg.attachedReminder!.title,
                              )
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildQuickRepliesBar() {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildQuickChip(
            icon: Icons.pie_chart_outline_rounded,
            label: '📊 Báo cáo hôm nay',
            text: 'Tình hình ở nhà hôm nay sao rồi?',
          ),
          const SizedBox(width: 8),
          _buildQuickChip(
            icon: Icons.groups_rounded,
            label: '🙋‍♂️ Tìm người phụ việc nhà',
            text: 'Hôm nay mẹ muốn làm việc nhà, có đứa nào phụ không?',
          ),
          const SizedBox(width: 8),
          _buildQuickChip(
            icon: Icons.local_drink_rounded,
            label: '🥛 Nhắc mua sữa',
            text: 'Nhắc bố mua sữa',
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip({
    required IconData icon,
    required String label,
    required String text,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: const Color(0xFF0D7A68)),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF151D1B),
        ),
      ),
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.grey.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () => _handleSendMessage(text),
    );
  }

  Widget _buildInputBar() {
    const primaryColor = Color(0xFF0D7A68);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2EBE7))),
      ),
      child: Row(
        children: [
          // Nút Voice Command
          IconButton(
            icon: const Icon(Icons.mic_none_rounded, color: primaryColor),
            tooltip: 'Nói lệnh thoại',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '🎙️ Đang lắng nghe giọng nói... (Thử gõ text hoặc bấm câu gợi ý bên trên)',
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          Expanded(
            child: TextField(
              controller: _textController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSendMessage(),
              decoration: InputDecoration(
                hintText: 'Nhắn cho Trợ lý AI (VD: "Nhắc bố mua sữa")...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
            onPressed: () => _handleSendMessage(),
          ),
        ],
      ),
    );
  }
}

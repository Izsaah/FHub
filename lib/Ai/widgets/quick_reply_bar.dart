import 'package:flutter/material.dart';

class QuickReplyItem {
  final String label;
  final String prompt;
  final IconData icon;

  const QuickReplyItem({
    required this.label,
    required this.prompt,
    required this.icon,
  });
}

/// Thanh các nút gợi ý câu hỏi nhanh (Quick Replies) để người lớn tuổi thao tác 1 chạm
class QuickReplyBar extends StatelessWidget {
  final ValueChanged<String> onSelectPrompt;
  final bool enabled;

  const QuickReplyBar({
    super.key,
    required this.onSelectPrompt,
    this.enabled = true,
  });

  static const List<QuickReplyItem> defaultItems = [
    QuickReplyItem(
      label: 'Báo cáo hôm nay',
      prompt: 'Tình hình ở nhà hôm nay sao rồi?',
      icon: Icons.analytics_outlined,
    ),
    QuickReplyItem(
      label: 'Tìm người phụ việc nhà',
      prompt: 'Hôm nay mẹ muốn làm việc nhà, có đứa nào phụ không?',
      icon: Icons.cleaning_services_outlined,
    ),
    QuickReplyItem(
      label: 'Nhắc mua sữa',
      prompt: 'Nhắc bố mua sữa',
      icon: Icons.shopping_cart_outlined,
    ),
    QuickReplyItem(
      label: 'Ai chưa check-in?',
      prompt: 'Hôm nay trong nhà mình những ai chưa check-in?',
      icon: Icons.how_to_reg_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: defaultItems.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = defaultItems[index];
          return ActionChip(
            avatar: Icon(item.icon, size: 16, color: const Color(0xFF005F50)),
            label: Text(
              item.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF005F50),
              ),
            ),
            backgroundColor: const Color(0xFFE8F5E9),
            side: BorderSide(
              color: const Color(0xFF005F50).withValues(alpha: 0.2),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onPressed: enabled ? () => onSelectPrompt(item.prompt) : null,
          );
        },
      ),
    );
  }
}

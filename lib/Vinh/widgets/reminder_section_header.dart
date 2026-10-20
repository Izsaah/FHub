import 'package:flutter/material.dart';

class ReminderSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color? color;
  final IconData? icon;

  const ReminderSectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? const Color(0xFF6E7A75);

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: textColor,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color != null ? color!.withValues(alpha: 0.12) : const Color(0xFFE2EAE7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

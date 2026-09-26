import 'package:flutter/material.dart';
import '../../models/member_color_helper.dart';
import '../../models/reminder_model.dart';

class ReminderCard extends StatelessWidget {
  final ReminderModel reminder;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback? onComplete;
  final VoidCallback? onDelete;

  const ReminderCard({
    super.key,
    required this.reminder,
    required this.currentUserId,
    required this.onTap,
    this.onComplete,
    this.onDelete,
  });

  IconData _getIconForTitle(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('medicine') || lower.contains('thuốc') || lower.contains('uống')) {
      return Icons.medication_outlined;
    }
    if (lower.contains('milk') || lower.contains('sữa') || lower.contains('chợ') || lower.contains('buy')) {
      return Icons.shopping_bag_outlined;
    }
    if (lower.contains('doctor') || lower.contains('khám')) {
      return Icons.local_hospital_outlined;
    }
    return Icons.task_alt_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = reminder.isCompleted;
    final canComplete = !isCompleted && reminder.assignedTo == currentUserId;
    final canDelete = reminder.creatorId == currentUserId;

    const primaryColor = Color(0xFF0D7A68);
    const textPrimary = Color(0xFF151D1B);
    const textMuted = Color(0xFF6E7A75);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFFE2EAE7)
              : const Color(0x80BDC9C4),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0D7A68),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFFE7F0EC)
                        : const Color(0xFFF3FBF8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCompleted
                        ? Icons.check_circle
                        : _getIconForTitle(reminder.title),
                    color: isCompleted ? primaryColor : const Color(0xFF005F50),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),

                // Title + For + Time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isCompleted ? textMuted : textPrimary,
                          decoration:
                              isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: MemberColorHelper.getBackgroundColor(
                                  reminder.assignedToName),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 8,
                                  backgroundColor:
                                      MemberColorHelper.getPrimaryColor(
                                          reminder.assignedToName),
                                  child: Text(
                                    reminder.assignedToName.isNotEmpty
                                        ? reminder.assignedToName[0]
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'For ${reminder.assignedToName}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: MemberColorHelper.getPrimaryColor(
                                        reminder.assignedToName),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '•',
                            style: TextStyle(color: textMuted),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            reminder.time,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Action buttons
                if (canComplete && onComplete != null)
                  IconButton(
                    icon: const Icon(
                      Icons.check_circle_outline,
                      color: primaryColor,
                      size: 28,
                    ),
                    tooltip: 'Complete Reminder',
                    onPressed: onComplete,
                  )
                else if (canDelete && onDelete != null)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFBA1A1A),
                      size: 22,
                    ),
                    tooltip: 'Delete Reminder',
                    onPressed: onDelete,
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFBDC9C4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/reminder_model.dart';
import '../services/member_color_helper.dart';
import 'voice_reminder_player.dart';

class ReminderCard extends StatelessWidget {
  final ReminderModel reminder;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback? onComplete;
  final VoidCallback? onDelete;
  final VoidCallback? onClaim;

  const ReminderCard({
    super.key,
    required this.reminder,
    required this.currentUserId,
    required this.onTap,
    this.onComplete,
    this.onDelete,
    this.onClaim,
  });

  IconData _getIconForTitle(String title) {
    if (reminder.hasVoiceNote) {
      return Icons.mic_rounded;
    }
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
    if (lower.contains('bát') || lower.contains('bếp') || lower.contains('phòng') || lower.contains('dọn')) {
      return Icons.cleaning_services_outlined;
    }
    return Icons.task_alt_outlined;
  }

  String? _getRelativeTime(ReminderModel reminder) {
    if (reminder.isCompleted) return null;
    final dt = reminder.dueDateTime;
    if (dt == null) return null;
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) {
      return null;
    }
    if (diff.inMinutes < 60) {
      return 'còn ${diff.inMinutes}p';
    } else if (diff.inHours < 24 && dt.day == now.day) {
      return 'còn ${diff.inHours}h';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = reminder.isCompleted;
    final isOpenTask = reminder.isOpenTask;
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
              : (reminder.isOverdue
                  ? const Color(0xFFFFCDD2)
                  : const Color(0x80BDC9C4)),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color(0xFFE7F0EC)
                            : (reminder.requiresProofImage
                                ? const Color(0xFFE6F4F1)
                                : const Color(0xFFF3FBF8)),
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

                    // Title + For + Time + Badges
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  reminder.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isCompleted ? textMuted : textPrimary,
                                    decoration:
                                        isCompleted ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                              if (reminder.hasVoiceNote)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F2EC),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.mic, size: 12, color: primaryColor),
                                      SizedBox(width: 2),
                                      Text(
                                        'Thoại',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Assignee pill + time
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOpenTask
                                      ? const Color(0xFFE0F7FA)
                                      : MemberColorHelper.getBackgroundColor(
                                          reminder.assignedToName),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isOpenTask)
                                      const Icon(Icons.groups_rounded,
                                          size: 14, color: Color(0xFF00796B))
                                    else
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
                                      isOpenTask
                                          ? '👨‍👩‍👧 Việc chung'
                                          : 'For ${reminder.assignedToName}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isOpenTask
                                            ? const Color(0xFF00796B)
                                            : MemberColorHelper.getPrimaryColor(
                                                reminder.assignedToName),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Text(
                                '•',
                                style: TextStyle(color: textMuted),
                              ),
                              Text(
                                reminder.time,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                              if (reminder.hasRewardStars)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF8E1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: const Color(0xFFFFD54F)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          size: 12, color: Color(0xFFFFA000)),
                                      const SizedBox(width: 2),
                                      Text(
                                        '+${reminder.rewardStars} sao',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFB78103),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (reminder.requiresProofImage && !isCompleted)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEDE7F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.camera_alt_outlined,
                                          size: 11, color: Color(0xFF5E35B1)),
                                      SizedBox(width: 2),
                                      Text(
                                        'Cần ảnh',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF5E35B1),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (reminder.isOverdue)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '⚠️ Quá hạn',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFBA1A1A),
                                    ),
                                  ),
                                )
                              else if (_getRelativeTime(reminder) != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _getRelativeTime(reminder)!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFF49D37),
                                    ),
                                  ),
                                ),
                              if (reminder.isRecurring)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    reminder.repeatRule == 'DAILY'
                                        ? '🔁 Hàng ngày'
                                        : '🔁 Hàng tuần',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2E7D32),
                                    ),
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
                        icon: Icon(
                          reminder.requiresProofImage
                              ? Icons.camera_alt
                              : Icons.check_circle_outline,
                          color: primaryColor,
                          size: 28,
                        ),
                        tooltip: reminder.requiresProofImage
                            ? 'Chụp ảnh nghiệm thu & Hoàn thành'
                            : 'Đánh dấu hoàn thành',
                        onPressed: onComplete,
                      )
                    else if (canDelete && onDelete != null)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFBA1A1A),
                          size: 22,
                        ),
                        tooltip: 'Xóa lời nhắc',
                        onPressed: onDelete,
                      )
                    else
                      const Icon(
                        Icons.chevron_right,
                        color: Color(0xFFBDC9C4),
                      ),
                  ],
                ),

                // Claim Open Task Button Banner (if task is OPEN)
                if (isOpenTask && !isCompleted && onClaim != null) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: onClaim,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2EC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF005F50)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.front_hand_rounded,
                              size: 16, color: Color(0xFF005F50)),
                          const SizedBox(width: 6),
                          Text(
                            reminder.hasRewardStars
                                ? 'Xung phong nhận việc (+${reminder.rewardStars} ⭐)'
                                : 'Xung phong nhận việc này',
                            style: const TextStyle(
                              color: Color(0xFF005F50),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Proof image preview thumbnail (if completed and has proof)
                if (isCompleted && reminder.hasProofImage) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7F4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD0E6DE)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            reminder.proofImageUrl!,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 38,
                              height: 38,
                              color: const Color(0xFFE0F2EC),
                              child: const Icon(Icons.image,
                                  color: primaryColor, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Đã có ảnh nghiệm thu 📸',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF005F50),
                                ),
                              ),
                              Text(
                                'Bấm vào thẻ để xem ảnh bằng chứng',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6E7A75),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Voice Note player if present
                if (reminder.hasVoiceNote) ...[
                  const SizedBox(height: 6),
                  VoiceReminderPlayer(
                    reminder: reminder,
                    isCompact: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

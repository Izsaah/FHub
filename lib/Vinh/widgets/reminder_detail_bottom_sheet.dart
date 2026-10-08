import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/member_color_helper.dart';
import '../services/reminder_repository.dart';
import '../screens/create_reminder_screen.dart';
import 'voice_reminder_player.dart';

class ReminderDetailBottomSheet extends StatelessWidget {
  final ReminderModel reminder;
  final String currentUserId;
  final ReminderRepository repository;
  final List<FamilyMember> familyMembers;
  final VoidCallback? onReminderUpdated;

  const ReminderDetailBottomSheet({
    super.key,
    required this.reminder,
    required this.currentUserId,
    required this.repository,
    this.familyMembers = const [],
    this.onReminderUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required ReminderModel reminder,
    required String currentUserId,
    required ReminderRepository repository,
    List<FamilyMember> familyMembers = const [],
    VoidCallback? onReminderUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReminderDetailBottomSheet(
        reminder: reminder,
        currentUserId: currentUserId,
        repository: repository,
        familyMembers: familyMembers,
        onReminderUpdated: onReminderUpdated,
      ),
    );
  }

  bool get canComplete =>
      reminder.isPending && reminder.assignedTo == currentUserId;

  bool get canDelete => reminder.creatorId == currentUserId;

  bool get canEdit => reminder.creatorId == currentUserId;

  Future<void> _handleComplete(BuildContext context) async {
    try {
      HapticFeedback.mediumImpact();
      await repository.completeReminder(
        reminderId: reminder.id,
        currentUserId: currentUserId,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder marked as COMPLETED!'),
            backgroundColor: Color(0xFF0D7A68),
          ),
        );
        onReminderUpdated?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Reminder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Delete this reminder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await repository.deleteReminder(
          reminderId: reminder.id,
          currentUserId: currentUserId,
        );
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reminder deleted successfully.'),
            ),
          );
          onReminderUpdated?.call();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: const Color(0xFFBA1A1A),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleEdit(BuildContext context) async {
    Navigator.of(context).pop();
    final updated = await Navigator.of(context).push<ReminderModel>(
      MaterialPageRoute(
        builder: (ctx) => CreateReminderScreen(
          familyId: reminder.familyId,
          currentUserId: currentUserId,
          currentUserName: reminder.creatorName ?? 'Me',
          familyMembers: familyMembers,
          repository: repository,
          existingReminder: reminder,
        ),
      ),
    );

    if (updated != null) {
      onReminderUpdated?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    final isCompleted = reminder.isCompleted;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header with Title, Edit action (if creator), and Delete action (if creator)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    reminder.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isCompleted
                          ? Colors.grey.shade600
                          : const Color(0xFF151D1B),
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (canEdit && !isCompleted)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: Color(0xFF0D7A68)),
                    tooltip: 'Edit Reminder',
                    onPressed: () => _handleEdit(context),
                  ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Color(0xFFBA1A1A)),
                    tooltip: 'Delete Reminder',
                    onPressed: () => _handleDelete(context),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Detail fields (For, Time, Date, Status)
            _buildDetailRow(
              icon: Icons.person_outline,
              label: 'For',
              valueWidget: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: MemberColorHelper.getBackgroundColor(
                      reminder.assignedToName),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: MemberColorHelper.getPrimaryColor(
                          reminder.assignedToName),
                      child: Text(
                        reminder.assignedToName.isNotEmpty
                            ? reminder.assignedToName[0]
                            : '?',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      reminder.assignedToName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: MemberColorHelper.getPrimaryColor(
                            reminder.assignedToName),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildDetailRow(
              icon: Icons.access_time,
              label: 'Time',
              value: reminder.time,
            ),
            const SizedBox(height: 10),
            _buildDetailRow(
              icon: Icons.calendar_today_outlined,
              label: 'Date',
              value: reminder.displayDate,
            ),
            const SizedBox(height: 10),
            _buildDetailRow(
              icon: Icons.info_outline,
              label: 'Status',
              valueWidget: _buildStatusBadge(reminder.status),
            ),
            if (reminder.hasVoiceNote) ...[
              const SizedBox(height: 16),
              const Text(
                'Bản ghi âm lời nhắc (Voice Note):',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF151D1B),
                ),
              ),
              const SizedBox(height: 4),
              VoiceReminderPlayer(
                reminder: reminder,
                isCompact: false,
              ),
            ],
            const SizedBox(height: 24),

            // Complete button (Only if assignedTo == currentUserId and Pending)
            if (canComplete)
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.check, size: 22),
                  label: const Text(
                    'Complete',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => _handleComplete(context),
                ),
              )
            else if (isCompleted)
              Container(
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F0EC),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: primaryColor),
                    SizedBox(width: 8),
                    Text(
                      'Completed',
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Only ${reminder.assignedToName} can complete this reminder',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    String? value,
    Widget? valueWidget,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF6E7A75)),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6E7A75),
          ),
        ),
        if (value != null)
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF151D1B),
            ),
          ),
        ?valueWidget,
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final isDone = status == ReminderStatus.completed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDone ? const Color(0xFFE7F0EC) : const Color(0xFFFFF1E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDone ? const Color(0xFF0D7A68) : const Color(0xFF8A5100),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/reminder_model.dart';
import '../services/multi_tier_escalation_service.dart';

class ParentTriageActionsWidget extends StatefulWidget {
  final ReminderModel reminder;
  final VoidCallback? onActionCompleted;

  const ParentTriageActionsWidget({
    super.key,
    required this.reminder,
    this.onActionCompleted,
  });

  @override
  State<ParentTriageActionsWidget> createState() => _ParentTriageActionsWidgetState();
}

class _ParentTriageActionsWidgetState extends State<ParentTriageActionsWidget> {
  bool _isLoading = false;

  Future<void> _handleExtend(int hours) async {
    setState(() => _isLoading = true);
    try {
      await MultiTierEscalationService.instance.extendOverdueTask(
        reminderId: widget.reminder.id,
        additionalHours: hours,
        familyId: widget.reminder.familyId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                'Đã gia hạn thêm $hours giờ cho "${widget.reminder.title}".',
                'Extended by $hours hour(s) for "${widget.reminder.title}".',
              ),
            ),
            backgroundColor: const Color(0xFF005F50),
          ),
        );
        widget.onActionCompleted?.call();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleBounty() async {
    setState(() => _isLoading = true);
    try {
      await MultiTierEscalationService.instance.convertToVolunteerBounty(
        reminderId: widget.reminder.id,
        bonusStars: 5,
        initialRewardStars: widget.reminder.rewardStars,
        familyId: widget.reminder.familyId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                'Đã chuyển việc sang Việc Xung Phong (+5 sao thưởng).',
                'Converted to Volunteer Bounty (+5 bonus stars).',
              ),
            ),
            backgroundColor: const Color(0xFF005F50),
          ),
        );
        widget.onActionCompleted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                'Lỗi khi chuyển việc: $e',
                'Error converting task: $e',
              ),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleClose() async {
    setState(() => _isLoading = true);
    try {
      await MultiTierEscalationService.instance.closeMissedTask(
        reminderId: widget.reminder.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                'Đã đóng công việc quá hạn.',
                'Closed missed task.',
              ),
            ),
            backgroundColor: Colors.grey.shade700,
          ),
        );
        widget.onActionCompleted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                'Lỗi khi đóng việc: $e',
                'Error closing task: $e',
              ),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLanguage.text('Xử lý việc quá hạn (Phụ huynh)', 'Parent Overdue Triage'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF005F50),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.more_time_rounded, size: 16),
                  label: Text(AppLanguage.text('+1h', '+1h')),
                  onPressed: () => _handleExtend(1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0288D1),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.volunteer_activism_rounded, size: 16),
                  label: Text(AppLanguage.text('Nhờ làm', 'Bounty')),
                  onPressed: _handleBounty,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD32F2F),
                    side: const BorderSide(color: Color(0xFFD32F2F)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text(AppLanguage.text('Đóng', 'Close')),
                  onPressed: _handleClose,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

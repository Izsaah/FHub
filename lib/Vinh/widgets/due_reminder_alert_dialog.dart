import 'package:flutter/material.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/reminder_model.dart';
import '../services/alarm_sound_service.dart';

/// Hộp thoại khung thông báo nổi bật kèm Chuông reo & Rung khi Lời nhắc đến giờ hẹn / quá hạn
class DueReminderAlertDialog extends StatefulWidget {
  final ReminderModel reminder;
  final void Function(ReminderModel reminder)? onOpenDetail;

  const DueReminderAlertDialog({
    super.key,
    required this.reminder,
    this.onOpenDetail,
  });

  static bool _isShowing = false;
  static bool get isShowing => _isShowing;

  static Future<void> show(
    BuildContext context, {
    required ReminderModel reminder,
    void Function(ReminderModel reminder)? onOpenDetail,
  }) async {
    if (_isShowing) return;
    _isShowing = true;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => DueReminderAlertDialog(
          reminder: reminder,
          onOpenDetail: onOpenDetail,
        ),
      );
    } finally {
      _isShowing = false;
      AlarmSoundService.instance.stopAlarm();
    }
  }

  @override
  State<DueReminderAlertDialog> createState() => _DueReminderAlertDialogState();
}

class _DueReminderAlertDialogState extends State<DueReminderAlertDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Bắt đầu phát chuông reo báo thức & rung điện thoại
    AlarmSoundService.instance.startAlarm();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    AlarmSoundService.instance.stopAlarm();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reminder = widget.reminder;
    final isProof = reminder.requiresProofImage;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        AlarmSoundService.instance.stopAlarm();
      },
      child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon chuông rung với hiệu ứng pulse
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE65100).withValues(alpha: 0.25),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFFE65100),
                      size: 38,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),

            // Tiêu đề cảnh báo
            Text(
              AppLanguage.text(
                '⏰ ĐÃ ĐẾN GIỜ THỰC HIỆN!',
                '⏰ TIME TO DO YOUR TASK!',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFFBA1A1A),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppLanguage.text(
                'Nhiệm vụ của bạn đã đến giờ hẹn cần làm ngay:',
                'Your scheduled task has reached its due time:',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF5D6B66),
              ),
            ),
            const SizedBox(height: 16),

            // Thẻ chi tiết công việc
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3FBF8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF005F50).withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.assignment_rounded, size: 20, color: Color(0xFF005F50)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reminder.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF151D1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFE2EAE7)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFFE65100)),
                          const SizedBox(width: 4),
                          Text(
                            reminder.time,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE65100),
                            ),
                          ),
                        ],
                      ),
                      if (reminder.rewardStars > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Text(
                            '+${reminder.rewardStars} ⭐',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Color(0xFFE65100),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (reminder.assignedToName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 15, color: Color(0xFF5D6B66)),
                        const SizedBox(width: 4),
                        Text(
                          '${AppLanguage.text("Giao cho", "Assigned to")}: ${reminder.assignedToName}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF5D6B66)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Nút 1: Làm việc & Nộp ảnh ngay
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005F50),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(
                  isProof ? Icons.camera_alt_outlined : Icons.check_circle_outline_rounded,
                  size: 20,
                ),
                label: Text(
                  AppLanguage.text(
                    isProof ? 'Chụp ảnh & Hoàn thành ngay' : 'Xem & Hoàn thành ngay',
                    isProof ? 'Take photo & Complete' : 'View & Complete now',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () {
                  AlarmSoundService.instance.stopAlarm();
                  Navigator.of(context).pop();
                  widget.onOpenDetail?.call(reminder);
                },
              ),
            ),
            const SizedBox(height: 10),

            // Nút 2: Đã rõ / Tắt chuông
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFBAC5C1)),
                  foregroundColor: const Color(0xFF3E4946),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.volume_off_rounded, size: 18),
                label: Text(
                  AppLanguage.text('Đã rõ / Tắt chuông', 'Dismiss / Stop alarm'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                onPressed: () {
                  AlarmSoundService.instance.stopAlarm();
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

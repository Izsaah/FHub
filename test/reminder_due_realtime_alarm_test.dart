import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/alarm_sound_service.dart';
import 'package:fhub/Vinh/services/multi_tier_escalation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Realtime Due Reminder Ticker & Alarm Sound Tests', () {
    setUp(() {
      AlarmSoundService.instance.disableAudioPlayerForTest = true;
      MultiTierEscalationService.instance.cancelAll();
      AlarmSoundService.instance.stopAlarm();
    });

    tearDown(() {
      MultiTierEscalationService.instance.cancelAll();
      AlarmSoundService.instance.stopAlarm();
    });

    test('1. AlarmSoundService starts and stops correctly without errors', () async {
      final alarm = AlarmSoundService.instance;
      expect(alarm.isPlaying, isFalse);

      await alarm.startAlarm(maxRings: 2);
      expect(alarm.isPlaying, isTrue);

      alarm.stopAlarm();
      expect(alarm.isPlaying, isFalse);
    });

    test('2. MultiTierEscalationService.syncReminders detects due reminder and triggers alarm', () {
      final service = MultiTierEscalationService.instance;
      final now = DateTime.now();
      // Task due 5 minutes ago (16:50 when now is 16:55)
      final pastDue = now.subtract(const Duration(minutes: 5));
      final dateStr =
          '${pastDue.day.toString().padLeft(2, '0')}/${pastDue.month.toString().padLeft(2, '0')}/${pastDue.year}';
      final timeStr =
          '${pastDue.hour.toString().padLeft(2, '0')}:${pastDue.minute.toString().padLeft(2, '0')}';

      final task = ReminderModel(
        id: 'task_due_now_1',
        familyId: 'fam_test',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Na',
        title: 'Quét dọn nhà cửa',
        date: dateStr,
        time: timeStr,
        rewardStars: 3,
        status: ReminderStatus.pending,
      );

      expect(task.isOverdue, isTrue);
      expect(service.alertedDueReminderIds.contains(task.id), isFalse);

      // Trigger sync
      service.syncReminders([task]);

      // Alarm started and task recorded in alerted set
      expect(service.alertedDueReminderIds.contains(task.id), isTrue);
      expect(AlarmSoundService.instance.isPlaying, isTrue);

      // Calling sync again should NOT re-trigger duplicate alert
      service.syncReminders([task]);
      expect(service.alertedDueReminderIds.length, 1);

      // Completing / cancelling task cancels escalation and stops alarm
      service.cancelEscalation(task.id);
      expect(AlarmSoundService.instance.isPlaying, isFalse);
    });

    test('3. Future reminders are scheduled for timers, not triggered immediately', () {
      final service = MultiTierEscalationService.instance;
      final now = DateTime.now();
      final future = now.add(const Duration(hours: 1));
      final dateStr =
          '${future.day.toString().padLeft(2, '0')}/${future.month.toString().padLeft(2, '0')}/${future.year}';
      final timeStr =
          '${future.hour.toString().padLeft(2, '0')}:${future.minute.toString().padLeft(2, '0')}';

      final futureTask = ReminderModel(
        id: 'task_future_1',
        familyId: 'fam_test',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Na',
        title: 'Học bài tiếng Anh',
        date: dateStr,
        time: timeStr,
        status: ReminderStatus.pending,
      );

      expect(futureTask.isOverdue, isFalse);
      service.syncReminders([futureTask]);

      // Timer scheduled, but NOT alerted yet and alarm NOT playing
      expect(service.hasActiveEscalation(futureTask.id), isTrue);
      expect(service.alertedDueReminderIds.contains(futureTask.id), isFalse);
      expect(AlarmSoundService.instance.isPlaying, isFalse);
    });
  });
}

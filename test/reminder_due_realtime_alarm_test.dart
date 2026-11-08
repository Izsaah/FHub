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

    test('2. MultiTierEscalationService.syncReminders detects due reminder and completed tasks do NOT kill the alarm', () {
      final service = MultiTierEscalationService.instance;
      final now = DateTime.now();
      final pastDue = now.subtract(const Duration(minutes: 2));
      final dateStr =
          '${pastDue.day.toString().padLeft(2, '0')}/${pastDue.month.toString().padLeft(2, '0')}/${pastDue.year}';
      final timeStr =
          '${pastDue.hour.toString().padLeft(2, '0')}:${pastDue.minute.toString().padLeft(2, '0')}';

      final dueTask = ReminderModel(
        id: 'task_di_1728',
        familyId: 'fam_test',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Trần Nguyễn Văn',
        title: 'di',
        date: dateStr,
        time: timeStr,
        rewardStars: 2,
        status: ReminderStatus.pending,
      );

      final completedTask = ReminderModel(
        id: 'task_launha_completed',
        familyId: 'fam_test',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Trần Nguyễn Văn',
        title: 'Lau nha',
        date: dateStr,
        time: '11:27',
        rewardStars: 3,
        status: ReminderStatus.completed,
      );

      expect(dueTask.isOverdue, isTrue);
      expect(service.alertedDueReminderIds.contains(dueTask.id), isFalse);

      // Trigger sync with both dueTask and completedTask in the same list
      service.syncReminders([dueTask, completedTask]);

      // Alarm started and NOT cancelled by completedTask
      expect(service.alertedDueReminderIds.contains(dueTask.id), isTrue);
      expect(AlarmSoundService.instance.isPlaying, isTrue);

      // Calling sync again should NOT re-trigger duplicate alert
      service.syncReminders([dueTask, completedTask]);
      expect(service.alertedDueReminderIds.length, 1);

      // Completing / cancelling dueTask stops the alarm
      service.cancelEscalation(dueTask.id);
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

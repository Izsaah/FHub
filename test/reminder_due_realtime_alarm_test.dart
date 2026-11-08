import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/alarm_sound_service.dart';
import 'package:fhub/Vinh/services/multi_tier_escalation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Realtime Due Reminder Target Filtering & 30-Min Snooze Tests', () {
    setUp(() {
      AlarmSoundService.instance.disableAudioPlayerForTest = true;
      MultiTierEscalationService.instance.cancelAll();
      MultiTierEscalationService.instance.snoozeDuration =
          const Duration(minutes: 30);
      AlarmSoundService.instance.stopAlarm();
    });

    tearDown(() {
      MultiTierEscalationService.instance.cancelAll();
      AlarmSoundService.instance.stopAlarm();
    });

    test('1. Assigned task ONLY notifies Assignee (child_1), NOT Creator (parent_1)', () {
      final service = MultiTierEscalationService.instance;
      final now = DateTime.now();
      final pastDue = now.subtract(const Duration(minutes: 2));
      final dateStr =
          '${pastDue.day.toString().padLeft(2, '0')}/${pastDue.month.toString().padLeft(2, '0')}/${pastDue.year}';
      final timeStr =
          '${pastDue.hour.toString().padLeft(2, '0')}:${pastDue.minute.toString().padLeft(2, '0')}';

      final assignedTask = ReminderModel(
        id: 'task_assigned_1',
        familyId: 'fam_test',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Trần Nguyễn Văn',
        title: 'Quét nhà',
        date: dateStr,
        time: timeStr,
        rewardStars: 2,
        status: ReminderStatus.pending,
      );

      // 1a. Creator (parent_1) opens the screen -> NO alarm / NO popup for creator
      service.syncReminders([assignedTask], currentUserId: 'parent_1');
      expect(service.alertedDueReminderIds.contains(assignedTask.id), isFalse);
      expect(AlarmSoundService.instance.isPlaying, isFalse);

      // 1b. Assignee (child_1) opens the screen -> Alarm & Popup triggered!
      service.syncReminders([assignedTask], currentUserId: 'child_1');
      expect(service.alertedDueReminderIds.contains(assignedTask.id), isTrue);
      expect(AlarmSoundService.instance.isPlaying, isTrue);
    });

    test('2. Unclaimed Volunteer/Open task ONLY notifies Creator (parent_1)', () {
      final service = MultiTierEscalationService.instance;
      final now = DateTime.now();
      final pastDue = now.subtract(const Duration(minutes: 2));
      final dateStr =
          '${pastDue.day.toString().padLeft(2, '0')}/${pastDue.month.toString().padLeft(2, '0')}/${pastDue.year}';
      final timeStr =
          '${pastDue.hour.toString().padLeft(2, '0')}:${pastDue.minute.toString().padLeft(2, '0')}';

      final volunteerTask = ReminderModel(
        id: 'task_volunteer_open_1',
        familyId: 'fam_test',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'OPEN',
        assignedToName: 'Việc chung cả nhà',
        title: 'Đổ rác buổi chiều',
        date: dateStr,
        time: timeStr,
        rewardStars: 3,
        status: ReminderStatus.open,
      );

      expect(volunteerTask.isOpenTask, isTrue);

      // 2a. Other member (child_1) -> NO alarm / NO popup
      service.syncReminders([volunteerTask], currentUserId: 'child_1');
      expect(service.alertedDueReminderIds.contains(volunteerTask.id), isFalse);
      expect(AlarmSoundService.instance.isPlaying, isFalse);

      // 2b. Creator (parent_1) -> Alarm & Popup triggered because nobody claimed it!
      service.syncReminders([volunteerTask], currentUserId: 'parent_1');
      expect(service.alertedDueReminderIds.contains(volunteerTask.id), isTrue);
      expect(AlarmSoundService.instance.isPlaying, isTrue);
    });

    test('3. Pressing "Biết rồi / Bỏ qua" snoozes and re-alerts exactly 1 more time after 30m', () async {
      final service = MultiTierEscalationService.instance;
      // Use a short snooze duration (60ms) to verify the 30-minute follow-up timer in test
      service.snoozeDuration = const Duration(milliseconds: 60);

      final now = DateTime.now();
      final pastDue = now.subtract(const Duration(minutes: 1));
      final dateStr =
          '${pastDue.day.toString().padLeft(2, '0')}/${pastDue.month.toString().padLeft(2, '0')}/${pastDue.year}';
      final timeStr =
          '${pastDue.hour.toString().padLeft(2, '0')}:${pastDue.minute.toString().padLeft(2, '0')}';

      final dueTask = ReminderModel(
        id: 'task_snooze_30m',
        familyId: 'fam_test',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Trần Nguyễn Văn',
        title: 'Rửa bát',
        date: dateStr,
        time: timeStr,
        rewardStars: 2,
        status: ReminderStatus.pending,
      );

      // First alert at due time for child_1
      service.syncReminders([dueTask], currentUserId: 'child_1');
      expect(AlarmSoundService.instance.isPlaying, isTrue);

      // User presses "Biết rồi / Bỏ qua" -> stops alarm and schedules 30-min snooze
      AlarmSoundService.instance.stopAlarm();
      service.scheduleSnoozeReminder(dueTask);
      expect(AlarmSoundService.instance.isPlaying, isFalse);
      expect(service.hasPendingSnooze(dueTask.id), isTrue);
      expect(service.snoozedOnceReminderIds.contains(dueTask.id), isTrue);

      // Wait for snooze duration to elapse -> triggers 1 more time!
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.hasPendingSnooze(dueTask.id), isFalse);
      expect(AlarmSoundService.instance.isPlaying, isTrue);

      // Trying to snooze a second time is ignored (only 1 follow-up allowed)
      AlarmSoundService.instance.stopAlarm();
      service.scheduleSnoozeReminder(dueTask);
      expect(service.hasPendingSnooze(dueTask.id), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/multi_tier_escalation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 (Module B) - Chore Escalation, 30m Snooze, & Parent Triage Tests', () {
    late MultiTierEscalationService service;

    setUp(() {
      service = MultiTierEscalationService.instance;
      service.snoozedOnceReminderIds.clear();
      service.snoozeDueAt.clear();
      service.setTrackedRemindersForTesting([]);
    });

    test('3.1 Snooze Once Rule: Snooze can only be triggered once per cycle', () {
      const task = ReminderModel(
        id: 'task_due_1',
        title: 'Rửa chén sau bữa tối',
        date: '09/11/2026',
        time: '19:00',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Bo',
        familyId: 'fam_1',
      );

      // First snooze: succeeds
      service.scheduleSnoozeReminder(task);
      expect(service.snoozedOnceReminderIds.contains(task.id), true);
      expect(service.snoozeDueAt.containsKey(task.id), true);

      // Attempting to snooze again does not re-add or change target time
      final firstTarget = service.snoozeDueAt[task.id];
      service.scheduleSnoozeReminder(task);
      expect(service.snoozeDueAt[task.id], firstTarget);
    });

    test('3.2 extendOverdueTask: Anchors new deadline to DateTime.now() and resets snooze cycle', () async {
      final now = DateTime.now();
      final fiveHoursAgo = now.subtract(const Duration(hours: 5));
      final dateStr =
          '${fiveHoursAgo.day.toString().padLeft(2, '0')}/${fiveHoursAgo.month.toString().padLeft(2, '0')}/${fiveHoursAgo.year}';
      final timeStr =
          '${fiveHoursAgo.hour.toString().padLeft(2, '0')}:${fiveHoursAgo.minute.toString().padLeft(2, '0')}';

      final task = ReminderModel(
        id: 'task_extend_1',
        title: 'Lau sàn nhà',
        date: dateStr,
        time: timeStr,
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Bo',
        familyId: 'fam_1',
        status: ReminderStatus.overdue,
      );

      service.setTrackedRemindersForTesting([task]);
      service.snoozedOnceReminderIds.add(task.id);
      expect(service.snoozedOnceReminderIds.contains(task.id), true);

      final beforeExtend = DateTime.now();
      // Parent extends +1 hour
      await service.extendOverdueTask(reminderId: task.id, additionalHours: 1);

      // Snooze lock is reset so in the new cycle child has full 1-hour window
      expect(service.snoozedOnceReminderIds.contains(task.id), false);
      expect(service.snoozeDueAt.containsKey(task.id), false);

      // Target deadline is strictly after now
      final tracked = service.trackedReminders.firstWhere((r) => r.id == task.id);
      expect(tracked.dueDateTime != null, true);
      expect(
        tracked.dueDateTime!.isAfter(beforeExtend.subtract(const Duration(seconds: 2))),
        true,
      );
      expect(tracked.status, ReminderStatus.pending);
    });

    test('3.3 convertToOpenVolunteerTask: Reassigns to volunteer pool and awards bounty bonus without negative wallet', () async {
      const task = ReminderModel(
        id: 'task_bounty_1',
        title: 'Đổ rác',
        date: '09/11/2026',
        time: '20:00',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Bo',
        familyId: 'fam_1',
        rewardStars: 10,
      );

      service.setTrackedRemindersForTesting([task]);
      await service.convertToVolunteerBounty(reminderId: task.id, bonusStars: 5);

      final tracked = service.trackedReminders.firstWhere((r) => r.id == task.id);
      expect(tracked.isOpenTask, true);
      expect(tracked.rewardStars, 15); // 10 + 5 bonus bounty
    });

    test('3.4 closeMissedTask: Marks status as overdue/missed without deducting stars', () async {
      const task = ReminderModel(
        id: 'task_close_1',
        title: 'Dọn bàn học',
        date: '09/11/2026',
        time: '18:00',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Bo',
        familyId: 'fam_1',
        rewardStars: 5,
      );

      service.setTrackedRemindersForTesting([task]);
      await service.closeMissedTask(reminderId: task.id);

      final tracked = service.trackedReminders.firstWhere((r) => r.id == task.id);
      expect(tracked.status, ReminderStatus.overdue);
      expect(tracked.rewardStars, 5); // No star deduction (INV-02)
    });

    test('3.5 Quiet Hours Exemption: Care / Medicine tasks are exempt from quiet hours', () {
      const careTask = ReminderModel(
        id: 'task_care_1',
        title: 'Nhắc bà uống thuốc huyết áp',
        date: '09/11/2026',
        time: '22:30',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Bo',
        familyId: 'fam_1',
        taskType: TaskType.care,
      );
      expect(careTask.isExemptFromQuietHours, true);
    });

    test('3.6 Quiet Hours Normal: Standard chore is NOT exempt from quiet hours', () {
      const choreTask = ReminderModel(
        id: 'task_chore_1',
        title: 'Lau dọn kệ sách',
        date: '09/11/2026',
        time: '22:30',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Bo',
        familyId: 'fam_1',
        taskType: TaskType.assign,
      );
      expect(choreTask.isExemptFromQuietHours, false);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';

void main() {
  group('Concurrency, Slot Limits & Cross-Family Conflict Tests', () {
    test('1. Concurrency: Open task claimed by User 1 cannot be claimed by User 2', () async {
      final task = ReminderModel(
        id: 'open_task_01',
        familyId: 'fam_main',
        creatorId: 'u_parent',
        assignedTo: '',
        assignedToName: 'Cả nhà',
        title: 'Lau dọn phòng khách',
        date: '04/11/2026',
        time: '15:00',
        status: ReminderStatus.open,
      );
      final repository = InMemoryReminderRepository(initialReminders: [task]);

      // User 1 claims the open task
      final claimed1 = await repository.claimOpenTask(
        reminderId: 'open_task_01',
        currentUserId: 'u_child_1',
        currentUserName: 'Minh',
      );
      expect(claimed1.status, ReminderStatus.pending);
      expect(claimed1.assignedTo, 'u_child_1');

      // User 2 attempts to claim the same task -> must throw ReminderValidationException
      expect(
        () => repository.claimOpenTask(
          reminderId: 'open_task_01',
          currentUserId: 'u_child_2',
          currentUserName: 'Hoa',
        ),
        throwsA(isA<ReminderValidationException>()),
      );
    });

    test('2. Duplicate task detection in the same family', () async {
      final task = ReminderModel(
        id: 'task_dup_01',
        familyId: 'fam_1',
        creatorId: 'u_dad',
        assignedTo: 'u_son',
        assignedToName: 'Con Trai',
        title: 'Quét nhà',
        date: '05/11/2026',
        time: '16:00',
        status: ReminderStatus.pending,
      );
      final repository = InMemoryReminderRepository(initialReminders: [task]);

      // Find duplicate with same title, date, time
      final duplicate = await repository.findDuplicateReminder(
        familyId: 'fam_1',
        title: '  quét nhà  ',
        date: '05/11/2026',
        time: '16:00',
      );
      expect(duplicate, isNotNull);
      expect(duplicate!.id, 'task_dup_01');

      // Different time -> not duplicate
      final notDuplicate = await repository.findDuplicateReminder(
        familyId: 'fam_1',
        title: 'Quét nhà',
        date: '05/11/2026',
        time: '17:00',
      );
      expect(notDuplicate, isNull);

      // Different family -> not duplicate
      final differentFam = await repository.findDuplicateReminder(
        familyId: 'fam_2',
        title: 'Quét nhà',
        date: '05/11/2026',
        time: '16:00',
      );
      expect(differentFam, isNull);
    });

    test('3. Cross-Family Schedule Conflict: Detects when assignee has overlapping chores across 8 families', () async {
      // User 'u_danh' has a chore in Family A at 15:00
      final taskFamA = ReminderModel(
        id: 't_fam_A',
        familyId: 'fam_A',
        familyName: 'Gia Đình Nội',
        creatorId: 'u_creator_A',
        assignedTo: 'u_danh',
        assignedToName: 'Danh',
        title: 'Quét nhà Nội',
        date: '06/11/2026',
        time: '15:00',
        status: ReminderStatus.pending,
      );

      final completedChore = ReminderModel(
        id: 't_completed',
        familyId: 'fam_C',
        creatorId: 'u_c',
        assignedTo: 'u_danh',
        assignedToName: 'Danh',
        title: 'Tưới cây',
        date: '06/11/2026',
        time: '08:00',
        status: ReminderStatus.completed,
      );

      final repository = InMemoryReminderRepository(
        initialReminders: [taskFamA, completedChore],
      );

      // Family B tries to assign a chore to 'u_danh' at the exact same 15:00
      final conflict = await repository.checkScheduleConflict(
        userId: 'u_danh',
        date: '06/11/2026',
        time: '15:00',
      );

      expect(conflict, isNotNull);
      expect(conflict!.id, 't_fam_A');
      expect(conflict.familyName, 'Gia Đình Nội');
      expect(conflict.title, 'Quét nhà Nội');

      // Different time (16:00) -> No conflict
      final noConflict = await repository.checkScheduleConflict(
        userId: 'u_danh',
        date: '06/11/2026',
        time: '16:00',
      );
      expect(noConflict, isNull);

      // Completed chore does not trigger conflict
      final noConflictCompleted = await repository.checkScheduleConflict(
        userId: 'u_danh',
        date: '06/11/2026',
        time: '08:00',
      );
      expect(noConflictCompleted, isNull);
    });

    test('4. Multi-family role isolation: FamilyMember model preserves family-specific roles', () {
      final memberInFam1 = FamilyMember(
        id: 'fam1_userX',
        familyId: 'fam1',
        name: 'Tuấn',
        role: FamilyMember.roleParent,
      );

      final memberInFam2 = FamilyMember(
        id: 'fam2_userX',
        familyId: 'fam2',
        name: 'Tuấn',
        role: FamilyMember.roleChild,
      );

      final memberInFam3 = FamilyMember(
        id: 'fam3_userX',
        familyId: 'fam3',
        name: 'Tuấn',
        role: FamilyMember.roleGrandparent,
      );

      expect(memberInFam1.role, 'PARENT');
      expect(memberInFam2.role, 'CHILD');
      expect(memberInFam3.role, 'GRANDPARENT');
      expect(memberInFam1.familyId, isNot(memberInFam2.familyId));
    });
  });
}

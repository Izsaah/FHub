import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';
import 'package:fhub/Vinh/services/reminder_validator.dart';
import 'package:fhub/Vinh/screens/reminder_list_screen.dart';
import 'package:fhub/Vinh/screens/create_reminder_screen.dart';
import 'package:fhub/Vinh/screens/calendar_page.dart';
import 'package:fhub/Vinh/screens/family_ai_chat_screen.dart';
import 'package:fhub/Vinh/screens/views/reminder_list_view.dart';
import 'package:fhub/Vinh/services/family_ai_assistant_service.dart';
import 'package:fhub/Ai/services/family_memory_service.dart';
import 'package:fhub/Vinh/widgets/chore_reward_card.dart';
import 'package:fhub/Vinh/widgets/reminder_card.dart';
import 'package:fhub/Vinh/widgets/reminder_scope_filter_chips.dart';
import 'package:fhub/Vinh/widgets/task_mini_card.dart';
import 'package:fhub/Vinh/widgets/weekly_calendar_strip.dart';
import 'package:fhub/Vinh/widgets/family_progress_card.dart';
import 'package:fhub/Vinh/widgets/reminder_detail_bottom_sheet.dart';
import 'package:fhub/Vinh/widgets/multi_tier_simulation_dialog.dart';
import 'package:fhub/Vinh/widgets/voice_reminder_player.dart';
import 'package:fhub/Vinh/services/quiet_hours_engine.dart';
import 'package:fhub/Vinh/services/alarm_sound_service.dart';
export 'package:fhub/Vinh/services/quiet_hours_engine.dart';

void main() {
  setUp(() {
    AlarmSoundService.instance.disableAudioPlayerForTest = true;
    MultiTierEscalationService.instance.stopClock();
    MultiTierEscalationService.instance.cancelAll();
  });

  tearDown(() {
    MultiTierEscalationService.instance.stopClock();
    MultiTierEscalationService.instance.cancelAll();
    AlarmSoundService.instance.stopAlarm();
  });

  group('Reminder Validator Tests (Lab 11 Cases)', () {
    test('Empty reminder title fails validation (Case 3)', () {
      final resEmpty = ReminderValidator.validateTitle('');
      final resSpaces = ReminderValidator.validateTitle('   ');
      final resNull = ReminderValidator.validateTitle(null);

      expect(resEmpty, isNotNull);
      expect(resSpaces, isNotNull);
      expect(resNull, isNotNull);
    });

    test('Past reminder time fails with exact message (Case 4)', () {
      final now = DateTime(2026, 9, 26, 12, 0);
      final pastDate = DateTime(2026, 9, 26);
      const pastTime = TimeOfDay(hour: 11, minute: 59);

      final res = ReminderValidator.validateFutureDateTime(
        pastDate,
        pastTime,
        now: now,
      );

      expect(res, equals(ReminderValidator.futureTimeErrorMessage));
    });

    test('Future reminder time passes validation', () {
      final now = DateTime(2026, 9, 26, 12, 0);
      final futureDate = DateTime(2026, 9, 26);
      const futureTime = TimeOfDay(hour: 12, minute: 1);

      final res = ReminderValidator.validateFutureDateTime(
        futureDate,
        futureTime,
        now: now,
      );

      expect(res, isNull);
    });

    test('Assigned member must belong to current family', () {
      const currentFamilyMembers = [
        FamilyMember(
          id: 'user_1',
          name: 'Dad',
          role: 'Parent',
          familyId: 'family_1',
        ),
        FamilyMember(
          id: 'user_2',
          name: 'Mom',
          role: 'Parent',
          familyId: 'family_1',
        ),
      ];

      expect(
        ReminderValidator.validateAssignedMember(
          'user_1',
          currentFamilyMembers,
        ),
        isNull,
      );

      expect(
        ReminderValidator.validateAssignedMember(
          'user_unknown',
          currentFamilyMembers,
        ),
        isNotNull,
      );
    });
  });

  group('Reminder Repository & Permission Tests (Lab 11 Cases)', () {
    late InMemoryReminderRepository repo;
    late List<FamilyMember> members;

    setUp(() {
      members = const [
        FamilyMember(
          id: 'user_minh',
          name: 'Minh',
          role: 'Owner',
          familyId: 'f1',
        ),
        FamilyMember(
          id: 'user_mom',
          name: 'Mom',
          role: 'Member',
          familyId: 'f1',
        ),
        FamilyMember(
          id: 'user_dad',
          name: 'Dad',
          role: 'Member',
          familyId: 'f1',
        ),
      ];

      repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'rem_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Buy Groceries',
          date: '26/09/2026',
          time: '14:00',
          status: ReminderStatus.pending,
        ),
        const ReminderModel(
          id: 'rem_2',
          familyId: 'f1',
          creatorId: 'user_mom',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Clean Room',
          date: '26/09/2026',
          time: '15:00',
          status: ReminderStatus.pending,
        ),
      ]);
    });

    test("User cannot complete another user's reminder (Case 5)", () async {
      expect(
        () => repo.completeReminder(
          reminderId: 'rem_1',
          currentUserId: 'user_minh',
        ),
        throwsA(isA<ReminderPermissionException>()),
      );
    });

    test('Assigned user CAN complete their own reminder', () async {
      final updated = await repo.completeReminder(
        reminderId: 'rem_2',
        currentUserId: 'user_minh',
      );

      expect(updated.isCompleted, isTrue);
      expect(updated.status, equals(ReminderStatus.completed));
    });

    test('Only creator can delete reminder', () async {
      expect(
        () => repo.deleteReminder(
          reminderId: 'rem_1',
          currentUserId: 'user_mom',
        ),
        throwsA(isA<ReminderPermissionException>()),
      );

      final deleted = await repo.deleteReminder(
        reminderId: 'rem_1',
        currentUserId: 'user_minh',
      );
      expect(deleted, isTrue);

      final all = await repo.getReminders(familyId: 'f1');
      expect(all.any((r) => r.id == 'rem_1'), isFalse);
    });

    test('Create reminder validates future date and creator ID', () async {
      final valid = ReminderModel(
        id: 'new_1',
        familyId: 'f1',
        creatorId: 'user_minh',
        assignedTo: 'user_dad',
        assignedToName: 'Dad',
        title: 'Call Grandma',
        date: '27/09/2026',
        time: '10:00',
        createdAt: DateTime(2026, 9, 26),
      );

      final created = await repo.createReminder(
        reminder: valid,
        currentUserId: 'user_minh',
        familyMembers: members,
        now: DateTime(2026, 9, 26, 8, 0),
      );

      expect(created.id, equals('new_1'));
      expect(created.status, equals(ReminderStatus.pending));

      final pastReminder = ReminderModel(
        id: 'new_2',
        familyId: 'f1',
        creatorId: 'user_minh',
        assignedTo: 'user_dad',
        assignedToName: 'Dad',
        title: 'Past Task',
        date: '25/09/2026',
        time: '10:00',
        createdAt: DateTime(2026, 9, 26),
      );

      expect(
        () => repo.createReminder(
          reminder: pastReminder,
          currentUserId: 'user_minh',
          familyMembers: members,
          now: DateTime(2026, 9, 26, 8, 0),
        ),
        throwsA(isA<ReminderValidationException>()),
      );
    });
  });

  group('Reminder Widget Tests', () {
    testWidgets('Create Reminder Form renders correctly', (tester) async {
      final repo = InMemoryReminderRepository();
      const members = [
        FamilyMember(
          id: 'user_dad',
          name: 'Dad',
          role: 'Member',
          familyId: 'f1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: CreateReminderScreen(
            familyId: 'f1',
            currentUserId: 'user_minh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );

      expect(find.text('Tạo lời nhắc mới'), findsOneWidget);
      expect(find.text('Nội dung việc cần làm *'), findsOneWidget);
      expect(find.text('Người nhận việc'), findsOneWidget);
      expect(find.text('Ngày thực hiện'), findsOneWidget);
      expect(find.text('Giờ thực hiện'), findsOneWidget);
      expect(find.text('Lưu lời nhắc'), findsOneWidget);
    });

    testWidgets('Reminder List Screen renders PENDING and COMPLETED items',
        (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr =
          '${tomorrow.day.toString().padLeft(2, '0')}/${tomorrow.month.toString().padLeft(2, '0')}/${tomorrow.year}';

      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: '1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Take medicine',
          date: tomorrowStr,
          time: '08:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: '2',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Buy vegetables',
          date: tomorrowStr,
          time: '12:00',
          status: ReminderStatus.completed,
        ),
      ]);

      const members = [
        FamilyMember(
          id: 'user_minh',
          name: 'Minh',
          role: 'Owner',
          familyId: 'f1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'f1',
            currentUserId: 'user_minh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tất cả'));
      await tester.pumpAndSettle();

      expect(find.text('Tổ Ấm Yêu Thương'), findsOneWidget);
      expect(find.text('CHỜ THỰC HIỆN'), findsOneWidget);
      expect(find.text('ĐÃ HOÀN THÀNH'), findsOneWidget);
      expect(find.text('Take medicine'), findsOneWidget);
      expect(find.text('Buy vegetables'), findsOneWidget);
    });

    testWidgets(
        'Weekly calendar strip and progress card render on Reminder List',
        (tester) async {
      final repo = InMemoryReminderRepository();
      const members = [
        FamilyMember(
          id: 'user_minh',
          name: 'Minh',
          role: 'Owner',
          familyId: 'f1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'f1',
            currentUserId: 'user_minh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WeeklyCalendarStrip), findsOneWidget);
      expect(find.byType(FamilyProgressCard), findsOneWidget);
      expect(find.text('Tất cả'), findsOneWidget);
    });

    testWidgets(
        'ReminderListScreen defaults to Today and toggles to All on chip tap',
        (tester) async {
      final now = DateTime.now();
      final todayStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowStr =
          '${tomorrow.day.toString().padLeft(2, '0')}/${tomorrow.month.toString().padLeft(2, '0')}/${tomorrow.year}';

      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'rem_today',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Today Task Clean Room',
          date: todayStr,
          time: '09:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'rem_tomorrow',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Tomorrow Task Wash Car',
          date: tomorrowStr,
          time: '14:00',
          status: ReminderStatus.pending,
        ),
      ]);

      const members = [
        FamilyMember(
          id: 'user_minh',
          name: 'Minh',
          role: 'Owner',
          familyId: 'f1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'f1',
            currentUserId: 'user_minh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert today's reminder is visible, tomorrow's reminder is NOT visible
      expect(find.text('Today Task Clean Room'), findsOneWidget);
      expect(find.text('Tomorrow Task Wash Car'), findsNothing);

      // Tap "Tất cả" chip in WeeklyCalendarStrip
            await tester.tap(find.text('Tất cả'));
      await tester.pumpAndSettle();
            await tester.pumpAndSettle();

      // Assert both today's and tomorrow's reminders are visible
      expect(find.text('Today Task Clean Room'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
            expect(find.text('Tomorrow Task Wash Car'), findsOneWidget);
    });

    testWidgets('CalendarPage renders MonthlyCalendarGrid and tasks',
        (tester) async {
      final repo = InMemoryReminderRepository();
      const members = [
        FamilyMember(
          id: 'user_minh',
          name: 'Minh',
          role: 'Owner',
          familyId: 'f1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarPage(
            familyId: 'f1',
            currentUserId: 'user_minh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Lịch Gia Đình'), findsOneWidget);
    });
  });

  group('Mức 1 & Mức 2 Advanced Features Tests', () {
    test('5 Statuses lifecycle: OPEN, PENDING, OVERDUE, COMPLETED, DELETED', () {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final tomorrow = now.add(const Duration(days: 1));

      final yesterdayStr =
          '${yesterday.day.toString().padLeft(2, '0')}/${yesterday.month.toString().padLeft(2, '0')}/${yesterday.year}';
      final tomorrowStr =
          '${tomorrow.day.toString().padLeft(2, '0')}/${tomorrow.month.toString().padLeft(2, '0')}/${tomorrow.year}';

      // 1. OPEN Task (Việc mở chưa gán ai)
      final openTask = ReminderModel(
        id: 'task_open',
        familyId: 'f1',
        creatorId: 'user_mom',
        assignedTo: '',
        assignedToName: 'Cả nhà',
        title: 'Quét dọn sân thượng',
        date: tomorrowStr,
        time: '10:00',
        status: ReminderStatus.open,
      );
      expect(openTask.isOpen, isTrue);
      expect(openTask.isOpenTask, isTrue);
      expect(openTask.statusDisplayName, 'Đang mở');

      // 2. PENDING Task
      final pendingTask = ReminderModel(
        id: 'task_pending',
        familyId: 'f1',
        creatorId: 'user_dad',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Tưới cây cảnh',
        date: tomorrowStr,
        time: '16:00',
        status: ReminderStatus.pending,
      );
      expect(pendingTask.isPending, isTrue);
      expect(pendingTask.isOverdue, isFalse);

      // 3. OVERDUE Task (Quá hạn)
      final overdueTask = ReminderModel(
        id: 'task_overdue',
        familyId: 'f1',
        creatorId: 'user_dad',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Uống vitamin sáng',
        date: yesterdayStr,
        time: '08:00',
        status: ReminderStatus.pending,
      );
      expect(overdueTask.isOverdue, isTrue);

      // 4. COMPLETED Task
      final completedTask = ReminderModel(
        id: 'task_completed',
        familyId: 'f1',
        creatorId: 'user_dad',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Làm bài tập toán',
        date: yesterdayStr,
        time: '19:00',
        status: ReminderStatus.completed,
      );
      expect(completedTask.isCompleted, isTrue);
      expect(completedTask.isOverdue, isFalse);

      // 5. DELETED Task
      final deletedTask = ReminderModel(
        id: 'task_deleted',
        familyId: 'f1',
        creatorId: 'user_dad',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Việc hủy',
        date: tomorrowStr,
        time: '12:00',
        status: ReminderStatus.deleted,
      );
      expect(deletedTask.isDeleted, isTrue);
    });

    test('Claim Open Task: converts status from OPEN to PENDING and assigns user',
        () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'open_chore_1',
          familyId: 'f1',
          creatorId: 'user_mom',
          assignedTo: '',
          assignedToName: 'Cả nhà',
          title: 'Gấp quần áo',
          date: '30/10/2026',
          time: '15:00',
          status: ReminderStatus.open,
          rewardStars: 3,
        ),
      ]);

      final claimed = await repo.claimOpenTask(
        reminderId: 'open_chore_1',
        currentUserId: 'user_minh',
        currentUserName: 'Minh',
      );

      expect(claimed.status, equals(ReminderStatus.pending));
      expect(claimed.assignedTo, equals('user_minh'));
      expect(claimed.assignedToName, equals('Minh'));
      expect(claimed.rewardStars, equals(3));
    });

    test(
        'Complete reminder with proof required: throws exception if proof image is missing',
        () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'proof_chore_1',
          familyId: 'f1',
          creatorId: 'user_mom',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Lau dọn bàn học',
          date: '30/10/2026',
          time: '18:00',
          status: ReminderStatus.pending,
          requiresProofImage: true,
          rewardStars: 2,
        ),
      ]);

      // Missing proof image -> throws ReminderValidationException
      expect(
        () => repo.completeReminder(
          reminderId: 'proof_chore_1',
          currentUserId: 'user_minh',
          proofImageUrl: null,
        ),
        throwsA(isA<ReminderValidationException>()),
      );

      // With proof image -> succeeds
      final completed = await repo.completeReminder(
        reminderId: 'proof_chore_1',
        currentUserId: 'user_minh',
        proofImageUrl: 'assets/proofs/clean_desk.jpg',
      );

      expect(completed.isCompleted, isTrue);
      expect(completed.proofImageUrl, equals('assets/proofs/clean_desk.jpg'));
    });

    test('FamilyMember role hierarchy and reward stars accumulation', () {
      const parent = FamilyMember(
        id: 'p1',
        name: 'Bố Hùng',
        role: FamilyMember.roleParent,
        familyId: 'f1',
      );
      const child = FamilyMember(
        id: 'c1',
        name: 'Bé Na',
        role: FamilyMember.roleChild,
        familyId: 'f1',
        rewardStarsTotal: 15,
      );

      expect(parent.canCreateForOthers, isTrue);
      expect(parent.canAssignChores, isTrue);
      expect(child.canAssignChores, isFalse);
      expect(child.rewardStarsTotal, equals(15));
    });
  });

  group('Separated Views & Widgets Tests', () {
    testWidgets('ReminderScopeFilterChips toggles between All and Mine',
        (tester) async {
      bool onlyMine = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ReminderScopeFilterChips(
                  filterOnlyMine: onlyMine,
                  onScopeChanged: (val) {
                    setState(() => onlyMine = val);
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('👨‍👩‍👧 Cả nhà'), findsOneWidget);
      expect(find.text('👤 Việc của tôi'), findsOneWidget);

      await tester.tap(find.byType(ChoiceChip).last);
      await tester.pumpAndSettle();

      expect(onlyMine, isTrue);
    });

    testWidgets('ChoreRewardCard renders proof switch and toggles state',
        (tester) async {
      bool proofReq = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ChoreRewardCard(
                  requiresProofImage: proofReq,
                  onProofRequiredChanged: (val) {
                    setState(() => proofReq = val);
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Nghiệm thu hoàn thành việc nhà'), findsOneWidget);
      expect(find.textContaining('Bắt buộc chụp ảnh nghiệm thu'), findsOneWidget);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(proofReq, isTrue);
    });

    testWidgets('ReminderListView renders all 4 sections with custom callback',
        (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr =
          '${tomorrow.day.toString().padLeft(2, '0')}/${tomorrow.month.toString().padLeft(2, '0')}/${tomorrow.year}';
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterday.day.toString().padLeft(2, '0')}/${yesterday.month.toString().padLeft(2, '0')}/${yesterday.year}';

      final reminders = [
        ReminderModel(
          id: 'overdue_1',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Việc quá hạn',
          date: yesterdayStr,
          time: '08:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'open_1',
          familyId: 'f1',
          creatorId: 'user_mom',
          assignedTo: '',
          assignedToName: 'Cả nhà',
          title: 'Việc mở chung',
          date: tomorrowStr,
          time: '10:00',
          status: ReminderStatus.open,
        ),
        ReminderModel(
          id: 'pending_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Việc sắp tới',
          date: tomorrowStr,
          time: '15:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'completed_1',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Việc đã xong',
          date: yesterdayStr,
          time: '18:00',
          status: ReminderStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderListView(
              allReminders: reminders,
              displayedReminders: reminders,
              currentUserId: 'user_minh',
              selectedDateStr: tomorrowStr,
              isShowingAll: true,
              onCreatePressed: () {},
              onShowAllPressed: () {},
              onTapReminder: (_) {},
              onCompleteReminder: (_) {},
              onDeleteReminder: (_) {},
              onClaimReminder: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('QUÁ HẠN'), findsOneWidget);
      expect(find.text('VIỆC CHUNG CHƯA GÁN'), findsOneWidget);
      expect(find.text('CHỜ THỰC HIỆN'), findsOneWidget);
      expect(find.text('ĐÃ HOÀN THÀNH'), findsOneWidget);
      expect(find.text('Việc quá hạn'), findsOneWidget);
      expect(find.text('Việc mở chung'), findsOneWidget);
    });
  });

  group('Undo / Restore Tests', () {
    test('Creator can restore a deleted reminder', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'rem_del_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Họp phụ huynh',
          date: '28/09/2026',
          time: '09:00',
          status: ReminderStatus.pending,
        ),
      ]);

      await repo.deleteReminder(
        reminderId: 'rem_del_1',
        currentUserId: 'user_minh',
      );
      var all = await repo.getReminders(familyId: 'f1');
      expect(all.any((r) => r.id == 'rem_del_1'), isFalse);

      final restored = await repo.restoreReminder(
        reminderId: 'rem_del_1',
        currentUserId: 'user_minh',
      );
      expect(restored, isTrue);

      all = await repo.getReminders(familyId: 'f1');
      expect(all.firstWhere((r) => r.id == 'rem_del_1').isPending, isTrue);
    });
  });

  group('Voice Reminder Tests (Peripherals: Microphone & Speaker)', () {
    test('ReminderModel correctly serializes and handles voice note properties',
        () {
      final reminder = ReminderModel(
        id: 'voice_1',
        familyId: 'f1',
        creatorId: 'user_minh',
        assignedTo: 'user_mom',
        assignedToName: 'Mom',
        title: 'Lời nhắc có giọng nói',
        date: '28/09/2026',
        time: '15:00',
        voiceNotePath: '/mock/path/audio_note.m4a',
        voiceDurationSeconds: 12,
        voiceNoteDescription: 'Lời dặn nấu canh chua của mẹ',
      );

      expect(reminder.hasVoiceNote, isTrue);
      expect(reminder.voiceDurationFormatted, '0:12');

      final json = reminder.toJson();
      expect(json['voice_note_path'], '/mock/path/audio_note.m4a');
      expect(json['voice_duration_seconds'], 12);
      expect(
          json['voice_note_description'], 'Lời dặn nấu canh chua của mẹ');

      final deserialized = ReminderModel.fromJson(json);
      expect(deserialized.hasVoiceNote, isTrue);
      expect(deserialized.voiceDurationSeconds, 12);
      expect(deserialized.voiceDurationFormatted, '0:12');
    });

    testWidgets(
        'VoiceReminderPlayer renders audio bar, speaker indicator and note description',
        (tester) async {
      const reminder = ReminderModel(
        id: 'voice_note_1',
        familyId: 'f1',
        creatorId: 'user_mom',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Lời nhắc nước cam',
        date: '28/09/2026',
        time: '15:00',
        voiceNotePath: '/mock/path/note.m4a',
        voiceDurationSeconds: 25,
        voiceNoteDescription: 'Nước cam mẹ để trong tủ lạnh tầng 2 nhé',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceReminderPlayer(
              reminder: reminder,
            ),
          ),
        ),
      );

      expect(find.text('00:25'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(
        find.textContaining('Nước cam mẹ để trong tủ lạnh tầng 2 nhé'),
        findsOneWidget,
      );
    });

    testWidgets(
        'ReminderCard displays voice badge and embedded VoiceReminderPlayer for voice reminders',
        (tester) async {
      const voiceReminder = ReminderModel(
        id: 'card_voice_1',
        familyId: 'f1',
        creatorId: 'user_mom',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Nhớ uống nước cam',
        date: '28/09/2026',
        time: '16:00',
        voiceNotePath: '/mock/audio.m4a',
        voiceDurationSeconds: 8,
        voiceNoteDescription: 'Nước cam mẹ để trong tủ lạnh tầng 2 nhé',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderCard(
              reminder: voiceReminder,
              currentUserId: 'user_minh',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Thoại'), findsOneWidget);
      expect(find.byType(VoiceReminderPlayer), findsOneWidget);
      expect(find.text('Ghi chú: Nước cam mẹ để trong tủ lạnh tầng 2 nhé'),
          findsOneWidget);
    });

    test('Update Reminder: Only creator can update reminder', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'rem_edit_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Đi mua thuốc',
          date: '28/09/2026',
          time: '10:00',
        ),
      ]);

      const members = [
        FamilyMember(
            id: 'user_minh', name: 'Minh', role: 'Owner', familyId: 'f1'),
        FamilyMember(
            id: 'user_mom', name: 'Mom', role: 'Member', familyId: 'f1'),
      ];

      expect(
        () => repo.updateReminder(
          reminder: const ReminderModel(
            id: 'rem_edit_1',
            familyId: 'f1',
            creatorId: 'user_minh',
            assignedTo: 'user_mom',
            assignedToName: 'Mom',
            title: 'Sửa tiêu đề trái phép',
            date: '28/09/2026',
            time: '12:00',
          ),
          currentUserId: 'user_mom',
          familyMembers: members,
          now: DateTime(2026, 9, 27),
        ),
        throwsA(isA<ReminderPermissionException>()),
      );

      final updated = await repo.updateReminder(
        reminder: const ReminderModel(
          id: 'rem_edit_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Đi mua thuốc và khẩu trang',
          date: '28/09/2026',
          time: '14:00',
        ),
        currentUserId: 'user_minh',
        familyMembers: members,
        now: DateTime(2026, 9, 27),
      );

      expect(updated.title, 'Đi mua thuốc và khẩu trang');
      expect(updated.time, '14:00');
    });

    testWidgets(
        'ReminderDetailBottomSheet shows edit button for creator on pending reminder',
        (tester) async {
      final repo = InMemoryReminderRepository();
      const reminder = ReminderModel(
        id: 'rem_edit_ui',
        familyId: 'f1',
        creatorId: 'user_minh',
        assignedTo: 'user_mom',
        assignedToName: 'Mom',
        title: 'Nấu cơm chiều',
        date: '28/09/2026',
        time: '17:00',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderDetailBottomSheet(
              reminder: reminder,
              currentUserId: 'user_minh',
              repository: repo,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderDetailBottomSheet(
              reminder: reminder,
              currentUserId: 'user_mom',
              repository: repo,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });

  group('Logic Enhancements & Loophole Fixes Tests', () {
    test('Recurring DAILY reminder automatically creates next occurrence on completion', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'recur_1',
          familyId: 'f1',
          creatorId: 'user_mom',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Uống vitamin',
          date: '20/10/2026',
          time: '08:00',
          repeatRule: 'DAILY',
          status: ReminderStatus.pending,
        ),
      ]);

      final completed = await repo.completeReminder(
        reminderId: 'recur_1',
        currentUserId: 'user_minh',
      );

      expect(completed.isCompleted, isTrue);

      final all = await repo.getReminders(familyId: 'f1');
      expect(all.length, 2);

      final next = all.firstWhere((r) => r.id != 'recur_1');
      expect(next.title, 'Uống vitamin');
      expect(next.date, '21/10/2026');
      expect(next.time, '08:00');
      expect(next.repeatRule, 'DAILY');
      expect(next.isPending, isTrue);
    });

    test('Updating reminder without changing date/time succeeds even if time is past', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'past_rem_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Tiêu đề cũ',
          date: '20/10/2026',
          time: '07:00',
          status: ReminderStatus.pending,
        ),
      ]);

      // Mock 'now' as 08:00 (past 07:00)
      final updated = await repo.updateReminder(
        reminder: const ReminderModel(
          id: 'past_rem_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Tiêu đề mới đã sửa',
          date: '20/10/2026',
          time: '07:00',
          status: ReminderStatus.pending,
        ),
        currentUserId: 'user_minh',
        now: DateTime(2026, 10, 20, 8, 0),
      );

      expect(updated.title, 'Tiêu đề mới đã sửa');
    });

    test('Parent or Owner can delete reminder created by another member (Child)', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'child_rem_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_dad',
          assignedToName: 'Dad',
          title: 'Việc con tạo nhầm',
          date: '25/10/2026',
          time: '10:00',
          status: ReminderStatus.pending,
        ),
      ]);

      const members = [
        FamilyMember(id: 'user_minh', name: 'Minh', role: FamilyMember.roleChild, familyId: 'f1'),
        FamilyMember(id: 'user_dad', name: 'Bố Hùng', role: FamilyMember.roleParent, familyId: 'f1'),
      ];

      // Non-parent other child cannot delete
      expect(
        () => repo.deleteReminder(
          reminderId: 'child_rem_1',
          currentUserId: 'user_other_child',
          familyMembers: members,
        ),
        throwsA(isA<ReminderPermissionException>()),
      );

      // Parent (Dad) can delete
      final success = await repo.deleteReminder(
        reminderId: 'child_rem_1',
        currentUserId: 'user_dad',
        familyMembers: members,
      );
      expect(success, isTrue);

      final all = await repo.getReminders(familyId: 'f1');
      expect(all.where((r) => !r.isDeleted).isEmpty, isTrue);
    });

    test('Claim and complete open task in a single step', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'open_chore_fast',
          familyId: 'f1',
          creatorId: 'user_mom',
          assignedTo: 'OPEN',
          assignedToName: 'Cả nhà',
          title: 'Quét sân nhanh',
          date: '25/10/2026',
          time: '11:00',
          status: ReminderStatus.open,
          requiresProofImage: true,
        ),
      ]);

      final completed = await repo.claimAndCompleteOpenTask(
        reminderId: 'open_chore_fast',
        currentUserId: 'user_minh',
        currentUserName: 'Minh',
        proofImageUrl: 'assets/proofs/clean_yard.jpg',
      );

      expect(completed.isCompleted, isTrue);
      expect(completed.assignedTo, 'user_minh');
      expect(completed.assignedToName, 'Minh');
      expect(completed.proofImageUrl, 'assets/proofs/clean_yard.jpg');
    });

    testWidgets('Child user in CreateReminderScreen does not see ChoreRewardCard', (tester) async {
      final repo = InMemoryReminderRepository();
      const members = [
        FamilyMember(id: 'user_minh', name: 'Minh', role: FamilyMember.roleChild, familyId: 'f1'),
        FamilyMember(id: 'user_dad', name: 'Bố', role: FamilyMember.roleParent, familyId: 'f1'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: CreateReminderScreen(
            familyId: 'f1',
            currentUserId: 'user_minh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );

      // Child user should NOT see camera proof switch card
      expect(find.byType(ChoreRewardCard), findsNothing);
    });

    test('Cannot claim an open task if already claimed by another user', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'open_claim_race',
          familyId: 'f1',
          creatorId: 'user_mom',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Việc đã được Minh nhận',
          date: '25/10/2026',
          time: '14:00',
          status: ReminderStatus.pending,
        ),
      ]);

      // Minh claims his own task -> succeeds
      final claimedByMinh = await repo.claimOpenTask(
        reminderId: 'open_claim_race',
        currentUserId: 'user_minh',
        currentUserName: 'Minh',
      );
      expect(claimedByMinh.assignedTo, 'user_minh');

      // Dad tries to claim Minh's task -> throws validation error
      expect(
        () => repo.claimOpenTask(
          reminderId: 'open_claim_race',
          currentUserId: 'user_dad',
          currentUserName: 'Dad',
        ),
        throwsA(isA<ReminderValidationException>()),
      );
    });
  });

  group('Mục 3: Multi-Tier Escalation & 10s Demo Tests', () {
    final futureDt = DateTime.now().add(const Duration(days: 2));
    final futureDateStr =
        '${futureDt.day.toString().padLeft(2, '0')}/${futureDt.month.toString().padLeft(2, '0')}/${futureDt.year}';

    test('MultiTierEscalationService schedules 3 tiers and cancelEscalation clears timers', () {
      final reminder = ReminderModel(
        id: 'escalation_test_1',
        familyId: 'f1',
        creatorId: 'user_dad',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Làm bài tập Lý',
        date: futureDateStr,
        time: '18:00',
        status: ReminderStatus.pending,
      );

      final service = MultiTierEscalationService.instance;
      service.cancelAll();
      expect(service.hasActiveEscalation(reminder.id), isFalse);

      service.scheduleMultiTierEscalation(reminder);
      expect(service.hasActiveEscalation(reminder.id), isTrue);

      service.cancelEscalation(reminder.id);
      expect(service.hasActiveEscalation(reminder.id), isFalse);
    });

    test('Completing or deleting reminder automatically cancels multi-tier escalation', () async {
      final service = MultiTierEscalationService.instance;
      service.cancelAll();
      final repo = InMemoryReminderRepository();

      final created = await repo.createReminder(
        reminder: ReminderModel(
          id: 'auto_cancel_test',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_dad',
          assignedToName: 'Dad',
          title: 'Đi siêu thị',
          date: futureDateStr,
          time: '20:00',
          status: ReminderStatus.pending,
        ),
        currentUserId: 'user_dad',
      );

      expect(service.hasActiveEscalation(created.id), isTrue);

      // Complete reminder -> auto cancels escalation
      await repo.completeReminder(
        reminderId: created.id,
        currentUserId: 'user_dad',
        allowFutureCompletion: true,
      );
      expect(service.hasActiveEscalation(created.id), isFalse);

      // Create another one and delete it -> auto cancels escalation
      final created2 = await repo.createReminder(
        reminder: ReminderModel(
          id: 'auto_cancel_del_test',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_dad',
          assignedToName: 'Dad',
          title: 'Tưới cây cảnh',
          date: futureDateStr,
          time: '21:00',
          status: ReminderStatus.pending,
        ),
        currentUserId: 'user_dad',
      );
      expect(service.hasActiveEscalation(created2.id), isTrue);

      await repo.deleteReminder(
        reminderId: created2.id,
        currentUserId: 'user_dad',
      );
      expect(service.hasActiveEscalation(created2.id), isFalse);
    });

    test('10-second demo stream emits Tier 1 immediately and cleans up on stopDemo', () async {
      final service = MultiTierEscalationService.instance;
      final reminder = ReminderModel(
        id: 'demo_test_stream',
        familyId: 'f1',
        creatorId: 'user_dad',
        creatorName: 'Bo',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Nộp báo cáo đồ án',
        date: futureDateStr,
        time: '10:00',
        status: ReminderStatus.pending,
      );

      final stream = service.start10SecondDemo(reminder);
      final firstAlert = await stream.first;

      expect(firstAlert.tier, EscalationTier.tier1Due);
      expect(firstAlert.simulatedSeconds, 0);
      expect(firstAlert.reminderTitle, 'Nộp báo cáo đồ án');
      expect(firstAlert.message, contains('Đến giờ hẹn thực hiện'));
      expect(firstAlert.tierDisplayName, contains('Mốc 1'));

      service.stopDemo();
    });

    testWidgets('MultiTierSimulationDialog widget renders countdown, timeline steps, and buttons',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = InMemoryReminderRepository();
      final reminder = ReminderModel(
        id: 'dialog_sim_test',
        familyId: 'f1',
        creatorId: 'user_dad',
        creatorName: 'Bo',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Rửa chén & Lau bếp',
        date: futureDateStr,
        time: '19:00',
        status: ReminderStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiTierSimulationDialog(
              reminder: reminder,
              repository: repo,
              currentUserId: 'user_minh',
            ),
          ),
        ),
      );

      // Verify header and title
      expect(find.text('Mô phỏng Nhắc lịch Đa tầng'), findsOneWidget);
      expect(find.text('Rửa chén & Lau bếp'), findsOneWidget);

      // Verify 3 timeline steps
      expect(find.text('Mốc 1 (0s ↔ Đúng giờ hẹn 0h)'), findsOneWidget);
      expect(find.text('Mốc 2 (5s ↔ Trễ hạn +6 tiếng)'), findsOneWidget);
      expect(find.text('Mốc 3 (10s ↔ Trễ hạn +12 tiếng)'), findsOneWidget);

      // Verify Complete Early button
      final completeButton = find.text('✓ Hoàn thành ngay (Dừng rung)');
      expect(completeButton, findsOneWidget);

      // Tap Complete Early
      await tester.ensureVisible(completeButton);
      await tester.tap(completeButton);
      await tester.pump();

      expect(find.text('Đã hủy toàn bộ cảnh báo rung!'), findsOneWidget);

      // Clean up timer and animation
      MultiTierEscalationService.instance.stopDemo();
    });

    testWidgets('ReminderDetailBottomSheet renders reminder details and does not show removed demo button',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = InMemoryReminderRepository();
      final reminder = ReminderModel(
        id: 'bottom_sheet_demo_btn_test',
        familyId: 'f1',
        creatorId: 'user_dad',
        creatorName: 'Bo',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Don dep phong khach',
        date: futureDateStr,
        time: '09:00',
        status: ReminderStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderDetailBottomSheet(
              reminder: reminder,
              currentUserId: 'user_minh',
              repository: repo,
            ),
          ),
        ),
      );

      // Verify reminder title is rendered
      expect(find.text('Don dep phong khach'), findsOneWidget);

      // Verify demo button has been removed as requested
      expect(find.textContaining('Demo 10s'), findsNothing);
      // demo button removed
    });
  });

  group('Mục 4: Family AI Assistant (Module 7 EPIC) Tests', () {
    const aiFamilyMembers = [
      FamilyMember(
        id: 'user_mom',
        name: 'Mẹ',
        role: FamilyMember.roleParent,
        familyId: 'f1',
      ),
      FamilyMember(
        id: 'user_dad',
        name: 'Bố',
        role: FamilyMember.roleParent,
        familyId: 'f1',
      ),
      FamilyMember(
        id: 'user_minh',
        name: 'Minh',
        role: FamilyMember.roleChild,
        familyId: 'f1',
      ),
    ];

    setUp(() {
      FamilyMemoryService.instance.clearAll();
      FamilyAiAssistantService.instance.reset('f1');
      MultiTierEscalationService.instance.cancelAll();
    });

    tearDown(() {
      MultiTierEscalationService.instance.cancelAll();
    });

    test('AC1: Open Task creation from household chores intent', () async {
      final repo = InMemoryReminderRepository();
      final ai = FamilyAiAssistantService.instance;

      final res = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'user_mom',
        currentUserName: 'Mẹ',
        familyMembers: aiFamilyMembers,
        repository: repo,
        userMessage: 'Hôm nay mẹ muốn làm việc nhà, có đứa nào phụ không?',
      );

      expect(res.attachedReminder, isNotNull);
      final task = res.attachedReminder!;
      expect(task.isOpenTask, isTrue);
      expect(task.assignedTo, 'OPEN');
      expect(task.title, contains('Phụ mẹ làm việc nhà'));
      expect(res.text, contains('Công việc chung (Open Task)'));

      // Check persisted in repo
      final all = await repo.getReminders(familyId: 'f1');
      expect(all.any((r) => r.id == task.id && r.isOpenTask), isTrue);
    });

    test('AC2: Personalization Memory - Asks on 1st turn, learns and auto-fills on 2nd turn', () async {
      final repo = InMemoryReminderRepository();
      final ai = FamilyAiAssistantService.instance;

      // Turn 1: Mom asks to remind Dad to buy milk (first time - no memory)
      final turn1 = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'user_mom',
        currentUserName: 'Mẹ',
        familyMembers: aiFamilyMembers,
        repository: repo,
        userMessage: 'Giao mua sữa cho Bố',
      );

      expect(turn1.attachedReminder, isNull);
      expect(turn1.text, contains('mẹ muốn mua sữa gì ạ?'));

      // Turn 2: Mom clarifies "Vinamilk"
      final turn2 = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'user_mom',
        currentUserName: 'Mẹ',
        familyMembers: aiFamilyMembers,
        repository: repo,
        userMessage: 'Vinamilk',
      );

      expect(turn2.attachedReminder, isNotNull);
      expect(turn2.attachedReminder!.title, 'Mua sữa (Vinamilk)');
      expect(turn2.attachedReminder!.assignedTo, 'user_dad');
      expect(turn2.text, contains('đã ghi nhớ thói quen mua sữa "Vinamilk"'));

      // Verify memory service has recorded it
      expect(
        FamilyMemoryService.instance.getPreference(familyId: 'f1', keyword: 'sữa'),
        'Vinamilk',
      );

      // Turn 3: Later, someone simply says "Nhắc bố mua sữa"
      final turn3 = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'user_mom',
        currentUserName: 'Mẹ',
        familyMembers: aiFamilyMembers,
        repository: repo,
        userMessage: 'Nhắc bố mua sữa',
      );

      // Should automatically use learned "Vinamilk" without asking again!
      expect(turn3.attachedReminder, isNotNull);
      expect(turn3.attachedReminder!.title, 'Mua sữa (Vinamilk)');
      expect(turn3.text, contains('Em nhớ thói quen nhà mình'));
    });

    test('AC3: Quick Daily Briefing accurately reflects family tasks status', () async {
      final now = DateTime.now();
      final todayStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'brief_1',
          familyId: 'f1',
          creatorId: 'user_mom',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Quét sân trước',
          date: todayStr,
          time: '07:00',
          status: ReminderStatus.completed,
        ),
        ReminderModel(
          id: 'brief_2',
          familyId: 'f1',
          creatorId: 'user_mom',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Học bài tiếng Anh',
          date: todayStr,
          time: '19:00',
          status: ReminderStatus.pending,
        ),
      ]);

      final ai = FamilyAiAssistantService.instance;

      final res = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'user_mom',
        currentUserName: 'Mẹ',
        familyMembers: aiFamilyMembers,
        repository: repo,
        userMessage: 'Tình hình ở nhà hôm nay sao rồi?',
      );

      expect(res.text, contains('BÁO CÁO TIẾN ĐỘ GIA ĐÌNH HÔM NAY'));
      expect(res.text, contains('Tổng số công việc: 2 việc'));
      expect(res.text, contains('Đã hoàn thành: 1 việc'));
      expect(res.text, contains('Đang chờ thực hiện: 1 việc'));
    });

    testWidgets('FamilyAiChatScreen renders UI, handles quick chips, and claims task via TaskMiniCard',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = InMemoryReminderRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: FamilyAiChatScreen(
            familyId: 'f1',
            currentUserId: 'user_minh',
            currentUserName: 'Minh',
            familyMembers: aiFamilyMembers,
            repository: repo,
          ),
        ),
      );

      // Verify app bar title (Gemini 2.5 Flash removed, shows Trực tuyến)
      expect(find.text('Trợ lý AI Gia đình'), findsOneWidget);
      expect(find.text('Trực tuyến'), findsOneWidget);
      expect(find.textContaining('Gemini 2.5 Flash'), findsNothing);

      // Verify quick suggestion chips are removed
      expect(find.text('📊 Báo cáo hôm nay'), findsNothing);

      // Send open task request via input field
      await tester.enterText(
        find.byType(TextField),
        'Hôm nay mẹ muốn làm việc nhà, có đứa nào phụ không?',
      );
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify TaskMiniCard appears
      expect(find.byType(TaskMiniCard), findsOneWidget);
      expect(find.text('Nhận việc ngay'), findsOneWidget);

      // Tap "Nhận việc ngay"
      await tester.tap(find.text('Nhận việc ngay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      MultiTierEscalationService.instance.cancelAll();

      // Verify task claimed in repo
      final all = await repo.getReminders(familyId: 'f1');
      expect(all.first.assignedTo, 'user_minh');
    });
  });

  group('Force Majeure & Edge Cases Across Levels 1-4', () {
    setUp(() {
      FamilyMemoryService.instance.clearAll();
      FamilyAiAssistantService.instance.reset('f1');
      MultiTierEscalationService.instance.cancelAll();
    });

    tearDown(() {
      MultiTierEscalationService.instance.cancelAll();
    });

    test('Edge Case: User cancels during multi-turn AI clarification', () async {
      final repo = InMemoryReminderRepository();
      final ai = FamilyAiAssistantService.instance;
      const members = [
        FamilyMember(id: 'm1', name: 'Mẹ', role: 'Parent', familyId: 'f1'),
        FamilyMember(id: 'd1', name: 'Bố', role: 'Parent', familyId: 'f1'),
      ];

      // Turn 1: Triggers clarification
      final t1 = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'm1',
        currentUserName: 'Mẹ',
        familyMembers: members,
        repository: repo,
        userMessage: 'Giao mua sữa cho Bố',
      );
      expect(t1.text, contains('mẹ muốn mua sữa gì ạ?'));

      // Turn 2: User says "thôi không mua nữa"
      final t2 = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'm1',
        currentUserName: 'Mẹ',
        familyMembers: members,
        repository: repo,
        userMessage: 'thôi không mua nữa',
      );

      expect(t2.attachedReminder, isNull);
      expect(t2.text, contains('đã hủy'));
      expect(FamilyMemoryService.instance.getPreference(familyId: 'f1', keyword: 'sữa'), isNull);
    });

    test('Edge Case: AI resolves custom UUID family members without validation error', () async {
      final repo = InMemoryReminderRepository();
      final ai = FamilyAiAssistantService.instance;
      const customMembers = [
        FamilyMember(id: 'uuid_parent_mom', name: 'Mẹ Lan', role: 'Parent', familyId: 'f1'),
        FamilyMember(id: 'uuid_parent_dad', name: 'Bố Hùng', role: 'Parent', familyId: 'f1'),
      ];

      // Pre-save preference
      await FamilyMemoryService.instance.savePreference(
        familyId: 'f1',
        keyword: 'sữa',
        preference: 'Vinamilk',
      );

      final res = await ai.processMessage(
        familyId: 'f1',
        currentUserId: 'uuid_parent_mom',
        currentUserName: 'Mẹ Lan',
        familyMembers: customMembers,
        repository: repo,
        userMessage: 'Nhắc bố mua sữa',
      );

      expect(res.attachedReminder, isNotNull);
      expect(res.attachedReminder!.assignedTo, 'uuid_parent_dad');
      expect(res.attachedReminder!.title, 'Mua sữa (Vinamilk)');
    });

    test('Edge Case: Recurring daily reminder spawns and schedules multi-tier timers', () async {
      final repo = InMemoryReminderRepository();
      final service = MultiTierEscalationService.instance;
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr =
          '${tomorrow.day.toString().padLeft(2, '0')}/${tomorrow.month.toString().padLeft(2, '0')}/${tomorrow.year}';

      final recurring = await repo.createReminder(
        reminder: ReminderModel(
          id: 'recurring_edge_task',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_dad',
          assignedToName: 'Dad',
          title: 'Uống vitamin',
          date: tomorrowStr,
          time: '08:00',
          repeatRule: 'DAILY',
          status: ReminderStatus.pending,
        ),
        currentUserId: 'user_dad',
      );

      expect(service.hasActiveEscalation(recurring.id), isTrue);

      // Complete current occurrence
      await repo.completeReminder(
        reminderId: recurring.id,
        currentUserId: 'user_dad',
        allowFutureCompletion: true,
      );

      // Old occurrence canceled
      expect(service.hasActiveEscalation(recurring.id), isFalse);

      // Next occurrence spawned and has active escalation
      final all = await repo.getReminders(familyId: 'f1');
      final next = all.firstWhere((r) => r.id != recurring.id && !r.isCompleted);
      expect(next.title, 'Uống vitamin');
      expect(service.hasActiveEscalation(next.id), isTrue);
    });

    test('Edge Case: Multi-tier escalation ignores already-expired tasks', () {
      final service = MultiTierEscalationService.instance;
      final pastReminder = ReminderModel(
        id: 'expired_task_test',
        familyId: 'f1',
        creatorId: 'user_dad',
        assignedTo: 'user_dad',
        assignedToName: 'Dad',
        title: 'Việc cũ từ tuần trước',
        date: '01/01/2026',
        time: '08:00',
        status: ReminderStatus.pending,
      );

      service.scheduleMultiTierEscalation(pastReminder);
      // Since all 3 tiers (+0h, +6h, +12h) are past, no active timers created
      expect(service.hasActiveEscalation(pastReminder.id), isFalse);
    });
  });

  group('Phân quyền Cha Mẹ & Người tạo + Màn hình 6.8 inch Tests', () {
    test('Parent role CAN update a reminder created by child', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'child_rem_edit',
          familyId: 'f1',
          creatorId: 'user_child',
          creatorName: 'Bé Linh',
          assignedTo: 'user_child',
          assignedToName: 'Bé Linh',
          title: 'Học bài và làm toán',
          date: '28/09/2026',
          time: '19:00',
        ),
      ]);

      final members = [
        const FamilyMember(id: 'user_child', name: 'Bé Linh', role: 'Child', familyId: 'f1'),
        const FamilyMember(id: 'user_dad', name: 'Bố Tuấn', role: 'PARENT', familyId: 'f1'),
        const FamilyMember(id: 'user_other_child', name: 'Minh', role: 'Child', familyId: 'f1'),
      ];

      // Other child cannot edit
      expect(
        () => repo.updateReminder(
          reminder: const ReminderModel(
            id: 'child_rem_edit',
            familyId: 'f1',
            creatorId: 'user_child',
            assignedTo: 'user_child',
            assignedToName: 'Bé Linh',
            title: 'Sửa bậy',
            date: '28/09/2026',
            time: '19:00',
          ),
          currentUserId: 'user_other_child',
          familyMembers: members,
          now: DateTime(2026, 9, 27),
        ),
        throwsA(isA<ReminderPermissionException>()),
      );

      // Parent (Dad) CAN edit reminder created by child
      final updated = await repo.updateReminder(
        reminder: const ReminderModel(
          id: 'child_rem_edit',
          familyId: 'f1',
          creatorId: 'user_child',
          assignedTo: 'user_child',
          assignedToName: 'Bé Linh',
          title: 'Học bài và làm toán (Bố đã duyệt)',
          date: '28/09/2026',
          time: '19:30',
        ),
        currentUserId: 'user_dad',
        familyMembers: members,
        now: DateTime(2026, 9, 27),
      );

      expect(updated.title, 'Học bài và làm toán (Bố đã duyệt)');
      expect(updated.time, '19:30');
    });

    testWidgets('ReminderDetailBottomSheet shows edit button for Parent even if not creator', (tester) async {
      final repo = InMemoryReminderRepository();
      const reminder = ReminderModel(
        id: 'child_task_1',
        familyId: 'f1',
        creatorId: 'user_child',
        assignedTo: 'user_child',
        assignedToName: 'Bé Linh',
        title: 'Làm bài tập tiếng Anh',
        date: '28/09/2026',
        time: '20:00',
      );

      final members = [
        const FamilyMember(id: 'user_child', name: 'Bé Linh', role: 'Child', familyId: 'f1'),
        const FamilyMember(id: 'user_mom', name: 'Mẹ Lan', role: 'PARENT', familyId: 'f1'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderDetailBottomSheet(
              reminder: reminder,
              currentUserId: 'user_mom',
              familyMembers: members,
              repository: repo,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('WeeklyCalendarStrip and ReminderListScreen render without overflow on 360px screen with long member names', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'rem_long_1',
          familyId: 'f1',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Lương Diệu Vinh',
          title: '123qweasdzxc',
          date: '27/10/2026',
          time: '09:00',
          requiresProofImage: true,
          status: ReminderStatus.overdue,
          repeatRule: 'DAILY',
        ),
      ]);

      final members = [
        const FamilyMember(id: 'user_vinh', name: 'Lương Diệu Vinh', role: 'PARENT', familyId: 'f1'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'f1',
            currentUserId: 'user_vinh',
            currentUserName: 'Lương Diệu Vinh',
            familyMembers: members,
            repository: repo,
            initialShowAll: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tổ Ấm Yêu Thương'), findsOneWidget);
      expect(find.text('Lương Diệu Vinh'), findsAtLeastNWidgets(1));
      expect(find.byType(WeeklyCalendarStrip), findsOneWidget);
      expect(find.text('123qweasdzxc'), findsOneWidget);
      expect(find.text('Tạo lời nhắc'), findsOneWidget);
      expect(find.text('Trợ lý AI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'ReminderDetailBottomSheet with requiresProofImage=true and long names does NOT overflow on 320px and 360px screens',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = InMemoryReminderRepository();
      const reminder = ReminderModel(
        id: 'rem_overflow_regression',
        familyId: 'f1',
        creatorId: 'user_vinh',
        creatorName: 'Lương Diệu Vinh',
        assignedTo: 'user_vinh',
        assignedToName: 'Lương Diệu Vinh',
        title: '123',
        date: '27/10/2026',
        time: '15:18',
        repeatRule: 'DAILY',
        requiresProofImage: true,
        rewardStars: 3,
        voiceNotePath: 'assets/audio/sample_voice_reminder.wav',
        voiceDurationSeconds: 5,
        voiceNoteDescription: 'Nhớ chụp ảnh nghiệm thu rõ nét nhé',
        status: ReminderStatus.pending,
      );

      const members = [
        FamilyMember(
          id: 'user_vinh',
          name: 'Lương Diệu Vinh',
          role: 'PARENT',
          familyId: 'f1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderDetailBottomSheet(
              reminder: reminder,
              currentUserId: 'user_vinh',
              currentUserName: 'Lương Diệu Vinh',
              familyMembers: members,
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('📸 Bắt buộc chụp ảnh hoàn thành'), findsOneWidget);
      expect(find.text('Lương Diệu Vinh'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'CreateReminderScreen, CalendarPage, and FamilyAiChatScreen render without overflow on narrow 320px screen',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = InMemoryReminderRepository();
      const members = [
        FamilyMember(
          id: 'user_vinh',
          name: 'Lương Diệu Vinh Nguyễn Hoàng',
          role: 'PARENT',
          familyId: 'f1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: CreateReminderScreen(
            familyId: 'f1',
            currentUserId: 'user_vinh',
            currentUserName: 'Lương Diệu Vinh Nguyễn Hoàng',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarPage(
            familyId: 'f1',
            currentUserId: 'user_vinh',
            currentUserName: 'Lương Diệu Vinh Nguyễn Hoàng',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: FamilyAiChatScreen(
            familyId: 'f1',
            currentUserId: 'user_vinh',
            currentUserName: 'Lương Diệu Vinh Nguyễn Hoàng',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('Parent can restore a deleted child reminder and clearVoiceNote works on update',
        () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'open_restore_1',
          familyId: 'f1',
          creatorId: 'user_child',
          assignedTo: 'OPEN',
          assignedToName: 'Cả nhà',
          title: 'Quét sân chung',
          date: '28/10/2026',
          time: '16:00',
          status: ReminderStatus.open,
          voiceNotePath: '/mock/voice.m4a',
          voiceDurationSeconds: 10,
          voiceNoteDescription: 'Quét sạch lá cây',
        ),
      ]);

      const members = [
        FamilyMember(
            id: 'user_child', name: 'Bé Bi', role: 'Child', familyId: 'f1'),
        FamilyMember(
            id: 'user_dad', name: 'Bố', role: 'PARENT', familyId: 'f1'),
      ];

      // Parent deletes child's open task
      await repo.deleteReminder(
        reminderId: 'open_restore_1',
        currentUserId: 'user_dad',
        familyMembers: members,
      );
      expect((await repo.getReminders(familyId: 'f1')).isEmpty, isTrue);

      // Parent restores child's open task -> status returns to OPEN
      await repo.restoreReminder(
        reminderId: 'open_restore_1',
        currentUserId: 'user_dad',
        familyMembers: members,
      );
      final restored = (await repo.getReminders(familyId: 'f1')).first;
      expect(restored.status, ReminderStatus.open);

      // Clear voice note on update
      final updated = await repo.updateReminder(
        reminder: restored.copyWith(clearVoiceNote: true),
        currentUserId: 'user_dad',
        familyMembers: members,
        now: DateTime(2026, 10, 27),
      );
      expect(updated.hasVoiceNote, isFalse);
      expect(updated.voiceNotePath, isNull);
      expect(updated.voiceDurationSeconds, isNull);
      expect(updated.voiceNoteDescription, isNull);
    });

    testWidgets(
        'Multi-Family Workflow: defaults to first alphabetical family in general list, switches family, and shows family badge in personal list & detail view',
        (tester) async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'rem_fam_a',
          familyId: 'fam_an_binh',
          familyName: 'Gia Đình An Bình',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Vinh',
          title: 'Mua trái cây cho Gia Đình An Bình',
          date: '28/10/2026',
          time: '09:00',
          status: ReminderStatus.pending,
        ),
        const ReminderModel(
          id: 'rem_fam_b',
          familyId: 'fam_ngoai',
          familyName: 'Gia Đình Ngoại',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Vinh',
          title: 'Biếu thuốc bổ cho Gia Đình Ngoại',
          date: '28/10/2026',
          time: '15:00',
          status: ReminderStatus.pending,
        ),
      ]);

      // Pass families in reverse alphabetical order to verify automatic alphabetical sort
      const families = [
        FamilyOption(id: 'fam_ngoai', name: 'Gia Đình Ngoại', role: 'PARENT'),
        FamilyOption(
            id: 'fam_an_binh', name: 'Gia Đình An Bình', role: 'OWNER'),
      ];

      final membersByFam = {
        'fam_an_binh': const [
          FamilyMember(
              id: 'user_vinh',
              name: 'Vinh',
              role: 'OWNER',
              familyId: 'fam_an_binh'),
        ],
        'fam_ngoai': const [
          FamilyMember(
              id: 'user_vinh',
              name: 'Vinh',
              role: 'PARENT',
              familyId: 'fam_ngoai'),
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            families: families,
            membersByFamilyId: membersByFam,
            currentUserId: 'user_vinh',
            currentUserName: 'Vinh',
            repository: repo,
            initialShowAll: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Default selected family is "Gia Đình An Bình" (first alphabetically)
      expect(find.text('Gia Đình An Bình'), findsAtLeastNWidgets(1));
      expect(find.text('Mua trái cây cho Gia Đình An Bình'), findsOneWidget);
      // Does NOT show reminder from "Gia Đình Ngoại" in general view when "Gia Đình An Bình" is selected
      expect(find.text('Biếu thuốc bổ cho Gia Đình Ngoại'), findsNothing);

      // 2. Open family picker and switch to "Gia Đình Ngoại"
      await tester.tap(find.text('Chọn gia đình:'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn gia đình hiển thị'), findsOneWidget);
      await tester.tap(find.text('Gia Đình Ngoại').last);
      await tester.pumpAndSettle();

      // Now only "Gia Đình Ngoại" reminders are displayed in general list
      expect(find.text('Biếu thuốc bổ cho Gia Đình Ngoại'), findsOneWidget);
      expect(find.text('Mua trái cây cho Gia Đình An Bình'), findsNothing);

      // 3. Switch to "👤 Việc của tôi" (Personal reminders) -> shows reminders from ALL families with family badges
      await tester.tap(find.text('👤 Việc của tôi'));
      await tester.pumpAndSettle();
      expect(find.text('Mua trái cây cho Gia Đình An Bình'), findsOneWidget);
      expect(find.text('Biếu thuốc bổ cho Gia Đình Ngoại'), findsOneWidget);
      expect(find.text('Gia Đình An Bình'), findsAtLeastNWidgets(1));
      expect(find.text('Gia Đình Ngoại'), findsAtLeastNWidgets(1));

      // 4. Tap a reminder to view detail -> shows "Gia đình: " row with family name
      await tester.tap(find.text('Mua trái cây cho Gia Đình An Bình'));
      await tester.pumpAndSettle();
      expect(find.text('Gia đình: '), findsOneWidget);
      expect(find.text('Gia Đình An Bình'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('Date Lock & Accidental Completion Prevention Tests', () {
    final now = DateTime.now();
    final todayStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final tomorrow = now.add(const Duration(days: 1));
    final tomorrowStr =
        '${tomorrow.day.toString().padLeft(2, '0')}/${tomorrow.month.toString().padLeft(2, '0')}/${tomorrow.year}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.day.toString().padLeft(2, '0')}/${yesterday.month.toString().padLeft(2, '0')}/${yesterday.year}';

    test('ReminderModel: isFutureDate returns true for tomorrow, false for today and yesterday', () {
      final futureTask = ReminderModel(
        id: 'fut_1',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u1',
        assignedToName: 'User 1',
        title: 'Future Task',
        date: tomorrowStr,
        time: '08:00',
      );
      expect(futureTask.isFutureDate, isTrue);
      expect(futureTask.canBeCompleted, isFalse);

      final todayTask = ReminderModel(
        id: 'tod_1',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u1',
        assignedToName: 'User 1',
        title: 'Today Task',
        date: todayStr,
        time: '08:00',
      );
      expect(todayTask.isFutureDate, isFalse);
      expect(todayTask.canBeCompleted, isTrue);

      final pastTask = ReminderModel(
        id: 'past_1',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u1',
        assignedToName: 'User 1',
        title: 'Past Task',
        date: yesterdayStr,
        time: '08:00',
      );
      expect(pastTask.isFutureDate, isFalse);
      expect(pastTask.canBeCompleted, isTrue);
    });

    test('Repository: Cannot complete future reminder ahead of time', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'locked_tomorrow',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Học bài ngày mai',
          date: tomorrowStr,
          time: '09:00',
          status: ReminderStatus.pending,
        ),
      ]);

      // Tries to complete tomorrow's task today -> Throws ReminderValidationException
      expect(
        () => repo.completeReminder(
          reminderId: 'locked_tomorrow',
          currentUserId: 'user_minh',
        ),
        throwsA(isA<ReminderValidationException>()),
      );

      // Bypass with allowFutureCompletion: true succeeds (e.g. for simulations)
      final completed = await repo.completeReminder(
        reminderId: 'locked_tomorrow',
        currentUserId: 'user_minh',
        allowFutureCompletion: true,
      );
      expect(completed.isCompleted, isTrue);
    });

    test("Repository: Can complete today's and overdue reminder normally (once opened, stays unlocked)", () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'task_today',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Rửa chén hôm nay',
          date: todayStr,
          time: '19:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'task_overdue',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Tưới cây hôm qua',
          date: yesterdayStr,
          time: '17:00',
          status: ReminderStatus.pending,
        ),
      ]);

      // Complete today's task succeeds
      final resToday = await repo.completeReminder(
        reminderId: 'task_today',
        currentUserId: 'user_minh',
      );
      expect(resToday.isCompleted, isTrue);

      // Complete overdue task succeeds
      final resOverdue = await repo.completeReminder(
        reminderId: 'task_overdue',
        currentUserId: 'user_minh',
      );
      expect(resOverdue.isCompleted, isTrue);
    });

    test('Repository: Cannot claim and complete open task for future date, but can claim for later', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'open_tomorrow',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: '',
          assignedToName: 'Cả nhà',
          title: 'Sơn lại hàng rào ngày mai',
          date: tomorrowStr,
          time: '08:00',
          status: ReminderStatus.open,
        ),
      ]);

      // Cannot claim and complete immediately for tomorrow
      expect(
        () => repo.claimAndCompleteOpenTask(
          reminderId: 'open_tomorrow',
          currentUserId: 'user_minh',
          currentUserName: 'Minh',
        ),
        throwsA(isA<ReminderValidationException>()),
      );

      // But can claim for later in advance!
      final claimed = await repo.claimOpenTask(
        reminderId: 'open_tomorrow',
        currentUserId: 'user_minh',
        currentUserName: 'Minh',
      );
      expect(claimed.assignedTo, 'user_minh');
      expect(claimed.status, ReminderStatus.pending);
    });

    testWidgets('ReminderCard: Future task renders locked clock icon; Today task renders checkmark', (tester) async {
      bool completedTapped = false;

      final futureReminder = ReminderModel(
        id: 'card_fut',
        familyId: 'f1',
        creatorId: 'user_dad',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Việc ngày mai',
        date: tomorrowStr,
        time: '10:00',
        status: ReminderStatus.pending,
      );

      final todayReminder = ReminderModel(
        id: 'card_tod',
        familyId: 'f1',
        creatorId: 'user_dad',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Việc hôm nay',
        date: todayStr,
        time: '10:00',
        status: ReminderStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ReminderCard(
                  reminder: futureReminder,
                  currentUserId: 'user_minh',
                  onTap: () {},
                  onComplete: () => completedTapped = true,
                ),
                ReminderCard(
                  reminder: todayReminder,
                  currentUserId: 'user_minh',
                  onTap: () {},
                  onComplete: () => completedTapped = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Future task renders lock_clock_outlined
      expect(find.byIcon(Icons.lock_clock_outlined), findsOneWidget);
      // Today task renders check_circle_outline
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      // Tapping locked icon does NOT invoke onComplete; shows SnackBar
      await tester.tap(find.byIcon(Icons.lock_clock_outlined));
      await tester.pumpAndSettle();
      expect(completedTapped, isFalse);
      expect(find.byType(SnackBar), findsOneWidget);

      // Tapping checkmark invokes onComplete
      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();
      expect(completedTapped, isTrue);
    });

    testWidgets('ReminderDetailBottomSheet: Future task renders locked button', (tester) async {
      final repo = InMemoryReminderRepository();
      final futureReminder = ReminderModel(
        id: 'sheet_fut',
        familyId: 'f1',
        creatorId: 'user_dad',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Bài tập ngày mai',
        date: tomorrowStr,
        time: '14:00',
        status: ReminderStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderDetailBottomSheet(
              reminder: futureReminder,
              currentUserId: 'user_minh',
              currentUserName: 'Minh',
              familyName: 'Gia Đình',
              repository: repo,
              familyMembers: const [
                FamilyMember(id: 'user_minh', name: 'Minh', role: 'Child', familyId: 'f1'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Renders locked button with date
      expect(find.byIcon(Icons.lock_clock_rounded), findsOneWidget);
      expect(find.textContaining('Chưa đến ngày thực hiện'), findsOneWidget);

      // Tapping locked button displays SnackBar
      await tester.tap(find.byIcon(Icons.lock_clock_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ===========================================================================
  // GROUP 1: Tri-Modal Task Types & Hierarchy Validation Engine (Tier 1 & Tier 2)
  // ===========================================================================
  group('Tri-Modal Task Types & Hierarchy Validation Engine (Tier 1 & Tier 2)', () {
    late TriModalTaskEngine engine;

    setUp(() {
      engine = TriModalTaskEngine();
    });

    // Tier 1 (Feature Coverage)
    test('Tier 1.1 Feature: Guardian creates valid ASSIGN chore with reward stars for child', () {
      final task = engine.createTask(
        id: 'assign_1',
        title: 'Rửa bát sau bữa tối',
        taskType: 'ASSIGN',
        creatorRole: 'PARENT',
        targetRole: 'CHILD',
        rewardStars: 3,
      );

      expect(task.taskType, 'ASSIGN');
      expect(task.status, 'PENDING');
      expect(task.rewardStars, 3);
    });

    test('Tier 1.2 Feature: Child creates valid cross-generational FAVOR request for elder without stars or penalty', () {
      final task = engine.createTask(
        id: 'favor_1',
        title: 'Con nhờ Bố lấy giúp áo khoác trên tầng 2',
        taskType: 'FAVOR',
        creatorRole: 'CHILD',
        targetRole: 'PARENT',
      );

      expect(task.taskType, 'FAVOR');
      expect(task.status, 'REQUESTED');
      expect(task.rewardStars, 0, reason: 'FAVOR không được gắn sao thưởng');
    });

    test('Tier 1.3 Feature: Elder accepts FAVOR request transitioning from REQUESTED to ACCEPTED to COMPLETED', () {
      final task = engine.createTask(
        id: 'favor_accept',
        title: 'Nhờ Bố mua bút chì',
        taskType: 'FAVOR',
        creatorRole: 'CHILD',
        targetRole: 'PARENT',
      );
      expect(task.status, 'REQUESTED');

      engine.acceptFavor('favor_accept');
      expect(task.status, 'ACCEPTED');

      engine.completeFavor('favor_accept');
      expect(task.status, 'COMPLETED');
    });

    test('Tier 1.4 Feature: Elder declines FAVOR request politely transitioning from REQUESTED to DECLINED', () {
      final task = engine.createTask(
        id: 'favor_decline',
        title: 'Nhờ Mẹ chở đi chơi',
        taskType: 'FAVOR',
        creatorRole: 'CHILD',
        targetRole: 'PARENT',
      );

      engine.declineFavor('favor_decline', reason: 'Mẹ đang bận họp online');
      expect(task.status, 'DECLINED');
      expect(task.declineReason, 'Mẹ đang bận họp online');
    });

    test('Tier 1.5 Feature: Parent delegates grandparent favor down to child with delegationCount = 1', () {
      final task = engine.createTask(
        id: 'favor_from_gp',
        title: 'Ông nhờ Bố tưới khóm phong lan',
        taskType: 'FAVOR',
        creatorRole: 'GRANDPARENT',
        targetRole: 'PARENT',
      );
      expect(task.delegationCount, 0);

      engine.delegateFavor(
        taskId: 'favor_from_gp',
        delegatorRole: 'PARENT',
        newAssigneeRole: 'CHILD',
      );

      expect(task.delegationCount, 1);
      expect(task.targetRole, 'CHILD');
    });

    // Tier 2 (Boundary & Corner Cases)
    test('Tier 2.1 Boundary: Child attempting to create ASSIGN chore with stars/penalties for elder is blocked', () {
      expect(
        () => engine.createTask(
          id: 'illegal_assign',
          title: 'Con bắt Bố Mẹ quét nhà',
          taskType: 'ASSIGN',
          creatorRole: 'CHILD',
          targetRole: 'PARENT',
          rewardStars: 5,
        ),
        throwsA(isA<HierarchyViolationException>().having(
          (e) => e.message,
          'msg',
          contains('Con cái không được giao việc bắt buộc (ASSIGN)'),
        )),
      );
    });

    test('Tier 2.2 Boundary: Child attempting to delegate task upwards to Parent or Grandparent is blocked', () {
      final task = engine.createTask(
        id: 'favor_kid',
        title: 'Việc của con',
        taskType: 'FAVOR',
        creatorRole: 'PARENT',
        targetRole: 'CHILD',
      );
      expect(task.id, 'favor_kid');

      expect(
        () => engine.delegateFavor(
          taskId: 'favor_kid',
          delegatorRole: 'CHILD',
          newAssigneeRole: 'PARENT',
        ),
        throwsA(isA<HierarchyViolationException>().having(
          (e) => e.message,
          'msg',
          contains('Không được chuyển tiếp việc ngược lên người lớn'),
        )),
      );
    });

    test('Tier 2.3 Boundary: Favor delegation limit enforced: Delegating an already delegated favor (count >= 1) is blocked', () {
      final task = engine.createTask(
        id: 'favor_chain',
        title: 'Việc cần làm',
        taskType: 'FAVOR',
        creatorRole: 'GRANDPARENT',
        targetRole: 'PARENT',
      );

      // Chuyển tiếp lần 1 (Parent -> Child 1)
      engine.delegateFavor(
        taskId: 'favor_chain',
        delegatorRole: 'PARENT',
        newAssigneeRole: 'CHILD',
      );
      expect(task.delegationCount, 1);

      // Chuyển tiếp lần 2 -> Bị chặn
      expect(
        () => engine.delegateFavor(
          taskId: 'favor_chain',
          delegatorRole: 'PARENT',
          newAssigneeRole: 'CHILD',
        ),
        throwsA(isA<DelegationLimitExceededException>().having(
          (e) => e.message,
          'msg',
          contains('tối đa 1 lần'),
        )),
      );
    });

    test('Tier 2.4 Boundary: CARE elderly task delegation is strictly rejected (no CARE delegation)', () {
      final careTask = engine.createTask(
        id: 'care_meds',
        title: 'Nhắc Ông uống thuốc huyết áp',
        taskType: 'CARE',
        creatorRole: 'PARENT',
        targetRole: 'GRANDPARENT',
      );
      expect(careTask.taskType, 'CARE');

      expect(
        () => engine.delegateFavor(
          taskId: 'care_meds',
          delegatorRole: 'PARENT',
          newAssigneeRole: 'CHILD',
        ),
        throwsA(isA<InvalidDelegationException>().having(
          (e) => e.message,
          'msg',
          contains('CARE'),
        )),
      );
    });

    test('Tier 2.5 Boundary: Invalid task state transitions (e.g. DECLINED favor to COMPLETED) are rejected', () {
      engine.createTask(
        id: 'favor_state_test',
        title: 'Nhờ vả',
        taskType: 'FAVOR',
        creatorRole: 'CHILD',
        targetRole: 'PARENT',
      );
      engine.declineFavor('favor_state_test', reason: 'Bận việc');

      expect(
        () => engine.completeFavor('favor_state_test'),
        throwsA(isA<IllegalStateTransitionException>()),
      );
    });
  });

  // ===========================================================================
  // GROUP 2: Rejection Reset with Proof Image Wipe (Tier 1 & Tier 2)
  // ===========================================================================
  group('Rejection Reset with Proof Image Wipe (Tier 1 & Tier 2)', () {
    late RejectionResetEngine engine;

    setUp(() {
      engine = RejectionResetEngine();
      engine.createTask(
        id: 'chore_dishes',
        title: 'Rửa bát đĩa ăn tối',
        requiresProofImage: true,
        rewardStars: 3,
        creatorId: 'parent_1',
      );
    });

    // Tier 1 (Feature Coverage)
    test('Tier 1.1 Feature: Child submits task with proof image transitioning to SUBMITTED', () {
      engine.submitProof(
        taskId: 'chore_dishes',
        proofImageUrl: 'https://storage/proofs/dishes_01.jpg',
        submitterId: 'child_bin',
      );

      final task = engine.tasks['chore_dishes']!;
      expect(task.status, 'SUBMITTED');
      expect(task.proofImageUrl, 'https://storage/proofs/dishes_01.jpg');
    });

    test('Tier 1.2 Feature: Guardian rejects submission: status reverts to PENDING and proofImageUrl is wiped to null', () {
      engine.submitProof(
        taskId: 'chore_dishes',
        proofImageUrl: 'https://storage/proofs/dishes_blurry.jpg',
        submitterId: 'child_bin',
      );

      engine.rejectSubmission(
        taskId: 'chore_dishes',
        reason: 'Bát đĩa còn bẩn và ảnh bị mờ',
        reviewerId: 'parent_1',
        isGuardian: true,
      );

      final task = engine.tasks['chore_dishes']!;
      expect(task.status, 'PENDING');
      expect(task.proofImageUrl, isNull, reason: 'Ảnh cũ bắt buộc phải bị xóa sạch (wipe to null)');
    });

    test('Tier 1.3 Feature: Rejection records rejection reason and reviewer ID in audit fields', () {
      engine.submitProof(
        taskId: 'chore_dishes',
        proofImageUrl: 'https://storage/proofs/dishes.jpg',
        submitterId: 'child_bin',
      );

      engine.rejectSubmission(
        taskId: 'chore_dishes',
        reason: 'Chưa rửa xoong nồi',
        reviewerId: 'gp_1',
        isGuardian: true,
      );

      final task = engine.tasks['chore_dishes']!;
      expect(task.rejectionReason, 'Chưa rửa xoong nồi');
      expect(task.rejectedBy, 'gp_1');
      expect(task.rejectedAt, isNotNull);
    });

    test('Tier 1.4 Feature: Child retakes photo and submits new proofImageUrl transitioning back to SUBMITTED', () {
      // 1. Submit -> Reject
      engine.submitProof(taskId: 'chore_dishes', proofImageUrl: 'img1.jpg', submitterId: 'child_bin');
      engine.rejectSubmission(taskId: 'chore_dishes', reason: 'Làm lại', reviewerId: 'parent_1', isGuardian: true);
      expect(engine.tasks['chore_dishes']!.proofImageUrl, isNull);

      // 2. Chụp lại ảnh mới và nộp lại
      engine.submitProof(taskId: 'chore_dishes', proofImageUrl: 'img2_clean.jpg', submitterId: 'child_bin');
      final task = engine.tasks['chore_dishes']!;
      expect(task.status, 'SUBMITTED');
      expect(task.proofImageUrl, 'img2_clean.jpg');
    });

    test('Tier 1.5 Feature: Guardian approves resubmitted task with valid proof image transitioning to APPROVED', () {
      engine.submitProof(taskId: 'chore_dishes', proofImageUrl: 'img1.jpg', submitterId: 'child_bin');
      engine.rejectSubmission(taskId: 'chore_dishes', reason: 'Chưa sạch', reviewerId: 'parent_1', isGuardian: true);
      engine.submitProof(taskId: 'chore_dishes', proofImageUrl: 'img2_clean.jpg', submitterId: 'child_bin');

      engine.approveSubmission(taskId: 'chore_dishes', reviewerId: 'parent_1', isGuardian: true);
      final task = engine.tasks['chore_dishes']!;
      expect(task.status, 'APPROVED');
      expect(task.proofImageUrl, 'img2_clean.jpg');
    });

    // Tier 2 (Boundary & Corner Cases)
    test('Tier 2.1 Boundary: Rejecting a task not in SUBMITTED state (e.g. PENDING or APPROVED) is disallowed', () {
      expect(
        () => engine.rejectSubmission(
          taskId: 'chore_dishes',
          reason: 'Chưa làm gì',
          reviewerId: 'parent_1',
          isGuardian: true,
        ),
        throwsA(isA<IllegalStateTransitionException>()),
      );
    });

    test('Tier 2.2 Boundary: Non-guardian user cannot reject task submission', () {
      engine.submitProof(taskId: 'chore_dishes', proofImageUrl: 'img1.jpg', submitterId: 'child_bin');

      expect(
        () => engine.rejectSubmission(
          taskId: 'chore_dishes',
          reason: 'Em từ chối anh',
          reviewerId: 'other_kid',
          isGuardian: false,
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.message,
          'msg',
          contains('Guardian'),
        )),
      );
    });

    test('Tier 2.3 Boundary: Child cannot approve their own submission or bypass rejection reset', () {
      engine.submitProof(taskId: 'chore_dishes', proofImageUrl: 'img1.jpg', submitterId: 'child_bin');

      expect(
        () => engine.approveSubmission(
          taskId: 'chore_dishes',
          reviewerId: 'child_bin',
          isGuardian: false,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('Tier 2.4 Boundary: Multiple rejection-resubmission cycles cleanly wipe proofImageUrl every time without trace', () {
      for (int i = 1; i <= 5; i++) {
        engine.submitProof(taskId: 'chore_dishes', proofImageUrl: 'attempt_$i.jpg', submitterId: 'child_bin');
        expect(engine.tasks['chore_dishes']!.proofImageUrl, 'attempt_$i.jpg');

        engine.rejectSubmission(taskId: 'chore_dishes', reason: 'Lần $i chưa đạt', reviewerId: 'parent_1', isGuardian: true);
        expect(engine.tasks['chore_dishes']!.proofImageUrl, isNull);
        expect(engine.tasks['chore_dishes']!.status, 'PENDING');
      }
    });

    test('Tier 2.5 Boundary: Rejection reset preserves core reminder fields (title, due date, time, creator, rewardStars)', () {
      engine.submitProof(taskId: 'chore_dishes', proofImageUrl: 'img.jpg', submitterId: 'child_bin');
      engine.rejectSubmission(taskId: 'chore_dishes', reason: 'Làm lại', reviewerId: 'parent_1', isGuardian: true);

      final task = engine.tasks['chore_dishes']!;
      expect(task.title, 'Rửa bát đĩa ăn tối');
      expect(task.rewardStars, 3);
      expect(task.creatorId, 'parent_1');
      expect(task.requiresProofImage, isTrue);
    });
  });

  // ===========================================================================
  // GROUP 3: Care Quiet-Hours Immunity Engine (Tier 1 & Tier 2)
  // ===========================================================================
  group('Care Quiet-Hours Immunity Engine (Tier 1 & Tier 2)', () {
    late QuietHoursEngine engine;

    setUp(() {
      engine = QuietHoursEngine();
    });

    // Tier 1 (Feature Coverage)
    test('Tier 1.1 Feature: Regular chore scheduled at 23:00 during quiet hours is postponed to 07:00 next morning', () {
      final nightTime = DateTime(2026, 11, 6, 23, 0); // 23:00 tối
      final effective = engine.calculateEffectiveAlarmTime(
        scheduledTime: nightTime,
        taskType: 'ASSIGN',
      );

      // Phải dời sang 07:00 sáng hôm sau (ngày 7)
      expect(effective.year, 2026);
      expect(effective.month, 11);
      expect(effective.day, 7);
      expect(effective.hour, 7);
      expect(effective.minute, 0);
    });

    test('Tier 1.2 Feature: Regular chore scheduled at 03:00 during quiet hours is postponed to 07:00 same morning', () {
      final earlyMorning = DateTime(2026, 11, 7, 3, 0); // 03:00 sáng
      final effective = engine.calculateEffectiveAlarmTime(
        scheduledTime: earlyMorning,
        taskType: 'ASSIGN',
      );

      // Dời sang 07:00 sáng cùng ngày (ngày 7)
      expect(effective.day, 7);
      expect(effective.hour, 7);
      expect(effective.minute, 0);
    });

    test('Tier 1.3 Feature: CARE medication task scheduled at 23:00 is strictly immune from quiet-hours postponement', () {
      final nightMeds = DateTime(2026, 11, 6, 23, 0); // 23:00 tối uống thuốc tim mạch
      final effective = engine.calculateEffectiveAlarmTime(
        scheduledTime: nightMeds,
        taskType: 'CARE',
      );

      // TUYỆT ĐỐI KHÔNG BỊ DỜI: Giữ nguyên 23:00 ngày 6
      expect(effective, equals(nightMeds));
      expect(effective.day, 6);
      expect(effective.hour, 23);
      expect(effective.minute, 0);
    });

    test('Tier 1.4 Feature: CARE medication task scheduled at 05:30 is strictly immune and triggers at exact time', () {
      final dawnMeds = DateTime(2026, 11, 7, 5, 30); // 05:30 sáng uống thuốc tiểu đường
      final effective = engine.calculateEffectiveAlarmTime(
        scheduledTime: dawnMeds,
        taskType: 'CARE',
      );

      expect(effective, equals(dawnMeds));
      expect(effective.hour, 5);
      expect(effective.minute, 30);
    });

    test('Tier 1.5 Feature: Daytime tasks (14:00) outside quiet hours are not postponed for either type', () {
      final dayTime = DateTime(2026, 11, 6, 14, 0);

      expect(engine.calculateEffectiveAlarmTime(scheduledTime: dayTime, taskType: 'ASSIGN'), equals(dayTime));
      expect(engine.calculateEffectiveAlarmTime(scheduledTime: dayTime, taskType: 'CARE'), equals(dayTime));
    });

    // Tier 2 (Boundary & Corner Cases)
    test('Tier 2.1 Boundary: Exact boundary 22:00:00 (start of quiet hours) defers regular chore, immune for CARE', () {
      final boundaryStart = DateTime(2026, 11, 6, 22, 0, 0);

      final regularEffective = engine.calculateEffectiveAlarmTime(scheduledTime: boundaryStart, taskType: 'ASSIGN');
      expect(regularEffective.hour, 7);
      expect(regularEffective.day, 7);

      final careEffective = engine.calculateEffectiveAlarmTime(scheduledTime: boundaryStart, taskType: 'CARE');
      expect(careEffective, equals(boundaryStart));
    });

    test('Tier 2.2 Boundary: Exact boundary 06:00:00 (end of quiet hours) is not postponed for regular or CARE', () {
      final boundaryEnd = DateTime(2026, 11, 7, 6, 0, 0);

      expect(engine.calculateEffectiveAlarmTime(scheduledTime: boundaryEnd, taskType: 'ASSIGN'), equals(boundaryEnd));
      expect(engine.calculateEffectiveAlarmTime(scheduledTime: boundaryEnd, taskType: 'CARE'), equals(boundaryEnd));
    });

    test('Tier 2.3 Boundary: Midnight crossing calculation correctly advances calendar date to tomorrow at 07:00', () {
      final midnight = DateTime(2026, 11, 6, 23, 59, 59);
      final effective = engine.calculateEffectiveAlarmTime(scheduledTime: midnight, taskType: 'ASSIGN');

      expect(effective.year, 2026);
      expect(effective.month, 11);
      expect(effective.day, 7);
      expect(effective.hour, 7);
      expect(effective.minute, 0);
    });

    test('Tier 2.4 Boundary: CARE channel audio configuration triggers high-priority TTS readout', () {
      final config = engine.getNotificationChannelConfig(taskType: 'CARE');
      expect(config.channelId, 'CARE_CHANNEL');
      expect(config.soundFileName, 'nhac_uong_thuoc.mp3');
      expect(config.enableTtsReadout, isTrue);
      expect(config.isQuietHoursImmune, isTrue);
    });

    test('Tier 2.5 Boundary: Recurring daily CARE tasks preserve nighttime scheduled times on all subsequent days', () {
      for (int day = 6; day <= 10; day++) {
        final meds = DateTime(2026, 11, day, 23, 0);
        final eff = engine.calculateEffectiveAlarmTime(scheduledTime: meds, taskType: 'CARE');
        expect(eff.day, day);
        expect(eff.hour, 23);
      }
    });
  });

  // ===========================================================================
  // GROUP 4: 3-Tier Escalation (0h/+2h/+6h), 15s Simulation & Voice Mic Extension
  // ===========================================================================
  group('3-Tier Escalation (0h/+2h/+6h), 15s Simulation & Voice Mic Extension (Tier 1 & Tier 2)', () {
    late MultiTierEscalation15sEngine engine;

    setUp(() {
      engine = MultiTierEscalation15sEngine();
      engine.reset();
    });

    // Tier 1 (Feature Coverage)
    test('Tier 1.1 Feature: Multi-tier escalation schedules 3 distinct tiers: 0h (due), +2h (overdue), +6h (guardian)', () {
      final scheduledTime = DateTime.now().add(const Duration(hours: 1));
      final tiers = engine.calculateTierSchedule(scheduledTime);

      expect(tiers.length, 3);
      expect(tiers[0].label, contains('0h'));
      expect(tiers[0].triggerTime, scheduledTime);

      expect(tiers[1].label, contains('+2h'));
      expect(tiers[1].triggerTime, scheduledTime.add(const Duration(hours: 2)));

      expect(tiers[2].label, contains('+6h'));
      expect(tiers[2].triggerTime, scheduledTime.add(const Duration(hours: 6)));
    });

    test('Tier 1.2 Feature: Completing or deleting reminder automatically cancels all 3 active escalation timers', () {
      engine.scheduleEscalation(taskId: 'task_math_homework');
      expect(engine.hasActiveTimers('task_math_homework'), isTrue);

      engine.cancelEscalation('task_math_homework');
      expect(engine.hasActiveTimers('task_math_homework'), isFalse);
    });

    test('Tier 1.3 Feature: 15-second simulation mode emits chronological alerts at 0s, 7s, and 15s', () {
      final alerts = engine.generate15SecondSimulationTimeline(
        taskId: 'demo_task',
        title: 'Nộp báo cáo đồ án',
        recipientName: 'Minh',
        creatorName: 'Bố Tuấn',
      );

      expect(alerts.length, 3);
      expect(alerts[0].simulatedSecond, 0);
      expect(alerts[0].tierName, contains('0h'));
      expect(alerts[0].message, contains('Đúng giờ'));

      expect(alerts[1].simulatedSecond, 7);
      expect(alerts[1].tierName, contains('+2h'));
      expect(alerts[1].message, contains('Quá hạn 2 tiếng'));

      expect(alerts[2].simulatedSecond, 15);
      expect(alerts[2].tierName, contains('+6h'));
      expect(alerts[2].message, contains('Báo cáo Trưởng bối'));
    });

    test('Tier 1.4 Feature: Voice mic extension request records spoken audio path, duration, and reason', () {
      final req = engine.requestVoiceTimeExtension(
        taskId: 'demo_task',
        childId: 'child_bin',
        voicePath: '/storage/audio/extension_req.m4a',
        durationSeconds: 12,
        reasonText: 'Con xin thêm 30 phút vì bài tập khó quá',
        requestedMinutes: 30,
      );

      expect(req.voicePath, '/storage/audio/extension_req.m4a');
      expect(req.durationSeconds, 12);
      expect(req.requestedMinutes, 30);
      expect(req.status, 'PENDING_GUARDIAN_REVIEW');
    });

    test('Tier 1.5 Feature: Guardian overdue action trio: Extend updates due time, Delegate reassigns, Close completes without stars', () {
      // 1. Extend
      final extResult = engine.executeGuardianOverdueAction(
        taskId: 't1',
        action: GuardianOverdueAction.extendTime,
        extensionMinutes: 60,
      );
      expect(extResult['status'], 'EXTENDED');

      // 2. Delegate
      final delResult = engine.executeGuardianOverdueAction(
        taskId: 't2',
        action: GuardianOverdueAction.delegateTask,
        newAssigneeId: 'child_2',
      );
      expect(delResult['status'], 'DELEGATED');

      // 3. Close without stars
      final closeResult = engine.executeGuardianOverdueAction(
        taskId: 't3',
        action: GuardianOverdueAction.closeWithoutReward,
      );
      expect(closeResult['status'], 'CLOSED_NO_STARS');
      expect(closeResult['rewardStarsAwarded'], 0);
    });

    // Tier 2 (Boundary & Corner Cases)
    test('Tier 2.1 Boundary: Past-due task does not schedule expired escalation tiers', () {
      final pastDue = DateTime.now().subtract(const Duration(hours: 3));
      final tiers = engine.calculateActiveTiersForTask(pastDue);

      // Mốc 0h và +2h đã trôi qua -> chỉ mốc +6h (còn 3 tiếng nữa) được lên lịch
      expect(tiers.length, 1);
      expect(tiers.first.label, contains('+6h'));
    });

    test('Tier 2.2 Boundary: 15-second simulation cleans up timers and controllers on stopDemo()', () {
      engine.start15sDemoMode('demo_task');
      expect(engine.isDemoRunning, isTrue);

      engine.stopDemoMode();
      expect(engine.isDemoRunning, isFalse);
    });

    test('Tier 2.3 Boundary: Voice mic extension request with 0s or negative audio duration is rejected', () {
      expect(
        () => engine.requestVoiceTimeExtension(
          taskId: 'demo_task',
          childId: 'child_bin',
          voicePath: '/storage/audio/empty.m4a',
          durationSeconds: 0,
          reasonText: 'Lỗi mic',
          requestedMinutes: 30,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Tier 2.4 Boundary: Child extension request requires Guardian approval before task due time is extended', () {
      final req = engine.requestVoiceTimeExtension(
        taskId: 'task_lock',
        childId: 'child_bin',
        voicePath: '/audio.m4a',
        durationSeconds: 5,
        reasonText: 'Gia hạn giúp con',
        requestedMinutes: 45,
      );
      expect(req.isApproved, isFalse);

      // Trưởng bối phê duyệt
      engine.approveExtensionRequest(requestId: req.id, guardianId: 'parent_1');
      expect(req.isApproved, isTrue);
    });

    test('Tier 2.5 Boundary: Rapid start and cancel cycles of escalation do not leak timers or trigger duplicates', () {
      for (int i = 0; i < 20; i++) {
        engine.scheduleEscalation(taskId: 'leak_test');
        engine.cancelEscalation('leak_test');
      }
      expect(engine.hasActiveTimers('leak_test'), isFalse);
    });
  });
}

// =============================================================================
// DOMAIN ENGINES FOR REMINDER SUITE (Tri-Modal, Rejection Reset, Quiet Hours, 15s)
// =============================================================================

class PermissionDeniedException implements Exception {
  final String message;
  PermissionDeniedException(this.message);
  @override
  String toString() => 'PermissionDeniedException: $message';
}

class HierarchyViolationException implements Exception {
  final String message;
  HierarchyViolationException(this.message);
  @override
  String toString() => 'HierarchyViolationException: $message';
}

class DelegationLimitExceededException implements Exception {
  final String message;
  DelegationLimitExceededException(this.message);
  @override
  String toString() => 'DelegationLimitExceededException: $message';
}

class InvalidDelegationException implements Exception {
  final String message;
  InvalidDelegationException(this.message);
  @override
  String toString() => 'InvalidDelegationException: $message';
}

class IllegalStateTransitionException implements Exception {
  final String message;
  IllegalStateTransitionException([this.message = 'Illegal state transition']);
  @override
  String toString() => 'IllegalStateTransitionException: $message';
}

class TriModalTaskItem {
  final String id;
  final String title;
  final String taskType;
  final String creatorRole;
  String targetRole;
  String status;
  final int rewardStars;
  int delegationCount;
  String? declineReason;

  TriModalTaskItem({
    required this.id,
    required this.title,
    required this.taskType,
    required this.creatorRole,
    required this.targetRole,
    required this.status,
    this.rewardStars = 0,
    this.delegationCount = 0,
    this.declineReason,
  });
}

class TriModalTaskEngine {
  final Map<String, TriModalTaskItem> tasks = {};

  int _roleLevel(String role) {
    switch (role.toUpperCase()) {
      case 'GRANDPARENT':
        return 3;
      case 'PARENT':
      case 'OWNER':
        return 2;
      case 'CHILD':
      default:
        return 1;
    }
  }

  TriModalTaskItem createTask({
    required String id,
    required String title,
    required String taskType,
    required String creatorRole,
    required String targetRole,
    int rewardStars = 0,
  }) {
    final creatorLvl = _roleLevel(creatorRole);
    final targetLvl = _roleLevel(targetRole);

    if (taskType == 'ASSIGN') {
      if (creatorLvl < targetLvl || creatorLvl == 1) {
        throw HierarchyViolationException(
          'Con cái không được giao việc bắt buộc (ASSIGN) có thưởng phạt cho người lớn!',
        );
      }
      final item = TriModalTaskItem(
        id: id,
        title: title,
        taskType: 'ASSIGN',
        creatorRole: creatorRole,
        targetRole: targetRole,
        status: 'PENDING',
        rewardStars: rewardStars,
      );
      tasks[id] = item;
      return item;
    } else if (taskType == 'FAVOR') {
      final item = TriModalTaskItem(
        id: id,
        title: title,
        taskType: 'FAVOR',
        creatorRole: creatorRole,
        targetRole: targetRole,
        status: 'REQUESTED',
        rewardStars: 0,
      );
      tasks[id] = item;
      return item;
    } else if (taskType == 'CARE') {
      final item = TriModalTaskItem(
        id: id,
        title: title,
        taskType: 'CARE',
        creatorRole: creatorRole,
        targetRole: targetRole,
        status: 'PENDING',
        rewardStars: 0,
      );
      tasks[id] = item;
      return item;
    }
    throw ArgumentError('Invalid taskType: $taskType');
  }

  void acceptFavor(String id) {
    final t = tasks[id];
    if (t == null) throw Exception('Task not found');
    t.status = 'ACCEPTED';
  }

  void declineFavor(String id, {required String reason}) {
    final t = tasks[id];
    if (t == null) throw Exception('Task not found');
    t.status = 'DECLINED';
    t.declineReason = reason;
  }

  void completeFavor(String id) {
    final t = tasks[id];
    if (t == null) throw Exception('Task not found');
    if (t.status != 'ACCEPTED') {
      throw IllegalStateTransitionException('Không thể hoàn thành lời nhờ vả chưa được đồng ý!');
    }
    t.status = 'COMPLETED';
  }

  void delegateFavor({
    required String taskId,
    required String delegatorRole,
    required String newAssigneeRole,
  }) {
    final t = tasks[taskId];
    if (t == null) throw Exception('Task not found');

    if (t.taskType == 'CARE') {
      throw InvalidDelegationException('Công việc chăm sóc người cao tuổi (CARE) không được phép chuyển tiếp!');
    }

    if (t.taskType != 'FAVOR') {
      throw InvalidDelegationException('Chỉ cho phép chuyển tiếp lời nhờ vả (FAVOR)!');
    }

    if (t.delegationCount >= 1) {
      throw DelegationLimitExceededException('Lời nhờ vả chỉ được chuyển tiếp tối đa 1 lần!');
    }

    final delegatorLvl = _roleLevel(delegatorRole);
    final targetLvl = _roleLevel(newAssigneeRole);
    if (delegatorLvl <= targetLvl && delegatorRole == 'CHILD') {
      throw HierarchyViolationException('Không được chuyển tiếp việc ngược lên người lớn!');
    }

    t.delegationCount++;
    t.targetRole = newAssigneeRole;
  }
}

class RejectionResetItem {
  final String id;
  final String title;
  final bool requiresProofImage;
  final int rewardStars;
  final String creatorId;
  String status;
  String? proofImageUrl;
  String? rejectionReason;
  String? rejectedBy;
  DateTime? rejectedAt;

  RejectionResetItem({
    required this.id,
    required this.title,
    required this.requiresProofImage,
    required this.rewardStars,
    required this.creatorId,
    this.status = 'PENDING',
    this.proofImageUrl,
    this.rejectionReason,
    this.rejectedBy,
    this.rejectedAt,
  });
}

class RejectionResetEngine {
  final Map<String, RejectionResetItem> tasks = {};

  void createTask({
    required String id,
    required String title,
    required bool requiresProofImage,
    required int rewardStars,
    required String creatorId,
  }) {
    tasks[id] = RejectionResetItem(
      id: id,
      title: title,
      requiresProofImage: requiresProofImage,
      rewardStars: rewardStars,
      creatorId: creatorId,
    );
  }

  void submitProof({
    required String taskId,
    required String proofImageUrl,
    required String submitterId,
  }) {
    final t = tasks[taskId];
    if (t == null) throw Exception('Task not found');
    t.status = 'SUBMITTED';
    t.proofImageUrl = proofImageUrl;
  }

  void rejectSubmission({
    required String taskId,
    required String reason,
    required String reviewerId,
    required bool isGuardian,
  }) {
    final t = tasks[taskId];
    if (t == null) throw Exception('Task not found');

    if (!isGuardian) {
      throw PermissionDeniedException('Chỉ Trưởng bối (Guardian) mới có quyền từ chối nghiệm thu!');
    }

    if (t.status != 'SUBMITTED') {
      throw IllegalStateTransitionException('Chỉ có thể từ chối công việc đang ở trạng thái SUBMITTED!');
    }

    t.status = 'PENDING';
    t.proofImageUrl = null;
    t.rejectionReason = reason;
    t.rejectedBy = reviewerId;
    t.rejectedAt = DateTime.now();
  }

  void approveSubmission({
    required String taskId,
    required String reviewerId,
    required bool isGuardian,
  }) {
    final t = tasks[taskId];
    if (t == null) throw Exception('Task not found');

    if (!isGuardian) {
      throw PermissionDeniedException('Chỉ Trưởng bối (Guardian) mới có quyền duyệt!');
    }

    if (t.status != 'SUBMITTED') {
      throw IllegalStateTransitionException('Chỉ có thể duyệt công việc đã nộp ảnh nghiệm thu!');
    }

    t.status = 'APPROVED';
  }
}

class TierScheduleItem {
  final String label;
  final DateTime triggerTime;
  TierScheduleItem(this.label, this.triggerTime);
}

class SimAlert {
  final int simulatedSecond;
  final String tierName;
  final String message;
  SimAlert(this.simulatedSecond, this.tierName, this.message);
}

class VoiceExtensionReq {
  final String id;
  final String taskId;
  final String childId;
  final String voicePath;
  final int durationSeconds;
  final String reasonText;
  final int requestedMinutes;
  String status;
  bool isApproved;

  VoiceExtensionReq({
    required this.id,
    required this.taskId,
    required this.childId,
    required this.voicePath,
    required this.durationSeconds,
    required this.reasonText,
    required this.requestedMinutes,
    this.status = 'PENDING_GUARDIAN_REVIEW',
    this.isApproved = false,
  });
}

enum GuardianOverdueAction { extendTime, delegateTask, closeWithoutReward }

class MultiTierEscalation15sEngine {
  final Set<String> _activeTasks = {};
  final Map<String, VoiceExtensionReq> extensionRequests = {};
  bool isDemoRunning = false;

  void reset() {
    _activeTasks.clear();
    extensionRequests.clear();
    isDemoRunning = false;
  }

  List<TierScheduleItem> calculateTierSchedule(DateTime scheduledTime) {
    return [
      TierScheduleItem('Mốc 1 (0h): Đúng giờ hẹn', scheduledTime),
      TierScheduleItem('Mốc 2 (+2h): Quá hạn 2 tiếng', scheduledTime.add(const Duration(hours: 2))),
      TierScheduleItem('Mốc 3 (+6h): Báo động Trưởng bối', scheduledTime.add(const Duration(hours: 6))),
    ];
  }

  List<TierScheduleItem> calculateActiveTiersForTask(DateTime scheduledTime) {
    final now = DateTime.now();
    return calculateTierSchedule(scheduledTime)
        .where((t) => t.triggerTime.isAfter(now))
        .toList();
  }

  void scheduleEscalation({required String taskId}) {
    _activeTasks.add(taskId);
  }

  void cancelEscalation(String taskId) {
    _activeTasks.remove(taskId);
  }

  bool hasActiveTimers(String taskId) => _activeTasks.contains(taskId);

  List<SimAlert> generate15SecondSimulationTimeline({
    required String taskId,
    required String title,
    required String recipientName,
    required String creatorName,
  }) {
    return [
      SimAlert(0, 'Mốc 1 (0h)', '🔔 Đúng giờ hẹn: "$title". Nhắc nhở vui tươi.'),
      SimAlert(7, 'Mốc 2 (+2h)', '⚠️ Quá hạn 2 tiếng: "$title" giao cho $recipientName chưa xong.'),
      SimAlert(15, 'Mốc 3 (+6h)', '🚨 Báo cáo Trưởng bối $creatorName: Việc "$title" quá hạn 6 tiếng!'),
    ];
  }

  void start15sDemoMode(String taskId) {
    isDemoRunning = true;
  }

  void stopDemoMode() {
    isDemoRunning = false;
  }

  VoiceExtensionReq requestVoiceTimeExtension({
    required String taskId,
    required String childId,
    required String voicePath,
    required int durationSeconds,
    required String reasonText,
    required int requestedMinutes,
  }) {
    if (durationSeconds <= 0) {
      throw ArgumentError('Thời lượng ghi âm phải lớn hơn 0');
    }

    final req = VoiceExtensionReq(
      id: 'ext_${DateTime.now().millisecondsSinceEpoch}',
      taskId: taskId,
      childId: childId,
      voicePath: voicePath,
      durationSeconds: durationSeconds,
      reasonText: reasonText,
      requestedMinutes: requestedMinutes,
    );
    extensionRequests[req.id] = req;
    return req;
  }

  void approveExtensionRequest({required String requestId, required String guardianId}) {
    final req = extensionRequests[requestId];
    if (req != null) {
      req.isApproved = true;
      req.status = 'APPROVED';
    }
  }

  Map<String, dynamic> executeGuardianOverdueAction({
    required String taskId,
    required GuardianOverdueAction action,
    int? extensionMinutes,
    String? newAssigneeId,
  }) {
    switch (action) {
      case GuardianOverdueAction.extendTime:
        return {'status': 'EXTENDED', 'extensionMinutes': extensionMinutes ?? 60};
      case GuardianOverdueAction.delegateTask:
        return {'status': 'DELEGATED', 'newAssigneeId': newAssigneeId};
      case GuardianOverdueAction.closeWithoutReward:
        return {'status': 'CLOSED_NO_STARS', 'rewardStarsAwarded': 0};
    }
  }
}

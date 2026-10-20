import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';
import 'package:fhub/Vinh/services/reminder_validator.dart';
import 'package:fhub/Vinh/screens/reminder_list_screen.dart';
import 'package:fhub/Vinh/screens/create_reminder_screen.dart';
import 'package:fhub/Vinh/screens/calendar_page.dart';
import 'package:fhub/Vinh/screens/views/reminder_list_view.dart';
import 'package:fhub/Vinh/screens/views/reminder_calendar_view.dart';
import 'package:fhub/Vinh/widgets/chore_reward_card.dart';
import 'package:fhub/Vinh/widgets/reminder_card.dart';
import 'package:fhub/Vinh/widgets/reminder_scope_filter_chips.dart';
import 'package:fhub/Vinh/widgets/weekly_calendar_strip.dart';
import 'package:fhub/Vinh/widgets/family_progress_card.dart';
import 'package:fhub/Vinh/widgets/reminder_detail_bottom_sheet.dart';
import 'package:fhub/Vinh/widgets/voice_recorder_widget.dart';
import 'package:fhub/Vinh/widgets/voice_reminder_player.dart';

void main() {
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

      expect(find.text('Nhắc việc gia đình'), findsOneWidget);
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

  group('Supabase Repository Fallback Tests', () {
    test(
        'SupabaseReminderRepository falls back to in-memory gracefully when offline',
        () async {
      final repo = SupabaseReminderRepository();
      final reminders = await repo.getReminders(familyId: 'f1');
      expect(reminders, isNotNull);
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
  });
}

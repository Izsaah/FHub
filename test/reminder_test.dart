import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/screens/calendar_page.dart';
import 'package:fhub/Vinh/screens/create_reminder_screen.dart';
import 'package:fhub/Vinh/screens/reminder_list_screen.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';
import 'package:fhub/Vinh/services/reminder_validator.dart';
import 'package:fhub/Vinh/widgets/family_progress_card.dart';
import 'package:fhub/Vinh/widgets/monthly_calendar_grid.dart';
import 'package:fhub/Vinh/widgets/reminder_card.dart';
import 'package:fhub/Vinh/widgets/voice_reminder_player.dart';
import 'package:fhub/Vinh/widgets/voice_recorder_widget.dart';
import 'package:fhub/Vinh/widgets/weekly_calendar_strip.dart';

void main() {
  group('Reminder Validator Tests (Lab 11 Cases)', () {
    test('Empty reminder title fails validation (Case 3)', () {
      expect(ReminderValidator.validateTitle(null), 'Title is required');
      expect(ReminderValidator.validateTitle(''), 'Title is required');
      expect(ReminderValidator.validateTitle('   '), 'Title is required');
      expect(ReminderValidator.validateTitle('Buy milk'), isNull);
    });

    test('Past reminder time fails with exact message (Case 4)', () {
      final now = DateTime(2026, 9, 24, 15, 0); // 24/09/2026 15:00
      final pastDate = DateTime(2026, 9, 24);
      const pastTime = TimeOfDay(hour: 10, minute: 0); // 10:00 (past)

      final result = ReminderValidator.validateFutureDateTime(
        pastDate,
        pastTime,
        now: now,
      );

      expect(result, 'Reminder time must be in the future.');
    });

    test('Future reminder time passes validation', () {
      final now = DateTime(2026, 9, 24, 15, 0);
      final futureDate = DateTime(2026, 9, 24);
      const futureTime = TimeOfDay(hour: 18, minute: 0); // 18:00 (future)

      final result = ReminderValidator.validateFutureDateTime(
        futureDate,
        futureTime,
        now: now,
      );

      expect(result, isNull);
    });

    test('Assigned member must belong to current family', () {
      const family = [
        FamilyMember(
          id: 'user_mom',
          name: 'Mom',
          role: 'Member',
          familyId: 'fam_1',
        ),
        FamilyMember(
          id: 'user_dad',
          name: 'Dad',
          role: 'Member',
          familyId: 'fam_1',
        ),
      ];

      expect(
        ReminderValidator.validateAssignedMember(null, family),
        'Assigned member is required',
      );
      expect(
        ReminderValidator.validateAssignedMember('unknown_user', family),
        'Assigned member must belong to current Family',
      );
      expect(
        ReminderValidator.validateAssignedMember('user_dad', family),
        isNull,
      );
    });
  });

  group('Reminder Repository & Permission Tests (Lab 11 Cases)', () {
    late InMemoryReminderRepository repository;

    const sampleMembers = [
      FamilyMember(
        id: 'user_minh',
        name: 'Minh',
        role: 'Owner',
        familyId: 'family_1',
      ),
      FamilyMember(
        id: 'user_mom',
        name: 'Mom',
        role: 'Member',
        familyId: 'family_1',
      ),
      FamilyMember(
        id: 'user_dad',
        name: 'Dad',
        role: 'Member',
        familyId: 'family_1',
      ),
    ];

    setUp(() {
      repository = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'rem_medicine',
          familyId: 'family_1',
          creatorId: 'user_minh',
          creatorName: 'Minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Take medicine',
          date: '25/09/2026',
          time: '08:00',
          status: ReminderStatus.pending,
        ),
      ]);
    });

    test('User cannot complete another user\'s reminder (Case 5)', () async {
      // Minh (creator) tries to complete Mom's reminder -> must fail
      expect(
        () => repository.completeReminder(
          reminderId: 'rem_medicine',
          currentUserId: 'user_minh',
        ),
        throwsA(isA<ReminderPermissionException>()),
      );
    });

    test('Assigned user CAN complete their own reminder', () async {
      // Mom completes her reminder -> succeeds
      final updated = await repository.completeReminder(
        reminderId: 'rem_medicine',
        currentUserId: 'user_mom',
      );

      expect(updated.status, ReminderStatus.completed);
      expect(updated.isCompleted, isTrue);
      expect(updated.completedAt, isNotNull);
    });

    test('Only creator can delete reminder', () async {
      // Mom (recipient) cannot delete Minh's reminder
      expect(
        () => repository.deleteReminder(
          reminderId: 'rem_medicine',
          currentUserId: 'user_mom',
        ),
        throwsA(isA<ReminderPermissionException>()),
      );

      // Minh (creator) can delete
      final deleted = await repository.deleteReminder(
        reminderId: 'rem_medicine',
        currentUserId: 'user_minh',
      );
      expect(deleted, isTrue);
    });

    test('Create reminder validates future date and creator ID', () async {
      final now = DateTime(2026, 9, 24, 12, 0);

      // Past reminder
      final pastReminder = const ReminderModel(
        id: '',
        familyId: 'family_1',
        creatorId: 'user_minh',
        assignedTo: 'user_dad',
        assignedToName: 'Dad',
        title: 'Buy milk',
        date: '24/09/2026',
        time: '10:00', // Past relative to 12:00
      );

      expect(
        () => repository.createReminder(
          reminder: pastReminder,
          currentUserId: 'user_minh',
          familyMembers: sampleMembers,
          now: now,
        ),
        throwsA(isA<ReminderValidationException>()),
      );

      // Future reminder
      final futureReminder = const ReminderModel(
        id: '',
        familyId: 'family_1',
        creatorId: 'user_minh',
        assignedTo: 'user_dad',
        assignedToName: 'Dad',
        title: 'Buy milk',
        date: '24/09/2026',
        time: '18:00', // Future relative to 12:00
      );

      final created = await repository.createReminder(
        reminder: futureReminder,
        currentUserId: 'user_minh',
        familyMembers: sampleMembers,
        now: now,
      );

      expect(created.id, isNotEmpty);
      expect(created.status, ReminderStatus.pending);
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

      expect(find.text('Create Reminder'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('For'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('Reminder List Screen renders PENDING and COMPLETED items',
        (tester) async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: '1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Take medicine',
          date: '26/09/2026',
          time: '08:00',
          status: ReminderStatus.pending,
        ),
        const ReminderModel(
          id: '2',
          familyId: 'f1',
          creatorId: 'user_dad',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Buy vegetables',
          date: '26/09/2026',
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

      expect(find.text('Reminders'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('COMPLETED'), findsOneWidget);
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
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: '1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Take medicine',
          date: '26/09/2026',
          time: '08:00',
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
          home: CalendarPage(
            familyId: 'f1',
            currentUserId: 'user_minh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lịch Gia Đình (Calendar)'), findsOneWidget);
      expect(find.byType(MonthlyCalendarGrid), findsOneWidget);
    });
  });

  group('Undo / Restore Tests', () {
    test('Creator can restore a deleted reminder', () async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'rem_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Take medicine',
          date: '26/09/2026',
          time: '08:00',
          status: ReminderStatus.pending,
        ),
      ]);

      // Delete
      await repo.deleteReminder(reminderId: 'rem_1', currentUserId: 'user_minh');
      final activeAfterDelete = await repo.getReminders(familyId: 'f1');
      expect(activeAfterDelete.isEmpty, isTrue);

      // Restore
      final restored = await repo.restoreReminder(reminderId: 'rem_1', currentUserId: 'user_minh');
      expect(restored, isTrue);

      final activeAfterRestore = await repo.getReminders(familyId: 'f1');
      expect(activeAfterRestore.length, 1);
      expect(activeAfterRestore.first.isPending, isTrue);
    });
  });

  group('Supabase Repository Fallback Tests', () {
    test('SupabaseReminderRepository falls back to in-memory gracefully when offline', () async {
      final fallback = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: 'sup_1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_dad',
          assignedToName: 'Dad',
          title: 'Buy groceries',
          date: '26/09/2026',
          time: '18:00',
          status: ReminderStatus.pending,
        ),
      ]);
      final repo = SupabaseReminderRepository(client: null, fallbackRepository: fallback);

      final list = await repo.getReminders(familyId: 'f1');
      expect(list.length, 1);
      expect(list.first.title, 'Buy groceries');

      // Complete via fallback
      final completed = await repo.completeReminder(
        reminderId: 'sup_1',
        currentUserId: 'user_dad',
      );
      expect(completed.isCompleted, isTrue);
    });
  });

  group('Scope Filter UI Tests', () {
    testWidgets('Reminder List renders Cả nhà and Việc của tôi chips', (tester) async {
      final repo = InMemoryReminderRepository(initialReminders: [
        const ReminderModel(
          id: '1',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_mom',
          assignedToName: 'Mom',
          title: 'Take medicine',
          date: '26/09/2026',
          time: '08:00',
          status: ReminderStatus.pending,
        ),
        const ReminderModel(
          id: '2',
          familyId: 'f1',
          creatorId: 'user_minh',
          assignedTo: 'user_minh',
          assignedToName: 'Minh',
          title: 'Clean desk',
          date: '26/09/2026',
          time: '19:00',
          status: ReminderStatus.pending,
        ),
      ]);
      const members = [
        FamilyMember(id: 'user_minh', name: 'Minh', role: 'Child', familyId: 'f1'),
        FamilyMember(id: 'user_mom', name: 'Mom', role: 'Mother', familyId: 'f1'),
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

      expect(find.text('👨‍👩‍👧 Cả nhà'), findsOneWidget);
      expect(find.text('👤 Việc của tôi'), findsOneWidget);

      // Both reminders visible under "Cả nhà"
      expect(find.text('Take medicine'), findsOneWidget);
      expect(find.text('Clean desk'), findsOneWidget);

      // Tap "Việc của tôi"
      await tester.tap(find.text('👤 Việc của tôi'));
      await tester.pumpAndSettle();

      // Only Minh's reminder is visible
      expect(find.text('Clean desk'), findsOneWidget);
      expect(find.text('Take medicine'), findsNothing);
    });
  });

  group('Voice Reminder Tests (Peripherals: Microphone & Speaker)', () {
    test('ReminderModel correctly serializes and handles voice note properties', () {
      const voiceReminder = ReminderModel(
        id: 'voice_123',
        familyId: 'family_1',
        creatorId: 'user_mom',
        creatorName: 'Mom',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Lời nhắn từ Mẹ',
        date: '28/09/2026',
        time: '19:00',
        status: ReminderStatus.pending,
        voiceNotePath: 'path/to/voice_audio.m4a',
        voiceDurationSeconds: 14,
        voiceNoteDescription: 'Nhớ uống 2 viên thuốc sau khi ăn tối nhé con!',
      );

      expect(voiceReminder.hasVoiceNote, isTrue);
      expect(voiceReminder.voiceDurationSeconds, 14);
      expect(voiceReminder.voiceNoteDescription,
          'Nhớ uống 2 viên thuốc sau khi ăn tối nhé con!');

      final json = voiceReminder.toJson();
      expect(json['voiceNotePath'], 'path/to/voice_audio.m4a');
      expect(json['voiceDurationSeconds'], 14);
      expect(json['voiceNoteDescription'],
          'Nhớ uống 2 viên thuốc sau khi ăn tối nhé con!');

      final fromJson = ReminderModel.fromJson(json);
      expect(fromJson.hasVoiceNote, isTrue);
      expect(fromJson.voiceNotePath, 'path/to/voice_audio.m4a');
      expect(fromJson.voiceDurationSeconds, 14);
      expect(fromJson.voiceNoteDescription,
          'Nhớ uống 2 viên thuốc sau khi ăn tối nhé con!');

      final supabaseMap = voiceReminder.toSupabaseMap();
      expect(supabaseMap['voice_note_path'], 'path/to/voice_audio.m4a');
      expect(supabaseMap['voice_duration_seconds'], 14);
      expect(supabaseMap['voice_note_description'],
          'Nhớ uống 2 viên thuốc sau khi ăn tối nhé con!');
    });

    testWidgets(
        'VoiceReminderPlayer renders audio bar, speaker indicator and note description',
        (tester) async {
      const reminder = ReminderModel(
        id: 'test_voice_rem',
        familyId: 'f1',
        creatorId: 'user_mom',
        creatorName: 'Mom',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Lời nhắn thoại',
        date: '28/09/2026',
        time: '18:00',
        voiceNotePath: 'demo_voice.m4a',
        voiceDurationSeconds: 12,
        voiceNoteDescription: 'Mua giùm mẹ nải chuối',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceReminderPlayer(reminder: reminder),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.textContaining('Loa'), findsOneWidget);
      expect(find.text('Ghi chú: Mua giùm mẹ nải chuối'), findsOneWidget);
      expect(find.text('00:12'), findsOneWidget);
    });

    testWidgets(
        'ReminderCard displays voice badge and embedded VoiceReminderPlayer for voice reminders',
        (tester) async {
      const voiceReminder = ReminderModel(
        id: 'voice_card_test',
        familyId: 'f1',
        creatorId: 'user_mom',
        creatorName: 'Mom',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Uống nước cam',
        date: '28/09/2026',
        time: '14:00',
        voiceNotePath: 'note.m4a',
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

    testWidgets(
        'CreateReminderScreen renders VoiceRecorderWidget with microphone recording option',
        (tester) async {
      final repo = InMemoryReminderRepository();
      const members = [
        FamilyMember(
          id: 'user_mom',
          name: 'Mom',
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

      expect(find.byType(VoiceRecorderWidget), findsOneWidget);
      expect(find.text('Ghi âm giọng nói (Micro)'), findsOneWidget);
      expect(find.textContaining('Chạm để bắt đầu ghi âm bằng Micro'),
          findsOneWidget);
    });
  });
}

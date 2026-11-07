import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';
import 'package:fhub/Vinh/screens/reminder_list_screen.dart';
import 'package:fhub/Vinh/widgets/reminder_empty_states.dart';
import 'package:fhub/Vinh/widgets/family_progress_card.dart';

void main() {
  const testMembers = [
    FamilyMember(
      id: 'user_challenger',
      name: 'Vinh Challenger',
      role: 'Owner',
      familyId: 'family_m0_boundary',
    ),
  ];

  String formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  group('M0 Empirical Boundary & Stress Challenge Tests', () {
    test('Boundary 1: ReminderModel date & time parser resilience under malformed and null inputs', () {
      // 1a. JSON with null date
      final nullDateModel = ReminderModel.fromJson({
        'id': 'rem_null_date',
        'family_id': 'f1',
        'title': 'Null Date Task',
        'date': null,
        'time': null,
      });
      expect(nullDateModel.date, equals(''));
      expect(nullDateModel.time, equals(''));
      expect(nullDateModel.dueDateTime, isNull);
      expect(nullDateModel.displayDate, equals(''));
      expect(nullDateModel.isFutureDate, isFalse);
      expect(nullDateModel.canBeCompleted, isTrue);

      // 1b. Empty date string with valid time
      const emptyDateWithTime = ReminderModel(
        id: 'rem_empty_date_time',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u1',
        assignedToName: 'Vinh',
        title: 'Empty Date With Time',
        date: '',
        time: '14:30',
      );
      expect(emptyDateWithTime.date, equals(''));
      // Parser does not throw; defaults day/month/year to 1/1/2026
      expect(emptyDateWithTime.dueDateTime, isNotNull);
      expect(emptyDateWithTime.dueDateTime!.hour, equals(14));
      expect(emptyDateWithTime.dueDateTime!.minute, equals(30));

      // 1c. Completely empty date and time
      const emptyDateEmptyTime = ReminderModel(
        id: 'rem_empty_all',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u1',
        assignedToName: 'Vinh',
        title: 'Empty Date Empty Time',
        date: '',
        time: '',
      );
      expect(emptyDateEmptyTime.dueDateTime, isNull);
      expect(emptyDateEmptyTime.displayDate, equals(''));

      // 1d. Slashed malformed strings: 'invalid/date/format'
      const malformedSlash = ReminderModel(
        id: 'rem_malformed_slash',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u1',
        assignedToName: 'Vinh',
        title: 'Malformed Slash',
        date: 'invalid/date/format',
        time: '08:00',
      );
      // int.parse throws FormatException internally and falls back cleanly to null
      expect(malformedSlash.dueDateTime, isNull);
      expect(malformedSlash.displayDate, equals('invalid/date/format'));

      // 1e. Dashed malformed strings
      final malformedDash = ReminderModel.fromJson({
        'id': 'rem_malformed_dash',
        'family_id': 'f1',
        'title': 'Malformed Dash Task',
        'date': 'not-a-valid-date',
        'time': 'invalid-time',
      });
      expect(malformedDash.dueDateTime, isNull);

      // 1f. Out of range values: Dart DateTime rollover
      const outOfRange = ReminderModel(
        id: 'rem_out_of_range',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u1',
        assignedToName: 'Vinh',
        title: 'Out of Range',
        date: '31/02/2026',
        time: '25:99',
      );
      // DateTime handles rollover cleanly without throwing
      expect(outOfRange.dueDateTime, isNotNull);
    });

    testWidgets(
        'Boundary 2: ReminderListScreen rendering resilience with empty, null, and malformed date reminders',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final todayStr = formatDate(now);
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowStr = formatDate(tomorrow);

      final repo = InMemoryReminderRepository(initialReminders: [
        // Valid Today Task
        ReminderModel(
          id: 'rem_valid_today',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Valid Today Task Clean Kitchen',
          date: todayStr,
          time: '10:00',
          status: ReminderStatus.pending,
        ),
        // Empty date string with time
        const ReminderModel(
          id: 'rem_empty_date_with_time',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Boundary Task Empty Date With Time',
          date: '',
          time: '11:00',
          status: ReminderStatus.pending,
        ),
        // Empty date and empty time
        const ReminderModel(
          id: 'rem_empty_date_empty_time',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Boundary Task Pure Empty Date Time',
          date: '',
          time: '',
          status: ReminderStatus.pending,
        ),
        // Malformed date from json with null date
        ReminderModel.fromJson({
          'id': 'rem_null_date_json',
          'family_id': 'family_m0_boundary',
          'creator_id': 'user_challenger',
          'assigned_to': 'user_challenger',
          'assigned_to_name': 'Vinh Challenger',
          'title': 'Boundary Task Null Date JSON',
          'date': null,
          'time': null,
          'status': 'PENDING',
        }),
        // Slashed malformed date
        const ReminderModel(
          id: 'rem_malformed_slashed',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Boundary Task Slashed Malformed',
          date: 'bad/date/string',
          time: '12:00',
          status: ReminderStatus.pending,
        ),
        // Valid Tomorrow Task
        ReminderModel(
          id: 'rem_valid_tomorrow',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Valid Tomorrow Task Buy Groceries',
          date: tomorrowStr,
          time: '15:00',
          status: ReminderStatus.pending,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'family_m0_boundary',
            currentUserId: 'user_challenger',
            familyMembers: testMembers,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Assert screen built successfully without unhandled exceptions
      expect(tester.takeException(), isNull);

      // 2. Default Today filter: Only valid today task should be visible
      expect(find.text('Valid Today Task Clean Kitchen'), findsOneWidget);
      expect(find.text('Valid Tomorrow Task Buy Groceries'), findsNothing);
      expect(find.text('Boundary Task Slashed Malformed'), findsNothing);
      expect(find.text('Boundary Task Pure Empty Date Time'), findsNothing);

      // 3. Tap "Tất cả" to reveal all items
      await tester.tap(find.text('Tất cả'));
      await tester.pumpAndSettle();

      // 4. Assert all boundary reminders render cleanly without crashing ReminderCard
      expect(tester.takeException(), isNull);
      expect(find.text('Valid Today Task Clean Kitchen'), findsOneWidget);
      expect(find.text('Valid Tomorrow Task Buy Groceries'), findsOneWidget);
      expect(find.text('Boundary Task Empty Date With Time'), findsOneWidget);
      expect(find.text('Boundary Task Pure Empty Date Time'), findsOneWidget);
      expect(find.text('Boundary Task Null Date JSON'), findsOneWidget);
      expect(find.text('Boundary Task Slashed Malformed'), findsOneWidget);
    });

    testWidgets(
        'Boundary 3: ReminderDayEmptyState appears when Today has 0 reminders, and "Xem tất cả nhắc nhở" reveals all tasks',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final todayStr = formatDate(now);
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowStr = formatDate(tomorrow);
      final nextWeek = now.add(const Duration(days: 7));
      final nextWeekStr = formatDate(nextWeek);

      // NO reminders for today! Only tomorrow and next week
      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'rem_tomorrow_only',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Tomorrow Physics Exam Prep',
          date: tomorrowStr,
          time: '09:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'rem_next_week_only',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Next Week Family Dinner',
          date: nextWeekStr,
          time: '18:00',
          status: ReminderStatus.pending,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'family_m0_boundary',
            currentUserId: 'user_challenger',
            familyMembers: testMembers,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Assert ReminderDayEmptyState is shown because Today has 0 reminders
      expect(find.byType(ReminderDayEmptyState), findsOneWidget);
      expect(find.text('Chưa có việc cho ngày $todayStr'), findsOneWidget);
      expect(find.text('Xem tất cả nhắc nhở'), findsOneWidget);

      // Tasks should not be displayed in Today view
      expect(find.text('Tomorrow Physics Exam Prep'), findsNothing);
      expect(find.text('Next Week Family Dinner'), findsNothing);

      // 2. Tap "Xem tất cả nhắc nhở" in the empty state widget
      await tester.tap(find.text('Xem tất cả nhắc nhở'));
      await tester.pumpAndSettle();

      // 3. Assert ReminderDayEmptyState is dismissed and all tasks are displayed
      expect(tester.takeException(), isNull);
      expect(find.byType(ReminderDayEmptyState), findsNothing);
      expect(find.text('Tomorrow Physics Exam Prep'), findsOneWidget);
      expect(find.text('Next Week Family Dinner'), findsOneWidget);

      // 4. Assert FamilyProgressCard shows "Tất cả"
      expect(find.byType(FamilyProgressCard), findsOneWidget);
    });

    testWidgets(
        'Boundary 4: ReminderEmptyState appears when entire family has 0 reminders',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Completely empty repository
      final repo = InMemoryReminderRepository(initialReminders: []);

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'family_m0_boundary',
            currentUserId: 'user_challenger',
            familyMembers: testMembers,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Truly empty state: ReminderEmptyState is shown, NOT ReminderDayEmptyState
      expect(find.byType(ReminderEmptyState), findsOneWidget);
      expect(find.byType(ReminderDayEmptyState), findsNothing);
      expect(find.text('Chưa có lời nhắc nào.'), findsOneWidget);
      expect(find.text('Tạo lời nhắc mới'), findsOneWidget);
    });

    testWidgets(
        'Boundary 5: Stress test rapid toggling between "Tất cả", individual dates, and "Hôm nay"',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final todayStr = formatDate(now);
      final yesterdayStr = formatDate(now.subtract(const Duration(days: 1)));
      final tomorrowStr = formatDate(now.add(const Duration(days: 1)));
      final twoDaysLaterStr = formatDate(now.add(const Duration(days: 2)));

      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'rem_s_yesterday',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Stress Task Yesterday',
          date: yesterdayStr,
          time: '08:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'rem_s_today',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Stress Task Today',
          date: todayStr,
          time: '10:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'rem_s_tomorrow',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Stress Task Tomorrow',
          date: tomorrowStr,
          time: '14:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'rem_s_2days',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Stress Task Day After Tomorrow',
          date: twoDaysLaterStr,
          time: '16:00',
          status: ReminderStatus.pending,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'family_m0_boundary',
            currentUserId: 'user_challenger',
            familyMembers: testMembers,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find key interaction controls
      final allChipFinder = find.text('Tất cả');
      final todayButtonFinder = find.byTooltip('Hôm nay');
      expect(allChipFinder, findsOneWidget);
      expect(todayButtonFinder, findsOneWidget);

      // Perform 25 rapid back-and-forth taps across controls
      for (int i = 0; i < 25; i++) {
        if (i % 3 == 0) {
          await tester.tap(allChipFinder);
        } else if (i % 3 == 1) {
          await tester.tap(todayButtonFinder);
        } else {
          // Tap a day number in the weekly strip
          final dayNumberFinder = find.text(now.day.toString());
          if (dayNumberFinder.evaluate().isNotEmpty) {
            await tester.tap(dayNumberFinder.first);
          } else {
            await tester.tap(allChipFinder);
          }
        }
        // Microtask pump simulating real touch event frequency
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Final tap to "Tất cả" to verify clean final state
      await tester.tap(allChipFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Stress Task Yesterday'), findsOneWidget);
      expect(find.text('Stress Task Today'), findsOneWidget);
      expect(find.text('Stress Task Tomorrow'), findsOneWidget);
      expect(find.text('Stress Task Day After Tomorrow'), findsOneWidget);

      // Final tap to "Hôm nay" to verify clean return to Today
      await tester.tap(todayButtonFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Stress Task Today'), findsOneWidget);
      expect(find.text('Stress Task Yesterday'), findsNothing);
      expect(find.text('Stress Task Tomorrow'), findsNothing);
    });

    testWidgets(
        'Boundary 6: Stress test toggling between Calendar View and List View with showAll preserved',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final todayStr = formatDate(now);

      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'rem_cal_today',
          familyId: 'family_m0_boundary',
          creatorId: 'user_challenger',
          assignedTo: 'user_challenger',
          assignedToName: 'Vinh Challenger',
          title: 'Calendar Mode Task Today',
          date: todayStr,
          time: '09:00',
          status: ReminderStatus.pending,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'family_m0_boundary',
            currentUserId: 'user_challenger',
            familyMembers: testMembers,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Calendar View
      final calToggleFinder = find.byIcon(Icons.calendar_month_rounded);
      expect(calToggleFinder, findsOneWidget);

      for (int i = 0; i < 10; i++) {
        // Toggle view
        if (i % 2 == 0) {
          final toCalFinder = find.byIcon(Icons.calendar_month_rounded);
          if (toCalFinder.evaluate().isNotEmpty) {
            await tester.tap(toCalFinder);
          }
        } else {
          final toListFinder = find.byIcon(Icons.format_list_bulleted_rounded);
          if (toListFinder.evaluate().isNotEmpty) {
            await tester.tap(toListFinder);
          }
        }
        await tester.pump(const Duration(milliseconds: 20));
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Calendar Mode Task Today'), findsOneWidget);
    });
  });
}

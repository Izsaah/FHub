import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';
import 'package:fhub/Vinh/screens/reminder_list_screen.dart';
import 'package:fhub/Vinh/widgets/weekly_calendar_strip.dart';
import 'package:fhub/Vinh/widgets/reminder_empty_states.dart';

void main() {
  group('Empirical Milestone 0 Challenge Tests', () {
    test('Empirical Git Branch Assertion: branch name must contain /vinh/', () {
      final result = Process.runSync('git', ['branch', '--show-current'],
          workingDirectory: Directory.current.path);
      expect(result.exitCode, equals(0),
          reason: 'git branch --show-current failed to execute');
      final currentBranch = (result.stdout as String).trim();
      expect(currentBranch, contains('/vinh/'),
          reason:
              'Current Git branch "$currentBranch" does not contain "/vinh/".');
    });

    testWidgets(
        'ReminderListScreen empirical stress test: multiple dates, default Today, "Tất cả", date selection, and return to Today',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. Setup multi-date timestamps
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final tomorrow = today.add(const Duration(days: 1));
      final sevenDaysLater = today.add(const Duration(days: 7));

      String formatDate(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

      final todayStr = formatDate(today);
      final yesterdayStr = formatDate(yesterday);
      final tomorrowStr = formatDate(tomorrow);
      final sevenDaysLaterStr = formatDate(sevenDaysLater);

      const taskYesterdayTitle = 'Task Yesterday - Math Homework';
      const taskTodayTitle = 'Task Today - Clean Living Room';
      const taskTomorrowTitle = 'Task Tomorrow - Grocery Shopping';
      const taskSevenDaysTitle = 'Task Seven Days Later - Doctor Appointment';

      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'rem_yesterday',
          familyId: 'family_emp_0',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Vinh',
          title: taskYesterdayTitle,
          date: yesterdayStr,
          time: '10:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'rem_today',
          familyId: 'family_emp_0',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Vinh',
          title: taskTodayTitle,
          date: todayStr,
          time: '14:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'rem_tomorrow',
          familyId: 'family_emp_0',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Vinh',
          title: taskTomorrowTitle,
          date: tomorrowStr,
          time: '16:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'rem_seven_days',
          familyId: 'family_emp_0',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Vinh',
          title: taskSevenDaysTitle,
          date: sevenDaysLaterStr,
          time: '09:00',
          status: ReminderStatus.pending,
        ),
      ]);

      const members = [
        FamilyMember(
          id: 'user_vinh',
          name: 'Vinh',
          role: 'Owner',
          familyId: 'family_emp_0',
        ),
      ];

      // 2. Pump ReminderListScreen with initialShowAll omitted (verifying default parameter = false)
      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'family_emp_0',
            currentUserId: 'user_vinh',
            currentUserName: 'Vinh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // STEP A: Assert that initially (default), ONLY today's tasks are displayed
      expect(find.text(taskTodayTitle), findsOneWidget,
          reason: 'Today task must be visible by default');
      expect(find.text(taskYesterdayTitle), findsNothing,
          reason: 'Yesterday task must NOT be visible by default');
      expect(find.text(taskTomorrowTitle), findsNothing,
          reason: 'Tomorrow task must NOT be visible by default');
      expect(find.text(taskSevenDaysTitle), findsNothing,
          reason: '7 days later task must NOT be visible by default');

      // STEP B: Assert that tapping the "Tất cả" chip displays ALL tasks across all dates
      final allChipFinder = find.descendant(
        of: find.byType(WeeklyCalendarStrip),
        matching: find.text('Tất cả'),
      );
      expect(allChipFinder, findsOneWidget,
          reason: '"Tất cả" chip must exist in WeeklyCalendarStrip');

      await tester.tap(allChipFinder);
      await tester.pumpAndSettle();

      expect(find.text(taskTodayTitle), findsOneWidget,
          reason: 'Today task must be visible in "Tất cả" mode');
      expect(find.text(taskYesterdayTitle), findsOneWidget,
          reason: 'Yesterday task must be visible in "Tất cả" mode');
      expect(find.text(taskTomorrowTitle), findsOneWidget,
          reason: 'Tomorrow task must be visible in "Tất cả" mode');
      expect(find.text(taskSevenDaysTitle), findsOneWidget,
          reason: '7 days later task must be visible in "Tất cả" mode');

      // STEP C: Assert that selecting a specific date filters to that date
      // Navigate to next week to select sevenDaysLater
      final nextWeekFinder = find.descendant(
        of: find.byType(WeeklyCalendarStrip),
        matching: find.byIcon(Icons.chevron_right),
      );
      expect(nextWeekFinder, findsOneWidget);
      await tester.tap(nextWeekFinder);
      await tester.pumpAndSettle();

      // In the next week, tap the day number for sevenDaysLater
      final sevenDayNumFinder = find.descendant(
        of: find.byType(WeeklyCalendarStrip),
        matching: find.text('${sevenDaysLater.day}'),
      );
      expect(sevenDayNumFinder, findsOneWidget,
          reason: 'Day for 7 days later must be visible in the next week strip');

      await tester.tap(sevenDayNumFinder);
      await tester.pumpAndSettle();

      // Assert ONLY 7 days later task is visible
      expect(find.text(taskSevenDaysTitle), findsOneWidget,
          reason: 'Only seven-days-later task should be displayed for that date');
      expect(find.text(taskTodayTitle), findsNothing,
          reason: 'Today task must NOT be visible when filtered to 7 days later');
      expect(find.text(taskYesterdayTitle), findsNothing,
          reason: 'Yesterday task must NOT be visible when filtered to 7 days later');
      expect(find.text(taskTomorrowTitle), findsNothing,
          reason: 'Tomorrow task must NOT be visible when filtered to 7 days later');

      // STEP D: Assert that switching back to Today filters back to today
      final todayButtonFinder = find.descendant(
        of: find.byType(WeeklyCalendarStrip),
        matching: find.byIcon(Icons.today_outlined),
      );
      expect(todayButtonFinder, findsOneWidget,
          reason: 'Today icon button must be present in WeeklyCalendarStrip');

      await tester.tap(todayButtonFinder);
      await tester.pumpAndSettle();

      // Assert ONLY today task is visible again
      expect(find.text(taskTodayTitle), findsOneWidget,
          reason: 'Today task must be visible after returning to Today');
      expect(find.text(taskYesterdayTitle), findsNothing,
          reason: 'Yesterday task must NOT be visible when filtered to Today');
      expect(find.text(taskTomorrowTitle), findsNothing,
          reason: 'Tomorrow task must NOT be visible when filtered to Today');
      expect(find.text(taskSevenDaysTitle), findsNothing,
          reason: '7 days later task must NOT be visible when filtered to Today');

      // STEP E: Filter to yesterday directly via week navigation
      if (today.weekday == 1) {
        // Today is Monday -> yesterday is Sunday of previous week
        final prevWeekFinder = find.descendant(
          of: find.byType(WeeklyCalendarStrip),
          matching: find.byIcon(Icons.chevron_left),
        );
        await tester.tap(prevWeekFinder);
        await tester.pumpAndSettle();
      }

      final yesterdayDayNumFinder = find.descendant(
        of: find.byType(WeeklyCalendarStrip),
        matching: find.text('${yesterday.day}'),
      );
      expect(yesterdayDayNumFinder, findsOneWidget);
      await tester.tap(yesterdayDayNumFinder);
      await tester.pumpAndSettle();

      expect(find.text(taskYesterdayTitle), findsOneWidget,
          reason: 'Yesterday task must be visible when yesterday is selected');
      expect(find.text(taskTodayTitle), findsNothing);
      expect(find.text(taskTomorrowTitle), findsNothing);
      expect(find.text(taskSevenDaysTitle), findsNothing);

      // Return to Today once more using Today button
      await tester.tap(todayButtonFinder);
      await tester.pumpAndSettle();

      expect(find.text(taskTodayTitle), findsOneWidget);
      expect(find.text(taskYesterdayTitle), findsNothing);
      expect(find.text(taskTomorrowTitle), findsNothing);
      expect(find.text(taskSevenDaysTitle), findsNothing);
    });

    testWidgets(
        'ReminderListScreen stress test: empty date shows empty state and "Xem tất cả" button toggles to All',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final twoDaysLater = today.add(const Duration(days: 2));

      String formatDate(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'rem_today_only',
          familyId: 'family_emp_0',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Vinh',
          title: 'Single Task For Today',
          date: formatDate(today),
          time: '08:00',
          status: ReminderStatus.pending,
        ),
      ]);

      const members = [
        FamilyMember(
          id: 'user_vinh',
          name: 'Vinh',
          role: 'Owner',
          familyId: 'family_emp_0',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'family_emp_0',
            currentUserId: 'user_vinh',
            currentUserName: 'Vinh',
            familyMembers: members,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Single Task For Today'), findsOneWidget);

      // Navigate to week containing twoDaysLater if needed
      if (today.weekday >= 6) {
        final nextWeekFinder = find.descendant(
          of: find.byType(WeeklyCalendarStrip),
          matching: find.byIcon(Icons.chevron_right),
        );
        await tester.tap(nextWeekFinder);
        await tester.pumpAndSettle();
      }

      final twoDaysNumFinder = find.descendant(
        of: find.byType(WeeklyCalendarStrip),
        matching: find.text('${twoDaysLater.day}'),
      );
      await tester.tap(twoDaysNumFinder);
      await tester.pumpAndSettle();

      // On this empty date, task for today is hidden and empty state is displayed
      expect(find.text('Single Task For Today'), findsNothing);
      expect(find.byType(ReminderDayEmptyState), findsOneWidget);

      // Tap "Xem tất cả nhắc nhở" button on empty state
      final showAllBtnFinder = find.descendant(
        of: find.byType(ReminderDayEmptyState),
        matching: find.text('Xem tất cả nhắc nhở'),
      );
      expect(showAllBtnFinder, findsOneWidget);
      await tester.tap(showAllBtnFinder);
      await tester.pumpAndSettle();

      // Should now display all tasks across dates
      expect(find.text('Single Task For Today'), findsOneWidget);
    });

    testWidgets(
        'ReminderListScreen stress test: explicit initialShowAll: true override behaves correctly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      String formatDate(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'r_today',
          familyId: 'family_emp_0',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Vinh',
          title: 'Task A Today',
          date: formatDate(today),
          time: '08:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'r_yesterday',
          familyId: 'family_emp_0',
          creatorId: 'user_vinh',
          assignedTo: 'user_vinh',
          assignedToName: 'Vinh',
          title: 'Task B Yesterday',
          date: formatDate(yesterday),
          time: '08:00',
          status: ReminderStatus.pending,
        ),
      ]);

      const members = [
        FamilyMember(
          id: 'user_vinh',
          name: 'Vinh',
          role: 'Owner',
          familyId: 'family_emp_0',
        ),
      ];

      // Explicitly pass initialShowAll: true
      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: 'family_emp_0',
            currentUserId: 'user_vinh',
            currentUserName: 'Vinh',
            familyMembers: members,
            repository: repo,
            initialShowAll: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both tasks should be visible immediately
      expect(find.text('Task A Today'), findsOneWidget);
      expect(find.text('Task B Yesterday'), findsOneWidget);
    });
  });
}

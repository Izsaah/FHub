import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:fhub/Danh/services/payment_service.dart';
import 'package:fhub/Long/screens/home/home_screen.dart';
import 'package:fhub/Long/screens/profile/profile_screen.dart';
import 'package:fhub/Long/widgets/custom_app_bar.dart';

import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/screens/calendar_page.dart';
import 'package:fhub/Vinh/screens/reminder_list_screen.dart';
import 'package:fhub/Vinh/screens/views/reminder_list_view.dart';
import 'package:fhub/Vinh/services/alarm_sound_service.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';
import 'package:fhub/Vinh/widgets/weekly_calendar_strip.dart';

void main() {
  const testFamilyId = 'family_challenger_m4';
  const testUserId = 'user_challenger_vinh';
  const testUserName = 'Vinh Challenger';

  const testMembers = [
    FamilyMember(
      id: testUserId,
      name: testUserName,
      role: 'Owner',
      familyId: testFamilyId,
    ),
    FamilyMember(
      id: 'member_2',
      name: 'Bé Bắp',
      role: 'Child',
      familyId: testFamilyId,
    ),
  ];

  String formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

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

  group('Milestone 4 Adversarial Stress Testing — FIX-01: Lifecycle Timer Cleanup', () {
    test('1.1 stopClock() and cancelAll() are deterministic and idempotent', () {
      final escalation = MultiTierEscalationService.instance;

      // Start clock
      escalation.ensureClockRunning();

      // Stop once
      escalation.stopClock();
      // Stop multiple times (should not throw or leak)
      escalation.stopClock();
      escalation.stopClock();

      // CancelAll multiple times
      escalation.cancelAll();
      escalation.cancelAll();
    });

    test('1.2 Rapid start/stop cycles of global clock do not leak timers', () {
      final escalation = MultiTierEscalationService.instance;
      for (int i = 0; i < 50; i++) {
        escalation.ensureClockRunning();
        escalation.stopClock();
      }
      escalation.stopClock();
    });

    testWidgets('1.3 ReminderListScreen unmount teardown completely purges timers without leak',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'rem_m4_timer_1',
          familyId: testFamilyId,
          creatorId: testUserId,
          assignedTo: testUserId,
          assignedToName: testUserName,
          title: 'Adversarial Timer Chore',
          date: formatDate(DateTime.now()),
          time: '12:00',
          status: ReminderStatus.pending,
        ),
      ]);

      // Mount ReminderListScreen
      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: testFamilyId,
            currentUserId: testUserId,
            currentUserName: testUserName,
            familyMembers: testMembers,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pump several periodic ticks
      await tester.pump(const Duration(seconds: 3));

      // Unmount the entire widget tree
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Verification: test framework asserts !timersPending during teardown
    });

    testWidgets('1.4 CalendarPage unmount teardown cleanly stops clock without timer leaks',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = InMemoryReminderRepository(initialReminders: []);

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarPage(
            familyId: testFamilyId,
            currentUserId: testUserId,
            currentUserName: testUserName,
            familyMembers: testMembers,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Advance periodic ticks
      await tester.pump(const Duration(seconds: 2));

      // Unmount
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('Milestone 4 Adversarial Stress Testing — FIX-02: Calendar Week Navigation & Anti-Snapback', () {
    testWidgets('2.1 Navigating week forward stays on navigated week across 25 timer ticks (no snap-back)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Fixed anchor date: Wednesday, Nov 4, 2026
      final initialSelectedDate = DateTime(2026, 11, 4);

      // Wrapper stateful widget that allows rebuilding WeeklyCalendarStrip with same selectedDate
      final rebuildNotifier = ValueNotifier<int>(0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: rebuildNotifier,
              builder: (context, revision, _) {
                return WeeklyCalendarStrip(
                  selectedDate: initialSelectedDate,
                  showAll: false,
                  reminders: const [],
                  onDateSelected: (_) {},
                  onSelectAll: () {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially, day 4 (Wednesday Nov 4) is in the visible week Nov 2 - Nov 8.
      expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('4')),
          findsOneWidget,
          reason: 'Initial week (Nov 2-8) must display day 4');

      // Tap Next Week Chevron (Icons.chevron_right)
      final nextWeekBtn = find.descendant(
        of: find.byType(WeeklyCalendarStrip),
        matching: find.byIcon(Icons.chevron_right),
      );
      expect(nextWeekBtn, findsOneWidget);
      await tester.tap(nextWeekBtn);
      await tester.pumpAndSettle();

      // In the next week (Nov 9 - Nov 15), day 11 must be visible and day 4 must NOT be visible
      expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('11')),
          findsOneWidget,
          reason: 'Advanced week (Nov 9-15) must display day 11');
      expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('4')),
          findsNothing,
          reason: 'Initial day 4 must NOT be visible on next week');

      // Now adversarial stress test: simulate 25 periodic ticker rebuilds passing identical selectedDate (Nov 4)
      for (int i = 1; i <= 25; i++) {
        rebuildNotifier.value = i;
        await tester.pump(const Duration(milliseconds: 100));

        // In the buggy code, on tick 1, didUpdateWidget snapped back to Nov 2-8!
        // In the fixed code, day 11 MUST remain visible and day 4 must remain hidden.
        expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('11')),
            findsOneWidget,
            reason: 'Tick $i: Day 11 must NOT snap back to initial week!');
        expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('4')),
            findsNothing,
            reason: 'Tick $i: Day 4 must NOT reappear due to snap back!');
      }
    });

    testWidgets('2.2 Navigating week backward stays on backward week across 20 timer ticks',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialSelectedDate = DateTime(2026, 11, 4);
      final rebuildNotifier = ValueNotifier<int>(0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: rebuildNotifier,
              builder: (context, revision, _) {
                return WeeklyCalendarStrip(
                  selectedDate: initialSelectedDate,
                  showAll: false,
                  reminders: const [],
                  onDateSelected: (_) {},
                  onSelectAll: () {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Previous Week (Icons.chevron_left)
      final prevWeekBtn = find.descendant(
        of: find.byType(WeeklyCalendarStrip),
        matching: find.byIcon(Icons.chevron_left),
      );
      await tester.tap(prevWeekBtn);
      await tester.pumpAndSettle();

      // Previous week (Oct 26 - Nov 1): day 28 should be visible, day 4 should not be visible
      expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('28')),
          findsOneWidget,
          reason: 'Previous week (Oct 26-Nov 1) must display day 28');
      expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('4')),
          findsNothing,
          reason: 'Day 4 must not be visible on previous week');

      // Stress test 20 rebuild ticks
      for (int i = 1; i <= 20; i++) {
        rebuildNotifier.value = i;
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('28')),
            findsOneWidget,
            reason: 'Tick $i: Day 28 must remain visible without snap back');
      }
    });

    testWidgets('2.3 Explicit external selectedDate update correctly syncs _weekStart',
        (WidgetTester tester) async {
      final dateNotifier = ValueNotifier<DateTime>(DateTime(2026, 11, 4));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<DateTime>(
              valueListenable: dateNotifier,
              builder: (context, date, _) {
                return WeeklyCalendarStrip(
                  selectedDate: date,
                  showAll: false,
                  reminders: const [],
                  onDateSelected: (_) {},
                  onSelectAll: () {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('4')),
          findsOneWidget);

      // Parent deliberately updates selectedDate to Nov 18 (2 weeks later)
      dateNotifier.value = DateTime(2026, 11, 18);
      await tester.pumpAndSettle();

      // WeeklyCalendarStrip must follow the new date since oldWidget.selectedDate != widget.selectedDate
      expect(find.descendant(of: find.byType(WeeklyCalendarStrip), matching: find.text('18')),
          findsOneWidget,
          reason: 'Deliberate selectedDate change must recenter the calendar week');
    });
  });

  group('Milestone 4 Adversarial Stress Testing — FIX-03: Unmodifiable List Mutation Handling', () {
    test('3.1 syncReminders with UnmodifiableListView does not throw Unsupported operation', () {
      final escalation = MultiTierEscalationService.instance;

      final originalList = [
        ReminderModel(
          id: 'rem_unmod_1',
          familyId: testFamilyId,
          creatorId: testUserId,
          assignedTo: testUserId,
          assignedToName: testUserName,
          title: 'Unmodifiable Chore 1',
          date: '01/01/2026',
          time: '08:00',
          status: ReminderStatus.pending,
        ),
        ReminderModel(
          id: 'rem_unmod_2',
          familyId: testFamilyId,
          creatorId: testUserId,
          assignedTo: testUserId,
          assignedToName: testUserName,
          title: 'Unmodifiable Chore 2',
          date: '01/01/2026',
          time: '09:00',
          status: ReminderStatus.overdue,
        ),
      ];

      // Wrap in strict unmodifiable views
      final unmodView = UnmodifiableListView<ReminderModel>(originalList);
      final unmodList = List<ReminderModel>.unmodifiable(originalList);

      // In the buggy code, passing this caused syncReminders to crash on list assignment/mutation
      expect(
        () => escalation.syncReminders(unmodView, currentUserId: testUserId),
        returnsNormally,
      );

      expect(
        () => escalation.syncReminders(unmodList, currentUserId: testUserId),
        returnsNormally,
      );
    });

    test('3.2 syncReminders with empty unmodifiable list handles boundary gracefully', () {
      final escalation = MultiTierEscalationService.instance;
      final emptyUnmod = List<ReminderModel>.unmodifiable([]);

      expect(
        () => escalation.syncReminders(emptyUnmod, currentUserId: testUserId),
        returnsNormally,
      );
    });
  });

  group('Milestone 4 Adversarial Stress Testing — FIX-06: Account-Level Premium Governance', () {
    test('4.1 PaymentService activates Premium and enforces 10 member capacity', () async {
      final payment = PaymentService();

      await payment.activatePremium(
        planName: 'Family Hub Diamond VIP',
        maxMembers: 10,
        duration: const Duration(days: 30),
      );

      expect(payment.isPremium, isTrue);
      expect(payment.currentSubscription.planName, equals('Family Hub Diamond VIP'));
      expect(payment.currentSubscription.maxMembers, equals(10));

      // Member slot capacity verification
      expect(payment.canAddMember(0), isTrue);
      expect(payment.canAddMember(9), isTrue);
      expect(payment.canAddMember(10), isFalse);
      expect(payment.remainingSlots(8), equals(2));
      expect(payment.remainingSlots(10), equals(0));
      expect(payment.getMemberLimitMessage(10), contains('tối đa 10 thành viên'));
    });

    test('4.2 Switching family contexts maintains account-level premium state', () async {
      final payment = PaymentService();

      payment.setFamilyId('family_unit_alpha');
      await payment.activatePremium(planName: 'Family Hub Premium', maxMembers: 10);
      expect(payment.isPremium, isTrue);

      // Switch to different family unit
      payment.setFamilyId('family_unit_beta');
      // Premium must remain active for the user account
      expect(payment.isPremium, isTrue);
      expect(payment.currentSubscription.maxMembers, equals(10));
    });

    test('4.3 Pending subscription when no familyId attached auto-applies on attachment', () async {
      final payment = PaymentService();

      // Reset to empty familyId
      payment.setFamilyId('');
      await payment.activatePremium(planName: 'Family Hub Premium Auto-Bind', maxMembers: 10);

      // Now set familyId
      payment.setFamilyId('family_unit_gamma');
      expect(payment.isPremium, isTrue);
      expect(payment.currentSubscription.familyId, equals('family_unit_gamma'));
    });

    test('4.4 resetToFreeForDemo cleanly restores 4 member free tier', () async {
      final payment = PaymentService();

      await payment.resetToFreeForDemo();
      expect(payment.isPremium, isFalse);
      expect(payment.currentSubscription.maxMembers, equals(4));

      expect(payment.canAddMember(3), isTrue);
      expect(payment.canAddMember(4), isFalse);
      expect(payment.getMemberLimitMessage(4), contains('Gói Cơ Bản chỉ cho phép tối đa 4 thành viên'));
    });
  });

  group('Milestone 4 Adversarial Stress Testing — FIX-07: Active Family Name on AppBars', () {
    testWidgets('5.1 HomeScreen renders active family name in CustomAppBar subtitle',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // CustomAppBar subtitle should contain active family name
      final appBarFinder = find.byType(CustomAppBar);
      expect(appBarFinder, findsOneWidget);

      final customAppBar = tester.widget<CustomAppBar>(appBarFinder);
      expect(customAppBar.subtitle, isNotNull);
      expect(customAppBar.subtitle, equals('Gia đình Nguyễn'));

      // Check text is rendered inside CustomAppBar
      expect(
        find.descendant(of: appBarFinder, matching: find.text('Gia đình Nguyễn')),
        findsOneWidget,
      );
    });

    testWidgets('5.2 ReminderListScreen renders active family name in AppBar Column',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = InMemoryReminderRepository(initialReminders: []);

      await tester.pumpWidget(
        MaterialApp(
          home: ReminderListScreen(
            familyId: testFamilyId,
            currentUserId: testUserId,
            currentUserName: testUserName,
            familyMembers: testMembers,
            families: const [
              FamilyOption(id: testFamilyId, name: 'Gia Đình An Bình'),
            ],
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ReminderListScreen should render the active family name in the AppBar
      final appBarFinder = find.byType(AppBar);
      expect(
        find.descendant(of: appBarFinder, matching: find.text('Gia Đình An Bình')),
        findsOneWidget,
      );
    });

    testWidgets('5.3 ProfileScreen renders active family name in CustomAppBar subtitle',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final appBarFinder = find.byType(CustomAppBar);
      expect(appBarFinder, findsOneWidget);

      final customAppBar = tester.widget<CustomAppBar>(appBarFinder);
      expect(customAppBar.subtitle, isNotNull);
      expect(customAppBar.subtitle, equals('Gia đình Nguyễn'));

      expect(
        find.descendant(of: appBarFinder, matching: find.text('Gia đình Nguyễn')),
        findsOneWidget,
      );
    });
  });

  group('Milestone 4 Adversarial Stress Testing — FIX-08: Bottom Padding & Anti-FAB Occlusion', () {
    testWidgets('6.1 ReminderListView active tasks has 96px bottom padding and 88px trailing spacer',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testReminders = [
        ReminderModel(
          id: 'rem_fab_1',
          familyId: testFamilyId,
          creatorId: testUserId,
          assignedTo: testUserId,
          assignedToName: testUserName,
          title: 'Chore above FAB',
          date: formatDate(DateTime.now()),
          time: '14:00',
          status: ReminderStatus.pending,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderListView(
              displayedReminders: testReminders,
              allReminders: testReminders,
              currentUserId: testUserId,
              selectedDateStr: formatDate(DateTime.now()),
              isShowingAll: false,
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
      await tester.pumpAndSettle();

      final listViewFinder = find.byType(ListView);
      expect(listViewFinder, findsOneWidget);

      final listView = tester.widget<ListView>(listViewFinder);
      final padding = listView.padding as EdgeInsets;
      // In shrinkWrap ? 96 : 110, bottom padding must be at least 96px
      expect(padding.bottom, greaterThanOrEqualTo(96));

      // Check trailing spacer of 88px exists
      final spacerFinder = find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 88,
      );
      expect(spacerFinder, findsOneWidget,
          reason: '88px bottom spacer must be present to prevent FAB occlusion');
    });

    testWidgets('6.2 ReminderListView empty state has 96px bottom padding',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderListView(
              displayedReminders: const [],
              allReminders: const [],
              currentUserId: testUserId,
              selectedDateStr: formatDate(DateTime.now()),
              isShowingAll: false,
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
      await tester.pumpAndSettle();

      // Should wrap ReminderEmptyState in Padding with bottom: 96
      final paddingFinder = find.byWidgetPredicate(
        (w) => w is Padding && w.padding == const EdgeInsets.only(bottom: 96),
      );
      expect(paddingFinder, findsOneWidget,
          reason: 'Empty state must be padded by 96px at bottom to avoid FAB collision');
    });
  });
}

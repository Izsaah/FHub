import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Long/widgets/app_toast.dart';
import 'package:fhub/Long/models/user_model.dart';
import 'package:fhub/Long/utils/long_strings.dart';

void main() {
  group('AppToast & UI Polish Tests', () {
    testWidgets('AppToast.show displays at the top and auto dismisses', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    AppToast.show(
                      context,
                      'Đã sao chép mã mời',
                      duration: const Duration(milliseconds: 500),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        ),
      );

      // Initially no toast
      expect(find.text('Đã sao chép mã mời'), findsNothing);

      // Tap button to trigger toast
      await tester.tap(find.text('Show Toast'));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 100));

      // Toast is visible
      expect(find.text('Đã sao chép mã mời'), findsOneWidget);

      // Fast forward past duration and dismiss animation
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 300));

      // Toast has disappeared
      expect(find.text('Đã sao chép mã mời'), findsNothing);
    });

    testWidgets('AppToast.showSuccess displays check icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => AppToast.showSuccess(context, 'Lưu thành công'),
                  child: const Text('Success'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Success'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Lưu thành công'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 300));
    });

    test('UserModel handles emoji avatars and preset types correctly', () {
      final user = UserModel(
        id: 'u123',
        name: 'Nguyen Van A',
        email: 'a@example.com',
        avatarType: 'dad',
        avatarUrl: 'emoji:👨',
      );

      expect(user.avatarType, 'dad');
      expect(user.avatarUrl, 'emoji:👨');
      expect(user.avatarUrl.startsWith('emoji:'), isTrue);
      expect(user.avatarUrl.replaceFirst('emoji:', ''), '👨');
    });

    test('LongStrings viewAllReminders is defined properly', () {
      expect(LongStrings.viewAllReminders.isNotEmpty, isTrue);
      expect(LongStrings.pendingRemindersTitle.isNotEmpty, isTrue);
    });
  });
}

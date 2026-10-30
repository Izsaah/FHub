// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/Thinh/screens/login_form_view.dart';
import '../lib/Thinh/screens/register_view.dart';
import '../lib/Thinh/theme/app_language.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('Family Hub Smoke Test'),
        ),
      ),
    );

    expect(find.text('Family Hub Smoke Test'), findsOneWidget);
  });

  testWidgets('Login form updates immediately when language changes', (
    WidgetTester tester,
  ) async {
    AppLanguage.isEnglish.value = false;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoginFormView())),
    );

    expect(find.text('Chào mừng trở về Nhà! 👋'), findsOneWidget);
    expect(find.text('Đăng nhập vào Tổ Ấm'), findsOneWidget);

    AppLanguage.isEnglish.value = true;
    await tester.pump();

    expect(find.text('Welcome home! 👋'), findsOneWidget);
    expect(find.text('Sign in to Family Hub'), findsOneWidget);
    expect(find.text('Chào mừng trở về Nhà! 👋'), findsNothing);
  });

  testWidgets('Registration form updates immediately when language changes', (
    WidgetTester tester,
  ) async {
    AppLanguage.isEnglish.value = false;
    await tester.pumpWidget(const MaterialApp(home: RegisterView()));

    expect(find.text('Tạo tài khoản mới'), findsOneWidget);
    expect(find.text('Họ và Tên'), findsOneWidget);

    AppLanguage.isEnglish.value = true;
    await tester.pump();

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Tạo tài khoản mới'), findsNothing);
  });
}

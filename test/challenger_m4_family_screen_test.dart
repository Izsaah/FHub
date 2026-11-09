import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';

import 'package:fhub/Long/screens/family/family_screen.dart';
import 'package:fhub/Long/widgets/custom_app_bar.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  });

  testWidgets('5.3 FamilyScreen renders active family name in CustomAppBar subtitle',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: FamilyScreen(),
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
}

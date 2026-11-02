import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Ai/services/gemini_chat_service.dart';
import 'package:fhub/Danh/screens/family_jackpot_screen.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';
import 'package:fhub/Danh/services/payment_service.dart';

void main() {
  group('End-User Simulation Tests (Mobile 360px & Virtual 3-Button Navigation Bar)', () {
    setUp(() async {
      await PaymentService().activatePremium();
      FamilyJackpotService.instance.initForFamily('f1');
    });

    testWidgets('1. Mobile 360px viewport: AppBar title, Wallet Card buttons, and Deposit header render without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              padding: EdgeInsets.only(top: 24, bottom: 48), // 48px thanh điều hướng ảo Android
            ),
            child: const FamilyJackpotScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify AppBar Title exists and is not truncated
      expect(find.text('Hũ Niềm Vui Gia Đình'), findsOneWidget);

      // Verify Actions: Bell notification icon and Help icon
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);

      // Verify Adaptive Wallet Card: Both 'Lịch Sử' and 'Rút Tiền' are visible
      expect(find.text('Ví Thưởng Của Tôi'), findsOneWidget);
      expect(find.text('Lịch Sử'), findsOneWidget);
      expect(find.text('Rút Tiền'), findsOneWidget);

      // Verify Deposit Section: Clean wrap layout without overlap
      expect(find.text('1. Nạp Tiền Vào Quỹ Hũ (VietQR)'), findsOneWidget);
      expect(find.text('MBBank 0000000001'), findsOneWidget);
      expect(find.text('+20.000 đ'), findsOneWidget);
      expect(find.text('+50.000 đ'), findsOneWidget);
      expect(find.text('+100.000 đ'), findsOneWidget);

      // Verify no flame / tacky icons in idle state
      expect(find.byIcon(Icons.whatshot_rounded), findsNothing);
    });

    testWidgets('2. End-user opens Rules Modal: "Đã Hiểu" button is elevated above virtual 3-button bar', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              padding: EdgeInsets.only(top: 24, bottom: 48),
            ),
            child: const FamilyJackpotScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Help icon to open Rules Modal
      await tester.tap(find.byIcon(Icons.help_outline_rounded));
      await tester.pumpAndSettle();

      // Verify Modal Title and Rules content
      expect(find.text('Luật Chơi Hũ Niềm Vui Gia Đình 📜'), findsOneWidget);
      expect(find.text('Đã Hiểu'), findsOneWidget);

      // Tap "Đã Hiểu" -> Modal closes smoothly
      await tester.tap(find.text('Đã Hiểu'));
      await tester.pumpAndSettle();

      expect(find.text('Luật Chơi Hũ Niềm Vui Gia Đình 📜'), findsNothing);
    });

    testWidgets('3. End-user opens Notification Hub: Displays header and 15-day rolling storage notice', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              padding: EdgeInsets.only(top: 24, bottom: 48),
            ),
            child: const FamilyJackpotScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Notification Bell icon
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      // Verify Notification Hub Header
      expect(find.text('Thông Báo Gia Đình'), findsOneWidget);
      expect(find.text('Lưu trữ tự động trong 15 ngày gần nhất'), findsOneWidget);
      expect(find.text('Đã đọc tất cả'), findsOneWidget);

      // Close modal
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Thông Báo Gia Đình'), findsNothing);
    });

    testWidgets('4. End-user opens Wallet History & Withdrawal Modals: Safe Area bottom padding applied', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              padding: EdgeInsets.only(top: 24, bottom: 48),
            ),
            child: const FamilyJackpotScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Lịch Sử' button on Wallet Card
      await tester.tap(find.text('Lịch Sử'));
      await tester.pumpAndSettle();

      expect(find.text('Lịch Sử Biến Động Ví & Quỹ'), findsOneWidget);
      expect(find.text('Lưu trữ tự động trong 15 ngày gần nhất'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Tap 'Rút Tiền' button on Wallet Card
      await tester.tap(find.text('Rút Tiền'));
      await tester.pumpAndSettle();

      expect(find.text('Ví Thưởng & Rút Tiền Về Ngân Hàng'), findsOneWidget);
      expect(find.text('Số tiền muốn rút (VNĐ)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    });

    test('5. End-user AI Chat conversation: Multi-intent dialogue testing without "chào mẹ"', () async {
      final ai = GeminiChatService.instance;

      // User Danh (Role: Con cái)
      await ai.initChat(
        familyId: 'f1',
        userId: 'u_danh',
        userName: 'Danh',
        userRole: 'Con cái',
        familyName: 'Tổ Ấm',
      );

      // Question 1: Role check
      final roleMsg = await ai.sendMessage('à mà bạn có thể cho tôi biết vai trò của tôi trong gia đình không ?');
      expect(roleMsg.text, isNot(contains('chào mẹ')));
      expect(roleMsg.text, isNot(contains('Chào mẹ')));
      expect(roleMsg.text, isNot(contains('Dạ mẹ')));
      expect(roleMsg.text, contains('Con cái'));

      // Question 2: Check-in status
      final checkInMsg = await ai.sendMessage('ai đã điểm danh hôm nay?');
      expect(checkInMsg.text, isNot(contains('chào mẹ')));
      expect(checkInMsg.text, contains('ĐIỂM DANH'));

      // Question 3: Progress summary
      final progressMsg = await ai.sendMessage('tóm tắt tiến độ công việc hôm nay');
      expect(progressMsg.text, isNot(contains('chào mẹ')));
      expect(progressMsg.text, contains('TIẾN ĐỘ'));

      // Question 4: Jackpot query
      final jackpotMsg = await ai.sendMessage('hũ niềm vui gia đình có bao nhiêu tiền và ai được nổ hũ?');
      expect(jackpotMsg.text, contains('HŨ NIỀM VUI'));
      expect(jackpotMsg.text, contains('30 giây'));

      // Question 5: Member identity query
      final roleMsg2 = await ai.sendMessage('tôi là ai trong gia đình này?');
      expect(roleMsg2.text, isNot(contains('chào mẹ')));
      expect(roleMsg2.text, contains('Danh'));
    });
  });
}

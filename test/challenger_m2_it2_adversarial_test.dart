import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/widgets/reminder_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CHALLENGER ADVERSARIAL SUITE 1: voiceDurationSeconds & Type Coercion Fuzzing', () {
    test('1.1 Standard & Boundary Integers and Null Fallbacks', () {
      // 0 seconds
      expect(ReminderModel.fromJson({'voiceDurationSeconds': 0}).voiceDurationSeconds, 0);
      expect(ReminderModel.fromJson({'voice_duration_seconds': 0}).voiceDurationSeconds, 0);

      // Positive integers
      expect(ReminderModel.fromJson({'voiceDurationSeconds': 1}).voiceDurationSeconds, 1);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': 60}).voiceDurationSeconds, 60);
      expect(ReminderModel.fromJson({'voice_duration_seconds': 3600}).voiceDurationSeconds, 3600);

      // Missing and null
      expect(ReminderModel.fromJson({}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': null}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voice_duration_seconds': null}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': null, 'voice_duration_seconds': null}).voiceDurationSeconds, isNull);
    });

    test('1.2 String Numeric Integers & Floating Point Coercion', () {
      // String integers
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '0'}).voiceDurationSeconds, 0);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '45'}).voiceDurationSeconds, 45);
      expect(ReminderModel.fromJson({'voice_duration_seconds': '120'}).voiceDurationSeconds, 120);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '+30'}).voiceDurationSeconds, 30);

      // Decimals as double
      expect(ReminderModel.fromJson({'voiceDurationSeconds': 45.9}).voiceDurationSeconds, 45);
      expect(ReminderModel.fromJson({'voice_duration_seconds': 12.1}).voiceDurationSeconds, 12);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': 0.0}).voiceDurationSeconds, 0);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': 0.999}).voiceDurationSeconds, 0);

      // Decimals as string
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '45.9'}).voiceDurationSeconds, 45);
      expect(ReminderModel.fromJson({'voice_duration_seconds': '12.1'}).voiceDurationSeconds, 12);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '0.0'}).voiceDurationSeconds, 0);

      // Scientific notation
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '1e2'}).voiceDurationSeconds, 100);
      expect(ReminderModel.fromJson({'voice_duration_seconds': '2.5e1'}).voiceDurationSeconds, 25);
    });

    test('1.3 Negative Numbers Handling & Duration Formatting', () {
      // Negative integers
      final neg1 = ReminderModel.fromJson({'voiceDurationSeconds': -1});
      expect(neg1.voiceDurationSeconds, -1);
      expect(neg1.voiceDurationFormatted, isNotEmpty);

      final neg45 = ReminderModel.fromJson({'voice_duration_seconds': -45});
      expect(neg45.voiceDurationSeconds, -45);

      // Negative string integers
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '-10'}).voiceDurationSeconds, -10);
      expect(ReminderModel.fromJson({'voice_duration_seconds': '-999'}).voiceDurationSeconds, -999);

      // Negative decimals
      expect(ReminderModel.fromJson({'voiceDurationSeconds': -15.8}).voiceDurationSeconds, -15);
      expect(ReminderModel.fromJson({'voice_duration_seconds': '-30.5'}).voiceDurationSeconds, -30);
    });

    test('1.4 Empty Strings, Whitespace, and Non-Numeric Garbage Safe Fallback', () {
      // Empty string
      expect(ReminderModel.fromJson({'voiceDurationSeconds': ''}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voice_duration_seconds': ''}).voiceDurationSeconds, isNull);

      // Whitespace
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '   '}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voice_duration_seconds': '\t\n'}).voiceDurationSeconds, isNull);

      // Non-numeric garbage
      expect(ReminderModel.fromJson({'voiceDurationSeconds': 'garbage'}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voice_duration_seconds': 'abc123'}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '45sec'}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': 'true'}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': 'null'}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': '--15'}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': r'$$$'}).voiceDurationSeconds, isNull);

      // Nested structures
      expect(ReminderModel.fromJson({'voiceDurationSeconds': []}).voiceDurationSeconds, isNull);
      expect(ReminderModel.fromJson({'voiceDurationSeconds': {}}).voiceDurationSeconds, isNull);
    });

    test('1.5 Key Precedence: snake_case vs camelCase Coalescing', () {
      // Both present with different integer values: snake_case wins because it is checked first
      final mBothInt = ReminderModel.fromJson({
        'voice_duration_seconds': 30,
        'voiceDurationSeconds': 60,
      });
      expect(mBothInt.voiceDurationSeconds, 30);

      // snake_case is null, camelCase is valid string
      final mFallbackCamel = ReminderModel.fromJson({
        'voice_duration_seconds': null,
        'voiceDurationSeconds': '75',
      });
      expect(mFallbackCamel.voiceDurationSeconds, 75);

      // snake_case is empty string, camelCase is valid int
      final mFallbackCamelFromEmpty = ReminderModel.fromJson({
        'voice_duration_seconds': '',
        'voiceDurationSeconds': 90,
      });
      expect(mFallbackCamelFromEmpty.voiceDurationSeconds, 90);

      // snake_case is valid string, camelCase is null
      final mFallbackSnake = ReminderModel.fromJson({
        'voice_duration_seconds': '105',
        'voiceDurationSeconds': null,
      });
      expect(mFallbackSnake.voiceDurationSeconds, 105);
    });

    test('1.6 Full Model Round-trip Serialization with Coerced Edge Fields', () {
      final jsonInput = {
        'id': 'edge_rem_001',
        'familyId': 'fam_001',
        'creatorId': 'u1',
        'assignedTo': 'u2',
        'title': 'Test Serialization',
        'date': '07/11/2026',
        'time': '09:00',
        'taskType': 'FaVoR',
        'taskStatus': 'SuBmItTeD',
        'rewardStars': '10',
        'delegationCount': '3',
        'voiceDurationSeconds': '55.4',
        'voiceNotePath': '/path/to/voice.m4a',
        'requiresProofImage': '1',
      };

      final reminder = ReminderModel.fromJson(jsonInput);
      expect(reminder.rewardStars, 10);
      expect(reminder.delegationCount, 3);
      expect(reminder.voiceDurationSeconds, 55);
      expect(reminder.requiresProofImage, isTrue);

      // Verify toMap, toJson, toFirestore preservation
      final map = reminder.toJson();
      expect(map['reward_stars'], 10);
      expect(map['voice_duration_seconds'], 55);
      expect(map['requires_proof_image'], true);

      final firestoreMap = reminder.toFirestore();
      expect(firestoreMap['reward_stars'], 10);
      expect(firestoreMap['voice_duration_seconds'], 55);
      expect(firestoreMap['requires_proof_image'], true);

      final fromMapAgain = ReminderModel.fromJson(map);
      expect(fromMapAgain.voiceDurationSeconds, 55);
      expect(fromMapAgain.rewardStars, 10);
      expect(fromMapAgain.requiresProofImage, isTrue);
    });
  });

  group('CHALLENGER ADVERSARIAL SUITE 2: Extreme Viewport & Text Overflow Stress Tests', () {
    final ultraCompactWidths = [300.0, 320.0, 340.0, 360.0];

    const longVietnameseFamily =
        'Gia đình Hoàng tộc Nguyễn Phúc Chu Cửu Đỉnh Thăng Long Hà Nội';
    const longVietnameseAssignee =
        'Nguyễn Phúc Hoàng Thân Công Tằng Tôn Nữ Long Hoa';
    const longVietnameseTitle =
        'Uống thuốc huyết áp Amlodipine 5mg sau bữa ăn sáng và kiểm tra chỉ số đường huyết định kỳ lúc 9 giờ';
    const longVietnameseRejection =
        'Hình ảnh chụp góc bàn học còn thiếu ánh sáng, đề nghị bạn bật thêm đèn học và chụp rõ góc sách vở';
    const unbrokenLongString =
        'TRUONG_HOP_CHUOI_SIEU_DAI_KHONG_CO_KHOANG_TRANG_DE_THU_NGHIEM_OVERFLOW_FLEXIBLE_XAC_THUC_LAYOUT_ELLIPSIS_1234567890';

    for (final width in ultraCompactWidths) {
      testWidgets('2.1 Viewport ${width}px: TaskType.care with maximum content length & family badge', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final careReminder = ReminderModel(
          id: 'care_card_${width.toInt()}',
          familyId: 'fam_care',
          familyName: longVietnameseFamily,
          creatorId: 'user_grandpa',
          creatorName: 'Ông Nội',
          assignedTo: 'user_grandma',
          assignedToName: longVietnameseAssignee,
          title: longVietnameseTitle,
          date: '07/11/2026',
          time: '08:00',
          status: 'PENDING',
          taskType: TaskType.care,
          taskStatus: TaskStatus.pending,
          voiceNotePath: '/recordings/care_audio.m4a',
          voiceDurationSeconds: 45,
          voiceNoteDescription: 'Dặn dò của bác sĩ về liều dùng thuốc',
        );

        String? layoutError;
        final origOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = origOnError);
        FlutterError.onError = (details) {
          layoutError = details.toString();
          origOnError?.call(details);
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ReminderCard(
                    reminder: careReminder,
                    currentUserId: 'user_grandpa',
                    showFamilyBadge: true,
                    familyName: longVietnameseFamily,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(layoutError, isNull, reason: 'RenderFlex overflow occurred on width ${width}px for CARE card!');
        expect(tester.takeException(), isNull);
        expect(find.byType(ReminderCard), findsOneWidget);
        expect(find.text('👵 Chăm sóc Ông Bà'), findsOneWidget);
      });

      testWidgets('2.2 Viewport ${width}px: TaskType.favor with delegation count & submitted photo badge', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final favorSubmittedReminder = ReminderModel(
          id: 'favor_card_${width.toInt()}',
          familyId: 'fam_favor',
          familyName: longVietnameseFamily,
          creatorId: 'user_sister',
          creatorName: 'Chị Mai',
          assignedTo: 'user_brother',
          assignedToName: longVietnameseAssignee,
          title: 'Nhờ em trai qua bưu điện gửi kiện quà biếu gia đình dì Năm',
          date: '07/11/2026',
          time: '14:30',
          status: 'SUBMITTED',
          taskType: TaskType.favor,
          taskStatus: TaskStatus.submitted,
          delegationCount: 2,
          requiresProofImage: true,
          proofImageUrl: 'https://storage/proof_favor.jpg',
        );

        String? layoutError;
        final origOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = origOnError);
        FlutterError.onError = (details) {
          layoutError = details.toString();
          origOnError?.call(details);
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ReminderCard(
                    reminder: favorSubmittedReminder,
                    currentUserId: 'user_sister',
                    showFamilyBadge: true,
                    familyName: longVietnameseFamily,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(layoutError, isNull, reason: 'RenderFlex overflow occurred on width ${width}px for FAVOR SUBMITTED card!');
        expect(tester.takeException(), isNull);
        expect(find.byType(ReminderCard), findsOneWidget);
        expect(find.text('🤝 Lời nhờ (Chuyển tiếp)'), findsOneWidget);
        expect(find.text('📸 Chờ duyệt ảnh'), findsOneWidget);
      });

      testWidgets('2.3 Viewport ${width}px: TaskType.assign with high stars, rejection reason & unbroken text', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final assignRejectedReminder = ReminderModel(
          id: 'assign_card_${width.toInt()}',
          familyId: 'fam_assign',
          familyName: longVietnameseFamily,
          creatorId: 'user_mom',
          creatorName: 'Mẹ Lan',
          assignedTo: 'user_kid',
          assignedToName: unbrokenLongString,
          title: unbrokenLongString,
          date: '07/11/2026',
          time: '19:00',
          status: 'REJECTED',
          taskType: TaskType.assign,
          taskStatus: TaskStatus.rejected,
          rejectionReason: longVietnameseRejection,
          requiresProofImage: true,
          rewardStars: 9999,
        );

        String? layoutError;
        final origOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = origOnError);
        FlutterError.onError = (details) {
          layoutError = details.toString();
          origOnError?.call(details);
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ReminderCard(
                    reminder: assignRejectedReminder,
                    currentUserId: 'user_kid',
                    showFamilyBadge: true,
                    familyName: longVietnameseFamily,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(layoutError, isNull, reason: 'RenderFlex overflow occurred on width ${width}px for ASSIGN REJECTED card!');
        expect(tester.takeException(), isNull);
        expect(find.byType(ReminderCard), findsOneWidget);
        expect(find.text('⭐ Giao việc (+9999 sao)'), findsOneWidget);
        expect(find.text('❌ Cần làm lại'), findsOneWidget);
      });

      testWidgets('2.4 Viewport ${width}px: Open Task with Claim action buttons', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final openReminder = ReminderModel(
          id: 'open_card_${width.toInt()}',
          familyId: 'fam_open',
          familyName: longVietnameseFamily,
          creatorId: 'user_dad',
          creatorName: 'Bố Tuấn',
          assignedTo: '',
          assignedToName: '',
          title: 'Dọn dẹp vườn cây sau nhà vào chiều thứ Bảy',
          date: '07/11/2026',
          time: '16:00',
          status: 'OPEN',
          taskType: TaskType.assign,
          taskStatus: TaskStatus.pending,
          rewardStars: 5,
        );

        String? layoutError;
        final origOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = origOnError);
        FlutterError.onError = (details) {
          layoutError = details.toString();
          origOnError?.call(details);
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ReminderCard(
                    reminder: openReminder,
                    currentUserId: 'user_kid',
                    showFamilyBadge: true,
                    familyName: longVietnameseFamily,
                    onTap: () {},
                    onClaim: () {},
                    onClaimAndComplete: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(layoutError, isNull, reason: 'RenderFlex overflow occurred on width ${width}px for OPEN task card!');
        expect(tester.takeException(), isNull);
        expect(find.byType(ReminderCard), findsOneWidget);
      });

      testWidgets('2.5 Viewport ${width}px: Voice note with negative and zero durations', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final voiceNegReminder = ReminderModel(
          id: 'voice_neg_card_${width.toInt()}',
          familyId: 'fam_voice',
          creatorId: 'user_1',
          creatorName: 'Người tạo',
          assignedTo: 'user_2',
          assignedToName: 'Người nhận',
          title: 'Lời nhắn âm thanh đặc biệt',
          date: '07/11/2026',
          time: '10:00',
          taskType: TaskType.favor,
          taskStatus: TaskStatus.pending,
          voiceNotePath: '/recordings/sample.m4a',
          voiceDurationSeconds: -10, // Negative duration probe
          voiceNoteDescription: 'Ghi chú kiểm tra thời lượng âm',
        );

        String? layoutError;
        final origOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = origOnError);
        FlutterError.onError = (details) {
          layoutError = details.toString();
          origOnError?.call(details);
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ReminderCard(
                    reminder: voiceNegReminder,
                    currentUserId: 'user_1',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(layoutError, isNull, reason: 'RenderFlex overflow occurred on width ${width}px for negative voice note!');
        expect(tester.takeException(), isNull);
        expect(find.byType(ReminderCard), findsOneWidget);
      });

      testWidgets('2.6 Viewport ${width}px: Elderly Large Font Scale (1.5x) Stress', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final elderlyReminder = ReminderModel(
          id: 'elderly_scale_${width.toInt()}',
          familyId: 'fam_elderly',
          familyName: longVietnameseFamily,
          creatorId: 'user_grandpa',
          creatorName: 'Ông Nội',
          assignedTo: 'user_grandma',
          assignedToName: longVietnameseAssignee,
          title: longVietnameseTitle,
          date: '07/11/2026',
          time: '08:00',
          taskType: TaskType.care,
          taskStatus: TaskStatus.pending,
        );

        String? layoutError;
        final origOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = origOnError);
        FlutterError.onError = (details) {
          layoutError = details.toString();
          origOnError?.call(details);
        };

        // Simulating elderly user setting large system text scale (1.5x)
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Scaffold(
                body: ListView(
                  children: [
                    ReminderCard(
                      reminder: elderlyReminder,
                      currentUserId: 'user_grandpa',
                      showFamilyBadge: true,
                      familyName: longVietnameseFamily,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(layoutError, isNull, reason: 'RenderFlex overflow occurred on width ${width}px under 1.5x text scale!');
        expect(tester.takeException(), isNull);
        expect(find.byType(ReminderCard), findsOneWidget);
      });
    }
  });
}

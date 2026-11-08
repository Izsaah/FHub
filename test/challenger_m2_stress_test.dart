import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/screens/create_reminder_screen.dart';
import 'package:fhub/Vinh/services/firebase_reminder_repository.dart';
import 'package:fhub/Vinh/services/in_memory_reminder_repository.dart';
import 'package:fhub/Vinh/services/reminder_exceptions.dart';
import 'package:fhub/Vinh/widgets/reminder_card.dart';

// Test oracle for quiet hours calculation
class QuietHoursOracle {
  static DateTime calculateEffectiveAlarmTime({
    required DateTime scheduledTime,
    required String taskType,
    String title = '',
  }) {
    final isCare = taskType == 'CARE' ||
        taskType == 'TaskType.care' ||
        title.toLowerCase().contains('thuốc') ||
        title.toLowerCase().contains('medicine');

    if (isCare) {
      return scheduledTime;
    }

    final h = scheduledTime.hour;
    if (h >= 22) {
      final nextDay = scheduledTime.add(const Duration(days: 1));
      return DateTime(nextDay.year, nextDay.month, nextDay.day, 7, 0, 0);
    } else if (h < 6) {
      return DateTime(scheduledTime.year, scheduledTime.month, scheduledTime.day, 7, 0, 0);
    }

    return scheduledTime;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CHALLENGER STRESS 1: Concurrency & Re-entrancy Invariant Stress Tests', () {
    late InMemoryReminderRepository repo;

    setUp(() {
      repo = InMemoryReminderRepository(initialReminders: [
        ReminderModel(
          id: 'task_race_1',
          familyId: 'fam_stress',
          creatorId: 'parent_1',
          assignedTo: 'child_1',
          assignedToName: 'Bin',
          title: 'Rửa bát đĩa ăn tối',
          date: '06/11/2026',
          time: '20:00',
          status: ReminderStatus.pending,
          taskType: TaskType.assign,
          taskStatus: TaskStatus.pending,
          requiresProofImage: true,
          rewardStars: 3,
        ),
      ]);
    });

    test('1.1 Concurrency Race: Rapid interleaved submit and reject operations maintain strict proof wipe invariants', () async {
      // 50 rapid alternating and overlapping calls
      for (int i = 0; i < 50; i++) {
        final proofUrl = 'https://storage/proofs/attempt_$i.jpg';
        final reason = 'Lần nộp $i chưa đạt tiêu chuẩn, hãy chụp lại';

        // Concurrent execution of submit and reject
        await Future.wait([
          repo.submitTaskWithProof(taskId: 'task_race_1', proofImageUrl: proofUrl),
          repo.rejectTaskSubmission(taskId: 'task_race_1', reason: reason),
        ]);

        final tasks = await repo.getReminders(familyId: 'fam_stress');
        final current = tasks.firstWhere((t) => t.id == 'task_race_1');

        // State machine invariant verification:
        if (current.taskStatus == TaskStatus.pending) {
          // If in PENDING / REJECTED state, proof image MUST BE completely wiped (null)
          expect(
            current.proofImageUrl,
            isNull,
            reason: 'Invariant Violation: Proof image leaked into PENDING state after rejection in cycle $i!',
          );
          expect(current.rejectionReason, isNotNull);
        } else if (current.taskStatus == TaskStatus.submitted) {
          // If in SUBMITTED state, proof image MUST BE present and rejection reason cleared
          expect(
            current.proofImageUrl,
            isNotNull,
            reason: 'Invariant Violation: SUBMITTED task has null proofImageUrl in cycle $i!',
          );
          expect(
            current.rejectionReason,
            isNull,
            reason: 'Invariant Violation: Rejection reason was not cleared on resubmission in cycle $i!',
          );
        }
      }
    });

    test('1.2 High-Volume Simultaneous Burst: 20 simultaneous submissions and rejections do not corrupt repository state', () async {
      final random = Random(42);
      final futures = <Future<void>>[];

      for (int i = 0; i < 20; i++) {
        if (random.nextBool()) {
          futures.add(repo.submitTaskWithProof(
            taskId: 'task_race_1',
            proofImageUrl: 'https://cdn/burst_proof_$i.png',
          ));
        } else {
          futures.add(repo.rejectTaskSubmission(
            taskId: 'task_race_1',
            reason: 'Burst reject reason #$i',
          ));
        }
      }

      await Future.wait(futures);

      final tasks = await repo.getReminders(familyId: 'fam_stress');
      final finalTask = tasks.firstWhere((t) => t.id == 'task_race_1');

      // Regardless of which completed last, the invariant must hold:
      if (finalTask.taskStatus == TaskStatus.pending) {
        expect(finalTask.proofImageUrl, isNull);
        expect(finalTask.rejectionReason, isNotNull);
      } else {
        expect(finalTask.taskStatus, TaskStatus.submitted);
        expect(finalTask.proofImageUrl, isNotNull);
      }
    });

    test('1.3 Error Boundary: Submitting or rejecting non-existent task throws ReminderNotFoundException', () async {
      expect(
        () => repo.submitTaskWithProof(taskId: 'non_existent_id', proofImageUrl: 'http://img.jpg'),
        throwsA(isA<ReminderNotFoundException>()),
      );

      expect(
        () => repo.rejectTaskSubmission(taskId: 'non_existent_id', reason: 'Không có việc'),
        throwsA(isA<ReminderNotFoundException>()),
      );
    });

    test('1.4 FirebaseReminderRepository Fallback Invariant: submitTaskWithProof and rejectTaskSubmission correctly update fallback & mockStore', () async {
      final fbRepo = FirebaseReminderRepository(
        firestore: null,
        fallbackRepository: repo,
      );

      await fbRepo.submitTaskWithProof(
        taskId: 'task_race_1',
        proofImageUrl: 'https://cdn/fb_proof.png',
      );

      var tasks = await fbRepo.getReminders(familyId: 'fam_stress');
      var t = tasks.firstWhere((item) => item.id == 'task_race_1');
      expect(t.taskStatus, TaskStatus.submitted);
      expect(t.proofImageUrl, 'https://cdn/fb_proof.png');

      await fbRepo.rejectTaskSubmission(
        taskId: 'task_race_1',
        reason: 'FB reject reason',
      );

      tasks = await fbRepo.getReminders(familyId: 'fam_stress');
      t = tasks.firstWhere((item) => item.id == 'task_race_1');
      expect(t.taskStatus, TaskStatus.pending);
      expect(t.proofImageUrl, isNull);
      expect(t.rejectionReason, 'FB reject reason');
    });
  });

  group('CHALLENGER STRESS 2: Serialization & Deserialization Invariant Fuzzing', () {
    final now = DateTime(2026, 11, 6, 14, 30);

    test('2.1 Round-trip Fuzzing: toMap/fromMap, toJson/fromJson, toFirestore/fromFirestore preserve all fields across all TaskType & TaskStatus variants', () {
      for (final type in TaskType.values) {
        for (final status in TaskStatus.values) {
          final original = ReminderModel(
            id: 'rem_${type.name}_${status.name}',
            familyId: 'fam_roundtrip',
            familyName: 'Gia đình Hạnh Phúc',
            creatorId: 'user_parent',
            creatorName: 'Bố Tuấn',
            assignedTo: 'user_kid',
            assignedToName: 'Bé Linh',
            title: 'Công việc thử nghiệm invariant: ${type.displayName}',
            date: '06/11/2026',
            time: '18:30',
            status: status.dbValue,
            repeatRule: 'DAILY',
            requiresProofImage: type == TaskType.assign,
            proofImageUrl: status == TaskStatus.submitted ? 'https://proof.img/pic.jpg' : null,
            rewardStars: type == TaskType.assign ? 3 : 0,
            voiceNotePath: '/path/to/voice.m4a',
            voiceDurationSeconds: 12,
            voiceNoteDescription: 'Ghi chú giọng nói',
            completedAt: status == TaskStatus.completed ? now : null,
            createdAt: now,
            taskType: type,
            taskStatus: status,
            rejectionReason: status == TaskStatus.rejected ? 'Ảnh mờ' : null,
            delegationCount: type == TaskType.favor ? 1 : 0,
            delegatedFromUserId: type == TaskType.favor ? 'user_gp' : null,
            originalTaskId: type == TaskType.favor ? 'orig_123' : null,
            creatorHierarchyRole: 'PARENT',
            targetHierarchyRole: 'CHILD',
          );

          // 1. toMap / fromMap round-trip
          final map = original.toMap();
          final fromMap = ReminderModel.fromMap(map);
          expect(fromMap.id, original.id);
          expect(fromMap.taskType, original.taskType);
          expect(fromMap.taskStatus, original.taskStatus);
          expect(fromMap.proofImageUrl, original.proofImageUrl);
          expect(fromMap.rejectionReason, original.rejectionReason);
          expect(fromMap.delegationCount, original.delegationCount);
          expect(fromMap.delegatedFromUserId, original.delegatedFromUserId);
          expect(fromMap.originalTaskId, original.originalTaskId);
          expect(fromMap.creatorHierarchyRole, original.creatorHierarchyRole);
          expect(fromMap.targetHierarchyRole, original.targetHierarchyRole);
          expect(fromMap.rewardStars, original.rewardStars);
          expect(fromMap.requiresProofImage, original.requiresProofImage);

          // 2. toJson / fromJson round-trip
          final json = original.toJson();
          final fromJson = ReminderModel.fromJson(json);
          expect(fromJson.id, original.id);
          expect(fromJson.taskType, original.taskType);
          expect(fromJson.taskStatus, original.taskStatus);
          expect(fromJson.proofImageUrl, original.proofImageUrl);
          expect(fromJson.rejectionReason, original.rejectionReason);
          expect(fromJson.delegationCount, original.delegationCount);

          // 3. toFirestore / fromJson (simulating Firestore raw data with Timestamp)
          final firestoreData = original.toFirestore();
          firestoreData['id'] = original.id;
          final fromFirestore = ReminderModel.fromJson(firestoreData);
          expect(fromFirestore.taskType, original.taskType);
          expect(fromFirestore.taskStatus, original.taskStatus);
          expect(fromFirestore.createdAt?.year, original.createdAt?.year);

          // 4. toMap / fromJson round-trip
          final mapData = original.toMap();
          mapData['id'] = original.id;
          final fromMapObj = ReminderModel.fromJson(mapData);
          expect(fromMapObj.taskType, original.taskType);
          expect(fromMapObj.taskStatus, original.taskStatus);
          expect(fromMapObj.delegationCount, original.delegationCount);
        }
      }
    });

    test('2.2 Legacy Data Compatibility: Missing fields safely default to standard values without null reference exceptions', () {
      // Legacy document with ONLY basic fields from older versions
      final legacyJson = {
        'id': 'legacy_rem_001',
        'family_id': 'fam_legacy',
        'creator_id': 'user_old_1',
        'assigned_to': 'user_old_2',
        'title': 'Việc quét sân ngày xưa',
        'date': '2026-11-06', // Old Postgres format
        'time': '08:00:00',
        'status': 'PENDING',
        // Notice missing: taskType, taskStatus, delegationCount, proofImageUrl, rejectionReason
      };

      final parsed = ReminderModel.fromJson(legacyJson);

      // Invariant checks:
      expect(parsed.taskType, TaskType.assign, reason: 'Missing taskType must safely default to TaskType.assign');
      expect(parsed.taskStatus, TaskStatus.pending, reason: 'Missing taskStatus must safely default to TaskStatus.pending');
      expect(parsed.delegationCount, 0, reason: 'Missing delegationCount must default to 0');
      expect(parsed.proofImageUrl, isNull);
      expect(parsed.rejectionReason, isNull);
      expect(parsed.requiresProofImage, isFalse);
      expect(parsed.rewardStars, 0);
      expect(parsed.date, '06/11/2026', reason: 'Postgres yyyy-MM-dd must normalize to dd/MM/yyyy');
      expect(parsed.time, '08:00', reason: 'Time with seconds must normalize to HH:mm');
    });

    test('2.3 Type Coercion Fuzzing: String numbers, mixed case enums, and null fallbacks parse cleanly', () {
      final fuzzJson = {
        'id': 'fuzz_001',
        'familyId': 'fam_fuzz',
        'creatorId': 'u1',
        'assignedTo': 'u2',
        'title': 'Fuzz task',
        'date': '06/11/2026',
        'time': '10:00',
        'status': 'submitted',
        'taskType': 'FaVoR', // Mixed case
        'taskStatus': 'SuBmItTeD', // Mixed case
        'rewardStars': '5', // String instead of int
        'delegationCount': '2', // String instead of int
        'voiceDurationSeconds': '45', // String instead of int
        'requiresProofImage': 'true', // String boolean
      };

      final parsed = ReminderModel.fromJson(fuzzJson);
      expect(parsed.taskType, TaskType.favor);
      expect(parsed.taskStatus, TaskStatus.submitted);
      expect(parsed.rewardStars, 5);
      expect(parsed.delegationCount, 2);
      expect(parsed.voiceDurationSeconds, 45);
    });

    test('2.4 Corrupt and Unknown TaskType / TaskStatus values fallback gracefully without crash', () {
      expect(TaskType.fromValue('UNKNOWN_GARBAGE'), TaskType.assign);
      expect(TaskType.fromValue(null), TaskType.assign);
      expect(TaskType.fromValue(''), TaskType.assign);
      expect(TaskType.fromValue(12345), TaskType.assign);

      expect(TaskStatus.fromValue('UNKNOWN_STATE'), TaskStatus.pending);
      expect(TaskStatus.fromValue(null), TaskStatus.pending);
      expect(TaskStatus.fromValue(''), TaskStatus.pending);
      expect(TaskStatus.fromValue('APPROVED'), TaskStatus.completed);
    });
  });

  group('CHALLENGER STRESS 3: Quiet-Hours Boundary Invariant Stress Tests', () {
    test('3.1 Exact Second Boundary Fuzzing for ASSIGN chores vs CARE elderly tasks', () {
      // 21:59:59 (Outside quiet hours - Not deferred)
      final t21_59 = DateTime(2026, 11, 6, 21, 59, 59);
      expect(QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t21_59, taskType: 'ASSIGN'), equals(t21_59));
      expect(QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t21_59, taskType: 'CARE'), equals(t21_59));

      // 22:00:00 (Start of quiet hours - ASSIGN deferred to 07:00 next day, CARE strictly immune)
      final t22_00 = DateTime(2026, 11, 6, 22, 0, 0);
      final effAssign22 = QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t22_00, taskType: 'ASSIGN');
      expect(effAssign22.day, 7);
      expect(effAssign22.hour, 7);
      expect(effAssign22.minute, 0);
      expect(QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t22_00, taskType: 'CARE'), equals(t22_00));

      // 23:59:59 (Before midnight - ASSIGN deferred to 07:00 next day, CARE immune)
      final t23_59 = DateTime(2026, 11, 6, 23, 59, 59);
      final effAssign23 = QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t23_59, taskType: 'ASSIGN');
      expect(effAssign23.day, 7);
      expect(effAssign23.hour, 7);
      expect(QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t23_59, taskType: 'CARE'), equals(t23_59));

      // 00:00:00 (Midnight - ASSIGN deferred to 07:00 same day, CARE immune)
      final t00_00 = DateTime(2026, 11, 7, 0, 0, 0);
      final effAssign00 = QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t00_00, taskType: 'ASSIGN');
      expect(effAssign00.day, 7);
      expect(effAssign00.hour, 7);
      expect(QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t00_00, taskType: 'CARE'), equals(t00_00));

      // 05:59:59 (Last second of quiet hours - ASSIGN deferred to 07:00 same day, CARE immune)
      final t05_59 = DateTime(2026, 11, 7, 5, 59, 59);
      final effAssign05 = QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t05_59, taskType: 'ASSIGN');
      expect(effAssign05.day, 7);
      expect(effAssign05.hour, 7);
      expect(QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t05_59, taskType: 'CARE'), equals(t05_59));

      // 06:00:00 (End of quiet hours - ASSIGN and CARE both trigger immediately without deferral)
      final t06_00 = DateTime(2026, 11, 7, 6, 0, 0);
      expect(QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t06_00, taskType: 'ASSIGN'), equals(t06_00));
      expect(QuietHoursOracle.calculateEffectiveAlarmTime(scheduledTime: t06_00, taskType: 'CARE'), equals(t06_00));
    });

    test('3.2 Medication keyword immunity check on ReminderModel', () {
      final chore = ReminderModel(
        id: 'c1',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u2',
        assignedToName: 'Thành viên',
        title: 'Lau nhà',
        date: '06/11/2026',
        time: '23:00',
        taskType: TaskType.assign,
      );
      expect(chore.isExemptFromQuietHours, isFalse);

      final medTask = ReminderModel(
        id: 'c2',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u2',
        assignedToName: 'Ông Nội',
        title: 'Uống thuốc huyết áp buổi tối',
        date: '06/11/2026',
        time: '23:00',
        taskType: TaskType.assign, // Even if created as assign, keyword "thuốc" grants immunity
      );
      expect(medTask.isExemptFromQuietHours, isTrue);

      final careTask = ReminderModel(
        id: 'c3',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u2',
        assignedToName: 'Ông Nội',
        title: 'Đo nhịp tim cho Ông',
        date: '06/11/2026',
        time: '23:00',
        taskType: TaskType.care,
      );
      expect(careTask.isExemptFromQuietHours, isTrue);
    });
  });

  group('CHALLENGER STRESS 4: Viewport Stress Testing & Long Vietnamese Text Resiliency', () {
    const extremeViewports = [
      Size(320, 640), // Ultra-narrow compact phone
      Size(360, 640), // Standard narrow Android
      Size(412, 915), // Modern Android flagship
      Size(800, 1280), // Tablet / Desktop
    ];

    const longVietnameseTitle =
        'Kính mời Ông Bà uống thuốc điều trị huyết áp Amlodipine 5mg và đo lại chỉ số huyết áp vào buổi sáng trước khi ăn điểm tâm cùng cả gia đình';
    const longVietnameseFamily =
        'Gia đình Đại Gia Đình Đa Thế Hệ Họ Nguyễn Văn Hạnh Phúc Toàn Diện';
    const longVietnameseAssignee =
        'Nguyễn Hoàng Minh Khôi (Cháu đích tôn trưởng nam)';
    const longRejectionReason =
        'Ảnh chụp bát đĩa bị nhòe và thiếu ánh sáng, không nhìn thấy rõ góc chạn bát phía trên bên phải đã được lau dọn sạch sẽ hay chưa, con vui lòng chụp lại nhé!';

    for (final size in extremeViewports) {
      testWidgets('4.1 Viewport ${size.width.toInt()}px x ${size.height.toInt()}px: ReminderCard renders without RenderFlex overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Test CARE task with extreme Vietnamese title and badges
        final careReminder = ReminderModel(
          id: 'card_care_extreme',
          familyId: 'fam_extreme',
          familyName: longVietnameseFamily,
          creatorId: 'user_parent',
          creatorName: 'Bố Tuấn',
          assignedTo: 'user_gp',
          assignedToName: 'Ông Nội',
          title: longVietnameseTitle,
          date: '06/11/2026',
          time: '08:00',
          status: ReminderStatus.pending,
          taskType: TaskType.care,
          taskStatus: TaskStatus.pending,
        );

        String? overflowDetails;
        final originalOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = originalOnError);
        FlutterError.onError = (details) {
          overflowDetails = details.toString();
          originalOnError?.call(details);
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ReminderCard(
                    reminder: careReminder,
                    currentUserId: 'user_parent',
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

        final err = tester.takeException();
        if (overflowDetails != null) {
          debugPrint('>>> OVERFLOW DETAILS:\n$overflowDetails');
        }
        expect(err, isNull, reason: 'RenderFlex overflow occurred on viewport ${size.width}px for CARE card!');
        expect(find.byType(ReminderCard), findsOneWidget);

        // Test ASSIGN task with rejection reason and long assignee
        final assignRejectedReminder = ReminderModel(
          id: 'card_assign_rejected',
          familyId: 'fam_extreme',
          familyName: longVietnameseFamily,
          creatorId: 'user_parent',
          assignedTo: 'user_kid',
          assignedToName: longVietnameseAssignee,
          title: 'Rửa bát đĩa ăn tối và lau dọn nhà bếp sạch sẽ bóng loáng',
          date: '06/11/2026',
          time: '20:00',
          status: 'REJECTED',
          taskType: TaskType.assign,
          taskStatus: TaskStatus.rejected,
          rejectionReason: longRejectionReason,
          requiresProofImage: true,
          rewardStars: 5,
        );

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

        expect(tester.takeException(), isNull, reason: 'RenderFlex overflow occurred on viewport ${size.width}px for REJECTED ASSIGN card!');

        // Test FAVOR task with delegation count
        final favorReminder = ReminderModel(
          id: 'card_favor_delegated',
          familyId: 'fam_extreme',
          creatorId: 'user_gp',
          assignedTo: 'user_kid',
          assignedToName: longVietnameseAssignee,
          title: 'Nhờ con đi gửi bưu phẩm tại bưu điện đầu ngõ giùm bà',
          date: '06/11/2026',
          time: '15:00',
          status: 'PENDING',
          taskType: TaskType.favor,
          taskStatus: TaskStatus.pending,
          delegationCount: 1,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ReminderCard(
                    reminder: favorReminder,
                    currentUserId: 'user_kid',
                    showFamilyBadge: false,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'RenderFlex overflow occurred on viewport ${size.width}px for FAVOR card!');
      });

      testWidgets('4.2 Viewport ${size.width.toInt()}px x ${size.height.toInt()}px: CreateReminderScreen renders & switches task types without RenderFlex overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final repo = InMemoryReminderRepository(initialReminders: []);
        const members = [
          FamilyMember(id: 'u_dad', name: 'Bố Tuấn', role: 'Parent', familyId: 'f1'),
          FamilyMember(id: 'u_mom', name: 'Mẹ Lan', role: 'Parent', familyId: 'f1'),
          FamilyMember(id: 'u_gp', name: 'Ông Nội', role: 'Grandparent', familyId: 'f1'),
          FamilyMember(id: 'u_kid', name: 'Bé Minh', role: 'Child', familyId: 'f1'),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: CreateReminderScreen(
              familyId: 'f1',
              familyName: longVietnameseFamily,
              currentUserId: 'u_dad',
              currentUserName: 'Bố Tuấn',
              familyMembers: members,
              repository: repo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'RenderFlex overflow on CreateReminderScreen at initial load on ${size.width}px!');

        // Switch to FAVOR
        final favorSegment = find.text('Nhờ vả');
        if (favorSegment.evaluate().isNotEmpty) {
          await tester.tap(favorSegment.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'RenderFlex overflow after switching to FAVOR on ${size.width}px!');
        }

        // Switch to CARE
        final careSegment = find.text('Chăm sóc');
        if (careSegment.evaluate().isNotEmpty) {
          await tester.tap(careSegment.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'RenderFlex overflow after switching to CARE on ${size.width}px!');
        }

        // Switch back to ASSIGN
        final assignSegment = find.text('Giao việc');
        if (assignSegment.evaluate().isNotEmpty) {
          await tester.tap(assignSegment.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'RenderFlex overflow after switching back to ASSIGN on ${size.width}px!');
        }
      });
    }
  });
}

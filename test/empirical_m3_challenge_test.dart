import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Vinh/services/star_economy_service.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EMPIRICAL CHALLENGE 1: High-Concurrency Double-Approval Protection (50 Concurrent Calls)', () {
    late StarEconomyService service;

    setUp(() {
      service = StarEconomyService.inMemory();
      service.resetMockData();
    });

    test('1.1 Concurrency Stress: 50 concurrent approvals on exact same taskId -> exactly 1 succeeds, 49 fail with DoubleApprovalException', () async {
      const familyId = 'fam_stress_1';
      const childId = 'child_stress_1';
      const taskId = 'chore_stress_50';
      const rewardStars = 10;
      const initialBalance = 100;

      service.seedMemberBalance(familyId, childId, initialBalance);
      service.seedTask(taskId, {
        'familyId': familyId,
        'assignedTo': childId,
        'status': 'SUBMITTED',
        'taskStatus': 'SUBMITTED',
        'rewardStars': rewardStars,
      });

      // Launch 50 concurrent approval calls simultaneously
      final futures = List.generate(50, (index) {
        return service
            .approveTaskWithDoubleAwardProtection(
              taskId: taskId,
              reviewerId: 'guardian_$index',
              reviewerName: 'Guardian $index',
              familyId: familyId,
              childId: childId,
              stars: rewardStars,
            )
            .then((_) => 'SUCCESS')
            .catchError((e) => 'EXCEPTION: ${e.runtimeType} -> $e');
      });

      final results = await Future.wait(futures);

      final successes = results.where((r) => r == 'SUCCESS').toList();
      final exceptions = results.where((r) => r.startsWith('EXCEPTION:')).toList();

      // Invariant 1: Exactly 1 call succeeds
      expect(successes.length, 1, reason: 'Expected exactly 1 successful approval call out of 50 concurrent attempts');

      // Invariant 2: Exactly 49 calls fail
      expect(exceptions.length, 49, reason: 'Expected exactly 49 failed approval calls out of 50 concurrent attempts');

      // Invariant 3: All 49 failures must be DoubleApprovalException
      for (final err in exceptions) {
        expect(
          err,
          contains('DoubleApprovalException'),
          reason: 'Expected DoubleApprovalException but received: $err',
        );
      }

      // Invariant 4: Balance incremented by exactly rewardStars once (100 + 10 = 110)
      final finalBalance = service.getBalance(familyId, childId);
      expect(finalBalance, initialBalance + rewardStars,
          reason: 'Balance must be incremented exactly once. Expected ${initialBalance + rewardStars}, got $finalBalance');

      // Invariant 5: Star ledger has exactly 1 entry for this reward
      final ledgerKey = 'reward_$taskId';
      expect(service.starLedger.containsKey(ledgerKey), isTrue);
      expect(service.starLedger[ledgerKey]!['amount'], rewardStars);
      expect(service.starLedger[ledgerKey]!['type'], 'TASK_REWARD');
      expect(service.starLedger[ledgerKey]!['userId'], childId);

      // Invariant 6: Reminder state updated to APPROVED and COMPLETED
      final task = service.reminders[taskId];
      expect(task, isNotNull);
      expect(task!['status'], 'APPROVED');
      expect(task['taskStatus'], 'COMPLETED');
      expect(task['isCompleted'], isTrue);
    });

    test('1.2 Concurrency Stress: 50 concurrent approvals dispatched across asynchronous microtasks', () async {
      const familyId = 'fam_stress_2';
      const childId = 'child_stress_2';
      const taskId = 'chore_stress_microtask';
      const rewardStars = 15;
      const initialBalance = 50;

      service.seedMemberBalance(familyId, childId, initialBalance);
      service.seedTask(taskId, {
        'familyId': familyId,
        'assignedTo': childId,
        'status': 'SUBMITTED',
        'taskStatus': 'SUBMITTED',
        'rewardStars': rewardStars,
      });

      // Schedule calls on the Dart event queue via Future(() => ...)
      final futures = List.generate(50, (index) {
        return Future(() => service.approveTaskWithDoubleAwardProtection(
              taskId: taskId,
              reviewerId: 'guardian_$index',
              reviewerName: 'Guardian $index',
              familyId: familyId,
              childId: childId,
              stars: rewardStars,
            ))
            .then((_) => 'SUCCESS')
            .catchError((e) => 'EXCEPTION: ${e.runtimeType} -> $e');
      });

      final results = await Future.wait(futures);

      final successes = results.where((r) => r == 'SUCCESS').toList();
      final exceptions = results.where((r) => r.startsWith('EXCEPTION:')).toList();

      expect(successes.length, 1);
      expect(exceptions.length, 49);
      for (final err in exceptions) {
        expect(err, contains('DoubleApprovalException'));
      }
      expect(service.getBalance(familyId, childId), initialBalance + rewardStars);
    });

    test('1.3 Multi-task Parallel Concurrency: 5 tasks concurrently hit with 10 approvals each (50 total calls)', () async {
      const familyId = 'fam_stress_3';
      const childId = 'child_stress_3';
      const initialBalance = 0;
      service.seedMemberBalance(familyId, childId, initialBalance);

      final taskIds = List.generate(5, (t) => 'parallel_task_$t');
      for (int t = 0; t < 5; t++) {
        service.seedTask(taskIds[t], {
          'familyId': familyId,
          'assignedTo': childId,
          'status': 'SUBMITTED',
          'rewardStars': (t + 1) * 10, // 10, 20, 30, 40, 50 stars
        });
      }

      // 50 total calls: 10 per task
      final allFutures = <Future<String>>[];
      for (int t = 0; t < 5; t++) {
        final tId = taskIds[t];
        final stars = (t + 1) * 10;
        for (int i = 0; i < 10; i++) {
          allFutures.add(
            service
                .approveTaskWithDoubleAwardProtection(
                  taskId: tId,
                  reviewerId: 'guardian_${t}_$i',
                  reviewerName: 'Guardian ${t}_$i',
                  familyId: familyId,
                  childId: childId,
                  stars: stars,
                )
                .then((_) => 'SUCCESS:$tId')
                .catchError((e) => 'ERR:$tId:${e.runtimeType}'),
          );
        }
      }

      final results = await Future.wait(allFutures);

      // Verify each task succeeded exactly once
      for (int t = 0; t < 5; t++) {
        final tId = taskIds[t];
        final successCount = results.where((r) => r == 'SUCCESS:$tId').length;
        final errorCount = results.where((r) => r.startsWith('ERR:$tId:')).length;

        expect(successCount, 1, reason: 'Task $tId must have exactly 1 success');
        expect(errorCount, 9, reason: 'Task $tId must have exactly 9 failures');
      }

      // Total expected stars = 10 + 20 + 30 + 40 + 50 = 150
      expect(service.getBalance(familyId, childId), 150);
      expect(service.starLedger.length, 5);
    });
  });

  group('EMPIRICAL CHALLENGE 2: Wishlist Double-Spending & Star Balance Invariant Stress Tests', () {
    late StarEconomyService service;

    setUp(() {
      service = StarEconomyService.inMemory();
      service.resetMockData();
    });

    test('2.1 Dispatch Invariant: Initial balance = 20 stars, 2 concurrent claims of 15 stars each -> 1 success, 1 InsufficientStarsException, final balance strictly 5', () async {
      const familyId = 'fam_wish_1';
      const childId = 'child_wish_1';
      service.seedMemberBalance(familyId, childId, 20);

      final results = await Future.wait([
        service
            .claimWishlistItem(
              claimId: 'claim_alpha',
              familyId: familyId,
              userId: childId,
              cost: 15,
              itemName: 'Món quà Alpha',
            )
            .then((_) => 'SUCCESS:alpha')
            .catchError((e) => 'EXCEPTION:alpha:${e.runtimeType} -> $e'),
        service
            .claimWishlistItem(
              claimId: 'claim_beta',
              familyId: familyId,
              userId: childId,
              cost: 15,
              itemName: 'Món quà Beta',
            )
            .then((_) => 'SUCCESS:beta')
            .catchError((e) => 'EXCEPTION:beta:${e.runtimeType} -> $e'),
      ]);

      final successCount = results.where((r) => r.startsWith('SUCCESS:')).length;
      final errorCount = results.where((r) => r.startsWith('EXCEPTION:')).length;

      expect(successCount, 1, reason: 'Expected exactly 1 claim to succeed');
      expect(errorCount, 1, reason: 'Expected exactly 1 claim to fail');

      // The failed claim MUST throw InsufficientStarsException
      final failedResult = results.firstWhere((r) => r.startsWith('EXCEPTION:'));
      expect(failedResult, contains('InsufficientStarsException'));

      // Final balance MUST BE strictly 5 stars (never negative)
      final finalBalance = service.getBalance(familyId, childId);
      expect(finalBalance, 5, reason: 'Balance must be strictly 5 stars, never negative');

      // Exactly 1 ledger claim document created
      expect(service.starLedger.length, 1);
      final singleEntry = service.starLedger.values.first;
      expect(singleEntry['amount'], -15);
      expect(singleEntry['type'], 'WISHLIST_CLAIM');
    });

    test('2.2 Overdraft Resistance: 10 concurrent claims of 5 stars with balance 20 -> exactly 4 succeed, 6 fail, final balance is 0', () async {
      const familyId = 'fam_wish_2';
      const childId = 'child_wish_2';
      service.seedMemberBalance(familyId, childId, 20);

      final futures = List.generate(10, (i) {
        return service
            .claimWishlistItem(
              claimId: 'claim_burst_$i',
              familyId: familyId,
              userId: childId,
              cost: 5,
              itemName: 'Món quà $i',
            )
            .then((_) => 'SUCCESS')
            .catchError((e) => 'ERR:${e.runtimeType}');
      });

      final results = await Future.wait(futures);

      final successCount = results.where((r) => r == 'SUCCESS').length;
      final errorCount = results.where((r) => r.startsWith('ERR:')).length;

      expect(successCount, 4, reason: '20 stars / 5 stars per claim = exactly 4 claims allowed');
      expect(errorCount, 6, reason: 'Remaining 6 claims must be rejected');

      for (final err in results.where((r) => r.startsWith('ERR:'))) {
        expect(err, 'ERR:InsufficientStarsException');
      }

      expect(service.getBalance(familyId, childId), 0);
      expect(service.starLedger.length, 4);
    });

    test('2.3 Micro-claim Race: 50 concurrent claims of 1 star with balance 10 -> exactly 10 succeed, 40 fail, balance strictly 0', () async {
      const familyId = 'fam_wish_3';
      const childId = 'child_wish_3';
      service.seedMemberBalance(familyId, childId, 10);

      final futures = List.generate(50, (i) {
        return service
            .claimWishlistItem(
              claimId: 'claim_micro_$i',
              familyId: familyId,
              userId: childId,
              cost: 1,
              itemName: 'Micro Item $i',
            )
            .then((_) => 'SUCCESS')
            .catchError((e) => 'ERR:${e.runtimeType}');
      });

      final results = await Future.wait(futures);

      final successCount = results.where((r) => r == 'SUCCESS').length;
      final errorCount = results.where((r) => r.startsWith('ERR:')).length;

      expect(successCount, 10);
      expect(errorCount, 40);
      expect(service.getBalance(familyId, childId), 0);
    });

    test('2.4 Zero balance claim: claiming 1 star with 0 initial balance throws InsufficientStarsException', () async {
      const familyId = 'fam_wish_4';
      const childId = 'child_wish_4';
      service.seedMemberBalance(familyId, childId, 0);

      expect(
        () => service.claimWishlistItem(
          claimId: 'claim_zero_bal',
          familyId: familyId,
          userId: childId,
          cost: 1,
          itemName: 'Item',
        ),
        throwsA(isA<InsufficientStarsException>()),
      );

      expect(service.getBalance(familyId, childId), 0);
      expect(service.starLedger.isEmpty, isTrue);
    });
  });

  group('EMPIRICAL CHALLENGE 3: Refund Idempotency & Financial Audit Ledger Integrity', () {
    late StarEconomyService service;

    setUp(() {
      service = StarEconomyService.inMemory();
      service.resetMockData();
    });

    test('3.1 Dispatch Invariant: Refund 15 stars -> balance becomes 20, duplicate refund attempt throws StateError', () async {
      const familyId = 'fam_ref_1';
      const childId = 'child_ref_1';
      const claimId = 'claim_for_refund';

      // 1. Initial 20 stars
      service.seedMemberBalance(familyId, childId, 20);

      // 2. Claim 15 stars -> leaves 5 stars
      await service.claimWishlistItem(
        claimId: claimId,
        familyId: familyId,
        userId: childId,
        cost: 15,
        itemName: 'Xe đạp mini',
      );
      expect(service.getBalance(familyId, childId), 5);

      // 3. Guardian rejects physical gift -> refund 15 stars
      await service.refundWishlistClaim(
        claimId: claimId,
        familyId: familyId,
        userId: childId,
        refundStars: 15,
        reason: 'Hết hàng tại cửa hàng',
      );

      // Verify balance restored to 20
      expect(service.getBalance(familyId, childId), 20);

      // Verify ledger refund doc exists
      final ledgerKey = 'refund_$claimId';
      expect(service.starLedger.containsKey(ledgerKey), isTrue);
      expect(service.starLedger[ledgerKey]!['amount'], 15);
      expect(service.starLedger[ledgerKey]!['type'], 'CLAIM_REFUND');
      expect(service.starLedger[ledgerKey]!['reason'], 'Hết hàng tại cửa hàng');

      // 4. Duplicate refund attempt for same claimId must throw StateError
      expect(
        () => service.refundWishlistClaim(
          claimId: claimId,
          familyId: familyId,
          userId: childId,
          refundStars: 15,
        ),
        throwsStateError,
      );

      // Balance remains strictly 20 (no double credit)
      expect(service.getBalance(familyId, childId), 20);
    });

    test('3.2 Concurrency Stress: 20 concurrent duplicate refund calls on same claimId -> exactly 1 succeeds, 19 throw StateError, balance increases by 15 once', () async {
      const familyId = 'fam_ref_2';
      const childId = 'child_ref_2';
      const claimId = 'claim_concurrent_refund';

      // Start with 5 stars
      service.seedMemberBalance(familyId, childId, 5);

      final futures = List.generate(20, (i) {
        return service
            .refundWishlistClaim(
              claimId: claimId,
              familyId: familyId,
              userId: childId,
              refundStars: 15,
              reason: 'Lý do $i',
            )
            .then((_) => 'SUCCESS')
            .catchError((e) => 'ERR:${e.runtimeType}');
      });

      final results = await Future.wait(futures);

      final successCount = results.where((r) => r == 'SUCCESS').length;
      final errorCount = results.where((r) => r.startsWith('ERR:')).length;

      expect(successCount, 1, reason: 'Expected exactly 1 successful refund call');
      expect(errorCount, 19, reason: 'Expected exactly 19 duplicate refund calls to be rejected');

      for (final err in results.where((r) => r.startsWith('ERR:'))) {
        expect(err, 'ERR:StateError');
      }

      // Balance must become 5 + 15 = 20 (not 5 + 20*15 = 305)
      expect(service.getBalance(familyId, childId), 20);
      expect(service.starLedger.containsKey('refund_$claimId'), isTrue);
    });
  });

  group('EMPIRICAL CHALLENGE 4: Sensor Accelerometer Debounce & Mutex Stress Tests', () {
    late AccelerometerShakeEngine engine;

    setUp(() {
      engine = AccelerometerShakeEngine();
      engine.reset();
    });

    test('4.1 High-frequency burst: 100 sensor events over 200ms meeting high-G threshold -> exactly 1 shake counted', () async {
      final t0 = DateTime(2026, 11, 6, 12, 0, 0);

      for (int i = 0; i < 100; i++) {
        await engine.handleSensorEvent(
          x: 12.0 + (i % 5),
          y: 11.0,
          z: 6.0,
          eventTime: t0.add(Duration(milliseconds: i * 2)), // 0ms to 198ms
        );
      }

      expect(engine.shakeCount, 1);
      expect(engine.isProcessingShake, isFalse);
    });

    test('4.2 Multi-burst chronological cooldown timeline stress', () async {
      final t0 = DateTime(2026, 11, 6, 12, 0, 0);

      // Burst 1 at t = 0s -> Shake 1
      for (int i = 0; i < 20; i++) {
        await engine.handleSensorEvent(
          x: 13.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(Duration(milliseconds: i * 10)),
        );
      }
      expect(engine.shakeCount, 1);

      // Burst 2 at t = 1.5s (< 3.0s cooldown) -> Ignored
      for (int i = 0; i < 20; i++) {
        await engine.handleSensorEvent(
          x: 13.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(Duration(milliseconds: 1500 + i * 10)),
        );
      }
      expect(engine.shakeCount, 1);

      // Burst 3 at t = 2.80s (< 3.0s cooldown, max 2895ms) -> Ignored
      for (int i = 0; i < 20; i++) {
        await engine.handleSensorEvent(
          x: 13.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(Duration(milliseconds: 2800 + i * 5)),
        );
      }
      expect(engine.shakeCount, 1);

      // Burst 4 at t = 3.10s (> 3.0s cooldown) -> Shake 2
      for (int i = 0; i < 20; i++) {
        await engine.handleSensorEvent(
          x: 13.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(Duration(milliseconds: 3100 + i * 10)),
        );
      }
      expect(engine.shakeCount, 2);

      // Burst 5 at t = 6.20s (> 3.0s from 3.10s) -> Shake 3
      for (int i = 0; i < 20; i++) {
        await engine.handleSensorEvent(
          x: 13.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(Duration(milliseconds: 6200 + i * 10)),
        );
      }
      expect(engine.shakeCount, 3);
    });

    test('4.3 Ambient environmental noise rejection (desk vibration & walking)', () async {
      // Resting on table with gentle jitter
      final accepted1 = await engine.handleSensorEvent(x: 0.1, y: 0.2, z: 9.81);
      expect(accepted1, isFalse);

      // Walking in pocket (g ~ 11.5, deltaG ~ 1.7)
      final accepted2 = await engine.handleSensorEvent(x: 2.0, y: 3.0, z: 11.0);
      expect(accepted2, isFalse);

      expect(engine.shakeCount, 0);
    });
  });

  group('EMPIRICAL CHALLENGE 5: Cash Prize Two-Way Handshake State Machine Boundary Stress', () {
    late CashGiftHandshakeEngine engine;

    setUp(() {
      engine = CashGiftHandshakeEngine();
    });

    test('5.1 Non-guardian cannot confirm payout', () {
      engine.createPrize(
        prizeId: 'prize_h1',
        childId: 'child_1',
        childName: 'Bé Hùng',
        amount: 50000,
      );

      expect(
        () => engine.guardianConfirmCashPayment(
          prizeId: 'prize_h1',
          guardianId: 'child_2',
          guardianName: 'Bé Mai',
          isGuardian: false,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Chỉ Trưởng bối (Guardian)'),
        )),
      );

      expect(engine.prizes['prize_h1']!.status, CashPrizeStatus.waitingTransfer);
    });

    test('5.2 Child cannot confirm receipt while WAITING_TRANSFER', () {
      engine.createPrize(
        prizeId: 'prize_h2',
        childId: 'child_1',
        childName: 'Bé Hùng',
        amount: 50000,
      );

      expect(
        () => engine.confirmChildReceipt(
          prizeId: 'prize_h2',
          childId: 'child_1',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('chưa thực hiện thanh toán'),
        )),
      );

      expect(engine.prizes['prize_h2']!.status, CashPrizeStatus.waitingTransfer);
    });

    test('5.3 Wrong child recipient cannot confirm receipt of another child prize', () {
      engine.createPrize(
        prizeId: 'prize_h3',
        childId: 'child_hung',
        childName: 'Bé Hùng',
        amount: 100000,
      );

      engine.guardianConfirmCashPayment(
        prizeId: 'prize_h3',
        guardianId: 'guardian_dad',
        guardianName: 'Bố Tuấn',
        isGuardian: true,
      );

      expect(
        () => engine.confirmChildReceipt(
          prizeId: 'prize_h3',
          childId: 'child_impostor',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Chỉ người nhận giải thưởng'),
        )),
      );

      expect(engine.prizes['prize_h3']!.status, CashPrizeStatus.paid);
      expect(engine.prizes['prize_h3']!.receivedAt, isNull);
    });

    test('5.4 Double receipt confirmation idempotency: second call succeeds without changing receivedAt', () {
      engine.createPrize(
        prizeId: 'prize_h4',
        childId: 'child_hung',
        childName: 'Bé Hùng',
        amount: 50000,
      );

      engine.guardianConfirmCashPayment(
        prizeId: 'prize_h4',
        guardianId: 'guardian_dad',
        guardianName: 'Bố Tuấn',
        isGuardian: true,
      );

      engine.confirmChildReceipt(prizeId: 'prize_h4', childId: 'child_hung');
      final firstReceivedAt = engine.prizes['prize_h4']!.receivedAt;
      expect(firstReceivedAt, isNotNull);

      // Second confirmation (double tap)
      engine.confirmChildReceipt(prizeId: 'prize_h4', childId: 'child_hung');
      expect(engine.prizes['prize_h4']!.receivedAt, firstReceivedAt);
      expect(engine.prizes['prize_h4']!.status, CashPrizeStatus.received);
    });
  });
}

// test/challenger_tier5_stress_test.dart
//
// Milestone: Final Milestone Phase 2 (Tier 5 Hardening)
// Focus: Empirical Concurrency & Boundary Stress Testing across:
// 1. High-concurrency Wishlist redemption races with exact balance exhaustion and oversubscription
// 2. Star Economy double-approval with simultaneous multi-guardian reviews
// 3. Jackpot accelerometer burst events at sub-millisecond precision
// 4. 2-way cash gift handshake transition attacks (out-of-sequence confirmations, impostor recipient claims)
// 5. 3-tier escalation simulation boundary timing (0s -> 7s -> 15s) and quiet-hours care exemption

import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Danh/services/family_jackpot_service.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/star_economy_service.dart';

import 'reminder_test.dart'
    show
        QuietHoursEngine,
        MultiTierEscalation15sEngine,
        GuardianOverdueAction;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TIER 5 EMPIRICAL STRESS SUITE (Concurrency & Boundary Hardening)', () {
    // =========================================================================
    // FOCUS AREA 1: High-concurrency Wishlist Redemption Races & Exhaustion
    // =========================================================================
    group('1. High-Concurrency Wishlist Redemption & Balance Exhaustion', () {
      late StarEconomyService service;

      setUp(() {
        service = StarEconomyService.inMemory();
        service.resetMockData();
      });

      test('1.1 Exact balance exhaustion with N concurrent requests: all succeed, balance strictly 0', () async {
        const initialBalance = 100;
        const requestCount = 10;
        const costPerRequest = 10;
        const familyId = 'fam_exhaust_1';
        const childId = 'child_exhaust_1';

        service.seedMemberBalance(familyId, childId, initialBalance);

        final results = await Future.wait(
          List.generate(requestCount, (i) {
            return service
                .claimWishlistItem(
                  claimId: 'claim_exact_$i',
                  familyId: familyId,
                  userId: childId,
                  cost: costPerRequest,
                  itemName: 'Prize Item $i',
                )
                .then((_) => 'SUCCESS')
                .catchError((e) => 'FAIL: $e');
          }),
        );

        final successes = results.where((r) => r == 'SUCCESS').length;
        final failures = results.where((r) => r.startsWith('FAIL')).length;

        expect(successes, equals(10), reason: 'All 10 requests should succeed for exact balance');
        expect(failures, equals(0), reason: 'No request should fail when total cost == balance');
        expect(service.getBalance(familyId, childId), equals(0), reason: 'Final balance must be exactly 0');

        // Verify ledger entries
        for (int i = 0; i < requestCount; i++) {
          final entry = service.starLedger['claim_claim_exact_$i'];
          expect(entry, isNotNull);
          expect(entry!['amount'], equals(-costPerRequest));
          expect(entry['type'], equals('WISHLIST_CLAIM'));
          expect(entry['userId'], equals(childId));
        }
      });

      test('1.2 Massive oversubscription race: 20 concurrent claims of 10 stars when balance is 50', () async {
        const initialBalance = 50;
        const totalRequests = 20; // 20 * 10 = 200 stars requested vs 50 available
        const cost = 10;
        const familyId = 'fam_oversub';
        const childId = 'child_oversub';

        service.seedMemberBalance(familyId, childId, initialBalance);

        final results = await Future.wait(
          List.generate(totalRequests, (i) {
            return service
                .claimWishlistItem(
                  claimId: 'claim_oversub_$i',
                  familyId: familyId,
                  userId: childId,
                  cost: cost,
                  itemName: 'Toy $i',
                )
                .then((_) => 'SUCCESS')
                .catchError((e) => e is InsufficientStarsException ? 'INSUFFICIENT' : 'OTHER_ERROR');
          }),
        );

        final successCount = results.where((r) => r == 'SUCCESS').length;
        final insufficientCount = results.where((r) => r == 'INSUFFICIENT').length;

        // Invariant: Exactly 5 claims can be funded, remaining 15 MUST fail
        expect(successCount, equals(5), reason: 'Only 5 claims can be funded from 50 stars');
        expect(insufficientCount, equals(15), reason: 'Remaining 15 claims must throw InsufficientStarsException');
        expect(service.getBalance(familyId, childId), equals(0), reason: 'Balance must be exhausted to 0 and never negative');

        // Invariant: Ledger must record exactly 5 entries
        final claimLedgerCount = service.starLedger.values
            .where((tx) => tx['type'] == 'WISHLIST_CLAIM' && tx['userId'] == childId)
            .length;
        expect(claimLedgerCount, equals(5));
      });

      test('1.3 Zero-balance spam attack: 50 concurrent requests rejected, 0 ledger entries, balance remains 0', () async {
        const familyId = 'fam_zero_spam';
        const childId = 'child_zero_spam';

        service.seedMemberBalance(familyId, childId, 0);

        final results = await Future.wait(
          List.generate(50, (i) {
            return service
                .claimWishlistItem(
                  claimId: 'claim_spam_$i',
                  familyId: familyId,
                  userId: childId,
                  cost: 1,
                  itemName: 'Micro Item $i',
                )
                .then((_) => 'SUCCESS')
                .catchError((e) => e is InsufficientStarsException ? 'BLOCKED' : 'OTHER');
          }),
        );

        expect(results.every((r) => r == 'BLOCKED'), isTrue, reason: 'All 50 spam claims must be blocked');
        expect(service.getBalance(familyId, childId), equals(0));
        expect(service.starLedger.isEmpty, isTrue, reason: 'Star ledger must be pristine');
      });

      test('1.4 Asymmetric multi-cost race: arbitrary costs strictly preserve conservation of stars', () async {
        const initialBalance = 100;
        final costs = [50, 40, 30, 20, 15, 10, 10, 5, 5, 5]; // Sum = 190
        const familyId = 'fam_asym';
        const childId = 'child_asym';

        service.seedMemberBalance(familyId, childId, initialBalance);

        final outcomes = await Future.wait(
          costs.asMap().entries.map((entry) {
            final idx = entry.key;
            final cost = entry.value;
            return service
                .claimWishlistItem(
                  claimId: 'claim_asym_$idx',
                  familyId: familyId,
                  userId: childId,
                  cost: cost,
                  itemName: 'Asym Item $idx ($cost stars)',
                )
                .then((_) => cost)
                .catchError((_) => 0);
          }),
        );

        final totalSpent = outcomes.reduce((a, b) => a + b);
        final finalBalance = service.getBalance(familyId, childId);

        expect(finalBalance, greaterThanOrEqualTo(0), reason: 'Final balance must never be negative');
        expect(totalSpent + finalBalance, equals(initialBalance), reason: 'Total spent + remaining balance must equal initial stars');
        expect(totalSpent, lessThanOrEqualTo(initialBalance));
      });

      test('1.5 Concurrent duplicate claimId replay attack: exactly 1 succeeds, 19 fail', () async {
        const familyId = 'fam_replay';
        const childId = 'child_replay';
        service.seedMemberBalance(familyId, childId, 100);

        const targetClaimId = 'replay_attack_tx_unique';

        final results = await Future.wait(
          List.generate(20, (i) {
            return service
                .claimWishlistItem(
                  claimId: targetClaimId,
                  familyId: familyId,
                  userId: childId,
                  cost: 10,
                  itemName: 'Replay Toy',
                )
                .then((_) => 'SUCCESS')
                .catchError((e) => 'REJECTED: $e');
          }),
        );

        final successes = results.where((r) => r == 'SUCCESS').length;
        final rejections = results.where((r) => r.startsWith('REJECTED')).length;

        expect(successes, equals(1), reason: 'Only the very first claimId transaction may succeed');
        expect(rejections, equals(19), reason: 'Subsequent 19 identical claimIds must be rejected as duplicates');
        expect(service.getBalance(familyId, childId), equals(90), reason: 'Balance deducted only once');
        expect(service.starLedger.containsKey('claim_$targetClaimId'), isTrue);
      });

      test('1.6 High-concurrency interleaved claim and refund stress preserves non-negative balance', () async {
        const familyId = 'fam_interleave';
        const childId = 'child_interleave';
        service.seedMemberBalance(familyId, childId, 30);

        // 10 claims of 10 stars and 10 refunds of 10 stars fired concurrently
        final futures = <Future<String>>[];

        for (int i = 0; i < 10; i++) {
          final claimIndex = i;
          futures.add(
            service
                .claimWishlistItem(
                  claimId: 'inter_claim_$claimIndex',
                  familyId: familyId,
                  userId: childId,
                  cost: 10,
                  itemName: 'Interleaved Item $claimIndex',
                )
                .then((_) => 'CLAIM_SUCCESS')
                .catchError((_) => 'CLAIM_FAIL'),
          );
        }

        for (int i = 0; i < 10; i++) {
          final refundIndex = i;
          futures.add(
            service
                .refundWishlistClaim(
                  claimId: 'inter_refund_$refundIndex',
                  familyId: familyId,
                  userId: childId,
                  refundStars: 10,
                  reason: 'TEST_REFUND',
                )
                .then((_) => 'REFUND_SUCCESS')
                .catchError((_) => 'REFUND_FAIL'),
          );
        }

        final results = await Future.wait(futures);
        final successfulClaims = results.where((r) => r == 'CLAIM_SUCCESS').length;
        final successfulRefunds = results.where((r) => r == 'REFUND_SUCCESS').length;

        final finalBalance = service.getBalance(familyId, childId);
        expect(finalBalance, greaterThanOrEqualTo(0));
        expect(finalBalance, equals(30 - (successfulClaims * 10) + (successfulRefunds * 10)));
      });

      test('1.7 Extreme numerical boundaries: integer arithmetic safety and invalid costs', () async {
        const familyId = 'fam_bound';
        const childId = 'child_bound';

        // 1 billion stars
        const hugeBalance = 1000000000;
        service.seedMemberBalance(familyId, childId, hugeBalance);

        // Claim hugeBalance + 1 -> InsufficientStarsException
        expect(
          () => service.claimWishlistItem(
            claimId: 'claim_huge_over',
            familyId: familyId,
            userId: childId,
            cost: hugeBalance + 1,
            itemName: 'Too Expensive',
          ),
          throwsA(isA<InsufficientStarsException>()),
        );

        // Claim exactly hugeBalance -> Succeeds
        await service.claimWishlistItem(
          claimId: 'claim_huge_exact',
          familyId: familyId,
          userId: childId,
          cost: hugeBalance,
          itemName: 'Exact 1 Billion',
        );
        expect(service.getBalance(familyId, childId), equals(0));

        // Invalid negative or zero cost
        expect(
          () => service.claimWishlistItem(
            claimId: 'claim_invalid_0',
            familyId: familyId,
            userId: childId,
            cost: 0,
            itemName: 'Zero Cost',
          ),
          throwsArgumentError,
        );
        expect(
          () => service.claimWishlistItem(
            claimId: 'claim_invalid_neg',
            familyId: familyId,
            userId: childId,
            cost: -10,
            itemName: 'Negative Cost',
          ),
          throwsArgumentError,
        );
      });
    });

    // =========================================================================
    // FOCUS AREA 2: Star Economy Double-Approval with Multi-Guardian Reviews
    // =========================================================================
    group('2. Star Economy Double-Approval with Simultaneous Multi-Guardian Reviews', () {
      late StarEconomyService service;

      setUp(() {
        service = StarEconomyService.inMemory();
        service.resetMockData();
      });

      test('2.1 Massive multi-guardian approval race (20 simultaneous guardians on single chore)', () async {
        const taskId = 'task_multi_guard_20';
        const familyId = 'fam_guard_race';
        const childId = 'child_guard_race';
        const reward = 25;

        service.seedMemberBalance(familyId, childId, 0);
        service.seedTask(taskId, {
          'familyId': familyId,
          'assignedTo': childId,
          'status': 'SUBMITTED',
          'taskStatus': 'SUBMITTED',
          'rewardStars': reward,
        });

        final results = await Future.wait(
          List.generate(20, (i) {
            return service
                .approveTaskWithDoubleAwardProtection(
                  taskId: taskId,
                  reviewerId: 'guardian_$i',
                  reviewerName: 'Guardian Name $i',
                )
                .then((_) => 'APPROVED')
                .catchError((e) => e is DoubleApprovalException ? 'BLOCKED' : 'OTHER');
          }),
        );

        final approvedCount = results.where((r) => r == 'APPROVED').length;
        final blockedCount = results.where((r) => r == 'BLOCKED').length;

        expect(approvedCount, equals(1), reason: 'Exactly one guardian review must succeed');
        expect(blockedCount, equals(19), reason: '19 concurrent reviews must be blocked with DoubleApprovalException');
        expect(service.getBalance(familyId, childId), equals(reward), reason: 'Child receives reward exactly once');

        final task = service.reminders[taskId];
        expect(task!['status'], equals('APPROVED'));
        expect(task['taskStatus'], equals('COMPLETED'));
        expect(task['isCompleted'], isTrue);

        final ledgerEntry = service.starLedger['reward_$taskId'];
        expect(ledgerEntry, isNotNull);
        expect(ledgerEntry!['amount'], equals(reward));
      });

      test('2.2 Ultra-high concurrency: 50 concurrent guardian reviews on single chore', () async {
        const taskId = 'task_ultra_50';
        const familyId = 'fam_ultra';
        const childId = 'child_ultra';

        service.seedMemberBalance(familyId, childId, 10);
        service.seedTask(taskId, {
          'familyId': familyId,
          'assignedTo': childId,
          'status': 'SUBMITTED',
          'taskStatus': 'SUBMITTED',
          'rewardStars': 15,
        });

        final results = await Future.wait(
          List.generate(50, (i) {
            return service
                .approveTaskWithDoubleAwardProtection(
                  taskId: taskId,
                  reviewerId: 'g_$i',
                  reviewerName: 'Grandparent $i',
                )
                .then((_) => 'APPROVED')
                .catchError((e) => e is DoubleApprovalException ? 'BLOCKED' : 'FAIL');
          }),
        );

        expect(results.where((r) => r == 'APPROVED').length, equals(1));
        expect(results.where((r) => r == 'BLOCKED').length, equals(49));
        expect(service.getBalance(familyId, childId), equals(25)); // 10 + 15
      });

      test('2.3 Cross-task multi-guardian concurrency matrix: 10 tasks x 5 guardians = 50 concurrent reviews', () async {
        const familyId = 'fam_matrix';
        const childId = 'child_matrix';
        service.seedMemberBalance(familyId, childId, 0);

        for (int t = 0; t < 10; t++) {
          service.seedTask('matrix_task_$t', {
            'familyId': familyId,
            'assignedTo': childId,
            'status': 'SUBMITTED',
            'taskStatus': 'SUBMITTED',
            'rewardStars': 10,
          });
        }

        final futures = <Future<String>>[];
        for (int t = 0; t < 10; t++) {
          for (int g = 0; g < 5; g++) {
            final taskId = 'matrix_task_$t';
            final guardianId = 'guardian_${t}_$g';
            futures.add(
              service
                  .approveTaskWithDoubleAwardProtection(
                    taskId: taskId,
                    reviewerId: guardianId,
                    reviewerName: 'Guardian $guardianId',
                  )
                  .then((_) => 'T${t}_OK')
                  .catchError((_) => 'T${t}_DUP'),
            );
          }
        }

        final results = await Future.wait(futures);

        // For each of the 10 tasks, exactly 1 OK and 4 DUP
        for (int t = 0; t < 10; t++) {
          final okCount = results.where((r) => r == 'T${t}_OK').length;
          final dupCount = results.where((r) => r == 'T${t}_DUP').length;
          expect(okCount, equals(1), reason: 'Task matrix_task_$t should have 1 approval');
          expect(dupCount, equals(4), reason: 'Task matrix_task_$t should have 4 duplicate blocks');
        }

        expect(service.getBalance(familyId, childId), equals(100), reason: '10 tasks * 10 stars = 100 stars');
        expect(service.starLedger.length, equals(10));
      });

      test('2.4 Post-approval burst attack: 20 approvals against already APPROVED task all throw DoubleApprovalException', () async {
        const taskId = 'already_approved_chore';
        const familyId = 'fam_already';
        const childId = 'child_already';

        service.seedMemberBalance(familyId, childId, 50);
        service.seedTask(taskId, {
          'familyId': familyId,
          'assignedTo': childId,
          'status': 'APPROVED',
          'taskStatus': 'COMPLETED',
          'approvedBy': 'earlier_guardian',
          'approvedByName': 'Bà Nội',
          'rewardStars': 20,
        });
        service.starLedger['reward_$taskId'] = {
          'id': 'reward_$taskId',
          'amount': 20,
          'userId': childId,
        };

        final results = await Future.wait(
          List.generate(20, (i) {
            return service
                .approveTaskWithDoubleAwardProtection(
                  taskId: taskId,
                  reviewerId: 'late_guard_$i',
                  reviewerName: 'Late Guardian $i',
                )
                .then((_) => 'LEAK')
                .catchError((e) => e is DoubleApprovalException ? 'BLOCKED' : 'OTHER');
          }),
        );

        expect(results.every((r) => r == 'BLOCKED'), isTrue);
        expect(service.getBalance(familyId, childId), equals(50), reason: 'Balance must remain unchanged');
      });

      test('2.5 Zero-reward chore concurrent approval: 10 guardians, exactly 1 succeeds, balance untouched', () async {
        const taskId = 'zero_reward_task';
        const familyId = 'fam_zero';
        const childId = 'child_zero';

        service.seedMemberBalance(familyId, childId, 15);
        service.seedTask(taskId, {
          'familyId': familyId,
          'assignedTo': childId,
          'status': 'SUBMITTED',
          'taskStatus': 'SUBMITTED',
          'rewardStars': 0,
        });

        final results = await Future.wait(
          List.generate(10, (i) {
            return service
                .approveTaskWithDoubleAwardProtection(
                  taskId: taskId,
                  reviewerId: 'g_$i',
                  reviewerName: 'Guardian $i',
                )
                .then((_) => 'OK')
                .catchError((e) => e is DoubleApprovalException ? 'BLOCKED' : 'FAIL');
          }),
        );

        expect(results.where((r) => r == 'OK').length, equals(1));
        expect(results.where((r) => r == 'BLOCKED').length, equals(9));
        expect(service.getBalance(familyId, childId), equals(15));
        expect(service.starLedger['reward_$taskId']!['amount'], equals(0));
      });
    });

    // =========================================================================
    // FOCUS AREA 3: Jackpot Accelerometer Burst Events at Sub-Millisecond Precision
    // =========================================================================
    group('3. Jackpot Accelerometer Burst Events at Sub-Millisecond Precision', () {
      late AccelerometerShakeEngine engine;

      setUp(() {
        engine = AccelerometerShakeEngine();
        engine.reset();
      });

      test('3.1 Sub-millisecond burst stress: 1000 events within 1 millisecond (1us intervals)', () async {
        final t0 = DateTime(2026, 11, 6, 14, 0, 0);

        final results = <bool>[];
        // 1000 events at 1 microsecond steps (0 to 999us)
        for (int i = 0; i < 1000; i++) {
          final eventTime = t0.add(Duration(microseconds: i));
          final accepted = await engine.handleSensorEvent(
            x: 0.0,
            y: 0.0,
            z: 25.0, // g = 25.0 > 15.0, deltaG = 15.19 > 4.5
            eventTime: eventTime,
          );
          results.add(accepted);
        }

        expect(results.first, isTrue, reason: 'Initial sub-millisecond event must be accepted');
        expect(results.skip(1).every((r) => r == false), isTrue, reason: 'Subsequent 999 events within 1ms must be rejected');
        expect(engine.shakeCount, equals(1), reason: 'Shake count must strictly equal 1');
        expect(engine.isProcessingShake, isFalse);
      });

      test('3.2 Exact 3000ms cooldown boundary precision: 2999ms (reject) vs 3000ms (accept)', () async {
        final t0 = DateTime(2026, 11, 6, 14, 0, 0);

        // Shake 1 at t0
        final s1 = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0,
        );
        expect(s1, isTrue);
        expect(engine.shakeCount, equals(1));

        // Event at 2999ms -> Rejected by cooldown
        final s2 = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 2999)),
        );
        expect(s2, isFalse, reason: '2999ms must be within 3000ms cooldown window');
        expect(engine.shakeCount, equals(1));

        // Event at 2999ms + 999us -> Rejected
        final s3 = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 2999, microseconds: 999)),
        );
        expect(s3, isFalse, reason: '2999.999ms must be strictly rejected');
        expect(engine.shakeCount, equals(1));

        // Event at exactly 3000ms -> Accepted (cooldown elapsed)
        final s4 = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 3000)),
        );
        expect(s4, isTrue, reason: 'Exact 3000ms boundary must be accepted as cooldown has expired');
        expect(engine.shakeCount, equals(2));

        // Burst at 3000ms + 500us -> Rejected
        final s5 = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 3000, microseconds: 500)),
        );
        expect(s5, isFalse);
        expect(engine.shakeCount, equals(2));

        // Event at 6000ms -> Accepted (3rd shake)
        final s6 = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 6000)),
        );
        expect(s6, isTrue);
        expect(engine.shakeCount, equals(3));
      });

      test('3.3 100 concurrent asynchronous sensor events via Future.wait yield exactly 1 shake', () async {
        final t0 = DateTime(2026, 11, 6, 14, 0, 0);

        final futures = List.generate(100, (i) {
          return engine.handleSensorEvent(
            x: 15.0,
            y: 10.0,
            z: 10.0, // g = sqrt(225+100+100) = sqrt(425) ~= 20.61 > 15.0
            eventTime: t0.add(Duration(microseconds: i * 10)),
          );
        });

        final results = await Future.wait(futures);
        final accepted = results.where((r) => r == true).length;

        expect(accepted, equals(1), reason: 'Concurrent async burst must resolve to exactly 1 registered shake');
        expect(engine.shakeCount, equals(1));
        expect(engine.isProcessingShake, isFalse);
      });

      test('3.4 Gravitational vector math boundary and alternating polarity stress', () async {
        final t0 = DateTime(2026, 11, 6, 14, 0, 0);

        // Sub-threshold g <= 15.0: x=8.6, y=8.6, z=8.6 -> g = sqrt(73.96*3) ~= 14.89 <= 15.0
        final subG = await engine.handleSensorEvent(
          x: 8.6,
          y: 8.6,
          z: 8.6,
          eventTime: t0,
        );
        expect(subG, isFalse, reason: 'g <= 15.0 must be rejected');
        expect(engine.shakeCount, equals(0));

        // Polarity inversion: negative coordinates still square to positive g
        // x=-12, y=-10, z=-5 -> g ~= 16.40 > 15.0, deltaG ~= 6.59 > 4.5
        final inv1 = await engine.handleSensorEvent(
          x: -12.0,
          y: -10.0,
          z: -5.0,
          eventTime: t0,
        );
        expect(inv1, isTrue, reason: 'Negative vector components must produce correct magnitude and register shake');
        expect(engine.shakeCount, equals(1));

        // Mixed signs after cooldown
        final inv2 = await engine.handleSensorEvent(
          x: 12.0,
          y: -10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 3100)),
        );
        expect(inv2, isTrue);
        expect(engine.shakeCount, equals(2));
      });

      test('3.5 Shaking phase dynamic toggle: mid-stream disable immediately rejects all bursts', () async {
        final t0 = DateTime(2026, 11, 6, 14, 0, 0);

        // First shake succeeds during active phase
        final s1 = await engine.handleSensorEvent(x: 20, y: 10, z: 10, eventTime: t0);
        expect(s1, isTrue);
        expect(engine.shakeCount, equals(1));

        // Disable phase (e.g. jackpot result revealed)
        engine.isShakingPhase = false;

        // 50 subsequent events across next 10 seconds must all be rejected
        final results = await Future.wait(
          List.generate(50, (i) {
            return engine.handleSensorEvent(
              x: 25,
              y: 25,
              z: 25,
              eventTime: t0.add(Duration(milliseconds: 4000 + i * 100)),
            );
          }),
        );

        expect(results.every((r) => r == false), isTrue);
        expect(engine.shakeCount, equals(1), reason: 'Shake count cannot increase when isShakingPhase is false');
      });
    });

    // =========================================================================
    // FOCUS AREA 4: 2-Way Cash Gift Handshake Transition Attacks
    // =========================================================================
    group('4. 2-Way Cash Gift Handshake Transition Attacks', () {
      late CashGiftHandshakeEngine engine;

      setUp(() {
        engine = CashGiftHandshakeEngine();
        engine.reset();
      });

      test('4.1 Out-of-sequence confirmation attack: Child claims receipt in WAITING_TRANSFER state', () {
        final prize = engine.createPrize(
          prizeId: 'prize_out_of_seq',
          childId: 'child_alice',
          childName: 'Bé Alice',
          amount: 50000,
        );

        expect(prize.status, equals(CashPrizeStatus.waitingTransfer));

        // Child attempts to confirm receipt before Guardian makes payout
        expect(
          () => engine.confirmChildReceipt(
            prizeId: 'prize_out_of_seq',
            childId: 'child_alice',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Không thể xác nhận nhận tiền khi Trưởng bối chưa thực hiện thanh toán!'),
            ),
          ),
        );

        expect(prize.status, equals(CashPrizeStatus.waitingTransfer), reason: 'Status must remain WAITING_TRANSFER');
        expect(prize.receivedAt, isNull);
      });

      test('4.2 Impostor recipient claim attack: Malicious child claims prize belonging to another child', () {
        final prize = engine.createPrize(
          prizeId: 'prize_impostor_test',
          childId: 'child_legit',
          childName: 'Bé Thảo',
          amount: 100000,
        );

        // Guardian pays legitimate prize
        engine.guardianConfirmCashPayment(
          prizeId: 'prize_impostor_test',
          guardianId: 'grandparent_1',
          guardianName: 'Ông Nội',
          isGuardian: true,
        );

        expect(prize.status, equals(CashPrizeStatus.paid));

        // Impostor child attempts confirmation
        expect(
          () => engine.confirmChildReceipt(
            prizeId: 'prize_impostor_test',
            childId: 'child_impostor_bob',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Chỉ người nhận giải thưởng mới có quyền bấm xác nhận nhận tiền!'),
            ),
          ),
        );

        expect(prize.status, equals(CashPrizeStatus.paid), reason: 'Status must remain PAID');
        expect(prize.receivedAt, isNull);

        // Legitimate child confirms -> succeeds
        engine.confirmChildReceipt(
          prizeId: 'prize_impostor_test',
          childId: 'child_legit',
        );
        expect(prize.status, equals(CashPrizeStatus.received));
        expect(prize.receivedAt, isNotNull);
      });

      test('4.3 Privilege escalation attack: Non-guardian unauthorized payout is rejected', () {
        engine.createPrize(
          prizeId: 'prize_escalate_test',
          childId: 'child_david',
          childName: 'David',
          amount: 20000,
        );

        // Child or stranger attempts to record payout with isGuardian: false
        expect(
          () => engine.guardianConfirmCashPayment(
            prizeId: 'prize_escalate_test',
            guardianId: 'child_david',
            guardianName: 'David',
            isGuardian: false,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Chỉ Trưởng bối (Guardian) mới có quyền xác nhận trao tiền mặt!'),
            ),
          ),
        );

        // VietQR non-guardian payout
        expect(
          () => engine.guardianConfirmVietQrTransfer(
            prizeId: 'prize_escalate_test',
            guardianId: 'stranger_uid',
            guardianName: 'Stranger',
            bankRef: 'VQR123456',
            isGuardian: false,
          ),
          throwsA(isA<StateError>()),
        );

        final prize = engine.prizes['prize_escalate_test'];
        expect(prize!.status, equals(CashPrizeStatus.waitingTransfer));
      });

      test('4.4 Cancelled prize payout attack: Guardian payout on cancelled prize throws StateError', () {
        final prize = engine.createPrize(
          prizeId: 'prize_cancelled_test',
          childId: 'child_c',
          childName: 'Bé C',
          amount: 50000,
        );
        prize.status = CashPrizeStatus.cancelled;

        expect(
          () => engine.guardianConfirmCashPayment(
            prizeId: 'prize_cancelled_test',
            guardianId: 'g_1',
            guardianName: 'Bố',
            isGuardian: true,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Giải thưởng đã bị hủy bỏ'),
            ),
          ),
        );
      });

      test('4.5 Concurrent duplicate confirmation flood by legitimate child is idempotent and safe', () async {
        engine.createPrize(
          prizeId: 'prize_flood_test',
          childId: 'child_flood',
          childName: 'Bé Flood',
          amount: 30000,
        );

        engine.guardianConfirmCashPayment(
          prizeId: 'prize_flood_test',
          guardianId: 'g_dad',
          guardianName: 'Bố',
          isGuardian: true,
        );

        // 20 concurrent confirmation requests
        final results = await Future.wait(
          List.generate(20, (i) {
            return Future(() {
              engine.confirmChildReceipt(
                prizeId: 'prize_flood_test',
                childId: 'child_flood',
              );
              return 'OK';
            });
          }),
        );

        expect(results.every((r) => r == 'OK'), isTrue);
        final prize = engine.prizes['prize_flood_test'];
        expect(prize!.status, equals(CashPrizeStatus.received));
        expect(prize.receivedAt, isNotNull);
      });

      test('4.6 Non-existent prize ID operations throw clear Exception', () {
        expect(
          () => engine.confirmChildReceipt(prizeId: 'ghost_prize', childId: 'c1'),
          throwsException,
        );
        expect(
          () => engine.guardianConfirmCashPayment(
            prizeId: 'ghost_prize',
            guardianId: 'g1',
            guardianName: 'G',
            isGuardian: true,
          ),
          throwsException,
        );
      });
    });

    // =========================================================================
    // FOCUS AREA 5: 3-Tier Escalation Boundary Timing & Quiet-Hours Care Exemption
    // =========================================================================
    group('5. 3-Tier Escalation Simulation Boundary Timing & Quiet-Hours Care Exemption', () {
      late MultiTierEscalation15sEngine escalationEngine;
      late QuietHoursEngine quietEngine;

      setUp(() {
        escalationEngine = MultiTierEscalation15sEngine();
        escalationEngine.reset();
        quietEngine = QuietHoursEngine();
      });

      test('5.1 15-second simulation timeline exact boundaries: 0s -> 7s -> 15s', () {
        final timeline = escalationEngine.generate15SecondSimulationTimeline(
          taskId: 'task_sim_boundary',
          title: 'Dọn phòng học tập',
          recipientName: 'Bé Nam',
          creatorName: 'Mẹ Hằng',
        );

        expect(timeline.length, equals(3));

        // Tier 1 boundary: 0s
        expect(timeline[0].simulatedSecond, equals(0));
        expect(timeline[0].tierName, contains('Mốc 1 (0h)'));
        expect(timeline[0].message, contains('Đúng giờ hẹn'));

        // Tier 2 boundary: 7s
        expect(timeline[1].simulatedSecond, equals(7));
        expect(timeline[1].tierName, contains('Mốc 2 (+2h)'));
        expect(timeline[1].message, contains('Quá hạn 2 tiếng'));

        // Tier 3 boundary: 15s
        expect(timeline[2].simulatedSecond, equals(15));
        expect(timeline[2].tierName, contains('Mốc 3 (+6h)'));
        expect(timeline[2].message, contains('Báo cáo Trưởng bối'));
      });

      test('5.2 Cancellation and disarming disarms escalation timers immediately', () {
        const taskId = 'task_cancel_sim';
        escalationEngine.scheduleEscalation(taskId: taskId);
        expect(escalationEngine.hasActiveTimers(taskId), isTrue);

        escalationEngine.cancelEscalation(taskId);
        expect(escalationEngine.hasActiveTimers(taskId), isFalse);
      });

      test('5.3 Quiet-hours sub-millisecond boundary stress: 21:59:59.999 vs 22:00:00.000 vs 06:00:00.000', () {
        // Boundary 1: 21:59:59.999 (Pre-quiet-hours) -> Neither is deferred
        final t2159Sub = DateTime(2026, 11, 6, 21, 59, 59, 999);
        expect(
          quietEngine.calculateEffectiveAlarmTime(scheduledTime: t2159Sub, taskType: 'ASSIGN'),
          equals(t2159Sub),
          reason: '21:59:59.999 is outside quiet hours, chore should alarm immediately',
        );
        expect(
          quietEngine.calculateEffectiveAlarmTime(scheduledTime: t2159Sub, taskType: 'CARE'),
          equals(t2159Sub),
        );

        // Boundary 2: 22:00:00.000 (Exact quiet-hours start boundary)
        final t2200Exact = DateTime(2026, 11, 6, 22, 0, 0, 0);
        final effAssign22 = quietEngine.calculateEffectiveAlarmTime(
          scheduledTime: t2200Exact,
          taskType: 'ASSIGN',
        );
        expect(effAssign22.year, equals(2026));
        expect(effAssign22.month, equals(11));
        expect(effAssign22.day, equals(7), reason: 'Chore must be deferred to next morning');
        expect(effAssign22.hour, equals(7));
        expect(effAssign22.minute, equals(0));

        // CARE task at 22:00:00 is strictly immune!
        expect(
          quietEngine.calculateEffectiveAlarmTime(scheduledTime: t2200Exact, taskType: 'CARE'),
          equals(t2200Exact),
          reason: 'Elderly medication CARE task must ring immediately regardless of quiet hours',
        );

        // Boundary 3: Midnight 00:00:00.000
        final t0000 = DateTime(2026, 11, 7, 0, 0, 0);
        final effAssign00 = quietEngine.calculateEffectiveAlarmTime(
          scheduledTime: t0000,
          taskType: 'ASSIGN',
        );
        expect(effAssign00.day, equals(7), reason: 'Deferred to 07:00 same day');
        expect(effAssign00.hour, equals(7));
        expect(
          quietEngine.calculateEffectiveAlarmTime(scheduledTime: t0000, taskType: 'CARE'),
          equals(t0000),
        );

        // Boundary 4: 05:59:59.999 (Last sub-millisecond of quiet hours)
        final t0559Sub = DateTime(2026, 11, 7, 5, 59, 59, 999);
        final effAssign05 = quietEngine.calculateEffectiveAlarmTime(
          scheduledTime: t0559Sub,
          taskType: 'ASSIGN',
        );
        expect(effAssign05.day, equals(7));
        expect(effAssign05.hour, equals(7));
        expect(
          quietEngine.calculateEffectiveAlarmTime(scheduledTime: t0559Sub, taskType: 'CARE'),
          equals(t0559Sub),
        );

        // Boundary 5: 06:00:00.000 (Quiet hours expired) -> Neither deferred
        final t0600 = DateTime(2026, 11, 7, 6, 0, 0);
        expect(
          quietEngine.calculateEffectiveAlarmTime(scheduledTime: t0600, taskType: 'ASSIGN'),
          equals(t0600),
          reason: '06:00:00 is post quiet hours, chore rings immediately',
        );
        expect(
          quietEngine.calculateEffectiveAlarmTime(scheduledTime: t0600, taskType: 'CARE'),
          equals(t0600),
        );
      });

      test('5.4 Calendar Rollover Boundaries: Year-end rollover and leap year preservation', () {
        // Year-end rollover: Dec 31, 2026 at 23:30 -> Jan 1, 2027 at 07:00
        final tNewYearEve = DateTime(2026, 12, 31, 23, 30, 0);
        final effNewYear = quietEngine.calculateEffectiveAlarmTime(
          scheduledTime: tNewYearEve,
          taskType: 'ASSIGN',
        );
        expect(effNewYear.year, equals(2027), reason: 'Must rollover year to 2027');
        expect(effNewYear.month, equals(1));
        expect(effNewYear.day, equals(1));
        expect(effNewYear.hour, equals(7));

        expect(
          quietEngine.calculateEffectiveAlarmTime(scheduledTime: tNewYearEve, taskType: 'CARE'),
          equals(tNewYearEve),
          reason: 'CARE remains on Dec 31, 2026 23:30',
        );

        // Leap year rollover: Feb 28, 2028 at 22:30 -> Feb 29, 2028 at 07:00
        final tLeapEve = DateTime(2028, 2, 28, 22, 30, 0);
        final effLeap = quietEngine.calculateEffectiveAlarmTime(
          scheduledTime: tLeapEve,
          taskType: 'ASSIGN',
        );
        expect(effLeap.year, equals(2028));
        expect(effLeap.month, equals(2));
        expect(effLeap.day, equals(29), reason: '2028 is leap year, rollover to Feb 29');
        expect(effLeap.hour, equals(7));
      });

      test('5.5 Model-level quiet hours immunity check on ReminderModel', () {
        final careReminder = ReminderModel(
          id: 'care_model_test',
          familyId: 'fam_c',
          creatorId: 'c1',
          assignedTo: 'a1',
          assignedToName: 'Bà Nội',
          title: 'Nhắc uống thuốc tiểu đường sau bữa tối',
          date: '06/11/2026',
          time: '22:30',
          taskType: TaskType.care,
        );
        expect(careReminder.isExemptFromQuietHours, isTrue);

        final titleMedReminder = ReminderModel(
          id: 'title_med_test',
          familyId: 'fam_c',
          creatorId: 'c1',
          assignedTo: 'a1',
          assignedToName: 'Ông Nội',
          title: 'Uống thuốc bổ mắt',
          date: '06/11/2026',
          time: '23:00',
          taskType: TaskType.assign,
        );
        expect(titleMedReminder.isExemptFromQuietHours, isTrue);

        final regularChore = ReminderModel(
          id: 'chore_model_test',
          familyId: 'fam_c',
          creatorId: 'c1',
          assignedTo: 'a1',
          assignedToName: 'Bé Nam',
          title: 'Quét dọn sân vườn',
          date: '06/11/2026',
          time: '23:00',
          taskType: TaskType.assign,
        );
        expect(regularChore.isExemptFromQuietHours, isFalse);
      });

      test('5.6 Notification channel config invariants for CARE vs ASSIGN tasks', () {
        final careConfig = quietEngine.getNotificationChannelConfig(taskType: 'CARE');
        expect(careConfig.channelId, equals('CARE_CHANNEL'));
        expect(careConfig.soundFileName, equals('nhac_uong_thuoc.mp3'));
        expect(careConfig.enableTtsReadout, isTrue);
        expect(careConfig.isQuietHoursImmune, isTrue);

        final regularConfig = quietEngine.getNotificationChannelConfig(taskType: 'ASSIGN');
        expect(regularConfig.channelId, equals('DEFAULT_CHANNEL'));
        expect(regularConfig.soundFileName, equals('default_chime.mp3'));
        expect(regularConfig.enableTtsReadout, isFalse);
        expect(regularConfig.isQuietHoursImmune, isFalse);
      });

      test('5.7 Voice extension request boundary tests and Guardian action trio', () {
        // Boundary: 0 or negative duration throws ArgumentError
        expect(
          () => escalationEngine.requestVoiceTimeExtension(
            taskId: 'task_voice_1',
            childId: 'child_voice',
            voicePath: '/tmp/voice.m4a',
            durationSeconds: 0,
            reasonText: 'Con xin thêm 30 phút',
            requestedMinutes: 30,
          ),
          throwsArgumentError,
        );

        expect(
          () => escalationEngine.requestVoiceTimeExtension(
            taskId: 'task_voice_1',
            childId: 'child_voice',
            voicePath: '/tmp/voice.m4a',
            durationSeconds: -5,
            reasonText: 'Negative duration',
            requestedMinutes: 30,
          ),
          throwsArgumentError,
        );

        // Valid voice extension
        final req = escalationEngine.requestVoiceTimeExtension(
          taskId: 'task_voice_1',
          childId: 'child_voice',
          voicePath: '/records/ext_voice_1.m4a',
          durationSeconds: 15,
          reasonText: 'Con đang bận làm bài tập toán chưa xong ạ',
          requestedMinutes: 45,
        );
        expect(req.status, equals('PENDING_GUARDIAN_REVIEW'));
        expect(req.isApproved, isFalse);

        // Guardian approves
        escalationEngine.approveExtensionRequest(
          requestId: req.id,
          guardianId: 'guardian_mom',
        );
        expect(req.isApproved, isTrue);
        expect(req.status, equals('APPROVED'));

        // Guardian action trio
        final actExtend = escalationEngine.executeGuardianOverdueAction(
          taskId: 'task_overdue_trio',
          action: GuardianOverdueAction.extendTime,
          extensionMinutes: 90,
        );
        expect(actExtend['status'], equals('EXTENDED'));
        expect(actExtend['extensionMinutes'], equals(90));

        final actDelegate = escalationEngine.executeGuardianOverdueAction(
          taskId: 'task_overdue_trio',
          action: GuardianOverdueAction.delegateTask,
          newAssigneeId: 'older_brother_uid',
        );
        expect(actDelegate['status'], equals('DELEGATED'));
        expect(actDelegate['newAssigneeId'], equals('older_brother_uid'));

        final actClose = escalationEngine.executeGuardianOverdueAction(
          taskId: 'task_overdue_trio',
          action: GuardianOverdueAction.closeWithoutReward,
        );
        expect(actClose['status'], equals('CLOSED_NO_STARS'));
        expect(actClose['rewardStarsAwarded'], equals(0));
      });
    });
  });
}

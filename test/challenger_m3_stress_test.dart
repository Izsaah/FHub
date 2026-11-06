import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/services/star_economy_service.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';

void main() {
  group('Milestone 3 Adversarial & Stress Testing', () {
    group('StarEconomyService Adversarial Vectors', () {
      late StarEconomyService service;

      setUp(() {
        service = StarEconomyService.inMemory();
        service.resetMockData();
      });

      test('ADV-1.1: Double-spending race with 5 concurrent requests exceeding balance', () async {
        // Child has 30 stars, 5 concurrent claims of 10 stars each = 50 stars requested
        service.seedMemberBalance('fam_adv', 'child_adv', 30);

        final results = await Future.wait(List.generate(5, (index) {
          return service
              .claimWishlistItem(
                claimId: 'claim_race_$index',
                familyId: 'fam_adv',
                userId: 'child_adv',
                cost: 10,
                itemName: 'Item $index',
              )
              .then((_) => 'success')
              .catchError((e) => 'error');
        }));

        final successes = results.where((r) => r == 'success').length;
        final errors = results.where((r) => r == 'error').length;

        // Exactly 3 should succeed, 2 should fail
        expect(successes, 3);
        expect(errors, 2);
        expect(service.getBalance('fam_adv', 'child_adv'), 0);
      });

      test('ADV-1.2: Extreme balance boundary (Large numbers / integer arithmetic)', () async {
        const largeBalance = 1000000000; // 1 billion stars
        service.seedMemberBalance('fam_adv', 'child_adv', largeBalance);

        await service.claimWishlistItem(
          claimId: 'claim_huge',
          familyId: 'fam_adv',
          userId: 'child_adv',
          cost: 999999999,
          itemName: 'Super prize',
        );

        expect(service.getBalance('fam_adv', 'child_adv'), 1);

        await service.refundWishlistClaim(
          claimId: 'claim_huge',
          familyId: 'fam_adv',
          userId: 'child_adv',
          refundStars: 999999999,
        );

        expect(service.getBalance('fam_adv', 'child_adv'), largeBalance);
      });

      test('ADV-1.3: Approval race with 10 concurrent guardians on the exact same task', () async {
        service.seedMemberBalance('fam_adv', 'child_adv', 0);
        service.seedTask('task_concurrent_10', {
          'familyId': 'fam_adv',
          'assignedTo': 'child_adv',
          'status': 'SUBMITTED',
          'rewardStars': 20,
        });

        final results = await Future.wait(List.generate(10, (i) {
          return service
              .approveTaskWithDoubleAwardProtection(
                taskId: 'task_concurrent_10',
                reviewerId: 'guardian_$i',
                reviewerName: 'Guardian $i',
              )
              .then((_) => 'approved')
              .catchError((e) => 'blocked');
        }));

        final approved = results.where((r) => r == 'approved').length;
        final blocked = results.where((r) => r == 'blocked').length;

        expect(approved, 1);
        expect(blocked, 9);
        expect(service.getBalance('fam_adv', 'child_adv'), 20);
      });

      test('ADV-1.4: Cross-family member balance isolation', () async {
        service.seedMemberBalance('fam_1', 'user_shared_id', 50);
        service.seedMemberBalance('fam_2', 'user_shared_id', 10);

        await service.claimWishlistItem(
          claimId: 'claim_fam_1',
          familyId: 'fam_1',
          userId: 'user_shared_id',
          cost: 30,
          itemName: 'Gift A',
        );

        // fam_1 is deducted
        expect(service.getBalance('fam_1', 'user_shared_id'), 20);
        // fam_2 remains untouched
        expect(service.getBalance('fam_2', 'user_shared_id'), 10);
      });

      test('ADV-1.5: Re-refunding claim in memory throws StateError idempotently', () async {
        service.seedMemberBalance('fam_adv', 'child_adv', 10);

        await service.refundWishlistClaim(
          claimId: 'refund_idempotent_test',
          familyId: 'fam_adv',
          userId: 'child_adv',
          refundStars: 10,
        );
        expect(service.getBalance('fam_adv', 'child_adv'), 20);

        expect(
          () => service.refundWishlistClaim(
            claimId: 'refund_idempotent_test',
            familyId: 'fam_adv',
            userId: 'child_adv',
            refundStars: 10,
          ),
          throwsStateError,
        );
        expect(service.getBalance('fam_adv', 'child_adv'), 20);
      });
    });

    group('Accelerometer & Jackpot Adversarial Vectors', () {
      late AccelerometerShakeEngine engine;

      setUp(() {
        engine = AccelerometerShakeEngine();
        engine.reset();
      });

      test('ADV-2.1: Negative 3D vector coordinates with high magnitude produce valid shake', () async {
        // x=-12.0, y=-10.0, z=-5.0 -> g = sqrt(144 + 100 + 25) = 16.40 > 15.0
        final accepted = await engine.handleSensorEvent(
          x: -12.0,
          y: -10.0,
          z: -5.0,
        );
        expect(accepted, isTrue);
        expect(engine.shakeCount, 1);
      });

      test('ADV-2.2: Pure single-axis extreme acceleration registers correctly', () async {
        // Pure X shake (x=16.0, y=0, z=0) -> g = 16.0 > 15.0, deltaG = 16 - 9.81 = 6.19 > 4.5
        final pureX = await engine.handleSensorEvent(x: 16.0, y: 0.0, z: 0.0);
        expect(pureX, isTrue);
        expect(engine.shakeCount, 1);

        // Within cooldown: pure Y shake (x=0, y=16.0, z=0) at +100ms is rejected
        final pureYCooldown = await engine.handleSensorEvent(
          x: 0.0,
          y: 16.0,
          z: 0.0,
          eventTime: engine.lastShakeTime!.add(const Duration(milliseconds: 100)),
        );
        expect(pureYCooldown, isFalse);
        expect(engine.shakeCount, 1);
      });

      test('ADV-2.3: Zero and near-zero gravity (free-fall state: x=0, y=0, z=0)', () async {
        // In free-fall, g = 0 <= 15.0, deltaG = 9.81 > 4.5
        // Since g <= 15.0, it must NOT trigger a shake!
        final freeFall = await engine.handleSensorEvent(x: 0.0, y: 0.0, z: 0.0);
        expect(freeFall, isFalse);
        expect(engine.shakeCount, 0);
      });

      test('ADV-2.4: Out-of-order / clock-skewed sensor event is handled safely', () async {
        final t1 = DateTime(2026, 11, 6, 12, 0, 10);
        final tPast = DateTime(2026, 11, 6, 12, 0, 5); // 5 seconds before t1

        final s1 = await engine.handleSensorEvent(x: 15.5, y: 10.0, z: 5.0, eventTime: t1);
        expect(s1, isTrue);

        // Out-of-order event from past: now.difference(lastShakeTime!) is negative Duration (-5s)
        // difference is negative, which is < cooldown (3s), so it is discarded
        final sPast = await engine.handleSensorEvent(x: 15.5, y: 10.0, z: 5.0, eventTime: tPast);
        expect(sPast, isFalse);
        expect(engine.shakeCount, 1);
      });

      test('ADV-2.5: High concurrency barrage on AccelerometerShakeEngine', () async {
        final baseTime = DateTime(2026, 11, 6, 12, 0, 0);

        // Launch 100 concurrent sensor events simultaneously
        final futures = List.generate(100, (i) {
          return engine.handleSensorEvent(
            x: 15.0 + (i % 5),
            y: 10.0,
            z: 5.0,
            eventTime: baseTime,
          );
        });

        final results = await Future.wait(futures);
        final accepted = results.where((r) => r == true).length;

        // Mutex + cooldown guarantee exactly 1 shake is registered
        expect(accepted, 1);
        expect(engine.shakeCount, 1);
        expect(engine.isProcessingShake, isFalse);
      });
    });

    group('Cash Gift Two-Way Handshake Adversarial Vectors', () {
      late CashGiftHandshakeEngine engine;

      setUp(() {
        engine = CashGiftHandshakeEngine();
      });

      test('ADV-3.1: Child cannot confirm twice with altered state', () {
        engine.createPrize(
          prizeId: 'adv_prize_1',
          childId: 'kid_a',
          childName: 'Bé A',
          amount: 50000,
        );

        engine.guardianConfirmCashPayment(
          prizeId: 'adv_prize_1',
          guardianId: 'g_1',
          guardianName: 'Bố',
          isGuardian: true,
        );

        engine.confirmChildReceipt(prizeId: 'adv_prize_1', childId: 'kid_a');
        expect(engine.prizes['adv_prize_1']!.status, CashPrizeStatus.received);

        // Safe idempotent repeat
        engine.confirmChildReceipt(prizeId: 'adv_prize_1', childId: 'kid_a');
        expect(engine.prizes['adv_prize_1']!.status, CashPrizeStatus.received);
      });

      test('ADV-3.2: Rejection of non-existent prize operation throws Exception', () {
        expect(
          () => engine.guardianConfirmCashPayment(
            prizeId: 'ghost_prize',
            guardianId: 'g_1',
            guardianName: 'Bố',
            isGuardian: true,
          ),
          throwsException,
        );

        expect(
          () => engine.confirmChildReceipt(
            prizeId: 'ghost_prize',
            childId: 'kid_a',
          ),
          throwsException,
        );
      });

      test('ADV-3.3: Cancelled prize cannot be paid by Guardian', () {
        final prize = engine.createPrize(
          prizeId: 'cancelled_prize',
          childId: 'kid_a',
          childName: 'Bé A',
          amount: 20000,
        );
        prize.status = CashPrizeStatus.cancelled;

        expect(
          () => engine.guardianConfirmCashPayment(
            prizeId: 'cancelled_prize',
            guardianId: 'g_1',
            guardianName: 'Bố',
            isGuardian: true,
          ),
          throwsStateError,
        );
      });

      test('ADV-3.4: VietQR payout stores bank reference securely', () {
        engine.createPrize(
          prizeId: 'qr_prize',
          childId: 'kid_b',
          childName: 'Bé B',
          amount: 150000,
        );

        engine.guardianConfirmVietQrTransfer(
          prizeId: 'qr_prize',
          guardianId: 'g_2',
          guardianName: 'Mẹ',
          bankRef: 'VQR-20261106-9999',
          isGuardian: true,
        );

        final p = engine.prizes['qr_prize']!;
        expect(p.paymentMethod, 'VIETQR');
        expect(p.bankRef, 'VQR-20261106-9999');
        expect(p.paidByName, 'Mẹ');
        expect(p.paidBy, 'g_2');
      });
    });
  });
}

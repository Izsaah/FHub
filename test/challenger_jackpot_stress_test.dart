import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';

void main() {
  group('Challenger M3 Stress Test: Sensor Jackpot Debounce & Cash Gift Handshake', () {
    // -------------------------------------------------------------------------
    // 1. ACCELEROMETER SENSOR SHAKE STRESS TEST
    // -------------------------------------------------------------------------
    group('1. Accelerometer Sensor Shake Adversarial & Stress Probing', () {
      late AccelerometerShakeEngine engine;

      setUp(() {
        engine = AccelerometerShakeEngine();
        engine.reset();
      });

      test('1.1 High-frequency sensor noise burst: 100 events within 500ms (g = 25.0, deltaG > 10.0)', () async {
        final t0 = DateTime(2026, 11, 6, 12, 0, 0);

        // 100 events spread evenly across 500ms (5ms intervals)
        // Physics: x=0, y=0, z=25.0 -> g = 25.0 > 15.0, deltaG = |25.0 - 9.81| = 15.19 > 10.0
        final results = <bool>[];
        for (int i = 0; i < 100; i++) {
          final eventTime = t0.add(Duration(milliseconds: i * 5)); // 0ms to 495ms
          final accepted = await engine.handleSensorEvent(
            x: 0.0,
            y: 0.0,
            z: 25.0,
            eventTime: eventTime,
          );
          results.add(accepted);
        }

        // Exact assertion: Exactly the 1st event is accepted; the remaining 99 are rejected
        expect(results.first, isTrue, reason: 'First sensor event at t0 should register a shake');
        expect(results.skip(1).every((r) => r == false), isTrue, reason: 'Subsequent 99 burst events within 500ms must be discarded');
        expect(engine.shakeCount, equals(1), reason: 'shakeCount must increment by EXACTLY 1 during burst');
        expect(engine.isProcessingShake, isFalse, reason: 'Mutex must be released after processing');
      });

      test('1.2 High-frequency sensor noise burst: 100 concurrent asynchronous events fired via Future.wait', () async {
        final t0 = DateTime(2026, 11, 6, 12, 0, 0);

        // Fire 100 events concurrently within a 500ms simulated window
        final futures = List.generate(100, (i) {
          final eventTime = t0.add(Duration(milliseconds: (i * 5) % 500));
          return engine.handleSensorEvent(
            x: 15.0,
            y: 15.0,
            z: 15.0, // g = sqrt(675) ~= 25.98 > 15.0, deltaG ~= 16.17 > 10.0
            eventTime: eventTime,
          );
        });

        final results = await Future.wait(futures);
        final acceptedCount = results.where((r) => r == true).length;

        expect(acceptedCount, equals(1), reason: 'Mutex lock and cooldown must ensure exactly 1 event succeeds');
        expect(engine.shakeCount, equals(1));
        expect(engine.isProcessingShake, isFalse);
      });

      test('1.3 Boundary timestamps: event at t = 0s, event at t = 2.999s (rejected), event at t = 3.001s (accepted, count = 2)', () async {
        final t0 = DateTime(2026, 11, 6, 12, 0, 0);

        // Event 1 at t = 0s
        final accepted1 = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 25.0,
          eventTime: t0,
        );
        expect(accepted1, isTrue, reason: 'Event at t=0s must be accepted');
        expect(engine.shakeCount, equals(1));

        // Event 2 at t = 2.999s (2999 milliseconds): strict rejection (< 3000ms cooldown)
        final accepted2 = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 25.0,
          eventTime: t0.add(const Duration(milliseconds: 2999)),
        );
        expect(accepted2, isFalse, reason: 'Event at t=2.999s must be rejected by 3.0s cooldown');
        expect(engine.shakeCount, equals(1), reason: 'shakeCount must remain 1 after boundary rejection');

        // Event 3 at t = 3.001s (3001 milliseconds): strict acceptance (> 3000ms cooldown)
        final accepted3 = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 25.0,
          eventTime: t0.add(const Duration(milliseconds: 3001)),
        );
        expect(accepted3, isTrue, reason: 'Event at t=3.001s must be accepted as cooldown has expired');
        expect(engine.shakeCount, equals(2), reason: 'shakeCount must increment to EXACTLY 2');

        // Event 4 at t = 5.999s (2998ms from 2nd shake): rejected
        final accepted4 = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 25.0,
          eventTime: t0.add(const Duration(milliseconds: 5999)),
        );
        expect(accepted4, isFalse, reason: 'Event at t=5.999s must be rejected (< 3000ms from 2nd shake)');
        expect(engine.shakeCount, equals(2));

        // Event 5 at t = 6.002s (3001ms from 2nd shake): accepted -> count = 3
        final accepted5 = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 25.0,
          eventTime: t0.add(const Duration(milliseconds: 6002)),
        );
        expect(accepted5, isTrue, reason: 'Event at t=6.002s must be accepted');
        expect(engine.shakeCount, equals(3));
      });

      test('1.4 Exact boundary at t = 3.000s (3000ms): difference is not < 3000ms, so accepted', () async {
        final t0 = DateTime(2026, 11, 6, 12, 0, 0);

        await engine.handleSensorEvent(x: 0.0, y: 0.0, z: 25.0, eventTime: t0);
        expect(engine.shakeCount, 1);

        // At exact 3000ms: difference is exactly Duration(milliseconds: 3000).
        // Since cooldown check is `diff < cooldown`, 3000ms is NOT < 3000ms -> accepted
        final acceptedExact = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 25.0,
          eventTime: t0.add(const Duration(milliseconds: 3000)),
        );
        expect(acceptedExact, isTrue);
        expect(engine.shakeCount, 2);
      });

      test('1.5 Sub-threshold vibration: g = 14.5 or deltaG = 4.0 must NOT register a shake', () async {
        // Case A: g = 14.5 (x=0, y=0, z=14.5 -> g = 14.5 <= 15.0, deltaG = |14.5 - 9.81| = 4.69)
        // Violates g > 15.0 requirement
        final acceptedA = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 14.5,
        );
        expect(acceptedA, isFalse, reason: 'Sub-threshold g = 14.5 <= 15.0 must be rejected');
        expect(engine.shakeCount, equals(0));

        // Case B: deltaG = 4.0 (x=0, y=0, z=13.81 -> g = 13.81 <= 15.0, deltaG = |13.81 - 9.81| = 4.0 <= 4.5)
        // Violates both g > 15.0 and deltaG > 4.5
        final acceptedB = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 13.81,
        );
        expect(acceptedB, isFalse, reason: 'Sub-threshold deltaG = 4.0 <= 4.5 must be rejected');
        expect(engine.shakeCount, equals(0));

        // Case C: Ambient resting table vibration (x=0.05, y=0.1, z=9.81 -> g ~= 9.81, deltaG ~= 0.001)
        final acceptedC = await engine.handleSensorEvent(
          x: 0.05,
          y: 0.1,
          z: 9.81,
        );
        expect(acceptedC, isFalse, reason: 'Resting desk vibration must be rejected');
        expect(engine.shakeCount, equals(0));

        // Case D: Gentle phone tilt (x=3.0, y=4.0, z=9.81 -> g ~= 11.01, deltaG ~= 1.20)
        final acceptedD = await engine.handleSensorEvent(
          x: 3.0,
          y: 4.0,
          z: 9.81,
        );
        expect(acceptedD, isFalse, reason: 'Gentle tilt must be rejected');
        expect(engine.shakeCount, equals(0));

        // Case E: Exact boundary threshold g = 15.0 (minG is 15.0, check is g <= minG)
        final acceptedE = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 15.0,
        );
        expect(acceptedE, isFalse, reason: 'Exact boundary g = 15.0 must be rejected (must be strictly > 15.0)');
        expect(engine.shakeCount, equals(0));
      });

      test('1.6 Inactive phase gate: events discarded when isShakingPhase == false', () async {
        engine.isShakingPhase = false;

        final accepted = await engine.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 30.0, // High acceleration
        );
        expect(accepted, isFalse, reason: 'Non-shaking phase must reject all accelerometer events');
        expect(engine.shakeCount, equals(0));
      });
    });

    // -------------------------------------------------------------------------
    // 2. CASH GIFT TWO-WAY HANDSHAKE ADVERSARIAL TEST
    // -------------------------------------------------------------------------
    group('2. Cash Gift Two-Way Handshake Adversarial Probing', () {
      late CashGiftHandshakeEngine engine;

      setUp(() {
        engine = CashGiftHandshakeEngine();
      });

      test('2.1 Attempt child receipt before guardian payout (WAITING_TRANSFER): must throw StateError', () {
        engine.createPrize(
          prizeId: 'prize_cash_adv_1',
          childId: 'child_minh',
          childName: 'Bé Minh',
          amount: 100000,
        );

        expect(
          () => engine.confirmChildReceipt(
            prizeId: 'prize_cash_adv_1',
            childId: 'child_minh',
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('chưa thực hiện thanh toán'),
          )),
          reason: 'Child confirming before guardian payout must be rejected with StateError',
        );

        final prize = engine.prizes['prize_cash_adv_1']!;
        expect(prize.status, equals(CashPrizeStatus.waitingTransfer));
        expect(prize.receivedAt, isNull);
      });

      test('2.2 Attempt confirmation by non-winning child: must throw StateError', () {
        engine.createPrize(
          prizeId: 'prize_cash_adv_2',
          childId: 'child_minh',
          childName: 'Bé Minh',
          amount: 200000,
        );

        // Guardian marks as PAID
        engine.guardianConfirmCashPayment(
          prizeId: 'prize_cash_adv_2',
          guardianId: 'guardian_grandpa',
          guardianName: 'Ông Nội',
          isGuardian: true,
        );

        // Impostor child attempts confirmation
        expect(
          () => engine.confirmChildReceipt(
            prizeId: 'prize_cash_adv_2',
            childId: 'child_impostor_999',
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Chỉ người nhận giải thưởng'),
          )),
          reason: 'Impostor child confirming receipt must be rejected with StateError',
        );

        final prize = engine.prizes['prize_cash_adv_2']!;
        expect(prize.status, equals(CashPrizeStatus.paid));
        expect(prize.receivedAt, isNull);
      });

      test('2.3 Non-guardian payout attempt: must throw StateError', () {
        engine.createPrize(
          prizeId: 'prize_cash_adv_3',
          childId: 'child_minh',
          childName: 'Bé Minh',
          amount: 50000,
        );

        expect(
          () => engine.guardianConfirmCashPayment(
            prizeId: 'prize_cash_adv_3',
            guardianId: 'child_impostor',
            guardianName: 'Bé Giả Mạo',
            isGuardian: false, // Not a guardian
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Chỉ Trưởng bối (Guardian)'),
          )),
          reason: 'Non-guardian cannot approve cash payout',
        );
      });

      test('2.4 Complete valid flow (WAITING_TRANSFER -> PAID -> RECEIVED)', () {
        final initialPrize = engine.createPrize(
          prizeId: 'prize_valid_flow',
          childId: 'child_an',
          childName: 'Bé An',
          amount: 150000,
          familyId: 'family_hanoi',
        );

        // Step 0: WAITING_TRANSFER
        expect(initialPrize.status, equals(CashPrizeStatus.waitingTransfer));
        expect(initialPrize.statusString, equals('WAITING_TRANSFER'));

        // Step 1: Guardian executes VietQR payout -> PAID
        engine.guardianConfirmVietQrTransfer(
          prizeId: 'prize_valid_flow',
          guardianId: 'guardian_father',
          guardianName: 'Bố Dũng',
          bankRef: 'VIETQR_REF_98765',
          isGuardian: true,
        );

        final paidPrize = engine.prizes['prize_valid_flow']!;
        expect(paidPrize.status, equals(CashPrizeStatus.paid));
        expect(paidPrize.statusString, equals('PAID'));
        expect(paidPrize.paymentMethod, equals('VIETQR'));
        expect(paidPrize.bankRef, equals('VIETQR_REF_98765'));
        expect(paidPrize.paidBy, equals('guardian_father'));
        expect(paidPrize.paidByName, equals('Bố Dũng'));
        expect(paidPrize.paidAt, isNotNull);
        expect(paidPrize.receivedAt, isNull);

        // Step 2: Child confirms receipt -> RECEIVED
        engine.confirmChildReceipt(
          prizeId: 'prize_valid_flow',
          childId: 'child_an',
        );

        final receivedPrize = engine.prizes['prize_valid_flow']!;
        expect(receivedPrize.status, equals(CashPrizeStatus.received));
        expect(receivedPrize.statusString, equals('RECEIVED'));
        expect(receivedPrize.receivedAt, isNotNull);
      });

      test('2.5 Repeat confirmation on RECEIVED prize: must be safely idempotent without error (10x taps)', () {
        engine.createPrize(
          prizeId: 'prize_idempotency_stress',
          childId: 'child_an',
          childName: 'Bé An',
          amount: 50000,
        );

        engine.guardianConfirmCashPayment(
          prizeId: 'prize_idempotency_stress',
          guardianId: 'guardian_mom',
          guardianName: 'Mẹ Thảo',
          isGuardian: true,
        );

        // Initial valid confirmation
        engine.confirmChildReceipt(
          prizeId: 'prize_idempotency_stress',
          childId: 'child_an',
        );

        final initialReceivedAt = engine.prizes['prize_idempotency_stress']!.receivedAt;
        expect(initialReceivedAt, isNotNull);

        // Rapid UI multi-taps (10 times)
        for (int i = 0; i < 10; i++) {
          expect(
            () => engine.confirmChildReceipt(
              prizeId: 'prize_idempotency_stress',
              childId: 'child_an',
            ),
            returnsNormally,
            reason: 'Repeated receipt confirmation must not throw an error',
          );
        }

        final finalPrize = engine.prizes['prize_idempotency_stress']!;
        expect(finalPrize.status, equals(CashPrizeStatus.received));
        expect(finalPrize.receivedAt, equals(initialReceivedAt), reason: 'receivedAt timestamp must be preserved identically');
      });

      test('2.6 Action on non-existent prize: must throw Exception', () {
        expect(
          () => engine.guardianConfirmCashPayment(
            prizeId: 'non_existent_prize',
            guardianId: 'g1',
            guardianName: 'Guardian',
            isGuardian: true,
          ),
          throwsA(isA<Exception>()),
        );

        expect(
          () => engine.confirmChildReceipt(
            prizeId: 'non_existent_prize',
            childId: 'c1',
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    // -------------------------------------------------------------------------
    // 3. SERVICE-LEVEL ADVERSARIAL INTEGRATION
    // -------------------------------------------------------------------------
    group('3. FamilyJackpotService High-Level Adversarial Integration', () {
      late FamilyJackpotService service;

      setUp(() {
        service = FamilyJackpotService.instance;
        service.accelerometerEngine.reset();
        service.cashGiftEngine.reset();
      });

      test('3.1 FamilyJackpotService handleSensorEvent respects 3.0s cooldown and mutex lock', () async {
        final t0 = DateTime(2026, 11, 6, 12, 0, 0);

        // Call 1 at t0 -> accepted by engine
        final r1 = await service.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 25.0,
          eventTime: t0,
        );
        expect(r1, isTrue);
        expect(service.shakeCount, equals(1));

        // Call 2 at t0 + 2000ms -> rejected by engine
        final r2 = await service.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 25.0,
          eventTime: t0.add(const Duration(milliseconds: 2000)),
        );
        expect(r2, isFalse);
        expect(service.shakeCount, equals(1));

        // Call 3 at t0 + 3100ms -> accepted by engine
        final r3 = await service.handleSensorEvent(
          x: 0.0,
          y: 0.0,
          z: 25.0,
          eventTime: t0.add(const Duration(milliseconds: 3100)),
        );
        expect(r3, isTrue);
        expect(service.shakeCount, equals(2));
      });

      test('3.2 FamilyJackpotService cash gift handshake end-to-end integration', () {
        final prize = service.createCashPrize(
          prizeId: 'svc_adv_prize_1',
          childId: 'kid_linh',
          childName: 'Bé Linh',
          amount: 500000,
          familyId: 'family_danang',
        );

        expect(prize.status, equals(CashPrizeStatus.waitingTransfer));

        // Attempt child confirmation early -> throws StateError
        expect(
          () => service.confirmChildReceipt(
            prizeId: 'svc_adv_prize_1',
            childId: 'kid_linh',
          ),
          throwsA(isA<StateError>()),
        );

        // Guardian pays via VietQR
        service.guardianConfirmVietQrTransfer(
          prizeId: 'svc_adv_prize_1',
          guardianId: 'grandma_hoa',
          guardianName: 'Bà Hoa',
          bankRef: 'MB_QR_778899',
          isGuardian: true,
        );

        expect(service.cashPrizes['svc_adv_prize_1']!.status, equals(CashPrizeStatus.paid));
        expect(service.cashPrizes['svc_adv_prize_1']!.bankRef, equals('MB_QR_778899'));

        // Child confirms
        service.childConfirmReceipt(
          prizeId: 'svc_adv_prize_1',
          childId: 'kid_linh',
        );

        expect(service.cashPrizes['svc_adv_prize_1']!.status, equals(CashPrizeStatus.received));

        // Re-confirm idempotent
        service.childConfirmReceipt(
          prizeId: 'svc_adv_prize_1',
          childId: 'kid_linh',
        );

        expect(service.cashPrizes['svc_adv_prize_1']!.status, equals(CashPrizeStatus.received));
      });
    });
  });
}

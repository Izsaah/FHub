import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';

void main() {
  group('FamilyJackpotService M3 - Sensor Debounce & Cash Gift Handshake', () {
    group('1. Accelerometer Shake Debounce Engine (3.0s cooldown & Mutex)', () {
      late AccelerometerShakeEngine engine;

      setUp(() {
        engine = AccelerometerShakeEngine();
        engine.reset();
      });

      test('1.1 Single shake meeting g > 15.0 AND deltaG > 4.5 is registered successfully', () async {
        // x=12, y=10, z=5 -> g = sqrt(144 + 100 + 25) = sqrt(269) ~= 16.40 > 15.0
        // deltaG = |16.40 - 9.81| = 6.59 > 4.5
        final accepted = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
        );

        expect(accepted, isTrue);
        expect(engine.shakeCount, 1);
        expect(engine.lastShakeTime, isNotNull);
        expect(engine.isProcessingShake, isFalse);
      });

      test('1.2 Sub-threshold gravity movement is discarded (g <= 15.0 or deltaG <= 4.5)', () async {
        // x=1, y=2, z=9.8 -> g ~= 10.05 <= 15.0, deltaG ~= 0.24 <= 4.5 (ambient table movement)
        final accepted = await engine.handleSensorEvent(
          x: 1.0,
          y: 2.0,
          z: 9.8,
        );

        expect(accepted, isFalse);
        expect(engine.shakeCount, 0);
        expect(engine.lastShakeTime, isNull);
      });

      test('1.3 Rapid shakes within 3.0s cooldown window are discarded', () async {
        final t0 = DateTime(2026, 11, 6, 10, 0, 0);

        // Shake 1 at t0 -> accepted
        final s1 = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0,
        );
        expect(s1, isTrue);
        expect(engine.shakeCount, 1);

        // Shake 2 at +500ms -> discarded by cooldown
        final s2 = await engine.handleSensorEvent(
          x: 14.0,
          y: 11.0,
          z: 6.0,
          eventTime: t0.add(const Duration(milliseconds: 500)),
        );
        expect(s2, isFalse);
        expect(engine.shakeCount, 1);

        // Shake 3 at +2000ms -> discarded by cooldown
        final s3 = await engine.handleSensorEvent(
          x: 13.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 2000)),
        );
        expect(s3, isFalse);
        expect(engine.shakeCount, 1);
      });

      test('1.4 Shake after 3.0s cooldown expires is accepted as 2nd shake', () async {
        final t0 = DateTime(2026, 11, 6, 10, 0, 0);

        await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0,
        );
        expect(engine.shakeCount, 1);

        // Shake at +3100ms (> 3000ms cooldown) -> accepted
        final s2 = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 3100)),
        );
        expect(s2, isTrue);
        expect(engine.shakeCount, 2);
      });

      test('1.5 Timing boundary: 2950ms is rejected; 3050ms is accepted', () async {
        final t0 = DateTime(2026, 11, 6, 10, 0, 0);

        await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0,
        );

        // Boundary: 2950ms (< 3000ms)
        final sBoundaryReject = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 2950)),
        );
        expect(sBoundaryReject, isFalse);
        expect(engine.shakeCount, 1);

        // Boundary: 3050ms (> 3000ms)
        final sBoundaryAccept = await engine.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
          eventTime: t0.add(const Duration(milliseconds: 3050)),
        );
        expect(sBoundaryAccept, isTrue);
        expect(engine.shakeCount, 2);
      });

      test('1.6 Mutex lock blocks concurrent re-entrant event loops', () async {
        final t0 = DateTime(2026, 11, 6, 10, 0, 0);

        // Fire 5 concurrent shakes at the exact same instant
        final results = await Future.wait([
          engine.handleSensorEvent(x: 12.0, y: 10.0, z: 5.0, eventTime: t0),
          engine.handleSensorEvent(x: 12.0, y: 10.0, z: 5.0, eventTime: t0),
          engine.handleSensorEvent(x: 12.0, y: 10.0, z: 5.0, eventTime: t0),
          engine.handleSensorEvent(x: 12.0, y: 10.0, z: 5.0, eventTime: t0),
          engine.handleSensorEvent(x: 12.0, y: 10.0, z: 5.0, eventTime: t0),
        ]);

        final acceptedCount = results.where((r) => r == true).length;
        expect(acceptedCount, 1);
        expect(engine.shakeCount, 1);
        expect(engine.isProcessingShake, isFalse);
      });

      test('1.7 Burst of 50 sensor events in 200ms yields exactly 1 registered shake', () async {
        final t0 = DateTime(2026, 11, 6, 10, 0, 0);

        for (int i = 0; i < 50; i++) {
          await engine.handleSensorEvent(
            x: 12.0 + (i % 3),
            y: 10.0,
            z: 5.0,
            eventTime: t0.add(Duration(milliseconds: i * 4)), // Total span 200ms
          );
        }

        expect(engine.shakeCount, 1);
      });

      test('1.8 When isShakingPhase == false, all sensor events are discarded', () async {
        engine.isShakingPhase = false;

        final accepted = await engine.handleSensorEvent(
          x: 20.0,
          y: 20.0,
          z: 20.0,
        );

        expect(accepted, isFalse);
        expect(engine.shakeCount, 0);
      });

      test('1.9 reset() clears shakeCount, lastShakeTime, and restores default state', () async {
        await engine.handleSensorEvent(x: 12.0, y: 10.0, z: 5.0);
        expect(engine.shakeCount, 1);
        expect(engine.lastShakeTime, isNotNull);

        engine.reset();
        expect(engine.shakeCount, 0);
        expect(engine.lastShakeTime, isNull);
        expect(engine.isProcessingShake, isFalse);
        expect(engine.isShakingPhase, isTrue);
      });
    });

    group('2. Real-World Cash Gift Two-Way Handshake Engine', () {
      late CashGiftHandshakeEngine engine;

      setUp(() {
        engine = CashGiftHandshakeEngine();
      });

      test('2.1 Prize starts in WAITING_TRANSFER state with pending payout details', () {
        final prize = engine.createPrize(
          prizeId: 'prize_lixi_100k',
          childId: 'child_hung',
          childName: 'Bé Hùng',
          amount: 100000,
          familyId: 'fam_1',
        );

        expect(prize.id, 'prize_lixi_100k');
        expect(prize.childId, 'child_hung');
        expect(prize.childName, 'Bé Hùng');
        expect(prize.amount, 100000);
        expect(prize.status, CashPrizeStatus.waitingTransfer);
        expect(prize.statusString, 'WAITING_TRANSFER');
        expect(prize.paidAt, isNull);
        expect(prize.receivedAt, isNull);
        expect(prize.paidBy, isNull);
        expect(prize.paymentMethod, isNull);
      });

      test('2.2 Guardian confirms CASH payment -> transitions to PAID', () {
        engine.createPrize(
          prizeId: 'prize_cash_50k',
          childId: 'child_mai',
          childName: 'Bé Mai',
          amount: 50000,
        );

        engine.guardianConfirmCashPayment(
          prizeId: 'prize_cash_50k',
          guardianId: 'guardian_grandpa',
          guardianName: 'Ông Nội',
          isGuardian: true,
        );

        final prize = engine.prizes['prize_cash_50k']!;
        expect(prize.status, CashPrizeStatus.paid);
        expect(prize.statusString, 'PAID');
        expect(prize.paymentMethod, 'CASH');
        expect(prize.paidBy, 'guardian_grandpa');
        expect(prize.paidByName, 'Ông Nội');
        expect(prize.paidAt, isNotNull);
        expect(prize.receivedAt, isNull);
      });

      test('2.3 Guardian confirms VIETQR payment -> transitions to PAID with bankRef', () {
        engine.createPrize(
          prizeId: 'prize_qr_200k',
          childId: 'child_hung',
          childName: 'Bé Hùng',
          amount: 200000,
        );

        engine.guardianConfirmVietQrTransfer(
          prizeId: 'prize_qr_200k',
          guardianId: 'guardian_mom',
          guardianName: 'Mẹ Lan',
          bankRef: 'FT261106MBB001',
          isGuardian: true,
        );

        final prize = engine.prizes['prize_qr_200k']!;
        expect(prize.status, CashPrizeStatus.paid);
        expect(prize.statusString, 'PAID');
        expect(prize.paymentMethod, 'VIETQR');
        expect(prize.paidBy, 'guardian_mom');
        expect(prize.bankRef, 'FT261106MBB001');
        expect(prize.paidAt, isNotNull);
      });

      test('2.4 Child confirms receipt after payout -> transitions to RECEIVED', () {
        engine.createPrize(
          prizeId: 'prize_handshake_flow',
          childId: 'child_hung',
          childName: 'Bé Hùng',
          amount: 50000,
        );

        engine.guardianConfirmCashPayment(
          prizeId: 'prize_handshake_flow',
          guardianId: 'guardian_dad',
          guardianName: 'Bố Tuấn',
          isGuardian: true,
        );

        // Child confirms receipt
        engine.confirmChildReceipt(
          prizeId: 'prize_handshake_flow',
          childId: 'child_hung',
        );

        final prize = engine.prizes['prize_handshake_flow']!;
        expect(prize.status, CashPrizeStatus.received);
        expect(prize.statusString, 'RECEIVED');
        expect(prize.receivedAt, isNotNull);
      });

      test('2.5 Invariant: Child CANNOT confirm receipt when status is WAITING_TRANSFER', () {
        engine.createPrize(
          prizeId: 'prize_unpaid',
          childId: 'child_hung',
          childName: 'Bé Hùng',
          amount: 50000,
        );

        expect(
          () => engine.confirmChildReceipt(
            prizeId: 'prize_unpaid',
            childId: 'child_hung',
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('chưa thực hiện thanh toán'),
          )),
        );
      });

      test('2.6 Invariant: Non-guardian CANNOT mark payout as PAID', () {
        engine.createPrize(
          prizeId: 'prize_unauthorized',
          childId: 'child_hung',
          childName: 'Bé Hùng',
          amount: 50000,
        );

        expect(
          () => engine.guardianConfirmCashPayment(
            prizeId: 'prize_unauthorized',
            guardianId: 'child_mai',
            guardianName: 'Bé Mai',
            isGuardian: false, // Child attempting to forge payment
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Chỉ Trưởng bối (Guardian)'),
          )),
        );
      });

      test('2.7 Invariant: Wrong child recipient CANNOT confirm receipt', () {
        engine.createPrize(
          prizeId: 'prize_wrong_child',
          childId: 'child_hung',
          childName: 'Bé Hùng',
          amount: 50000,
        );

        engine.guardianConfirmCashPayment(
          prizeId: 'prize_wrong_child',
          guardianId: 'guardian_dad',
          guardianName: 'Bố Tuấn',
          isGuardian: true,
        );

        expect(
          () => engine.confirmChildReceipt(
            prizeId: 'prize_wrong_child',
            childId: 'other_kid_99', // Different child
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Chỉ người nhận giải thưởng'),
          )),
        );
      });

      test('2.8 Idempotency: Re-confirming already RECEIVED prize is a safe no-op', () {
        engine.createPrize(
          prizeId: 'prize_idempotent',
          childId: 'child_hung',
          childName: 'Bé Hùng',
          amount: 50000,
        );

        engine.guardianConfirmCashPayment(
          prizeId: 'prize_idempotent',
          guardianId: 'guardian_dad',
          guardianName: 'Bố Tuấn',
          isGuardian: true,
        );

        engine.confirmChildReceipt(
          prizeId: 'prize_idempotent',
          childId: 'child_hung',
        );

        final firstReceivedAt = engine.prizes['prize_idempotent']!.receivedAt;
        expect(firstReceivedAt, isNotNull);

        // Tap [Đã nhận tiền] again
        engine.confirmChildReceipt(
          prizeId: 'prize_idempotent',
          childId: 'child_hung',
        );

        // Preserves original receivedAt timestamp
        expect(engine.prizes['prize_idempotent']!.receivedAt, firstReceivedAt);
        expect(engine.prizes['prize_idempotent']!.status, CashPrizeStatus.received);
      });

      test('2.9 Model serialization: toMap and fromMap preserve all fields and status formats', () {
        final original = CashPrizeModel(
          id: 'p_ser_1',
          childId: 'c1',
          childName: 'Bé Na',
          amount: 75000,
          status: CashPrizeStatus.paid,
          paymentMethod: 'VIETQR',
          paidBy: 'g1',
          paidByName: 'Mẹ Lan',
          bankRef: 'REF123',
          paidAt: DateTime(2026, 11, 6, 14, 0, 0),
          familyId: 'fam_test',
        );

        final map = original.toMap();
        expect(map['id'], 'p_ser_1');
        expect(map['amount'], 75000);
        expect(map['status'], 'paid');
        expect(map['statusCode'], 'PAID');
        expect(map['paymentMethod'], 'VIETQR');

        final restored = CashPrizeModel.fromMap('p_ser_1', map);
        expect(restored.id, original.id);
        expect(restored.childName, original.childName);
        expect(restored.amount, original.amount);
        expect(restored.status, CashPrizeStatus.paid);
        expect(restored.paymentMethod, 'VIETQR');
        expect(restored.bankRef, 'REF123');
      });
    });

    group('3. FamilyJackpotService Integration (Service Methods & Debounce Integration)', () {
      late FamilyJackpotService service;

      setUp(() {
        service = FamilyJackpotService.instance;
        service.accelerometerEngine.reset();
        service.cashGiftEngine.reset();
      });

      test('3.1 FamilyJackpotService delegates sensor events to AccelerometerShakeEngine', () async {
        final accepted = await service.handleSensorEvent(
          x: 12.0,
          y: 10.0,
          z: 5.0,
        );

        expect(accepted, isTrue);
        expect(service.shakeCount, 1);
        expect(service.lastShakeTime, isNotNull);
        expect(service.isProcessingShake, isFalse);
      });

      test('3.2 FamilyJackpotService exposes full Cash Gift Handshake lifecycle', () {
        final prize = service.createCashPrize(
          prizeId: 'svc_prize_1',
          childId: 'child_tom',
          childName: 'Bé Tom',
          amount: 25000,
          familyId: 'fam_1',
        );

        expect(service.cashPrizes.containsKey('svc_prize_1'), isTrue);
        expect(prize.status, CashPrizeStatus.waitingTransfer);

        service.guardianConfirmCashPayment(
          prizeId: 'svc_prize_1',
          guardianId: 'gp_1',
          guardianName: 'Bà Ngoại',
          isGuardian: true,
        );
        expect(service.cashPrizes['svc_prize_1']!.status, CashPrizeStatus.paid);

        service.confirmChildReceipt(
          prizeId: 'svc_prize_1',
          childId: 'child_tom',
        );
        expect(service.cashPrizes['svc_prize_1']!.status, CashPrizeStatus.received);
      });
    });
  });
}

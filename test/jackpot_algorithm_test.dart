import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/services/jackpot_algorithm.dart';

void main() {
  group('JackpotAlgorithm Comprehensive Unit Tests', () {
    test('1. Solo shaker (1 nguoi lac, 2 nguoi con lai 0 lac) -> Nguoi lac 100% nhan Giai Nhat', () {
      final participants = ['user_active', 'user_parent_1', 'user_parent_2'];
      final shakes = {
        'user_active': 25,
        'user_parent_1': 0,
        'user_parent_2': 0,
      };
      const totalPot = 200000;

      // Run multiple times to verify 100% deterministic guarantee
      for (int i = 0; i < 20; i++) {
        final result = JackpotAlgorithm.calculate(
          totalAmount: totalPot,
          shakeCounts: shakes,
          participantIds: participants,
        );

        // Nguoi lac duy nhat phai la Giai Nhat
        expect(result.firstPrizeWinnerId, equals('user_active'));
        expect(result.topShakerId, equals('user_active'));
        expect(result.isTopShakerUnlucky, isFalse);

        // Tong tien trao thuong phai bang 100% tong hu (200.000)
        final totalWon = result.prizes.values.fold<int>(0, (sum, val) => sum + val);
        expect(totalWon, equals(totalPot));

        // Nguoi lac phai nhan nhieu tien nhat
        final activePrize = result.prizes['user_active']!;
        expect(activePrize, greaterThan(result.prizes['user_parent_1']!));
        expect(activePrize, greaterThan(result.prizes['user_parent_2']!));
      }
    });

    test('2. Multi-shakers: Active shakers luon dung truoc idle shakers (0 lac)', () {
      final participants = ['shaker_A', 'shaker_B', 'idle_C', 'idle_D'];
      final shakes = {
        'shaker_A': 50,
        'shaker_B': 30,
        'idle_C': 0,
        'idle_D': 0,
      };
      const totalPot = 500000;

      for (int i = 0; i < 20; i++) {
        final result = JackpotAlgorithm.calculate(
          totalAmount: totalPot,
          shakeCounts: shakes,
          participantIds: participants,
        );

        // Giai nhat phai thuoc ve A hoac B, KHONG BAO GIO la C hoac D
        expect(['shaker_A', 'shaker_B'].contains(result.firstPrizeWinnerId), isTrue);

        // Tong tien phai bang chinh xac 100%
        final totalWon = result.prizes.values.fold<int>(0, (sum, val) => sum + val);
        expect(totalWon, equals(totalPot));

        // Nguoi khong lac van nhan duoc phan chia du theo nguyen tac ca nha co qua
        expect(result.prizes['idle_C'], greaterThanOrEqualTo(0));
        expect(result.prizes['idle_D'], greaterThanOrEqualTo(0));
      }
    });

    test('3. Ý Trời Dramatic Event: Top shaker bi nguoi lac it hon giat mat Giai Nhat', () {
      // Top shaker co 40 lac, Shaker B co 10 lac
      // Run loop to encounter Ý Trời
      bool sawYTroi = false;
      const totalPot = 100000;

      for (int i = 0; i < 100; i++) {
        final result = JackpotAlgorithm.calculate(
          totalAmount: totalPot,
          shakeCounts: {'shaker_A': 40, 'shaker_B': 10},
          participantIds: ['shaker_A', 'shaker_B'],
        );

        if (result.firstPrizeWinnerId == 'shaker_B') {
          sawYTroi = true;
          expect(result.topShakerId, equals('shaker_A'));
          expect(result.isTopShakerUnlucky, isTrue);
          break;
        }
      }
      // Voi ti le 10 / 50 = 20%, trong 100 lan test chac chan gap it nhat 1 lan Y Troi
      expect(sawYTroi, isTrue);
    });

    test('4. Khi tat ca deu 0 lac: Chia deu / bac thang an toan, 100% pot', () {
      final participants = ['user_1', 'user_2', 'user_3'];
      final shakes = {'user_1': 0, 'user_2': 0, 'user_3': 0};
      const totalPot = 300000;

      final result = JackpotAlgorithm.calculate(
        totalAmount: totalPot,
        shakeCounts: shakes,
        participantIds: participants,
      );

      final totalWon = result.prizes.values.fold<int>(0, (sum, val) => sum + val);
      expect(totalWon, equals(totalPot));
      expect(result.topShakerId, isNull);
      expect(result.isTopShakerUnlucky, isFalse);
    });

    test('5. Hu 0 dong hoac khong co thanh vien: Tra ve rong an toan', () {
      final resultZeroPot = JackpotAlgorithm.calculate(
        totalAmount: 0,
        shakeCounts: {'u1': 10},
        participantIds: ['u1'],
      );
      expect(resultZeroPot.prizes.isEmpty, isTrue);

      final resultNoParticipants = JackpotAlgorithm.calculate(
        totalAmount: 100000,
        shakeCounts: {},
        participantIds: [],
      );
      expect(resultNoParticipants.prizes.isEmpty, isTrue);
    });
  });
}

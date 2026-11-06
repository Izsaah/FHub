import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/services/jackpot_algorithm.dart';

void main() {
  group('JackpotAlgorithm Comprehensive Unit Tests', () {
    test('1. Solo shaker (1 người lắc, 2 người còn lại 0 lắc) -> Người lắc nhận trọn 100% quỹ Hũ, người 0 lắc nhận 0đ', () {
      final participants = ['user_active', 'user_parent_1', 'user_parent_2'];
      final shakes = {
        'user_active': 25,
        'user_parent_1': 0,
        'user_parent_2': 0,
      };
      const totalPot = 200000;

      for (int i = 0; i < 20; i++) {
        final result = JackpotAlgorithm.calculate(
          totalAmount: totalPot,
          shakeCounts: shakes,
          participantIds: participants,
        );

        // Người lắc duy nhất phải là Giải Nhất
        expect(result.firstPrizeWinnerId, equals('user_active'));
        expect(result.topShakerId, equals('user_active'));
        expect(result.isTopShakerUnlucky, isFalse);

        // Người lắc duy nhất nhận trọn 100% quỹ hũ (200.000 đ)
        expect(result.prizes['user_active'], equals(totalPot));

        // 2 người không lắc nhận 0 đ
        expect(result.prizes['user_parent_1'] ?? 0, equals(0));
        expect(result.prizes['user_parent_2'] ?? 0, equals(0));

        // Tổng tiền trao thưởng đúng bằng 100% tổng hũ
        final totalWon = result.prizes.values.fold<int>(0, (sum, val) => sum + val);
        expect(totalWon, equals(totalPot));
      }
    });

    test('2. Multi-shakers: Chỉ những người CÓ LẮC mới chia nhau quỹ hũ, người 0 lần lắc nhận 0đ', () {
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

        // Giải nhất phải thuộc về A hoặc B, KHÔNG BAO GIỜ là C hoặc D
        expect(['shaker_A', 'shaker_B'].contains(result.firstPrizeWinnerId), isTrue);

        // Người không lắc nhận 0đ (không có trong map prizes)
        expect(result.prizes['idle_C'] ?? 0, equals(0));
        expect(result.prizes['idle_D'] ?? 0, equals(0));

        // Tổng tiền chia giữa A và B phải đúng bằng 100% tổng quỹ (500.000)
        final totalWon = result.prizes.values.fold<int>(0, (sum, val) => sum + val);
        expect(totalWon, equals(totalPot));
      }
    });

    test('3. Ý Trời Dramatic Event: Top shaker bị người lắc ít hơn giật mất Giải Nhất', () {
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
      expect(sawYTroi, isTrue);
    });

    test('4. Khi tất cả đều 0 lần lắc: Trả về prizes rỗng (hũ bảo toàn để chơi lại)', () {
      final participants = ['user_1', 'user_2', 'user_3'];
      final shakes = {'user_1': 0, 'user_2': 0, 'user_3': 0};
      const totalPot = 300000;

      final result = JackpotAlgorithm.calculate(
        totalAmount: totalPot,
        shakeCounts: shakes,
        participantIds: participants,
      );

      expect(result.prizes.isEmpty, isTrue);
      expect(result.topShakerId, isNull);
      expect(result.isTopShakerUnlucky, isFalse);
    });

    test('5. Hũ 0 đồng hoặc không có thành viên: Trả về rỗng an toàn', () {
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

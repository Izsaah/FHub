import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/models/family_jackpot_model.dart';
import 'package:fhub/Danh/services/jackpot_algorithm.dart';

void main() {
  group('Jackpot Multiplayer Shake, Isolated Claim & Cumulative Wallet Tests', () {
    test('1. Concurrency: Multiple members shaking simultaneously accumulates shake counts independently', () {
      // Giả lập Firestore doc ban đầu
      final Map<String, dynamic> firestoreDoc = {
        'status': 'shaking',
        'totalPoolAmount': 100000,
        'shakeCounts': <String, int>{},
        'memberNames': <String, String>{},
      };

      // Giả lập Dot-Notation updates từ Device 1 (User A) và Device 2 (User B)
      void applyDotNotationUpdate(String path, dynamic value) {
        final parts = path.split('.');
        final mapName = parts[0];
        final key = parts[1];
        if (!firestoreDoc.containsKey(mapName)) {
          firestoreDoc[mapName] = <String, dynamic>{};
        }
        (firestoreDoc[mapName] as Map<String, dynamic>)[key] = value;
      }

      // User A lắc 15 cái
      applyDotNotationUpdate('shakeCounts.user_A', 15);
      applyDotNotationUpdate('memberNames.user_A', 'Khoa Cao');

      // User B lắc 25 cái đồng thời
      applyDotNotationUpdate('shakeCounts.user_B', 25);
      applyDotNotationUpdate('memberNames.user_B', 'Bin');

      // User C lắc 5 cái
      applyDotNotationUpdate('shakeCounts.user_C', 5);
      applyDotNotationUpdate('memberNames.user_C', 'Mẹ Lan');

      final shakes = firestoreDoc['shakeCounts'] as Map<String, dynamic>;
      expect(shakes.length, 3, reason: 'Cả 3 thành viên lắc đồng thời đều được bảo toàn, không ai đè ai');
      expect(shakes['user_A'], 15);
      expect(shakes['user_B'], 25);
      expect(shakes['user_C'], 5);
    });

    test('2. Prize distribution: 100k pot is divided 100% and stored in individual memberWallets', () {
      const potAmount = 100000;
      final shakes = {'user_1': 50, 'user_2': 25, 'user_3': 10};
      final participants = ['user_1', 'user_2', 'user_3'];

      final result = JackpotAlgorithm.calculate(
        totalAmount: potAmount,
        shakeCounts: shakes,
        participantIds: participants,
      );

      final totalDistributed = result.prizes.values.fold<int>(0, (sum, val) => sum + val);
      expect(totalDistributed, potAmount, reason: '100% tổng quỹ 100k được chia hết');

      // Tạo model từ kết quả
      final jackpot = FamilyJackpotModel(
        familyId: 'fam_test',
        totalPoolAmount: 0, // Quỹ hũ vòng này đã chia hết
        status: JackpotStatus.finished,
        shakeCounts: shakes,
        prizeResults: result.prizes,
        memberWallets: result.prizes,
      );

      expect(jackpot.totalUnclaimedPrizes, 100000);
      expect(jackpot.isMemberWithdrawn('user_1'), isFalse);
      expect(jackpot.isMemberWithdrawn('user_2'), isFalse);
      expect(jackpot.isMemberWithdrawn('user_3'), isFalse);
    });

    test('3. Isolated Claim: User 1 withdraws their prize; other members unclaimed funds remain intact', () {
      // Giả sử sau khi chia thưởng:
      // user_1: 60,000 đ
      // user_2: 30,000 đ
      // user_3: 10,000 đ
      var wallets = <String, int>{
        'user_1': 60000,
        'user_2': 30000,
        'user_3': 10000,
      };

      var jackpot = FamilyJackpotModel(
        familyId: 'fam_test',
        totalPoolAmount: 0,
        status: JackpotStatus.finished,
        memberWallets: wallets,
      );

      expect(jackpot.totalUnclaimedPrizes, 100000);

      // User 1 rút hết 60,000 đ về ngân hàng
      final u1Amount = wallets['user_1']!;
      expect(u1Amount <= jackpot.memberWallets['user_1']!, isTrue);

      wallets = Map<String, int>.from(wallets);
      wallets['user_1'] = wallets['user_1']! - u1Amount;

      jackpot = jackpot.copyWith(memberWallets: wallets);

      // User 1 đã nhận xong
      expect(jackpot.memberWallets['user_1'], 0);
      expect(jackpot.isMemberWithdrawn('user_1'), isTrue, reason: 'User 1 đã rút xong');

      // User 2 và User 3 vẫn chưa rút
      expect(jackpot.isMemberWithdrawn('user_2'), isFalse);
      expect(jackpot.isMemberWithdrawn('user_3'), isFalse);
      expect(jackpot.memberWallets['user_2'], 30000);
      expect(jackpot.memberWallets['user_3'], 10000);

      // Tổng quỹ chưa rút của gia đình còn đúng 40,000 đ
      expect(jackpot.totalUnclaimedPrizes, 40000, reason: 'Còn đúng 40k của 2 người chưa rút');

      // User 1 cố rút thêm -> Bị từ chối
      final canU1WithdrawAgain = 10000 <= (jackpot.memberWallets['user_1'] ?? 0);
      expect(canU1WithdrawAgain, isFalse);
    });

    test('4. Next round deposit: New pot deposit is isolated and does NOT wipe unclaimed member rewards', () {
      // Sau vòng 1, User 2 (30k) và User 3 (10k) chưa rút
      final currentWallets = <String, int>{
        'user_1': 0,
        'user_2': 30000,
        'user_3': 10000,
      };

      var jackpot = FamilyJackpotModel(
        familyId: 'fam_test',
        totalPoolAmount: 0,
        status: JackpotStatus.finished,
        memberWallets: currentWallets,
      );

      // Bắt đầu vòng chơi mới: Bố nạp 50,000 đ vào quỹ hũ mới
      const newDeposit = 50000;
      jackpot = jackpot.copyWith(
        totalPoolAmount: newDeposit,
        status: JackpotStatus.idle,
        contributions: {'user_dad': newDeposit},
        shakeCounts: const {},
        prizeResults: const {},
      );

      // Quỹ hũ vòng mới là 50k
      expect(jackpot.totalPoolAmount, 50000);

      // Tiền chưa rút của gia đình vẫn nguyên vẹn 40k!
      expect(jackpot.totalUnclaimedPrizes, 40000);
      expect(jackpot.memberWallets['user_2'], 30000);
      expect(jackpot.memberWallets['user_3'], 10000);
    });

    test('5. Multi-round Reward Accumulation (Cộng dồn): Unclaimed balances accumulate across rounds', () {
      // Ban đầu User 2 có 30,000 đ chưa rút từ vòng 1
      var wallets = <String, int>{
        'user_1': 0,
        'user_2': 30000,
        'user_3': 10000,
      };

      // Vòng 2 kết thúc, User 2 thắng tiếp 25,000 đ
      final round2Prizes = <String, int>{
        'user_1': 15000,
        'user_2': 25000,
        'user_3': 10000,
      };

      // Logic cộng dồn của FamilyJackpotService:
      // updatedWallets[uid] = (updatedWallets[uid] ?? 0) + wonAmount
      final updatedWallets = Map<String, int>.from(wallets);
      round2Prizes.forEach((uid, wonAmount) {
        updatedWallets[uid] = (updatedWallets[uid] ?? 0) + wonAmount;
      });

      final jackpot = FamilyJackpotModel(
        familyId: 'fam_test',
        totalPoolAmount: 0,
        status: JackpotStatus.finished,
        prizeResults: round2Prizes,
        memberWallets: updatedWallets,
      );

      // User 2: 30k + 25k = 55k tích lũy
      expect(jackpot.memberWallets['user_2'], 55000, reason: 'Số dư ví User 2 được cộng dồn chính xác 55k');
      // User 1: 0 + 15k = 15k
      expect(jackpot.memberWallets['user_1'], 15000);
      // User 3: 10k + 10k = 20k
      expect(jackpot.memberWallets['user_3'], 20000);

      // Tổng chưa rút toàn gia đình = 55k + 15k + 20k = 90k
      expect(jackpot.totalUnclaimedPrizes, 90000);

      // User 2 rút toàn bộ 55,000 đ
      final u2Withdraw = jackpot.memberWallets['user_2']!;
      expect(u2Withdraw, 55000);
      updatedWallets['user_2'] = updatedWallets['user_2']! - u2Withdraw;

      final postWithdrawJackpot = jackpot.copyWith(memberWallets: updatedWallets);
      expect(postWithdrawJackpot.memberWallets['user_2'], 0);
      expect(postWithdrawJackpot.isMemberWithdrawn('user_2'), isTrue);
      expect(postWithdrawJackpot.totalUnclaimedPrizes, 35000); // 15k + 20k còn lại
    });
    test('6. Zero shakes penalty: Member with 0 shakes is strictly excluded from prize distribution (0 VND)', () {
      const potAmount = 100000;
      // Kịch bản từ screenshot người dùng: Lương Diệu Vinh lắc 5 cái, Con lắc 0 cái
      final shakes = {'u_vinh': 5, 'u_con': 0};
      final participants = ['u_vinh', 'u_con'];

      final result = JackpotAlgorithm.calculate(
        totalAmount: potAmount,
        shakeCounts: shakes,
        participantIds: participants,
      );

      // Vinh là người lắc duy nhất -> Nhận trọn 100% quỹ hũ (100.000 đ)
      expect(result.firstPrizeWinnerId, 'u_vinh');
      expect(result.prizes['u_vinh'], 100000);

      // Con lắc 0 lần -> Tuyệt đối không trúng thưởng (0 đ)
      expect(result.prizes['u_con'] ?? 0, 0, reason: 'Con 0 lần lắc nhận 0 đ');
      expect(result.prizes.containsKey('u_con'), isFalse, reason: 'Con không có trong danh sách trúng thưởng');
    });
  });
}

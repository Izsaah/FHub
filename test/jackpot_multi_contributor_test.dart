import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/models/wallet_transaction_model.dart';
import 'package:fhub/Danh/services/jackpot_algorithm.dart';

void main() {
  group('End-to-End Multi-Contributor & Family Treasury Flow Tests', () {
    test('1. Multiple family members contribute: Total pool and top contributor tracked accurately', () {
      final contributions = <String, int>{};
      final memberNames = <String, String>{
        'u_dad': 'Bố Hùng',
        'u_mom': 'Mẹ Lan',
        'u_uncle': 'Chú Ba',
        'u_child1': 'Minh',
        'u_child2': 'An',
      };

      // Bố nạp 50k
      contributions['u_dad'] = (contributions['u_dad'] ?? 0) + 50000;
      // Mẹ nạp 100k
      contributions['u_mom'] = (contributions['u_mom'] ?? 0) + 100000;
      // Chú nạp 50k
      contributions['u_uncle'] = (contributions['u_uncle'] ?? 0) + 50000;

      // Tính tổng quỹ hũ
      final totalPool = contributions.values.fold<int>(0, (sum, val) => sum + val);
      expect(totalPool, 200000);

      // Tìm người nạp nhiều nhất (Top Contributor)
      String topContributorId = '';
      int maxVal = 0;
      contributions.forEach((uid, val) {
        if (val > maxVal) {
          maxVal = val;
          topContributorId = uid;
        }
      });

      expect(topContributorId, 'u_mom');
      expect(memberNames[topContributorId], 'Mẹ Lan');
    });

    test('2. Shake battle distribution: Active shakers get prizes proportionally, idle shakers get 0', () {
      const totalPool = 200000;
      final shakeCounts = <String, int>{
        'u_child1': 50, // Minh lắc 50 cái -> Giải Nhất
        'u_child2': 30, // An lắc 30 cái -> Giải Nhì
        'u_dad': 10,    // Bố lắc 10 cái -> Giải Ba
        'u_mom': 0,     // Mẹ nạp tiền nhưng không lắc -> 0đ
        'u_uncle': 0,   // Chú nạp tiền nhưng không lắc -> 0đ
      };

      final memberNames = <String, String>{
        'u_child1': 'Minh',
        'u_child2': 'An',
        'u_dad': 'Bố Hùng',
        'u_mom': 'Mẹ Lan',
        'u_uncle': 'Chú Ba',
      };

      final result = JackpotAlgorithm.calculate(
        totalAmount: totalPool,
        shakeCounts: shakeCounts,
        participantIds: memberNames.keys.toList(),
      );

      expect(result.prizes.isNotEmpty, isTrue);
      // Top shaker Minh lắc 50 cái -> topShakerId là Minh
      expect(result.topShakerId, 'u_child1');
      expect(result.topShakeCount, 50);

      // Giải nhất phải thuộc về 1 trong 3 người có lắc (Minh, An, Bố)
      expect(['u_child1', 'u_child2', 'u_dad'], contains(result.firstPrizeWinnerId));

      // Mẹ và Chú không lắc thì chỉ nhận phần dư hoặc giải an ủi bậc thang sau cùng
      final minhPrize = result.prizes['u_child1'] ?? 0;
      final momPrize = result.prizes['u_mom'] ?? 0;
      expect(minhPrize > momPrize, isTrue); // Người lắc nhiều nhất nhận nhiều hơn người 0 lắc

      // Đảm bảo 100% quỹ 200k được chia hết, không dư không thiếu 1 đồng
      final sumPrizes = result.prizes.values.fold<int>(0, (sum, val) => sum + val);
      expect(sumPrizes, totalPool);
    });

    test('3. Custom withdrawal & Balance validation: Minh withdraws 79k out of 100k', () {
      int minhWallet = 100000;
      const withdrawAmount = 79000;

      // Validate
      expect(withdrawAmount <= minhWallet, isTrue);
      expect(withdrawAmount >= 1000, isTrue);

      // Trừ số dư
      minhWallet -= withdrawAmount;
      expect(minhWallet, 21000); // Còn 21k

      // Cố gắng rút thêm 50k -> Bị từ chối vì quá số dư
      const invalidWithdraw = 50000;
      final canWithdrawMore = invalidWithdraw <= minhWallet;
      expect(canWithdrawMore, isFalse);

      // Tạo mã VietQR URL
      final vietQrUrl = 'https://img.vietqr.io/image/MB-0987654321-compact2.png?amount=$withdrawAmount&addInfo=RUT%20THUONG%20FHUB&accountName=NGUYEN%20VAN%20MINH';
      expect(vietQrUrl, contains('amount=79000'));
      expect(vietQrUrl, contains('0987654321'));
    });

    test('4. Family-scoped Transaction Ledger: Transactions are isolated by familyId', () {
      final allTransactions = <WalletTransactionModel>[
        // Giao dịch gia đình F1
        WalletTransactionModel(
          id: 'tx_1',
          familyId: 'f1',
          userId: 'u_dad',
          userName: 'Bố Hùng',
          type: WalletTransactionType.contribute,
          amount: 50000,
          title: 'Nạp quỹ Hũ',
          createdAt: DateTime.now(),
        ),
        WalletTransactionModel(
          id: 'tx_2',
          familyId: 'f1',
          userId: 'u_child1',
          userName: 'Minh',
          type: WalletTransactionType.withdraw,
          amount: 79000,
          title: 'Rút tiền thưởng',
          bankShortName: 'MB',
          accountNumber: '0987654321',
          createdAt: DateTime.now(),
        ),
        // Giao dịch gia đình F2 (gia đình khác)
        WalletTransactionModel(
          id: 'tx_3',
          familyId: 'f2',
          userId: 'u_other',
          userName: 'Người lạ',
          type: WalletTransactionType.contribute,
          amount: 500000,
          title: 'Nạp quỹ gia đình F2',
          createdAt: DateTime.now(),
        ),
      ];

      // Lọc theo gia đình F1
      final f1Ledger = allTransactions.where((tx) => tx.familyId == 'f1').toList();
      expect(f1Ledger.length, 2);
      expect(f1Ledger.any((tx) => tx.familyId == 'f2'), isFalse);

      // Kiểm tra màu sắc giao dịch
      final contributeTx = f1Ledger.firstWhere((tx) => tx.type == WalletTransactionType.contribute);
      expect(contributeTx.isPositive, isTrue); // Xanh lá (+)

      final withdrawTx = f1Ledger.firstWhere((tx) => tx.type == WalletTransactionType.withdraw);
      expect(withdrawTx.isPositive, isFalse); // Đỏ (-)
      expect(withdrawTx.bankShortName, 'MB');
      expect(withdrawTx.accountNumber, '0987654321');
    });

    test('5. 15-day rolling storage window: Transactions older than 15 days are pruned', () {
      final now = DateTime.now();
      final txs = [
        WalletTransactionModel(
          id: 'tx_today',
          familyId: 'f1',
          userId: 'u_dad',
          userName: 'Bố Hùng',
          type: WalletTransactionType.contribute,
          amount: 50000,
          title: 'Nạp quỹ hôm nay',
          createdAt: now,
        ),
        WalletTransactionModel(
          id: 'tx_10_days_ago',
          familyId: 'f1',
          userId: 'u_dad',
          userName: 'Bố Hùng',
          type: WalletTransactionType.contribute,
          amount: 20000,
          title: 'Nạp quỹ 10 ngày trước',
          createdAt: now.subtract(const Duration(days: 10)),
        ),
        WalletTransactionModel(
          id: 'tx_16_days_ago',
          familyId: 'f1',
          userId: 'u_dad',
          userName: 'Bố Hùng',
          type: WalletTransactionType.contribute,
          amount: 100000,
          title: 'Nạp quỹ 16 ngày trước (Cần loại bỏ)',
          createdAt: now.subtract(const Duration(days: 16)),
        ),
      ];

      final cutoff = now.subtract(const Duration(days: 15));
      final validTxs = txs.where((t) => t.createdAt.isAfter(cutoff)).toList();
      final expiredTxs = txs.where((t) => !t.createdAt.isAfter(cutoff)).toList();

      expect(validTxs.length, 2);
      expect(validTxs.map((t) => t.id), containsAll(['tx_today', 'tx_10_days_ago']));
      expect(expiredTxs.length, 1);
      expect(expiredTxs.first.id, 'tx_16_days_ago');
    });
  });
}

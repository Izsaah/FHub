import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/services/star_economy_service.dart';
import 'package:fhub/Vinh/models/wishlist_models.dart';

void main() {
  group('Phase 2 (Module B) - Star Economy Atomic Redemption & Lì Xì Anti-Exploit Tests', () {
    late StarEconomyService service;

    setUp(() {
      service = StarEconomyService.inMemory();
      // Setup initial balances
      service.memberBalances['fam_1_child_1'] = 20;
      service.memberBalances['fam_1_child_2'] = 10;
      service.memberBalances['fam_1_parent_1'] = 100;
    });

    test('2.1 ExpectedPrice Guard: Aborts if expectedPrice does not match catalog price (Race Condition prevention)', () async {
      final item = WishlistRewardItem(
        id: 'reward_1',
        title: 'Trà Sữa Khoai Môn',
        starCost: 10, // Price on server is 10
        familyId: 'fam_1',
        createdBy: 'parent_1',
        createdByName: 'Bố Tuấn',
        createdAt: DateTime(2026, 1, 1),
      );
      service.wishlistCatalog[item.id] = item;

      // Child saw price = 1 star on screen, but Dad updated it to 10
      expect(
        () => service.submitWishlistRedemption(
          familyId: 'fam_1',
          childId: 'child_1',
          childName: 'Bé Bo',
          item: item,
          expectedPrice: 1, // Con expects 1 star
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('ITEM_PRICE_CHANGED'),
        )),
      );

      // Verify balance is untouched
      expect(service.memberBalances['fam_1_child_1'], 20);
    });

    test('2.2 ExpectedPrice Matches: Deducts balance and moves to PENDING successfully', () async {
      final item = WishlistRewardItem(
        id: 'reward_2',
        title: 'Xem Phim Hoạt Hình',
        starCost: 5,
        familyId: 'fam_1',
        createdBy: 'parent_1',
        createdByName: 'Bố Tuấn',
        createdAt: DateTime(2026, 1, 1),
      );
      service.wishlistCatalog[item.id] = item;

      final claim = await service.submitWishlistRedemption(
        familyId: 'fam_1',
        childId: 'child_1',
        childName: 'Bé Bo',
        item: item,
        expectedPrice: 5,
      );

      expect(claim.status, WishlistClaimStatus.pending);
      expect(claim.starCost, 5);
      expect(service.memberBalances['fam_1_child_1'], 15); // 20 - 5 = 15
      expect(service.starLedger.containsKey('claim_${claim.id}'), true);
    });

    test('2.3 Idempotency Key: Duplicate claim submission does not double-debit balance', () async {
      final item = WishlistRewardItem(
        id: 'reward_3',
        title: 'Bút Vẽ Màu',
        starCost: 4,
        familyId: 'fam_1',
        createdBy: 'parent_1',
        createdByName: 'Bố Tuấn',
        createdAt: DateTime(2026, 1, 1),
      );
      service.wishlistCatalog[item.id] = item;

      const customClaimId = 'claim_fixed_idempotent_key_123';

      // First call succeeds
      await service.submitWishlistRedemption(
        familyId: 'fam_1',
        childId: 'child_1',
        childName: 'Bé Bo',
        item: item,
        claimId: customClaimId,
      );
      expect(service.memberBalances['fam_1_child_1'], 16);

      // Re-call with same claimId throws StateError and balance remains 16
      expect(
        () => service.submitWishlistRedemption(
          familyId: 'fam_1',
          childId: 'child_1',
          childName: 'Bé Bo',
          item: item,
          claimId: customClaimId,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('đã được xử lý'),
        )),
      );
      expect(service.memberBalances['fam_1_child_1'], 16);
    });

    test('2.4 Lì Xì Anti-Exploit: Cannot self-sponsor (Sender == Receiver)', () async {
      expect(
        () => service.giftStarsToChild(
          familyId: 'fam_1',
          senderId: 'parent_1',
          senderName: 'Bố Tuấn',
          senderRole: 'PARENT',
          childId: 'parent_1', // Same as sender
          stars: 10,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('ANTI_EXPLOIT_SELF_SPONSOR'),
        )),
      );
    });

    test('2.5 Lì Xì Anti-Exploit: Cannot send 0 or negative stars', () async {
      expect(
        () => service.giftStarsToChild(
          familyId: 'fam_1',
          senderId: 'parent_1',
          senderName: 'Bố Tuấn',
          senderRole: 'PARENT',
          childId: 'child_1',
          stars: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => service.giftStarsToChild(
          familyId: 'fam_1',
          senderId: 'parent_1',
          senderName: 'Bố Tuấn',
          senderRole: 'PARENT',
          childId: 'child_1',
          stars: -15,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('2.6 Lì Xì Success: Credits recipient and logs sponsor entry in star ledger', () async {
      await service.giftStarsToChild(
        familyId: 'fam_1',
        senderId: 'parent_1',
        senderName: 'Bố Tuấn',
        senderRole: 'PARENT',
        childId: 'child_2',
        stars: 15,
        note: 'Lì xì chăm ngoan',
      );

      expect(service.memberBalances['fam_1_child_2'], 25); // 10 + 15 = 25
      expect(service.memberBalances['fam_1_parent_1'], 85); // 100 - 15 = 85 (sender deducted)
      final ledgerEntries = service.starLedger.values.where((e) => e['type'] == 'RELATIVE_SPONSOR');
      expect(ledgerEntries.isNotEmpty, true);
    });

    test('2.8 Lì Xì Anti-Exploit: Cannot send more than 20 stars in a single gift', () async {
      expect(
        () => service.giftStarsToChild(
          familyId: 'fam_1',
          senderId: 'parent_1',
          senderName: 'Bố Tuấn',
          senderRole: 'PARENT',
          childId: 'child_1',
          stars: 25,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('tối đa'),
        )),
      );
    });

    test('2.9 Lì Xì Anti-Exploit: Cannot send more stars than sender current balance', () async {
      service.memberBalances['fam_1_parent_low'] = 5;
      expect(
        () => service.giftStarsToChild(
          familyId: 'fam_1',
          senderId: 'parent_low',
          senderName: 'Bố Tuấn',
          senderRole: 'PARENT',
          childId: 'child_1',
          stars: 10,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Số dư sao không đủ'),
        )),
      );
    });

    test('2.10 Reward Concurrency & Removal: Pending reward blocks second claim, approved reward removed from catalog', () async {
      final rtx = WishlistRewardItem(
        id: 'rtx_5090',
        title: 'RTX5090',
        starCost: 10,
        familyId: 'fam_1',
        createdBy: 'parent_1',
        createdByName: 'Bố Tuấn',
        createdAt: DateTime(2026, 1, 1),
      );
      service.wishlistCatalog[rtx.id] = rtx;

      // Child 1 claims RTX5090
      final claim1 = await service.submitWishlistRedemption(
        familyId: 'fam_1',
        childId: 'child_1',
        childName: 'Khoa Cao',
        item: rtx,
      );
      expect(claim1.status, WishlistClaimStatus.pending);

      // Child 2 tries to claim same RTX5090 at the same time -> blocked
      expect(
        () => service.submitWishlistRedemption(
          familyId: 'fam_1',
          childId: 'child_2',
          childName: 'Bé Na',
          item: rtx,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('REWARD_ALREADY_CLAIMED'),
        )),
      );

      // Parent approves Child 1's claim -> Reward permanently removed from catalog
      await service.approveWishlistRedemption(
        claimId: claim1.id,
        guardianId: 'parent_1',
        guardianName: 'Bố Tuấn',
        guardianRole: 'PARENT',
      );

      expect(service.wishlistCatalog.containsKey(rtx.id), isFalse,
          reason: 'Approved reward must no longer remain in catalog');
    });

    test('2.7 Refund: When parent rejects claim, 100% stars returned with REFUND ledger entry', () async {
      const claimId = 'claim_test_refund_456';
      await service.claimWishlistItem(
        claimId: claimId,
        familyId: 'fam_1',
        userId: 'child_1',
        cost: 10,
        itemName: 'Bút Vẽ',
      );
      expect(service.memberBalances['fam_1_child_1'], 10); // 20 - 10 = 10

      await service.refundWishlistClaim(
        claimId: claimId,
        familyId: 'fam_1',
        userId: 'child_1',
        refundStars: 10,
        reason: 'Hết hàng ngoài đời',
        approvedBy: 'parent_1',
      );

      expect(service.memberBalances['fam_1_child_1'], 20); // 100% refunded
      final refundEntry = service.starLedger['refund_$claimId'];
      expect(refundEntry, isNotNull);
      expect(refundEntry?['type'], 'CLAIM_REFUND');
      expect(refundEntry?['amount'], 10);
    });
  });
}

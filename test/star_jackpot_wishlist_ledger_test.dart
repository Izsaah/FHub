import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';
import 'package:fhub/Danh/services/payment_service.dart';
import 'package:fhub/Danh/services/jackpot_algorithm.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/wishlist_models.dart';
import 'package:fhub/Vinh/screens/wishlist_and_ledger_screen.dart';
import 'package:fhub/Vinh/screens/views/reminder_list_view.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/star_economy_service.dart';
import 'package:fhub/Long/models/family_member_model.dart';
import 'package:fhub/Long/models/user_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M3 + M4 + M5: Star Jackpot, Real-World Wishlist Rewards, Relative Sponsor & Star Ledger', () {
    late StarEconomyService starService;

    setUp(() {
      starService = StarEconomyService.inMemory();
      starService.resetMockData();
      StarEconomyService.instance.resetMockData();
      FamilyJackpotService.instance.resetJackpot();
      FamilyJackpotService.instance.overrideCanUseJackpotForTest = true;
    });

    // -------------------------------------------------------------------------
    // R1 (M3): STAR JACKPOT POOL ACCUMULATION & SHAKE DISTRIBUTION
    // -------------------------------------------------------------------------
    group('R1 (M3): Star Jackpot Pool Accumulation & Shake Distribution', () {
      test('1.1 Approving a chore with rewardStars > 0 rewards child only and does NOT auto accumulate stars into Family Star Pool', () async {
        starService.seedMemberBalance('fam_star', 'child_bo', 10);
        starService.seedTask('task_clean_kitchen', {
          'familyId': 'fam_star',
          'creatorId': 'parent_dad',
          'assignedTo': 'child_bo',
          'status': 'SUBMITTED',
          'taskStatus': 'SUBMITTED',
          'rewardStars': 10,
        });

        await starService.approveTaskWithDoubleAwardProtection(
          taskId: 'task_clean_kitchen',
          reviewerId: 'parent_dad',
          reviewerName: 'Bố Tuấn',
          isGuardian: true,
        );

        // Child gets +10 stars (10 + 10 = 20)
        expect(starService.getBalance('fam_star', 'child_bo'), 20);
        // Chores do NOT auto-contribute to the Family Star Pool
        expect(starService.getFamilyStarPool('fam_star'), 0);
      });

      test('1.1b Daily check-in mission awards +10 ⭐ to Family Star Pot when all members check in', () async {
        final jackpotSvc = FamilyJackpotService.instance;
        await jackpotSvc.resetJackpot();
        expect(jackpotSvc.isDailyCheckInCompletedToday(), isFalse);

        // Member 1 checks in (1/2 members)
        final r1 = await jackpotSvc.checkInDaily(
          userId: 'parent_dad',
          userName: 'Bố Tuấn',
          totalFamilyMembers: 2,
        );
        expect(r1, isFalse);
        expect(jackpotSvc.getTodayCheckInCount(), 1);
        expect(jackpotSvc.isDailyCheckInCompletedToday(), isFalse);

        // Member 2 checks in (2/2 members) -> triggers +10 stars
        final r2 = await jackpotSvc.checkInDaily(
          userId: 'child_bo',
          userName: 'Cu Bo',
          totalFamilyMembers: 2,
        );
        expect(r2, isTrue);
        expect(jackpotSvc.isDailyCheckInCompletedToday(), isTrue);
        expect(jackpotSvc.jackpot.totalPoolStars, 10);
      });

      test('1.1c Wishlist redemption contributes 10% cashback of starCost to Family Star Pot', () async {
        starService.seedMemberBalance('fam_cashback', 'child_bo', 100);
        final catalog = starService.seedDefaultWishlistRewardsForTest('fam_cashback');
        final comicItem = catalog.firstWhere((i) => i.starCost == 50);

        final initialPot = FamilyJackpotService.instance.jackpot.totalPoolStars;
        await starService.submitWishlistRedemption(
          familyId: 'fam_cashback',
          childId: 'child_bo',
          childName: 'Cu Bo',
          item: comicItem,
          claimId: 'claim_cashback_test',
        );

        // 10% of 50 stars = 5 stars cashback contributed to jackpot
        expect(
          FamilyJackpotService.instance.jackpot.totalPoolStars,
          initialPot + 5,
        );
      });

      test('1.2 JackpotAlgorithm distributes small star pool (e.g. 50 stars) accurately among active shakers', () {
        const totalStarPot = 50;
        final shakes = {
          'child_bo': 30,
          'child_na': 15,
          'parent_dad': 0, // 0 shakes -> 0 stars
        };

        final result = JackpotAlgorithm.calculate(
          totalAmount: totalStarPot,
          shakeCounts: shakes,
          participantIds: ['child_bo', 'child_na', 'parent_dad'],
        );

        expect(result.prizes['parent_dad'] ?? 0, 0);
        expect((result.prizes['child_bo'] ?? 0) > 0, isTrue);
        expect((result.prizes['child_na'] ?? 0) > 0, isTrue);

        final totalDistributed =
            result.prizes.values.fold<int>(0, (sum, s) => sum + s);
        expect(totalDistributed, totalStarPot);
      });

      test('1.3 FamilyJackpotService.contributeStars & distributeStarPotNow credit won stars to StarEconomyService and star_ledger', () async {
        final jackpotSvc = FamilyJackpotService.instance;
        await jackpotSvc.contributeStars(
          stars: 40,
          memberId: 'parent_dad',
          memberName: 'Bố Tuấn',
        );
        expect(jackpotSvc.jackpot.totalPoolStars, 40);

        final result = await jackpotSvc.distributeStarPotNow(
          overrideShakeCounts: {'child_bo': 25, 'child_na': 10},
          overrideParticipantIds: ['child_bo', 'child_na'],
          roundId: 'round_test_1',
        );

        final boWon = result.prizes['child_bo'] ?? 0;
        final naWon = result.prizes['child_na'] ?? 0;
        expect(boWon + naWon, 40);
        expect(jackpotSvc.jackpot.totalPoolStars, 0);
        expect(jackpotSvc.jackpot.isFinished, isTrue);

        // StarEconomyService.instance balances and star_ledger updated
        expect(
          StarEconomyService.instance.starLedger
              .containsKey('jackpot_round_test_1_child_bo'),
          isTrue,
        );
        expect(
          StarEconomyService.instance.starLedger
              .containsKey('jackpot_round_test_1_child_na'),
          isTrue,
        );
      });
    });

    // -------------------------------------------------------------------------
    // R2 (M4): REAL-WORLD WISHLIST CATALOG, REDEMPTION & REFUND ON REJECTION
    // -------------------------------------------------------------------------
    group('R2 (M4): Real-World Wishlist Catalog, Redemption & Refund', () {
      test('2.1 Guardian can create real-world reward items; Child and Relative are blocked', () async {
        final item = await starService.createWishlistRewardItem(
          familyId: 'fam_wish',
          creatorId: 'parent_mom',
          creatorName: 'Mẹ Lan',
          creatorRole: 'PARENT',
          title: 'Đi tắm biển Vũng Tàu cuối tuần',
          description: 'Dành cho bé đạt 100 sao trong tháng',
          starCost: 100,
          iconEmoji: '🏖️',
          itemId: 'reward_vung_tau',
        );

        expect(item.id, 'reward_vung_tau');
        expect(item.starCost, 100);
        expect(starService.wishlistCatalog.containsKey('reward_vung_tau'), isTrue);

        // Child blocked from creating catalog item
        expect(
          () => starService.createWishlistRewardItem(
            familyId: 'fam_wish',
            creatorId: 'child_bo',
            creatorName: 'Cu Bo',
            creatorRole: 'CHILD',
            title: 'Mua PS5 1 sao',
            starCost: 1,
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('GUARDIAN_REQUIRED'),
          )),
        );

        // Relative blocked from creating catalog item
        expect(
          () => starService.createWishlistRewardItem(
            familyId: 'fam_wish',
            creatorId: 'uncle_ba',
            creatorName: 'Chú Ba',
            creatorRole: 'RELATIVE',
            title: 'Quà tự tạo',
            starCost: 10,
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('GUARDIAN_REQUIRED'),
          )),
        );
      });

      test('2.2 Child redeeming reward deducts stars immediately, creates PENDING claim, and Guardian can approve', () async {
        starService.seedMemberBalance('fam_wish', 'child_bo', 60);
        final catalog = starService.seedDefaultWishlistRewardsForTest('fam_wish');
        final comicItem =
            catalog.firstWhere((i) => i.starCost == 50); // Mua 1 quyển truyện tranh (50 sao)

        final claim = await starService.submitWishlistRedemption(
          familyId: 'fam_wish',
          childId: 'child_bo',
          childName: 'Cu Bo',
          item: comicItem,
          claimId: 'claim_comic_1',
        );

        // Balance immediately deducted: 60 - 50 = 10
        expect(starService.getBalance('fam_wish', 'child_bo'), 10);
        expect(claim.status, WishlistClaimStatus.pending);
        expect(starService.starLedger.containsKey('claim_claim_comic_1'), isTrue);

        // Guardian approves the claim
        final approved = await starService.approveWishlistRedemption(
          claimId: 'claim_comic_1',
          guardianId: 'parent_mom',
          guardianName: 'Mẹ Lan',
          guardianRole: 'PARENT',
        );
        expect(approved.status, WishlistClaimStatus.approved);
        expect(approved.reviewedBy, 'parent_mom');
        // Balance stays 10
        expect(starService.getBalance('fam_wish', 'child_bo'), 10);
      });

      test('2.3 Guardian rejecting a PENDING claim automatically refunds 100% of stars to the child and writes refund_{claimId}', () async {
        starService.seedMemberBalance('fam_wish', 'child_bo', 50);
        final catalog = starService.seedDefaultWishlistRewardsForTest('fam_wish');
        final movieItem =
            catalog.firstWhere((i) => i.starCost == 15); // Xem phim 30 phút (15 sao)

        await starService.submitWishlistRedemption(
          familyId: 'fam_wish',
          childId: 'child_bo',
          childName: 'Cu Bo',
          item: movieItem,
          claimId: 'claim_movie_reject',
        );

        expect(starService.getBalance('fam_wish', 'child_bo'), 35); // 50 - 15

        // Guardian rejects -> 15 stars refunded -> balance back to 50
        final rejected = await starService.rejectWishlistRedemption(
          claimId: 'claim_movie_reject',
          guardianId: 'parent_dad',
          guardianName: 'Bố Tuấn',
          guardianRole: 'PARENT',
          reason: 'Mai con thi học kỳ nên để cuối tuần sau xem nhé',
        );

        expect(rejected.status, WishlistClaimStatus.rejected);
        expect(starService.getBalance('fam_wish', 'child_bo'), 50);
        expect(
          starService.starLedger.containsKey('refund_claim_movie_reject'),
          isTrue,
        );
        expect(
          starService.starLedger['refund_claim_movie_reject']!['amount'],
          15,
        );
      });

      test('2.4 Guardian can edit WishlistRewardItem; non-guardian is blocked with StateError', () async {
        final catalog = starService.seedDefaultWishlistRewardsForTest('fam_edit_test');
        final item = catalog.first;

        // Guardian can edit title, description, starCost
        final updated = await starService.updateWishlistRewardItem(
          familyId: 'fam_edit_test',
          itemId: item.id,
          editorId: 'parent_dad',
          editorName: 'Bố Tuấn',
          editorRole: 'PARENT',
          title: 'Xem hoạt hình 45 phút cuối tuần',
          starCost: 25,
        );

        expect(updated.title, 'Xem hoạt hình 45 phút cuối tuần');
        expect(updated.starCost, 25);
        expect(starService.wishlistCatalog[item.id]?.starCost, 25);

        // Non-guardian (CHILD) is blocked
        expect(
          () => starService.updateWishlistRewardItem(
            familyId: 'fam_edit_test',
            itemId: item.id,
            editorId: 'child_bo',
            editorName: 'Cu Bo',
            editorRole: 'CHILD',
            title: 'Hacker reward',
            starCost: 1,
          ),
          throwsStateError,
        );
      });

      test('2.5 Guardian can remove WishlistRewardItem; non-guardian is blocked with StateError', () async {
        final catalog = starService.seedDefaultWishlistRewardsForTest('fam_remove_test');
        final item = catalog.last;

        // Non-guardian (CHILD) is blocked
        expect(
          () => starService.removeWishlistRewardItem(
            familyId: 'fam_remove_test',
            itemId: item.id,
            removerId: 'child_bo',
            removerName: 'Cu Bo',
            removerRole: 'CHILD',
          ),
          throwsStateError,
        );

        // Guardian can remove
        await starService.removeWishlistRewardItem(
          familyId: 'fam_remove_test',
          itemId: item.id,
          removerId: 'parent_dad',
          removerName: 'Bố Tuấn',
          removerRole: 'PARENT',
        );

        expect(starService.wishlistCatalog.containsKey(item.id), isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // R3 (M4): RELATIVE STAR SPONSORING (LÌ XÌ SAO KHÍCH LỆ) & PENALTY BLOCK
    // -------------------------------------------------------------------------
    group('R3 (M4): Relative Star Sponsoring & Penalty Block', () {
      test('3.1 RELATIVE (Cô/Dì/Chú/Bác) can sponsor positive stars to Child and writes RELATIVE_SPONSOR ledger entry', () async {
        starService.seedMemberBalance('fam_rel', 'child_bo', 20);

        await starService.giftStarsToChild(
          familyId: 'fam_rel',
          senderId: 'uncle_ba',
          senderName: 'Chú Ba',
          senderRole: 'RELATIVE',
          childId: 'child_bo',
          childName: 'Cu Bo',
          stars: 15,
          giftId: 'lixi_hoc_gioi',
          note: 'Chú Ba thưởng cháu đạt điểm 10 Toán',
        );

        expect(starService.getBalance('fam_rel', 'child_bo'), 35); // 20 + 15
        final entry = starService.starLedger['sponsor_lixi_hoc_gioi'];
        expect(entry, isNotNull);
        expect(entry!['type'], 'RELATIVE_SPONSOR');
        expect(entry['amount'], 15);
        expect(entry['senderName'], 'Chú Ba');
      });

      test('3.2 RELATIVE attempting to deduct/penalize stars (stars <= 0) throws CULTURE_GOVERNANCE_VIOLATION StateError', () async {
        starService.seedMemberBalance('fam_rel', 'child_bo', 20);

        expect(
          () => starService.giftStarsToChild(
            familyId: 'fam_rel',
            senderId: 'uncle_ba',
            senderName: 'Chú Ba',
            senderRole: 'RELATIVE',
            childId: 'child_bo',
            stars: -10,
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_GOVERNANCE_VIOLATION'),
          )),
        );

        expect(starService.getBalance('fam_rel', 'child_bo'), 20);
      });

      test('3.3 CHILD attempting to sponsor stars is blocked with ANTI_EXPLOIT_CHILD_CANNOT_SPONSOR', () async {
        expect(
          () => starService.giftStarsToChild(
            familyId: 'fam_rel',
            senderId: 'child_bo',
            senderName: 'Cu Bo',
            senderRole: 'CHILD',
            childId: 'child_na',
            stars: 10,
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ANTI_EXPLOIT_CHILD_CANNOT_SPONSOR'),
          )),
        );
      });
    });

    // -------------------------------------------------------------------------
    // R5 (M5): STAR LEDGER HISTORY & WISHLIST UI SCREEN VERIFICATION
    // -------------------------------------------------------------------------
    group('R5 (M5): Star Ledger History & Wishlist UI Screen Verification', () {
      test('4.1 getStarLedgerHistory returns complete audit trail across all transaction types', () async {
        starService.seedMemberBalance('fam_audit', 'child_bo', 0);
        starService.seedTask('task_1', {
          'familyId': 'fam_audit',
          'creatorId': 'parent_dad',
          'assignedTo': 'child_bo',
          'status': 'SUBMITTED',
          'rewardStars': 30,
        });

        // 1. Task reward (+30)
        await starService.approveTaskWithDoubleAwardProtection(
          taskId: 'task_1',
          reviewerId: 'parent_dad',
          reviewerName: 'Bố Tuấn',
          isGuardian: true,
        );

        // 2. Relative sponsor (+20)
        await starService.giftStarsToChild(
          familyId: 'fam_audit',
          senderId: 'aunt_lan',
          senderName: 'Cô Lan',
          senderRole: 'RELATIVE',
          childId: 'child_bo',
          childName: 'Cu Bo',
          stars: 20,
          giftId: 'gift_1',
        );

        // 3. Jackpot win (+10)
        await starService.creditJackpotStarWin(
          familyId: 'fam_audit',
          winnerId: 'child_bo',
          winnerName: 'Cu Bo',
          wonStars: 10,
          roundId: 'round_audit_1',
          isFirstPrize: true,
        );

        // 4. Wishlist claim (-15)
        starService.seedDefaultWishlistRewardsForTest('fam_audit');
        final movieItem = starService
            .getWishlistCatalog('fam_audit')
            .firstWhere((i) => i.starCost == 15);
        await starService.submitWishlistRedemption(
          familyId: 'fam_audit',
          childId: 'child_bo',
          childName: 'Cu Bo',
          item: movieItem,
          claimId: 'claim_audit_1',
        );

        // 5. Reject & Refund (+15)
        await starService.rejectWishlistRedemption(
          claimId: 'claim_audit_1',
          guardianId: 'parent_dad',
          guardianName: 'Bố Tuấn',
          guardianRole: 'PARENT',
        );

        // Final balance = 30 + 20 + 10 - 15 + 15 = 60
        expect(starService.getBalance('fam_audit', 'child_bo'), 60);

        final history = starService.getStarLedgerHistory('fam_audit');
        expect(history.length, 5);
        final types = history.map((e) => e.type).toSet();
        expect(
          types,
          containsAll([
            'TASK_REWARD',
            'RELATIVE_SPONSOR',
            'JACKPOT_WIN',
            'WISHLIST_CLAIM',
            'CLAIM_REFUND',
          ]),
        );
      });

      testWidgets('4.2 WishlistAndLedgerScreen renders Star Balance, Catalog, Redemption, and Ledger tabs', (tester) async {
        starService.seedMemberBalance('fam_ui', 'child_bo', 55);
        starService.seedDefaultWishlistRewardsForTest('fam_ui');
        const members = [
          FamilyMember(
            id: 'child_bo',
            name: 'Cu Bo',
            role: 'CHILD',
            familyId: 'fam_ui',
            rewardStarsTotal: 55,
          ),
          FamilyMember(
            id: 'parent_dad',
            name: 'Bố Tuấn',
            role: 'PARENT',
            familyId: 'fam_ui',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: WishlistAndLedgerScreen(
              familyId: 'fam_ui',
              currentUserId: 'child_bo',
              currentUserName: 'Cu Bo',
              currentUserRole: 'CHILD',
              familyMembers: members,
              starEconomyService: starService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Shows initial 55 ⭐ balance
        expect(find.byKey(const Key('user_star_balance_text')), findsOneWidget);
        expect(find.text('55 ⭐'), findsOneWidget);

        // Redeem 15-star movie reward
        final redeemBtn = find.byKey(const Key('btn_redeem_fam_ui_reward_movie_30m'));
        expect(redeemBtn, findsOneWidget);
        await tester.tap(redeemBtn);
        await tester.pumpAndSettle();

        // Balance updated to 40 ⭐ (55 - 15)
        expect(find.text('40 ⭐'), findsOneWidget);

        // Switch to Star Ledger History tab
        await tester.tap(find.textContaining('Lịch Sử Sao'));
        await tester.pumpAndSettle();

        expect(find.text('Đổi quà: Xem phim hoạt hình 30 phút'), findsOneWidget);
        expect(find.text('-15 ⭐'), findsOneWidget);
      });
    });

    // R6: MULTI-FAMILY MARKET ISOLATION & COMPREHENSIVE FIREBASE KEYS
    group('R6: Multi-Family Market Isolation & Comprehensive Firebase Keys', () {
      test('5.1 WishlistRewardItem.toMap & fromMap correctly serialize and deserialize all required Firebase keys', () {
        final now = DateTime(2026, 11, 7, 18, 0, 0);
        final item = WishlistRewardItem(
          id: 'reward_custom_001',
          familyId: 'fam_doan_tu',
          title: 'Đi nhà sách FAHASA cuối tuần',
          description: 'Bố mẹ dẫn đi chọn sách và đồ dùng học tập',
          starCost: 60,
          iconEmoji: '📖',
          createdBy: 'user_vinh_parent',
          createdByName: 'Lương Diệu Vinh',
          createdAt: now,
          isActive: true,
        );

        final map = item.toMap();
        // Check standard camelCase keys
        expect(map['id'], 'reward_custom_001');
        expect(map['familyId'], 'fam_doan_tu');
        expect(map['title'], 'Đi nhà sách FAHASA cuối tuần');
        expect(map['description'], 'Bố mẹ dẫn đi chọn sách và đồ dùng học tập');
        expect(map['starCost'], 60);
        expect(map['iconEmoji'], '📖');
        expect(map['createdBy'], 'user_vinh_parent');
        expect(map['createdByName'], 'Lương Diệu Vinh');
        expect(map['isActive'], true);

        // Check snake_case alias keys for Firebase interoperability
        expect(map['family_id'], 'fam_doan_tu');
        expect(map['name'], 'Đi nhà sách FAHASA cuối tuần');
        expect(map['desc'], 'Bố mẹ dẫn đi chọn sách và đồ dùng học tập');
        expect(map['star_cost'], 60);
        expect(map['icon_emoji'], '📖');
        expect(map['created_by'], 'user_vinh_parent');
        expect(map['created_by_name'], 'Lương Diệu Vinh');
        expect(map['is_active'], true);

        // Deserialization from pure snake_case map
        final snakeMap = {
          'family_id': 'fam_tinh_nguoi',
          'name': 'Xem đá bóng sân vận động',
          'desc': 'Đi xem bóng đá cùng bố',
          'star_cost': 100,
          'icon_emoji': '⚽',
          'created_by': 'user_father_02',
          'created_by_name': 'Bố Vinh',
          'created_at': '2026-11-07T18:00:00.000',
          'is_active': true,
        };

        final fromSnake = WishlistRewardItem.fromMap('reward_snake_002', snakeMap);
        expect(fromSnake.id, 'reward_snake_002');
        expect(fromSnake.familyId, 'fam_tinh_nguoi');
        expect(fromSnake.title, 'Xem đá bóng sân vận động');
        expect(fromSnake.description, 'Đi xem bóng đá cùng bố');
        expect(fromSnake.starCost, 100);
        expect(fromSnake.iconEmoji, '⚽');
        expect(fromSnake.createdBy, 'user_father_02');
        expect(fromSnake.createdByName, 'Bố Vinh');
        expect(fromSnake.isActive, isTrue);
      });

      test('5.2 Multi-family market isolation: Each family has an independent rewards catalog', () async {
        final starService = StarEconomyService.inMemory();
        starService.resetMockData();

        const familyA = 'fam_doan_tu_MGJL5440';
        const familyB = 'fam_tinh_nguoi_WZFG0038';

        // Parent creates a reward in Family A
        await starService.createWishlistRewardItem(
          familyId: familyA,
          creatorId: 'user_vinh',
          creatorName: 'Lương Diệu Vinh',
          creatorRole: 'PARENT',
          title: 'Phần thưởng gia đình Đoàn Tụ',
          description: 'Dành riêng cho gia đình Đoàn Tụ',
          starCost: 45,
          iconEmoji: '🎉',
        );

        // Parent creates a different reward in Family B
        await starService.createWishlistRewardItem(
          familyId: familyB,
          creatorId: 'user_vinh',
          creatorName: 'Lương Diệu Vinh',
          creatorRole: 'PARENT',
          title: 'Phần thưởng gia đình Tình Người',
          description: 'Dành riêng cho gia đình Tình Người',
          starCost: 90,
          iconEmoji: '🏡',
        );

        final catalogA = starService.getWishlistCatalog(familyA);
        final catalogB = starService.getWishlistCatalog(familyB);

        // Strict isolation: Family A must only contain its own reward
        expect(catalogA.length, 1);
        expect(catalogA.first.title, 'Phần thưởng gia đình Đoàn Tụ');
        expect(catalogA.first.starCost, 45);
        expect(catalogA.first.familyId, familyA);

        // Family B must only contain its own reward
        expect(catalogB.length, 1);
        expect(catalogB.first.title, 'Phần thưởng gia đình Tình Người');
        expect(catalogB.first.starCost, 90);
        expect(catalogB.first.familyId, familyB);
      });

      testWidgets('5.3 Empty catalog renders friendly Empty State with Add Reward CTA', (tester) async {
        final starService = StarEconomyService.inMemory();
        starService.resetMockData();
        const emptyFamily = 'fam_brand_new_empty';

        await tester.pumpWidget(
          MaterialApp(
            home: WishlistAndLedgerScreen(
              familyId: emptyFamily,
              currentUserId: 'parent_user',
              currentUserName: 'Phụ huynh Vinh',
              currentUserRole: 'PARENT',
              familyMembers: const [
                FamilyMember(
                  id: 'parent_user',
                  name: 'Phụ huynh Vinh',
                  role: 'PARENT',
                  familyId: emptyFamily,
                ),
              ],
              starEconomyService: starService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verifies the friendly empty state
        expect(find.text('Gia đình chưa có phần thưởng nào!'), findsOneWidget);
        expect(find.byKey(const Key('btn_add_first_reward')), findsOneWidget);
      });
    });

    // -------------------------------------------------------------------------
    // R6: ADVANCED GOVERNANCE & ANTI-EXPLOIT (Tasks, Wishlist & Jackpot)
    // -------------------------------------------------------------------------
    group('R6: Advanced Governance & Anti-Exploit Rules', () {
      test('6.1 awardStarsForCompletedChore awards stars when creatorId != completerId', () async {
        starService.seedMemberBalance('fam_gov', 'child_vinh', 0);

        await starService.awardStarsForCompletedChore(
          familyId: 'fam_gov',
          taskId: 'task_wash_dishes',
          completerId: 'child_vinh',
          completerName: 'Lương Diệu Vinh',
          creatorId: 'parent_dad',
          creatorName: 'Bố Tuấn',
          stars: 4,
          taskTitle: 'Rửa chén sau bữa tối',
        );

        expect(starService.getBalance('fam_gov', 'child_vinh'), 4);
        expect(starService.starLedger.containsKey('reward_task_wash_dishes'), isTrue);
      });

      test('6.2 awardStarsForCompletedChore BLOCKS awarding stars when creatorId == completerId', () async {
        starService.seedMemberBalance('fam_gov', 'creator_user', 10);

        // User creates task for themselves and completes it
        await starService.awardStarsForCompletedChore(
          familyId: 'fam_gov',
          taskId: 'task_self_award',
          completerId: 'creator_user',
          completerName: 'Tự Làm Việc',
          creatorId: 'creator_user',
          creatorName: 'Tự Làm Việc',
          stars: 5,
          taskTitle: 'Tự tạo việc cho mình',
        );

        // Balance should NOT change! Anti-exploit protection
        expect(starService.getBalance('fam_gov', 'creator_user'), 10);
        expect(starService.starLedger.containsKey('reward_task_self_award'), isFalse);
      });

      test('6.3 Wishlist redemption BLOCKS creator from redeeming their own item', () async {
        starService.seedMemberBalance('fam_gov', 'parent_vinh', 100);
        final item = WishlistRewardItem(
          id: 'item_self_created',
          familyId: 'fam_gov',
          title: 'Vật phẩm tự tạo',
          description: 'Test',
          starCost: 10,
          iconEmoji: '🎁',
          createdBy: 'parent_vinh',
          createdByName: 'Lương Diệu Vinh',
          createdAt: DateTime.now(),
        );

        expect(
          () => starService.submitWishlistRedemption(
            familyId: 'fam_gov',
            childId: 'parent_vinh',
            childName: 'Lương Diệu Vinh',
            item: item,
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('6.4 onPremiumLost() preserves accumulated pot stars (does NOT reset to 0)', () async {
        final jackpotSvc = FamilyJackpotService.instance;
        await jackpotSvc.resetJackpot();
        await jackpotSvc.contributeStars(stars: 80, memberId: 'u_donor', memberName: 'Nhà hảo tâm');
        expect(jackpotSvc.jackpot.totalPoolStars, 80);

        // Family loses premium
        await jackpotSvc.onPremiumLost();

        // Pot stars MUST BE PRESERVED!
        expect(jackpotSvc.jackpot.totalPoolStars, 80);
      });

      test('6.5 Ending shake battle distributes stars to each participant personal balance', () async {
        final jackpotSvc = FamilyJackpotService.instance;
        await jackpotSvc.resetJackpot();
        await jackpotSvc.contributeStars(stars: 100, memberId: 'u_donor', memberName: 'Nhà hảo tâm');
        StarEconomyService.instance.seedMemberBalance('f1', 'user_a', 0);
        StarEconomyService.instance.seedMemberBalance('f1', 'user_b', 0);

        final result = await jackpotSvc.distributeStarPotNow(
          overrideShakeCounts: {'user_a': 50, 'user_b': 30},
          overrideParticipantIds: ['user_a', 'user_b'],
        );

        expect(result.prizes.isNotEmpty, isTrue);
        // Pot is emptied after successful settlement
        expect(jackpotSvc.jackpot.totalPoolStars, 0);
        // Personal balances are credited to each participant
        final balanceA = StarEconomyService.instance.getBalance('f1', 'user_a');
        final balanceB = StarEconomyService.instance.getBalance('f1', 'user_b');
        expect(balanceA + balanceB, 100);
        expect(balanceA, greaterThan(0));
        expect(balanceB, greaterThan(0));
      });

      test('6.6 syncCheckInsFromMembers syncs check-in status from home members (with and without Premium)', () async {
        final jackpotSvc = FamilyJackpotService.instance;
        await jackpotSvc.resetJackpot();

        final member1 = FamilyMemberModel(
          familyId: 'f1',
          user: UserModel(id: 'm1', name: 'Member 1', email: 'm1@test.com'),
          role: Role.owner,
          lastCheckInAt: DateTime.now(),
        );
        final member2 = FamilyMemberModel(
          familyId: 'f1',
          user: UserModel(id: 'm2', name: 'Member 2', email: 'm2@test.com'),
          role: Role.member,
          lastCheckInAt: DateTime.now(),
        );

        // Case A: When family has Premium -> syncs and awards +10 ⭐ to pot
        jackpotSvc.overrideCanUseJackpotForTest = true;
        await jackpotSvc.syncCheckInsFromMembers([member1, member2]);
        expect(jackpotSvc.isDailyCheckInCompletedToday(), isTrue);
        expect(jackpotSvc.jackpot.totalPoolStars, 10);

        // Case B: When family does NOT have Premium -> pot stars remain 0, no stars added
        await jackpotSvc.resetJackpot();
        jackpotSvc.overrideCanUseJackpotForTest = false;
        await jackpotSvc.syncCheckInsFromMembers([member1, member2]);
        expect(jackpotSvc.isDailyCheckInCompletedToday(), isTrue);
        expect(jackpotSvc.jackpot.totalPoolStars, 0);
      });

      testWidgets('6.7 ReminderListView renders CHỜ DUYỆT NGHIỆM THU when task is submitted, and ReminderCard displays Duyệt ngay button', (tester) async {
        final submittedReminder = ReminderModel(
          id: 'task_submitted_1',
          familyId: 'f1',
          title: 'Quét nhà sạch sẽ',
          date: '07/11/2026',
          time: '20:30',
          assignedTo: 'child_bo',
          assignedToName: 'Cu Bo',
          creatorId: 'parent_dad',
          creatorName: 'Bố Tuấn',
          taskType: TaskType.assign,
          taskStatus: TaskStatus.submitted,
          requiresProofImage: true,
          proofImageUrl: 'https://example.com/proof.jpg',
          rewardStars: 5,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReminderListView(
                allReminders: [submittedReminder],
                displayedReminders: [submittedReminder],
                currentUserId: 'parent_dad',
                selectedDateStr: '07/11/2026',
                isShowingAll: false,
                isParentOrOwner: true,
                onCreatePressed: () {},
                onShowAllPressed: () {},
                onTapReminder: (_) {},
                onCompleteReminder: (_) {},
                onDeleteReminder: (_) {},
                onClaimReminder: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. The PENDING APPROVAL section header MUST be present!
        expect(find.text('CHỜ DUYỆT NGHIỆM THU'), findsOneWidget);
        // 2. The task title must be shown
        expect(find.text('Quét nhà sạch sẽ'), findsOneWidget);
        // 3. The 'Duyệt ngay' action button on the card must be visible!
        expect(find.text('Duyệt ngay'), findsOneWidget);
      });

      testWidgets('6.8 ReminderListView renders cleanly inside SingleChildScrollView with shrinkWrap for Calendar View', (tester) async {
        final task = ReminderModel(
          id: 'task_cal_scroll_1',
          familyId: 'f1',
          title: 'Tưới cây cảnh',
          date: '07/11/2026',
          time: '18:00',
          assignedTo: 'child_bo',
          assignedToName: 'Cu Bo',
          creatorId: 'parent_dad',
          taskType: TaskType.assign,
          taskStatus: TaskStatus.pending,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    const Text('Top Header Calendar Content'),
                    ReminderListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      allReminders: [task],
                      displayedReminders: [task],
                      currentUserId: 'parent_dad',
                      selectedDateStr: '07/11/2026',
                      isShowingAll: false,
                      onCreatePressed: () {},
                      onShowAllPressed: () {},
                      onTapReminder: (_) {},
                      onCompleteReminder: (_) {},
                      onDeleteReminder: (_) {},
                      onClaimReminder: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Top Header Calendar Content'), findsOneWidget);
        expect(find.text('Tưới cây cảnh'), findsOneWidget);
      });

      test('6.9 Concurrency: If reward price increases while child has insufficient stars, redemption throws ITEM_PRICE_CHANGED and 0 stars are deducted', () async {
        final starService = StarEconomyService();
        starService.seedMemberBalance('fam_race', 'child_bo', 2); // Cu Bo chỉ có 2 sao
        
        final item = WishlistRewardItem(
          id: 'reward_ice_cream',
          familyId: 'fam_race',
          title: 'Kem sô-cô-la',
          starCost: 1, // Snapshot cũ là 1 sao
          createdBy: 'parent_mom',
          createdByName: 'Mẹ Lan',
          createdAt: DateTime.now(),
        );
        starService.wishlistCatalog[item.id] = item;

        // Phụ huynh vừa cập nhật giá thành 10 sao
        starService.wishlistCatalog[item.id] = item.copyWith(starCost: 10);

        // Cu Bo bấm đổi với snapshot cũ (1 sao)
        expect(
          () => starService.submitWishlistRedemption(
            familyId: 'fam_race',
            childId: 'child_bo',
            childName: 'Cu Bo',
            item: item,
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ITEM_PRICE_CHANGED'),
          )),
        );

        // Số dư của Cu Bo vẫn nguyên vẹn 2 sao (không bị trừ oan)
        expect(starService.getBalance('fam_race', 'child_bo'), 2);
      });

      test('6.10 Soft Delete & Auto Refund: Removing reward item automatically cancels and refunds 100% stars for PENDING claims', () async {
        final starService = StarEconomyService();
        starService.seedMemberBalance('fam_soft_del', 'child_bo', 50);

        final item = WishlistRewardItem(
          id: 'reward_book',
          familyId: 'fam_soft_del',
          title: 'Sách truyện Harry Potter',
          starCost: 30,
          createdBy: 'parent_dad',
          createdByName: 'Bố Tuấn',
          createdAt: DateTime.now(),
        );
        starService.wishlistCatalog[item.id] = item;

        // Cu Bo đổi quà: 50 - 30 = 20 sao
        final claim = await starService.submitWishlistRedemption(
          familyId: 'fam_soft_del',
          childId: 'child_bo',
          childName: 'Cu Bo',
          item: item,
          claimId: 'claim_book_1',
        );
        expect(claim.status, WishlistClaimStatus.pending);
        expect(starService.getBalance('fam_soft_del', 'child_bo'), 20);

        // Phụ huynh xóa món quà khỏi shop
        await starService.removeWishlistRewardItem(
          familyId: 'fam_soft_del',
          itemId: item.id,
          removerId: 'parent_dad',
          removerName: 'Bố Tuấn',
          removerRole: 'PARENT',
        );

        // Claim chuyển sang rejected và hoàn 100% sao (20 + 30 = 50 sao)
        expect(starService.wishlistClaims['claim_book_1']?.status, WishlistClaimStatus.rejected);
        expect(starService.getBalance('fam_soft_del', 'child_bo'), 50);
        expect(starService.starLedger.containsKey('refund_claim_book_1'), isTrue);
      });

      test('6.11 Star Jackpot: Sole member (1 person family) achieves 100% consensus and triggers shake battle immediately', () async {
        final jackpotService = FamilyJackpotService.instance;
        jackpotService.overrideCanUseJackpotForTest = true;
        jackpotService.initForFamily('fam_sole');
        await jackpotService.contributeStars(
          stars: 10,
          memberId: 'system_daily_mission',
          memberName: 'Cả nhà điểm danh',
        );

        // Gia đình 1 thành viên
        expect(jackpotService.hasReachedShakeConsensus, isTrue);
        final started = await jackpotService.voteToShakeNow(
          userId: 'u_sole',
          userName: 'Người dùng đơn thân',
        );
        expect(started, isTrue);
        expect(jackpotService.jackpot.isShaking, isTrue);
      });

      test('6.12 Account-Level Premium: PaymentService maintains isPremium across families when account has active subscription', () async {
        final paymentService = PaymentService();
        paymentService.clearFamily();
        expect(paymentService.isPremium, isFalse);

        await paymentService.activatePremium(planName: 'Family Hub Premium', maxMembers: 10);
        expect(paymentService.isPremium, isTrue);
        expect(paymentService.memberLimit, 10);

        // Chuyển sang gia đình mới được tạo mà không làm mất trạng thái Premium
        paymentService.setFamilyId('fam_new_created');
        expect(paymentService.isPremium, isTrue);
      });
    });

  });
}

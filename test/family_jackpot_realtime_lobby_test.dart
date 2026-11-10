import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/models/family_jackpot_model.dart';
import 'package:fhub/Danh/screens/family_jackpot_screen.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';
import 'package:fhub/Long/models/family_member_model.dart';
import 'package:fhub/Long/models/user_model.dart';

void main() {
  group('Realtime Multiplayer Jackpot Lobby & 5-Minute Ticket Tests', () {
    test('1. Model: Lobby fields defaults and serialization (toMap & fromMap)', () {
      final now = DateTime.now();
      final expires = now.add(const Duration(minutes: 5));

      final model = FamilyJackpotModel(
        familyId: 'fam_123',
        totalPoolAmount: 50,
        lobbyStatus: 'waiting',
        lobbyInitiatorId: 'dad_01',
        lobbyInitiatorName: 'Bố Tuấn',
        lobbyCreatedAt: now,
        lobbyExpiresAt: expires,
        lobbyTargetMemberIds: ['dad_01', 'mom_02', 'kid_03'],
        lobbyAcceptedMemberIds: ['dad_01'],
      );

      expect(model.isLobbyActive, isTrue);
      expect(model.remainingLobbySeconds, inInclusiveRange(290, 300));
      expect(model.hasAllTargetMembersAccepted, isFalse);

      final map = model.toMap();
      expect(map['lobbyStatus'], 'waiting');
      expect(map['lobbyInitiatorId'], 'dad_01');
      expect(map['lobbyInitiatorName'], 'Bố Tuấn');
      expect(map['lobbyTargetMemberIds'], ['dad_01', 'mom_02', 'kid_03']);
      expect(map['lobbyAcceptedMemberIds'], ['dad_01']);

      final restored = FamilyJackpotModel.fromMap('fam_123', map);
      expect(restored.lobbyStatus, 'waiting');
      expect(restored.lobbyInitiatorId, 'dad_01');
      expect(restored.lobbyInitiatorName, 'Bố Tuấn');
      expect(restored.lobbyTargetMemberIds, ['dad_01', 'mom_02', 'kid_03']);
      expect(restored.lobbyAcceptedMemberIds, ['dad_01']);
      expect(restored.isLobbyActive, isTrue);
    });

    test('2. Model: Lobby expiration when 5 minutes elapse', () {
      final expiredTime = DateTime.now().subtract(const Duration(seconds: 1));
      final expiredModel = FamilyJackpotModel(
        familyId: 'fam_123',
        totalPoolAmount: 50,
        lobbyStatus: 'waiting',
        lobbyExpiresAt: expiredTime,
      );

      expect(expiredModel.isLobbyActive, isFalse, reason: 'Khi qua thời gian expiresAt thì phòng chờ không còn active');
      expect(expiredModel.remainingLobbySeconds, 0);
    });

    test('3. Model: hasAllTargetMembersAccepted triggers when all target members accept', () {
      final now = DateTime.now();
      final expires = now.add(const Duration(minutes: 5));

      var model = FamilyJackpotModel(
        familyId: 'fam_123',
        totalPoolAmount: 50,
        lobbyStatus: 'waiting',
        lobbyExpiresAt: expires,
        lobbyTargetMemberIds: ['dad_01', 'mom_02', 'kid_03'],
        lobbyAcceptedMemberIds: ['dad_01'],
      );

      expect(model.hasAllTargetMembersAccepted, isFalse);

      // Mẹ đồng ý
      model = model.copyWith(lobbyAcceptedMemberIds: ['dad_01', 'mom_02']);
      expect(model.hasAllTargetMembersAccepted, isFalse);

      // Con đồng ý -> Đủ 100%
      model = model.copyWith(lobbyAcceptedMemberIds: ['dad_01', 'mom_02', 'kid_03']);
      expect(model.hasAllTargetMembersAccepted, isTrue);
    });

    test('4. Service: Parent initiates 5-minute lobby with selected members', () async {
      final service = FamilyJackpotService.instance;
      service.overrideCanUseJackpotForTest = true;
      await service.resetJackpot();
      await service.contributeStars(stars: 60, memberId: 'dad_01', memberName: 'Bố Tuấn');

      expect(service.jackpot.totalPoolAmount, 60);
      expect(service.jackpot.isLobbyActive, isFalse);

      // Bố phát động nổ hũ cho Bố, Mẹ, Con
      await service.initiateJackpotLobby(
        initiatorId: 'dad_01',
        initiatorName: 'Bố Tuấn',
        targetMemberIds: ['dad_01', 'mom_02', 'kid_03'],
      );

      expect(service.jackpot.isLobbyActive, isTrue);
      expect(service.jackpot.lobbyStatus, 'waiting');
      expect(service.jackpot.lobbyInitiatorId, 'dad_01');
      expect(service.jackpot.lobbyTargetMemberIds, ['dad_01', 'mom_02', 'kid_03']);
      expect(service.jackpot.lobbyAcceptedMemberIds, ['dad_01'], reason: 'Người phát động tự động được tính là đã tham gia');
      expect(service.jackpot.remainingLobbySeconds, inInclusiveRange(295, 300));
    });

    test('5. Service: 100% member acceptance automatically starts the 30-second shake battle', () async {
      final service = FamilyJackpotService.instance;
      service.overrideCanUseJackpotForTest = true;
      await service.resetJackpot();
      await service.contributeStars(stars: 100, memberId: 'dad_01', memberName: 'Bố Tuấn');

      await service.initiateJackpotLobby(
        initiatorId: 'dad_01',
        initiatorName: 'Bố Tuấn',
        targetMemberIds: ['dad_01', 'mom_02'],
      );

      expect(service.jackpot.isLobbyActive, isTrue);
      expect(service.jackpot.isShaking, isFalse);

      // Mẹ bấm xác nhận tham gia
      await service.acceptJackpotLobby(userId: 'mom_02', userName: 'Mẹ Lan');

      // Khi 2/2 người đã chấp nhận -> Tự động kích hoạt lắc 30s
      expect(service.jackpot.isShaking, isTrue);
      expect(service.jackpot.lobbyStatus, 'started');
      expect(service.jackpot.remainingShakeSeconds, inInclusiveRange(28, 30));
    });

    test('6. Service: Parent can trigger start early with currently present members', () async {
      final service = FamilyJackpotService.instance;
      service.overrideCanUseJackpotForTest = true;
      await service.resetJackpot();
      await service.contributeStars(stars: 80, memberId: 'dad_01', memberName: 'Bố Tuấn');

      // Chọn 3 người nhưng mới có 2 người bấm tham gia
      await service.initiateJackpotLobby(
        initiatorId: 'dad_01',
        initiatorName: 'Bố Tuấn',
        targetMemberIds: ['dad_01', 'mom_02', 'kid_03'],
      );
      await service.acceptJackpotLobby(userId: 'mom_02', userName: 'Mẹ Lan');

      expect(service.jackpot.isLobbyActive, isTrue);
      expect(service.jackpot.isShaking, isFalse);

      // Phụ huynh quyết định bấm "Bắt đầu ngay" sớm không cần chờ bé út
      await service.startShakeBattleEarly(initiatorId: 'dad_01');

      expect(service.jackpot.isShaking, isTrue);
      expect(service.jackpot.lobbyStatus, 'started');
    });

    test('7. Service: Single-member family immediately triggers shake without 5-min waiting', () async {
      final service = FamilyJackpotService.instance;
      service.overrideCanUseJackpotForTest = true;
      await service.resetJackpot();
      await service.contributeStars(stars: 40, memberId: 'solo_user', memberName: 'Một Mình');

      await service.initiateJackpotLobby(
        initiatorId: 'solo_user',
        initiatorName: 'Một Mình',
        targetMemberIds: ['solo_user'],
      );

      // Với gia đình 1 người, tự động vào hiệp lắc ngay
      expect(service.jackpot.isShaking, isTrue);
      expect(service.jackpot.lobbyStatus, 'started');
    });

    test('8. Star Distribution: Payout correctly awards accepted lobby participants and resets lobby', () async {
      final service = FamilyJackpotService.instance;
      service.overrideCanUseJackpotForTest = true;
      await service.resetJackpot();
      await service.contributeStars(stars: 100, memberId: 'dad_01', memberName: 'Bố Tuấn');

      await service.initiateJackpotLobby(
        initiatorId: 'dad_01',
        initiatorName: 'Bố Tuấn',
        targetMemberIds: ['dad_01', 'mom_02'],
      );
      await service.acceptJackpotLobby(userId: 'mom_02', userName: 'Mẹ Lan');

      // Cả hai người lắc
      final result = await service.distributeStarPotNow(
        overrideShakeCounts: {'dad_01': 20, 'mom_02': 40},
        overrideParticipantIds: ['dad_01', 'mom_02'],
      );

      expect(result.prizes.length, 2);
      final totalPaid = result.prizes.values.fold<int>(0, (a, b) => a + b);
      expect(totalPaid, 100, reason: '100% quỹ 100 sao được trao cho các thành viên tham gia');
      expect(service.jackpot.status, JackpotStatus.finished);
      expect(service.jackpot.lobbyStatus, 'idle', reason: 'Lobby được reset về idle sau khi nổ hũ xong');
    });

    testWidgets('9. UI Finished State: Renders "Nhận sao từ hũ" and "Góp sao hũ mới"', (tester) async {
      final service = FamilyJackpotService.instance;
      service.overrideCanUseJackpotForTest = true;
      service.initForFamily('f1');
      await service.resetJackpot();

      await service.contributeStars(stars: 10, memberId: 'u1', memberName: 'Trần Văn');
      await service.distributeStarPotNow(
        overrideShakeCounts: {'u1': 20},
        overrideParticipantIds: ['u1'],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: FamilyJackpotScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Vào Cửa Hàng Đổi Quà'), findsOneWidget);
      expect(find.text('Nuôi Heo Đất đợt mới'), findsOneWidget);
      expect(find.textContaining('Rút Tiền Thưởng Về Ngân Hàng'), findsNothing);
      expect(find.text('Góp Vui Hũ Mới & Chơi Tiếp'), findsNothing);
    });

    testWidgets('10. UI Empty Pot SnackBar and Lobby Ratio Sanity: Ratio never shows inverted 2/1', (tester) async {
      final service = FamilyJackpotService.instance;
      service.overrideCanUseJackpotForTest = true;
      service.initForFamily('f1');
      await service.resetJackpot();

      // Test Empty Pot SnackBar
      await tester.pumpWidget(
        const MaterialApp(
          home: FamilyJackpotScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final emptyBtn = find.textContaining('Heo Đất Trống (0 ⭐)');
      expect(emptyBtn, findsOneWidget);
      await tester.ensureVisible(emptyBtn);
      await tester.pumpAndSettle();
      await tester.tap(emptyBtn);
      await tester.pump();

      expect(find.textContaining('Điểm danh mỗi ngày'), findsOneWidget);

      // Test Lobby: Initiated with 2 targets, second member accepts -> ratio is 2/2, NOT 2/1
      await service.contributeStars(stars: 10, memberId: 'u1', memberName: 'Trần Văn');
      await service.initiateJackpotLobby(
        initiatorId: 'u1',
        initiatorName: 'Trần Văn',
        targetMemberIds: ['u1', 'u2'],
      );
      expect(service.jackpot.isLobbyActive, isTrue);

      await tester.pump();
      expect(find.textContaining('(1/2)'), findsOneWidget);
      expect(find.textContaining('(2/1)'), findsNothing);

      // u2 accepts -> completes 100% acceptance
      await service.acceptJackpotLobby(userId: 'u2', userName: 'Lương Vinh');
      expect(service.jackpot.isShaking, isTrue);

      await service.resetJackpot();
    });

    test('11. Daily Check-in mission idempotency: +10 ⭐ is awarded strictly ONCE per day and persists across resetJackpot', () async {
      final service = FamilyJackpotService.instance;
      service.overrideCanUseJackpotForTest = true;
      service.resetDailyMissionStateForTesting();
      await service.resetJackpot();

      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      expect(service.isDailyCheckInCompletedToday(), isFalse);
      expect(service.jackpot.totalPoolStars, 0);

      // Member 1 checks in
      final firstCheck = await service.checkInDaily(userId: 'u1', userName: 'Member 1', totalFamilyMembers: 2);
      expect(firstCheck, isFalse);
      expect(service.jackpot.totalPoolStars, 0);
      expect(service.isDailyCheckInCompletedToday(), isFalse);

      // Member 2 checks in -> Threshold (2) reached -> Awards +10 ⭐
      final secondCheck = await service.checkInDaily(userId: 'u2', userName: 'Member 2', totalFamilyMembers: 2);
      expect(secondCheck, isTrue);
      expect(service.jackpot.totalPoolStars, 10);
      expect(service.isDailyCheckInCompletedToday(), isTrue);
      expect(service.jackpot.lastDailyCheckInAwardedDate, todayStr);
      expect(service.jackpot.dailyCheckInAwardedDates.contains(todayStr), isTrue);

      // Repeated check-in attempts on the same day MUST NOT add any more stars!
      final duplicateCheck = await service.checkInDaily(userId: 'u1', userName: 'Member 1', totalFamilyMembers: 2);
      expect(duplicateCheck, isFalse);
      expect(service.jackpot.totalPoolStars, 10);

      // Member sync MUST NOT add stars again
      final mockMembers = [
        FamilyMemberModel(
          familyId: 'f1',
          user: UserModel(id: 'u1', name: 'Member 1', email: 'u1@test.com'),
          role: Role.owner,
          lastCheckInAt: DateTime.now(),
        ),
        FamilyMemberModel(
          familyId: 'f1',
          user: UserModel(id: 'u2', name: 'Member 2', email: 'u2@test.com'),
          role: Role.member,
          lastCheckInAt: DateTime.now(),
        ),
      ];
      await service.syncCheckInsFromMembers(mockMembers);
      expect(service.jackpot.totalPoolStars, 10);

      // CRITICAL: Reset jackpot (after shake battle or user action)
      await service.resetJackpot();
      expect(service.jackpot.totalPoolStars, 0); // Pool resets to 0
      // BUT daily check-in completed status MUST PERSIST for today!
      expect(service.isDailyCheckInCompletedToday(), isTrue);
      expect(service.jackpot.lastDailyCheckInAwardedDate, todayStr);

      // Now sync or check-in again -> STILL BLOCKED, does NOT re-award +10 ⭐!
      await service.syncCheckInsFromMembers(mockMembers);
      expect(service.jackpot.totalPoolStars, 0); // Still 0, no duplicate +10!
      final postResetCheck = await service.checkInDaily(userId: 'u1', userName: 'Member 1', totalFamilyMembers: 2);
      expect(postResetCheck, isFalse);
      expect(service.jackpot.totalPoolStars, 0);
    });

    test('12. Model serialization: lastDailyCheckInAwardedDate & dailyCheckInAwardedDates serialize and deserialize properly', () {
      final model = FamilyJackpotModel(
        familyId: 'f1',
        totalPoolAmount: 50,
        lastDailyCheckInAwardedDate: '2026-11-08',
        dailyCheckInAwardedDates: const ['2026-11-07', '2026-11-08'],
        dailyCheckedInMemberIds: const ['u1', 'u2'],
      );

      final map = model.toMap();
      expect(map['lastDailyCheckInAwardedDate'], '2026-11-08');
      expect(map['dailyCheckInAwardedDates'], ['2026-11-07', '2026-11-08']);
      expect(map['dailyCheckedInMemberIds'], ['u1', 'u2']);

      final restored = FamilyJackpotModel.fromMap('f1', map);
      expect(restored.lastDailyCheckInAwardedDate, '2026-11-08');
      expect(restored.dailyCheckInAwardedDates, containsAll(['2026-11-07', '2026-11-08']));
      expect(restored.dailyCheckedInMemberIds, containsAll(['u1', 'u2']));
      expect(restored.isDailyCheckInAwardedForDate('2026-11-08'), isTrue);
      expect(restored.isDailyCheckInAwardedForDate('2026-11-09'), isFalse);
    });

    test('13. 10% Cashback rounding logic & detailed ledger description: >= 0.5 rounds up, < 0.5 rounds down, records raw and rounded', () async {
      final service = FamilyJackpotService.instance;
      service.overrideCanUseJackpotForTest = true;
      service.resetDailyMissionStateForTesting();
      await service.resetJackpot();

      // Case A: 15 stars -> 10% = 1.5 -> remainder 0.5 >= 0.5 -> rounds up to 2
      final rawCashbackA = 15 * 0.1; // 1.5
      final remainderA = rawCashbackA - rawCashbackA.floor();
      final roundedA = remainderA >= 0.5 ? rawCashbackA.ceil() : rawCashbackA.floor();
      expect(roundedA, 2);

      await service.contributeStars(
        stars: roundedA,
        familyId: 'f1',
        memberId: 'child_1',
        memberName: 'Bé Na',
        sourceTaskId: 'cashback_claim_01',
        rawStars: rawCashbackA,
      );
      expect(service.jackpot.totalPoolStars, 2);

      final txA = service.localWalletTransactions.firstWhere((t) => t.title.contains('Tích điểm 10%'));
      expect(txA.amount, 2);
      expect(txA.description, contains('Gốc 10%: 1.5 ⭐, làm tròn: +2 ⭐'));

      // Case B: 14 stars -> 10% = 1.4 -> remainder 0.4 < 0.5 -> rounds down to 1
      final rawCashbackB = 14 * 0.1; // 1.4
      final remainderB = rawCashbackB - rawCashbackB.floor();
      final roundedB = remainderB >= 0.5 ? rawCashbackB.ceil() : rawCashbackB.floor();
      expect(roundedB, 1);

      await service.contributeStars(
        stars: roundedB,
        familyId: 'f1',
        memberId: 'child_2',
        memberName: 'Bé Bi',
        sourceTaskId: 'cashback_claim_02',
        rawStars: rawCashbackB,
      );
      expect(service.jackpot.totalPoolStars, 3); // 2 + 1 = 3

      final txB = service.localWalletTransactions.firstWhere((t) => t.description?.contains('1.4') == true);
      expect(txB.amount, 1);
      expect(txB.description, contains('Gốc 10%: 1.4 ⭐, làm tròn: +1 ⭐'));

      // Case C: 3 stars -> 10% = 0.3 -> remainder 0.3 < 0.5 -> floor = 0 -> minimum 1 star
      final rawCashbackC = 3 * 0.1; // 0.3
      final remainderC = rawCashbackC - rawCashbackC.floor();
      final roundedC = remainderC >= 0.5 ? rawCashbackC.ceil() : rawCashbackC.floor();
      final effectiveC = roundedC > 0 ? roundedC : 1;
      expect(effectiveC, 1);

      await service.contributeStars(
        stars: effectiveC,
        familyId: 'f1',
        memberId: 'child_3',
        memberName: 'Bé Bắp',
        sourceTaskId: 'cashback_claim_03',
        rawStars: rawCashbackC,
      );
      expect(service.jackpot.totalPoolStars, 4); // 3 + 1 = 4

      final txC = service.localWalletTransactions.firstWhere((t) => t.description?.contains('0.3') == true);
      expect(txC.amount, 1);
      expect(txC.description, contains('Gốc 10%: 0.3 ⭐, làm tròn: +1 ⭐'));
    });
  });
}

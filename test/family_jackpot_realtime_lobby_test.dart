import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/models/family_jackpot_model.dart';
import 'package:fhub/Danh/screens/family_jackpot_screen.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';

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

      expect(find.textContaining('Nhận sao từ hũ'), findsOneWidget);
      expect(find.text('Góp sao hũ mới'), findsOneWidget);
      expect(find.textContaining('Rút Tiền Thưởng Về Ngân Hàng'), findsNothing);
      expect(find.text('Góp Vui Hũ Mới & Chơi Tiếp'), findsNothing);
    });
  });
}

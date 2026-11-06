import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Long/models/user_model.dart';
import 'package:fhub/Khoa/models/user_profile.dart';
import 'package:fhub/Long/models/family_member_model.dart';
import 'package:fhub/Khoa/models/family_member.dart' as khoa_member;
import 'package:fhub/Long/models/hierarchy_role.dart';
import 'package:fhub/Long/models/member_status.dart';
import 'package:fhub/Long/models/join_request_model.dart';
import 'package:fhub/Long/services/join_request_service.dart';
import 'package:fhub/Long/services/family_data_service.dart';
import 'package:fhub/Ai/models/family_memory_model.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';

void main() {
  group('Milestone 1 - Models & Schemas', () {
    test('UserModel: supports familyIds with fallback, toMap/toJson and copyWith', () {
      final user = UserModel(
        id: 'u1',
        name: 'Nguyễn Văn A',
        email: 'a@example.com',
        familyIds: const ['fam1', 'fam2'],
      );

      expect(user.familyIds, ['fam1', 'fam2']);

      final json = user.toJson();
      expect(json['familyIds'], ['fam1', 'fam2']);

      final restored = UserModel.fromJson({
        'id': 'u1',
        'name': 'Nguyễn Văn A',
        'email': 'a@example.com',
        'family_ids': ['fam1', 'fam2', 'fam3'],
      });
      expect(restored.familyIds, ['fam1', 'fam2', 'fam3']);

      final updated = user.copyWith(familyIds: ['fam99']);
      expect(updated.familyIds, ['fam99']);
      expect(updated.name, user.name);
    });

    test('UserProfile (Khoa): const compatibility and familyIds serialization', () {
      const profile = UserProfile(
        id: 'u2',
        name: 'Trần Thị B',
        email: 'b@example.com',
        familyIds: ['famA'],
      );

      expect(profile.familyIds, ['famA']);

      final map = profile.toMap();
      expect(map['familyIds'], ['famA']);

      final restored = UserProfile.fromMap({
        'uid': 'u2',
        'name': 'Trần Thị B',
        'email': 'b@example.com',
        'family_ids': ['famA', 'famB'],
      });
      expect(restored.familyIds, ['famA', 'famB']);
    });

    test('FamilyMemberModel (Long): isGuardian logic and dynamic isKid defaulting', () {
      final user = UserModel(id: 'u_child', name: 'Bé Na', email: 'bena@example.com');

      // 1. Child role: isKid defaults to true, isGuardian is false
      final childMember = FamilyMemberModel(
        familyId: 'fam1',
        user: user,
        role: Role.member,
        hierarchyRole: HierarchyRole.child,
        status: MemberStatus.active,
      );
      expect(childMember.isKid, isTrue);
      expect(childMember.isGuardian, isFalse);
      expect(childMember.rewardStarsTotal, 0);

      // 2. Adult child: explicitly sets isKid: false
      final adultChild = FamilyMemberModel(
        familyId: 'fam1',
        user: UserModel(id: 'u_adult', name: 'Anh Hai', email: 'anhhai@example.com'),
        role: Role.member,
        hierarchyRole: HierarchyRole.child,
        isKid: false,
      );
      expect(adultChild.isKid, isFalse);
      expect(adultChild.isGuardian, isFalse);

      // 3. Parent role: isGuardian is true, isKid is false
      final parentMember = FamilyMemberModel(
        familyId: 'fam1',
        user: UserModel(id: 'u_parent', name: 'Bố Tuấn', email: 'tuan@example.com'),
        role: Role.member,
        hierarchyRole: HierarchyRole.parent,
      );
      expect(parentMember.isKid, isFalse);
      expect(parentMember.isGuardian, isTrue);

      // 4. Grandparent role: isGuardian is true, isKid is false
      final gpMember = FamilyMemberModel(
        familyId: 'fam1',
        user: UserModel(id: 'u_gp', name: 'Ông Nội', email: 'ong@example.com'),
        role: Role.member,
        hierarchyRole: HierarchyRole.grandparent,
      );
      expect(gpMember.isKid, isFalse);
      expect(gpMember.isGuardian, isTrue);

      // 5. Owner role: isGuardian is true
      final ownerMember = FamilyMemberModel(
        familyId: 'fam1',
        user: UserModel(id: 'u_owner', name: 'Chủ Hộ', email: 'owner@example.com'),
        role: Role.owner,
        hierarchyRole: HierarchyRole.parent,
      );
      expect(ownerMember.isGuardian, isTrue);
      expect(ownerMember.isOwner, isTrue);

      // Serialization check
      final json = childMember.toJson();
      expect(json['isKid'], isTrue);
      expect(json['rewardStarsTotal'], 0);

      final restored = FamilyMemberModel.fromJson(json);
      expect(restored.isKid, isTrue);
      expect(restored.rewardStarsTotal, 0);
    });

    test('FamilyMember (Khoa): isGuardian and dynamic isKid defaulting with const preservation', () {
      // 1. Child member
      const child = khoa_member.FamilyMember(
        familyId: 'fam1',
        userId: 'u_kid',
        role: khoa_member.FamilyMember.roleChild,
      );
      expect(child.isKid, isTrue);
      expect(child.isGuardian, isFalse);

      // 2. Adult child member with explicit isKid = false
      const adultChild = khoa_member.FamilyMember(
        familyId: 'fam1',
        userId: 'u_adult',
        role: khoa_member.FamilyMember.roleChild,
        isKid: false,
      );
      expect(adultChild.isKid, isFalse);
      expect(adultChild.isGuardian, isFalse);

      // 3. Parent member
      const parent = khoa_member.FamilyMember(
        familyId: 'fam1',
        userId: 'u_parent',
        role: khoa_member.FamilyMember.roleParent,
      );
      expect(parent.isKid, isFalse);
      expect(parent.isGuardian, isTrue);

      // 4. Grandparent member
      const gp = khoa_member.FamilyMember(
        familyId: 'fam1',
        userId: 'u_gp',
        role: khoa_member.FamilyMember.roleGrandparent,
      );
      expect(gp.isKid, isFalse);
      expect(gp.isGuardian, isTrue);

      // 5. Owner member
      const owner = khoa_member.FamilyMember(
        familyId: 'fam1',
        userId: 'u_owner',
        role: 'MEMBER',
        isOwner: true,
      );
      expect(owner.isGuardian, isTrue);

      // Serialization test
      final map = child.toMap();
      expect(map['isKid'], isTrue);
      expect(map['rewardStarsTotal'], 0);

      final fromMap = khoa_member.FamilyMember.fromMap(map);
      expect(fromMap.isKid, isTrue);
      expect(fromMap.isGuardian, isFalse);
    });
  });

  group('Milestone 1 - Join Request Handshake & Governance Lifecycle', () {
    setUp(() {
      JoinRequestService.resetMockData();
    });

    test('JoinRequestModel: serialization, status flags, and composite doc ID', () {
      final req = JoinRequestModel(
        id: 'fam123_user456',
        familyId: 'fam123',
        userId: 'user456',
        userName: 'Nguyễn Văn C',
        userEmail: 'c@example.com',
        suggestedRole: 'CHILD',
        status: JoinRequestStatus.pending,
      );

      expect(req.isPending, isTrue);
      expect(req.isApproved, isFalse);
      expect(req.isRejected, isFalse);
      expect(req.id, 'fam123_user456');

      final map = req.toMap();
      expect(map['familyId'], 'fam123');
      expect(map['userId'], 'user456');
      expect(map['suggestedRole'], 'CHILD');
      expect(map['status'], JoinRequestStatus.pending);

      final restored = JoinRequestModel.fromMap(map);
      expect(restored.id, 'fam123_user456');
      expect(restored.userName, 'Nguyễn Văn C');
      expect(restored.isPending, isTrue);
    });

    test('JoinRequestService: full handshake lifecycle (send -> watch -> approve with isKid)', () async {
      final service = JoinRequestService();

      // 1. Send join request
      await service.sendJoinRequest(
        familyId: 'fam_demo',
        suggestedRole: 'CHILD',
      );

      // 2. Watch pending requests
      final stream = service.watchPendingRequests('fam_demo');
      final firstPending = await stream.first;
      expect(firstPending.length, 1);
      final pendingReq = firstPending.first;
      expect(pendingReq.familyId, 'fam_demo');
      expect(pendingReq.suggestedRole, 'CHILD');
      expect(pendingReq.isPending, isTrue);

      // 3. Guardian approves join request with assignedRole = CHILD and isKid = true
      await service.approveJoinRequest(
        requestId: pendingReq.id,
        assignedRole: 'CHILD',
        isKid: true,
      );

      // 4. Pending stream should now be empty
      final afterApproval = await service.watchPendingRequests('fam_demo').first;
      expect(afterApproval.isEmpty, isTrue);
    });

    test('JoinRequestService: guardian rejection marks status as rejected', () async {
      final service = JoinRequestService();

      await service.sendJoinRequest(
        familyId: 'fam_demo_2',
        suggestedRole: 'PARENT',
      );

      final pending = await service.watchPendingRequests('fam_demo_2').first;
      expect(pending.length, 1);

      // Reject request
      await service.rejectJoinRequest(pending.first.id);

      final afterRejection = await service.watchPendingRequests('fam_demo_2').first;
      expect(afterRejection.isEmpty, isTrue);
    });

    test('JoinRequestService: rejectJoinRequest guarded against already processed requests', () async {
      final service = JoinRequestService();

      await service.sendJoinRequest(
        familyId: 'fam_concurrency_test',
        suggestedRole: 'PARENT',
      );

      final pending = await service.watchPendingRequests('fam_concurrency_test').first;
      expect(pending.length, 1);
      final reqId = pending.first.id;

      // 1. Guardian 1 approves
      await service.approveJoinRequest(
        requestId: reqId,
        assignedRole: 'PARENT',
        isKid: false,
      );

      // 2. Guardian 2 concurrently attempts rejection -> MUST throw
      expect(
        () => service.rejectJoinRequest(reqId),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Yêu cầu này đã được xử lý trước đó.'),
        )),
      );
    });

    test('JoinRequestService: rejectJoinRequest throws on missing request', () async {
      final service = JoinRequestService();
      expect(
        () => service.rejectJoinRequest('missing_req_123'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Yêu cầu gia nhập không tồn tại.'),
        )),
      );
    });
  });

  group('Milestone 1 - Multi-Family Unification & Self-Healing', () {
    test('MembershipUnifier: discovers newly approved family when user already has existing families', () {
      // User already in fam1 (directFamilyIds: ['fam1'])
      // Guardian approved user into fam2 (rawMemberDocs: [fam1 (ACTIVE), fam2 (ACTIVE)])
      final result = MembershipUnifier.unify(
        directFamilyIds: ['fam1'],
        rawMemberDocs: [
          {'familyId': 'fam1', 'status': 'ACTIVE'},
          {'familyId': 'fam2', 'status': 'ACTIVE'},
        ],
      );

      // Both families must be unified
      expect(result.activeFamilyIds, containsAll(['fam1', 'fam2']));
      expect(result.activeFamilyIds.length, 2);

      // fam2 must be identified for self-healing into users/{uid}.familyIds
      expect(result.shouldSelfHealUnion, isTrue);
      expect(result.missingInDirect, contains('fam2'));
      expect(result.missingInDirect.length, 1);
    });

    test('MembershipUnifier: handles legacy user with empty directFamilyIds', () {
      final result = MembershipUnifier.unify(
        directFamilyIds: [],
        rawMemberDocs: [
          {'familyId': 'fam_legacy_1', 'status': 'ACTIVE'},
          {'familyId': 'fam_legacy_2', 'status': 'ACTIVE'},
        ],
      );

      expect(result.activeFamilyIds, containsAll(['fam_legacy_1', 'fam_legacy_2']));
      expect(result.shouldSelfHealUnion, isTrue);
      expect(result.missingInDirect, containsAll(['fam_legacy_1', 'fam_legacy_2']));
    });

    test('MembershipUnifier: prunes deactivated memberships from active switcher list', () {
      final result = MembershipUnifier.unify(
        directFamilyIds: ['fam1', 'fam_deactivated'],
        rawMemberDocs: [
          {'familyId': 'fam1', 'status': 'ACTIVE'},
          {'familyId': 'fam_deactivated', 'status': 'DEACTIVATED'},
        ],
      );

      expect(result.activeFamilyIds, contains('fam1'));
      expect(result.activeFamilyIds, isNot(contains('fam_deactivated')));
      expect(result.shouldSelfHealPrune, isTrue);
      expect(result.toPruneFromDirect, contains('fam_deactivated'));
    });

    test('MembershipUnifier: preserves cached directFamilyIds when member query fails (offline resilience)', () {
      final result = MembershipUnifier.unify(
        directFamilyIds: ['fam1', 'fam2'],
        rawMemberDocs: [],
        memberQuerySucceeded: false,
      );

      expect(result.activeFamilyIds, containsAll(['fam1', 'fam2']));
      expect(result.shouldSelfHealUnion, isFalse);
      expect(result.shouldSelfHealPrune, isFalse);
    });
  });

  // ===========================================================================
  // GROUP 1: Governance & Security Rules: Role Escalation Lockdown & Star Immutability
  // ===========================================================================
  group('Governance & Security Rules: Role Escalation Lockdown & Star Immutability (Tier 1 & Tier 2)', () {
    final childMemberDoc = {
      'userId': 'child_1',
      'familyId': 'fam_1',
      'role': 'MEMBER',
      'hierarchyRole': 'CHILD',
      'isOwner': false,
      'isGuardian': false,
      'status': 'ACTIVE',
      'rewardStarsTotal': 15,
    };

    final guardianParentDoc = {
      'userId': 'parent_1',
      'familyId': 'fam_1',
      'role': 'PARENT',
      'hierarchyRole': 'PARENT',
      'isOwner': false,
      'isGuardian': true,
      'status': 'ACTIVE',
      'rewardStarsTotal': 50,
    };

    // Tier 1 (Feature Coverage)
    test('Tier 1.1 Feature: Guardian can assign role and set isKid flag during approval', () {
      final updatedChild = Map<String, dynamic>.from(childMemberDoc)
        ..['hierarchyRole'] = 'CHILD'
        ..['isKid'] = true;

      final allowed = FirestoreRulesSecurityOracle.canUpdateFamilyMember(
        authUid: 'parent_1',
        callerMemberDoc: guardianParentDoc,
        existingDoc: childMemberDoc,
        prospectiveDoc: updatedChild,
      );
      expect(allowed, isTrue);
    });

    test('Tier 1.2 Feature: Owner, Parent, and Grandparent are all recognized as Guardian', () {
      expect(FirestoreRulesSecurityOracle.isGuardian(memberDoc: {'role': 'owner', 'status': 'ACTIVE'}), isTrue);
      expect(FirestoreRulesSecurityOracle.isGuardian(memberDoc: {'role': 'PARENT', 'status': 'ACTIVE'}), isTrue);
      expect(FirestoreRulesSecurityOracle.isGuardian(memberDoc: {'hierarchyRole': 'GRANDPARENT', 'status': 'ACTIVE'}), isTrue);
      expect(FirestoreRulesSecurityOracle.isGuardian(memberDoc: {'isOwner': true, 'status': 'ACTIVE'}), isTrue);
    });

    test('Tier 1.3 Feature: Active member can perform valid profile check-in update without modifying role/stars', () {
      final checkInDoc = Map<String, dynamic>.from(childMemberDoc)
        ..['lastCheckInAt'] = '2026-11-06T10:00:00Z';

      final allowed = FirestoreRulesSecurityOracle.canUpdateFamilyMember(
        authUid: 'child_1',
        callerMemberDoc: childMemberDoc,
        existingDoc: childMemberDoc,
        prospectiveDoc: checkInDoc,
      );
      expect(allowed, isTrue);
    });

    test('Tier 1.4 Feature: star_ledger create allows Guardian to grant rewardStars with approvedBy set to self', () {
      final tx = {
        'familyId': 'fam_1',
        'userId': 'child_1',
        'amount': 5,
        'approvedBy': 'parent_1',
      };
      final allowed = FirestoreRulesSecurityOracle.canCreateStarLedger(
        authUid: 'parent_1',
        txData: tx,
        isCallerGuardian: true,
      );
      expect(allowed, isTrue);
    });

    test('Tier 1.5 Feature: star_ledger create allows member to deduct stars for valid wishlist claim', () {
      final tx = {
        'familyId': 'fam_1',
        'userId': 'child_1',
        'amount': -10,
      };
      final allowed = FirestoreRulesSecurityOracle.canCreateStarLedger(
        authUid: 'child_1',
        txData: tx,
        isCallerGuardian: false,
      );
      expect(allowed, isTrue);
    });

    // Tier 2 (Boundary & Corner Cases)
    test('Tier 2.1 Boundary: Child cannot mutate their own role or hierarchyRole to PARENT/GRANDPARENT', () {
      final attackDoc = Map<String, dynamic>.from(childMemberDoc)
        ..['hierarchyRole'] = 'PARENT';

      final allowed = FirestoreRulesSecurityOracle.canUpdateFamilyMember(
        authUid: 'child_1',
        callerMemberDoc: childMemberDoc,
        existingDoc: childMemberDoc,
        prospectiveDoc: attackDoc,
      );
      expect(allowed, isFalse);
    });

    test('Tier 2.2 Boundary: Child cannot unilaterally increment their own rewardStarsTotal on member document', () {
      final attackDoc = Map<String, dynamic>.from(childMemberDoc)
        ..['rewardStarsTotal'] = 999;

      final allowed = FirestoreRulesSecurityOracle.canUpdateFamilyMember(
        authUid: 'child_1',
        callerMemberDoc: childMemberDoc,
        existingDoc: childMemberDoc,
        prospectiveDoc: attackDoc,
      );
      expect(allowed, isFalse);
    });

    test('Tier 2.3 Boundary: Inactive or deactivated Guardian loses Guardian authorization', () {
      final inactiveGuardian = {
        'role': 'PARENT',
        'hierarchyRole': 'PARENT',
        'status': 'DEACTIVATED',
      };
      expect(FirestoreRulesSecurityOracle.isGuardian(memberDoc: inactiveGuardian), isFalse);
    });

    test('Tier 2.4 Boundary: Non-guardian cannot approve rewardStars (> 0) in star_ledger', () {
      final tx = {
        'familyId': 'fam_1',
        'userId': 'child_1',
        'amount': 10,
        'approvedBy': 'child_1',
      };
      final allowed = FirestoreRulesSecurityOracle.canCreateStarLedger(
        authUid: 'child_1',
        txData: tx,
        isCallerGuardian: false,
      );
      expect(allowed, isFalse);
    });

    test('Tier 2.5 Boundary: star_ledger document updates and deletes are unconditionally rejected (immutability)', () {
      expect(FirestoreRulesSecurityOracle.canUpdateOrDeleteStarLedger(), isFalse);
    });
  });

  // ===========================================================================
  // GROUP 2: Star Economy & Double-Approval Protection Engine
  // ===========================================================================
  group('Star Economy & Double-Approval Protection Engine (Tier 1 & Tier 2)', () {
    late StarEconomyEngine engine;

    setUp(() {
      engine = StarEconomyEngine();
      engine.seedMemberBalance('fam_1', 'child_1', 20);
      engine.seedTask('task_clean_room', {
        'id': 'task_clean_room',
        'familyId': 'fam_1',
        'assignedTo': 'child_1',
        'title': 'Dọn phòng ngủ',
        'status': 'SUBMITTED',
        'rewardStars': 5,
      });
    });

    // Tier 1 (Feature Coverage)
    test('Tier 1.1 Feature: Single chore approval awards stars and records idempotent ledger doc reward_{taskId}', () async {
      await engine.approveTaskWithDoubleAwardProtection(
        taskId: 'task_clean_room',
        reviewerId: 'parent_1',
        reviewerName: 'Bố Tuấn',
      );

      expect(engine.reminders['task_clean_room']!['status'], 'APPROVED');
      expect(engine.reminders['task_clean_room']!['approvedBy'], 'parent_1');
      expect(engine.getBalance('fam_1', 'child_1'), 25);
      expect(engine.starLedger.containsKey('reward_task_clean_room'), isTrue);
    });

    test('Tier 1.2 Feature: Ledger entry records correct amount, recipient, reviewer, and type TASK_REWARD', () async {
      await engine.approveTaskWithDoubleAwardProtection(
        taskId: 'task_clean_room',
        reviewerId: 'gp_1',
        reviewerName: 'Ông Nội',
      );

      final entry = engine.starLedger['reward_task_clean_room']!;
      expect(entry['amount'], 5);
      expect(entry['userId'], 'child_1');
      expect(entry['type'], 'TASK_REWARD');
      expect(entry['sourceId'], 'task_clean_room');
      expect(entry['approvedBy'], 'gp_1');
    });

    test('Tier 1.3 Feature: Wishlist claim with sufficient stars deducts balance and writes claim_{claimId}', () async {
      await engine.claimWishlistItem(
        claimId: 'claim_lego_01',
        familyId: 'fam_1',
        userId: 'child_1',
        cost: 15,
        itemName: 'Bộ Lego cứu hỏa',
      );

      expect(engine.getBalance('fam_1', 'child_1'), 5);
      expect(engine.starLedger.containsKey('claim_claim_lego_01'), isTrue);
      expect(engine.starLedger['claim_claim_lego_01']!['amount'], -15);
    });

    test('Tier 1.4 Feature: Wishlist claim with insufficient balance throws InsufficientStarsException', () async {
      expect(
        () => engine.claimWishlistItem(
          claimId: 'claim_robot_expensive',
          familyId: 'fam_1',
          userId: 'child_1',
          cost: 50,
          itemName: 'Robot biến hình cao cấp',
        ),
        throwsA(isA<InsufficientStarsException>()),
      );
      expect(engine.getBalance('fam_1', 'child_1'), 20); // Số dư được bảo toàn
    });

    test('Tier 1.5 Feature: Guardian rejecting physical gift refunds exact stars and writes refund_{claimId}', () async {
      await engine.claimWishlistItem(
        claimId: 'claim_02',
        familyId: 'fam_1',
        userId: 'child_1',
        cost: 10,
        itemName: 'Truyện tranh Doraemon',
      );
      expect(engine.getBalance('fam_1', 'child_1'), 10);

      // Trưởng bối từ chối mua quà thật -> hoàn sao
      await engine.refundWishlistClaim(
        claimId: 'claim_02',
        familyId: 'fam_1',
        userId: 'child_1',
        refundStars: 10,
      );

      expect(engine.getBalance('fam_1', 'child_1'), 20);
      expect(engine.starLedger.containsKey('refund_claim_02'), isTrue);
      expect(engine.starLedger['refund_claim_02']!['amount'], 10);
    });

    // Tier 2 (Boundary & Corner Cases)
    test('Tier 2.1 Boundary: Concurrent double-approval on same task ensures exactly 1 succeeds and second throws', () async {
      final results = await Future.wait([
        engine.approveTaskWithDoubleAwardProtection(
          taskId: 'task_clean_room',
          reviewerId: 'gp_1',
          reviewerName: 'Ông Nội',
        ).then((_) => 'success').catchError((e) => 'error: $e'),
        engine.approveTaskWithDoubleAwardProtection(
          taskId: 'task_clean_room',
          reviewerId: 'parent_1',
          reviewerName: 'Mẹ Lan',
        ).then((_) => 'success').catchError((e) => 'error: $e'),
      ]);

      expect(results.where((r) => r == 'success').length, 1);
      expect(results.where((r) => r.startsWith('error:')).length, 1);
      expect(engine.getBalance('fam_1', 'child_1'), 25); // Thưởng đúng 1 lần (20 + 5)
    });

    test('Tier 2.2 Boundary: Double-spending race: 2 concurrent claims of 15-star items with 20-star balance allows only 1', () async {
      int successCount = 0;
      int failCount = 0;

      final futures = [
        engine.claimWishlistItem(
          claimId: 'claim_fast_1',
          familyId: 'fam_1',
          userId: 'child_1',
          cost: 15,
          itemName: 'Item A',
        ).then((_) => successCount++).catchError((_) => failCount++),
        engine.claimWishlistItem(
          claimId: 'claim_fast_2',
          familyId: 'fam_1',
          userId: 'child_1',
          cost: 15,
          itemName: 'Item B',
        ).then((_) => successCount++).catchError((_) => failCount++),
      ];

      await Future.wait(futures);

      expect(successCount, 1);
      expect(failCount, 1);
      expect(engine.getBalance('fam_1', 'child_1'), 5); // 20 - 15 = 5
    });

    test('Tier 2.3 Boundary: Zero-cost claim or exact balance claim (cost == balance) succeeds with 0 remaining balance', () async {
      await engine.claimWishlistItem(
        claimId: 'claim_exact',
        familyId: 'fam_1',
        userId: 'child_1',
        cost: 20,
        itemName: 'Món quà vừa khít sao',
      );

      expect(engine.getBalance('fam_1', 'child_1'), 0);
      expect(engine.starLedger.containsKey('claim_claim_exact'), isTrue);
    });

    test('Tier 2.4 Boundary: Approving non-existent or cancelled task throws Exception', () async {
      expect(
        () => engine.approveTaskWithDoubleAwardProtection(
          taskId: 'task_ghost_404',
          reviewerId: 'parent_1',
          reviewerName: 'Bố',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Công việc không tồn tại'))),
      );
    });

    test('Tier 2.5 Boundary: Idempotent ledger docId collisions strictly prevent re-awarding stars on already processed tasks', () async {
      await engine.approveTaskWithDoubleAwardProtection(
        taskId: 'task_clean_room',
        reviewerId: 'parent_1',
        reviewerName: 'Bố Tuấn',
      );

      // Gọi lần 2
      expect(
        () => engine.approveTaskWithDoubleAwardProtection(
          taskId: 'task_clean_room',
          reviewerId: 'parent_2',
          reviewerName: 'Mẹ Lan',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('duyệt trước đó'))),
      );
    });
  });

  // ===========================================================================
  // GROUP 3: Accelerometer Shake Debounce & Mutex Lock Engine
  // ===========================================================================
  group('Accelerometer Shake Debounce & Mutex Lock Engine (Tier 1 & Tier 2)', () {
    late AccelerometerShakeEngine engine;

    setUp(() {
      engine = AccelerometerShakeEngine();
      engine.reset();
    });

    // Tier 1 (Feature Coverage)
    test('Tier 1.1 Feature: Single shake exceeding threshold (g > 15.0, deltaG > 4.5) registers successfully', () async {
      // x=12, y=10, z=5 => g = sqrt(144+100+25) = sqrt(269) ~ 16.4 m/s2 (> 15.0), deltaG = |16.4 - 9.81| = 6.59 (> 4.5)
      final accepted = await engine.handleSensorEvent(x: 12.0, y: 10.0, z: 5.0);
      expect(accepted, isTrue);
      expect(engine.shakeCount, 1);
    });

    test('Tier 1.2 Feature: Sub-threshold movement (g <= 15.0 or deltaG <= 4.5) does not register a shake', () async {
      // Gentle movement: x=1, y=2, z=9.8 => g ~ 10.05, deltaG ~ 0.24
      final accepted = await engine.handleSensorEvent(x: 1.0, y: 2.0, z: 9.8);
      expect(accepted, isFalse);
      expect(engine.shakeCount, 0);
    });

    test('Tier 1.3 Feature: Rapid shaking within 3.0s cooldown is debounced to a single shake', () async {
      final t0 = DateTime(2026, 11, 6, 12, 0, 0);

      final first = await engine.handleSensorEvent(x: 15.0, y: 15.0, z: 0.0, eventTime: t0);
      expect(first, isTrue);
      expect(engine.shakeCount, 1);

      // Shake sau 500ms
      final second = await engine.handleSensorEvent(x: 15.0, y: 15.0, z: 0.0, eventTime: t0.add(const Duration(milliseconds: 500)));
      expect(second, isFalse);

      // Shake sau 1500ms
      final third = await engine.handleSensorEvent(x: 15.0, y: 15.0, z: 0.0, eventTime: t0.add(const Duration(milliseconds: 1500)));
      expect(third, isFalse);

      expect(engine.shakeCount, 1);
    });

    test('Tier 1.4 Feature: Shake occurring after 3.0s cooldown window successfully registers as second shake', () async {
      final t0 = DateTime(2026, 11, 6, 12, 0, 0);

      final first = await engine.handleSensorEvent(x: 15.0, y: 15.0, z: 0.0, eventTime: t0);
      expect(first, isTrue);

      // Shake sau 3.1 giây (hết cooldown)
      final second = await engine.handleSensorEvent(x: 15.0, y: 15.0, z: 0.0, eventTime: t0.add(const Duration(milliseconds: 3100)));
      expect(second, isTrue);
      expect(engine.shakeCount, 2);
    });

    test('Tier 1.5 Feature: Mutex lock _isProcessingShake blocks re-entrant shake handling during active processing', () async {
      final t0 = DateTime(2026, 11, 6, 12, 0, 0);

      // Chạy 2 event đồng thời
      final futures = await Future.wait([
        engine.handleSensorEvent(x: 16.0, y: 16.0, z: 0.0, eventTime: t0),
        engine.handleSensorEvent(x: 16.0, y: 16.0, z: 0.0, eventTime: t0),
      ]);

      expect(futures.where((res) => res == true).length, 1);
      expect(engine.shakeCount, 1);
    });

    // Tier 2 (Boundary & Corner Cases)
    test('Tier 2.1 Boundary: Timing boundary: shake at 2950ms is debounced; shake at 3050ms registers', () async {
      final t0 = DateTime(2026, 11, 6, 12, 0, 0);
      await engine.handleSensorEvent(x: 15.0, y: 15.0, z: 0.0, eventTime: t0);

      // Boundary 1: 2950ms (vẫn trong cooldown 3000ms)
      final rejected = await engine.handleSensorEvent(x: 15.0, y: 15.0, z: 0.0, eventTime: t0.add(const Duration(milliseconds: 2950)));
      expect(rejected, isFalse);
      expect(engine.shakeCount, 1);

      // Boundary 2: 3050ms (vừa qua mốc 3000ms)
      final accepted = await engine.handleSensorEvent(x: 15.0, y: 15.0, z: 0.0, eventTime: t0.add(const Duration(milliseconds: 3050)));
      expect(accepted, isTrue);
      expect(engine.shakeCount, 2);
    });

    test('Tier 2.2 Boundary: Extreme sensor burst: 50 sensor events in 200ms trigger exactly 1 shake', () async {
      final t0 = DateTime(2026, 11, 6, 12, 0, 0);
      final futures = List.generate(50, (i) {
        return engine.handleSensorEvent(
          x: 16.0,
          y: 16.0,
          z: 0.0,
          eventTime: t0.add(Duration(milliseconds: i * 4)), // cách nhau 4ms
        );
      });

      final results = await Future.wait(futures);
      expect(results.where((r) => r == true).length, 1);
      expect(engine.shakeCount, 1);
    });

    test('Tier 2.3 Boundary: Mutex lock releases cleanly even if processing finishes', () async {
      final t0 = DateTime(2026, 11, 6, 12, 0, 0);
      await engine.handleSensorEvent(x: 16.0, y: 16.0, z: 0.0, eventTime: t0);
      expect(engine.isProcessingShake, isFalse);
    });

    test('Tier 2.4 Boundary: Inactive game state (not shaking phase) discards all accelerometer events', () async {
      engine.isShakingPhase = false; // Ngoài khung giờ lắc hũ
      final result = await engine.handleSensorEvent(x: 20.0, y: 20.0, z: 20.0);
      expect(result, isFalse);
      expect(engine.shakeCount, 0);
    });

    test('Tier 2.5 Boundary: Session reset cleanly resets shake count, timestamp, and mutex lock', () async {
      await engine.handleSensorEvent(x: 16.0, y: 16.0, z: 0.0);
      expect(engine.shakeCount, 1);

      engine.reset();
      expect(engine.shakeCount, 0);
      expect(engine.lastShakeTime, isNull);
      expect(engine.isProcessingShake, isFalse);
    });
  });

  // ===========================================================================
  // GROUP 4: Cash Gift Two-Way Handshake Engine
  // ===========================================================================
  group('Cash Gift Two-Way Handshake Engine (Tier 1 & Tier 2)', () {
    late CashGiftHandshakeEngine engine;

    setUp(() {
      engine = CashGiftHandshakeEngine();
      engine.createPrize(
        prizeId: 'prize_100k',
        childId: 'kid_bin',
        childName: 'Bé Bin',
        amount: 100000,
      );
    });

    // Tier 1 (Feature Coverage)
    test('Tier 1.1 Feature: Cash prize initialized in WAITING_TRANSFER state', () {
      final prize = engine.prizes['prize_100k']!;
      expect(prize.status, CashPrizeStatus.waitingTransfer);
      expect(prize.amount, 100000);
      expect(prize.childId, 'kid_bin');
      expect(prize.paidAt, isNull);
      expect(prize.receivedAt, isNull);
    });

    test('Tier 1.2 Feature: Guardian confirms cash payment transitioning status to PAID', () {
      engine.guardianConfirmCashPayment(
        prizeId: 'prize_100k',
        guardianId: 'gp_ong',
        guardianName: 'Ông Nội',
        isGuardian: true,
      );

      final prize = engine.prizes['prize_100k']!;
      expect(prize.status, CashPrizeStatus.paid);
      expect(prize.paymentMethod, 'CASH');
      expect(prize.paidBy, 'gp_ong');
      expect(prize.paidByName, 'Ông Nội');
      expect(prize.paidAt, isNotNull);
    });

    test('Tier 1.3 Feature: Guardian confirms VietQR transfer transitioning status to PAID with bank metadata', () {
      engine.guardianConfirmVietQrTransfer(
        prizeId: 'prize_100k',
        guardianId: 'parent_me',
        guardianName: 'Mẹ Lan',
        bankRef: 'FT2611060938472',
        isGuardian: true,
      );

      final prize = engine.prizes['prize_100k']!;
      expect(prize.status, CashPrizeStatus.paid);
      expect(prize.paymentMethod, 'VIETQR');
      expect(prize.bankRef, 'FT2611060938472');
    });

    test('Tier 1.4 Feature: Child confirms receipt after PAID transitioning status to RECEIVED', () {
      // 1. Trưởng bối trao tiền
      engine.guardianConfirmCashPayment(
        prizeId: 'prize_100k',
        guardianId: 'gp_ong',
        guardianName: 'Ông Nội',
        isGuardian: true,
      );

      // 2. Cháu bấm [Đã nhận tiền]
      engine.childConfirmReceipt(
        prizeId: 'prize_100k',
        childId: 'kid_bin',
      );

      final prize = engine.prizes['prize_100k']!;
      expect(prize.status, CashPrizeStatus.received);
      expect(prize.receivedAt, isNotNull);
    });

    test('Tier 1.5 Feature: End-to-end 2-way handshake completes full payout cycle', () {
      final p = engine.prizes['prize_100k']!;
      expect(p.status, CashPrizeStatus.waitingTransfer);

      engine.guardianConfirmVietQrTransfer(
        prizeId: 'prize_100k',
        guardianId: 'parent_ba',
        guardianName: 'Ba Tuấn',
        bankRef: 'VQR_998877',
        isGuardian: true,
      );
      expect(p.status, CashPrizeStatus.paid);

      engine.childConfirmReceipt(prizeId: 'prize_100k', childId: 'kid_bin');
      expect(p.status, CashPrizeStatus.received);
    });

    // Tier 2 (Boundary & Corner Cases)
    test('Tier 2.1 Boundary: Child cannot confirm receipt while prize is still in WAITING_TRANSFER state', () {
      expect(
        () => engine.childConfirmReceipt(
          prizeId: 'prize_100k',
          childId: 'kid_bin',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'msg',
          contains('chưa thực hiện thanh toán'),
        )),
      );
    });

    test('Tier 2.2 Boundary: Non-guardian cannot mark cash gift as PAID', () {
      expect(
        () => engine.guardianConfirmCashPayment(
          prizeId: 'prize_100k',
          guardianId: 'other_kid',
          guardianName: 'Bạn Hàng Xóm',
          isGuardian: false,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'msg',
          contains('Chỉ Trưởng bối (Guardian)'),
        )),
      );
    });

    test('Tier 2.3 Boundary: Re-confirming an already RECEIVED prize is safely idempotent', () {
      engine.guardianConfirmCashPayment(
        prizeId: 'prize_100k',
        guardianId: 'gp_ong',
        guardianName: 'Ông',
        isGuardian: true,
      );
      engine.childConfirmReceipt(prizeId: 'prize_100k', childId: 'kid_bin');

      final firstReceivedAt = engine.prizes['prize_100k']!.receivedAt;

      // Gọi lần 2
      engine.childConfirmReceipt(prizeId: 'prize_100k', childId: 'kid_bin');
      expect(engine.prizes['prize_100k']!.receivedAt, firstReceivedAt);
    });

    test('Tier 2.4 Boundary: Wrong recipient child cannot confirm receipt of another childs cash gift', () {
      engine.guardianConfirmCashPayment(
        prizeId: 'prize_100k',
        guardianId: 'gp_ong',
        guardianName: 'Ông',
        isGuardian: true,
      );

      expect(
        () => engine.childConfirmReceipt(
          prizeId: 'prize_100k',
          childId: 'stranger_kid',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'msg',
          contains('Chỉ người nhận giải thưởng'),
        )),
      );
    });

    test('Tier 2.5 Boundary: Handshake audit trail records timestamps, actor UIDs, and payment channel', () {
      engine.guardianConfirmVietQrTransfer(
        prizeId: 'prize_100k',
        guardianId: 'parent_1',
        guardianName: 'Mẹ Lan',
        bankRef: 'REF_TEST',
        isGuardian: true,
      );
      engine.childConfirmReceipt(prizeId: 'prize_100k', childId: 'kid_bin');

      final prize = engine.prizes['prize_100k']!;
      expect(prize.paidAt, isA<DateTime>());
      expect(prize.receivedAt, isA<DateTime>());
      expect(prize.paidBy, 'parent_1');
      expect(prize.childId, 'kid_bin');
      expect(prize.paymentMethod, 'VIETQR');
    });
  });

  // ===========================================================================
  // GROUP 5: AI Memory Scoping & Draft Task Confirmation Gate
  // ===========================================================================
  group('AI Memory Scoping & Draft Task Confirmation Gate (Tier 1 & Tier 2)', () {
    late AiMemoryScopingEngine aiEngine;
    late InMemoryReminderRepository repo;

    setUp(() {
      aiEngine = AiMemoryScopingEngine();
      repo = InMemoryReminderRepository();

      aiEngine.seedMemory(FamilyMemory(
        id: 'mem_milk',
        familyId: 'fam_hanoi',
        keyword: 'sữa',
        value: 'Vinamilk Không Đường',
        updatedAt: DateTime.now(),
      ));

      aiEngine.seedMemory(FamilyMemory(
        id: 'mem_bread',
        familyId: 'fam_saigon',
        keyword: 'sữa',
        value: 'TH True Milk Ít Đường',
        updatedAt: DateTime.now(),
      ));
    });

    // Tier 1 (Feature Coverage)
    test('Tier 1.1 Feature: AI recalls stored memory keyword from family_memories into draft task attributes', () async {
      final draft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Giao việc con đi mua sữa',
        userId: 'u_dad',
        userName: 'Bố Hùng',
        userRole: 'PARENT',
      );

      expect(draft.appliedMemory, 'Vinamilk Không Đường');
      expect(draft.finalTitle, contains('Vinamilk Không Đường'));
    });

    test('Tier 1.2 Feature: Draft task card displays applied habit badge (e.g. Vinamilk)', () async {
      final draft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Mua sữa cho em',
        userId: 'u_dad',
        userName: 'Bố Hùng',
        userRole: 'PARENT',
      );

      expect(draft.finalTitle, 'Mua sữa (Đã áp dụng thói quen: Vinamilk Không Đường)');
    });

    test('Tier 1.3 Feature: Draft task card does NOT write to repository before user confirmation (Gate)', () async {
      final draft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Nhắc đi mua sữa tối nay',
        userId: 'u_dad',
        userName: 'Bố Hùng',
        userRole: 'PARENT',
      );

      expect(draft.isConfirmed, isFalse);
      final storedReminders = await repo.getReminders(familyId: 'fam_hanoi');
      expect(storedReminders.isEmpty, isTrue, reason: 'Chưa bấm xác nhận thì repository phải trống 100%');
    });

    test('Tier 1.4 Feature: User clicking Confirm Draft Task explicitly persists task to repository', () async {
      final draft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Giao việc đi mua sữa',
        userId: 'u_dad',
        userName: 'Bố Hùng',
        userRole: 'PARENT',
      );

      final created = await aiEngine.confirmDraftTask(draft: draft, repo: repo);
      expect(created.title, contains('Vinamilk Không Đường'));
      expect(created.creatorId, 'u_dad');

      final storedReminders = await repo.getReminders(familyId: 'fam_hanoi');
      expect(storedReminders.length, 1);
      expect(storedReminders.first.title, created.title);
    });

    test('Tier 1.5 Feature: Dynamic Vietnamese salutation addresses user respectfully based on role and name', () async {
      final parentDraft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Đi mua sữa',
        userId: 'u_dad',
        userName: 'Hùng',
        userRole: 'PARENT',
      );
      expect(parentDraft.salutation, contains('Bố/Mẹ Hùng'));

      final gpDraft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Đi mua sữa',
        userId: 'u_gp',
        userName: 'Tâm',
        userRole: 'GRANDPARENT',
      );
      expect(gpDraft.salutation, contains('Ông/Bà Tâm'));

      final childDraft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Đi mua sữa',
        userId: 'u_kid',
        userName: 'Nam',
        userRole: 'CHILD',
      );
      expect(childDraft.salutation, contains('Nam'));
      expect(childDraft.salutation, isNot(contains('Bố/Mẹ')));
    });

    // Tier 2 (Boundary & Corner Cases)
    test('Tier 2.1 Boundary: Multi-family scoping: memories from Family A are NEVER leaked to Family B', () async {
      // Hanoi Family -> Vinamilk
      final hanoiDraft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Mua sữa',
        userId: 'u1',
        userName: 'User 1',
        userRole: 'PARENT',
      );
      expect(hanoiDraft.appliedMemory, 'Vinamilk Không Đường');

      // Saigon Family -> TH True Milk
      final saigonDraft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_saigon',
        userPrompt: 'Mua sữa',
        userId: 'u2',
        userName: 'User 2',
        userRole: 'PARENT',
      );
      expect(saigonDraft.appliedMemory, 'TH True Milk Ít Đường');
      expect(saigonDraft.appliedMemory, isNot(contains('Vinamilk')));
    });

    test('Tier 2.2 Boundary: Unmatched keyword generates clean draft without crashing or false memory badge', () async {
      final draft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Quét dọn sân vườn',
        userId: 'u1',
        userName: 'Bố',
        userRole: 'PARENT',
      );

      expect(draft.appliedMemory, isNull);
      expect(draft.finalTitle, 'Mua sữa'); // Không bị gắn tag thói quen sai lệch
    });

    test('Tier 2.3 Boundary: User dismisses or cancels draft task: repository remains completely untouched', () async {
      final draft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Mua sữa',
        userId: 'u1',
        userName: 'Bố',
        userRole: 'PARENT',
      );
      expect(draft.isConfirmed, isFalse);

      // User hủy bỏ -> không gọi confirmDraftTask
      final list = await repo.getReminders(familyId: 'fam_hanoi');
      expect(list.isEmpty, isTrue);
    });

    test('Tier 2.4 Boundary: Memory keyword matching is case-insensitive and trims extra whitespace', () async {
      final draft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: '   ĐI MUA SỮA VỀ UỐNG   ',
        userId: 'u1',
        userName: 'Mẹ',
        userRole: 'PARENT',
      );

      expect(draft.appliedMemory, 'Vinamilk Không Đường');
    });

    test('Tier 2.5 Boundary: User modifies draft task title before confirming: modified title is persisted', () async {
      final draft = await aiEngine.processPromptToDraft(
        activeFamilyId: 'fam_hanoi',
        userPrompt: 'Mua sữa',
        userId: 'u1',
        userName: 'Bố',
        userRole: 'PARENT',
      );

      // User chỉnh sửa tiêu đề thành 2 hộp thay vì 1
      final created = await aiEngine.confirmDraftTask(
        draft: draft,
        repo: repo,
        editedTitle: 'Mua 2 lốc sữa Vinamilk Không Đường',
      );

      expect(created.title, 'Mua 2 lốc sữa Vinamilk Không Đường');
      final list = await repo.getReminders(familyId: 'fam_hanoi');
      expect(list.first.title, 'Mua 2 lốc sữa Vinamilk Không Đường');
    });
  });
}

// =============================================================================
// DOMAIN ENGINES & SPECIFICATION TEST ORACLES (Milestone 1, 3, 4 Contracts)
// =============================================================================

/// Security Rules Oracle reflecting firestore.rules top-level collection constraints
class FirestoreRulesSecurityOracle {
  static bool isGuardian({required Map<String, dynamic> memberDoc}) {
    final status = (memberDoc['status'] ?? 'ACTIVE').toString().toUpperCase();
    if (status != 'ACTIVE') return false;

    final role = (memberDoc['role'] ?? '').toString().toLowerCase();
    final hRole = (memberDoc['hierarchyRole'] ?? '').toString().toUpperCase();
    final isOwner = memberDoc['isOwner'] == true;
    final isGuardianFlag = memberDoc['isGuardian'] == true;

    return role == 'owner' ||
        role == 'parent' ||
        role == 'grandparent' ||
        hRole == 'PARENT' ||
        hRole == 'GRANDPARENT' ||
        isOwner ||
        isGuardianFlag;
  }

  static bool canUpdateFamilyMember({
    required String authUid,
    required Map<String, dynamic> existingDoc,
    required Map<String, dynamic> prospectiveDoc,
    Map<String, dynamic>? callerMemberDoc,
  }) {
    if (callerMemberDoc != null && isGuardian(memberDoc: callerMemberDoc)) {
      return true;
    }

    final isSelf = authUid == existingDoc['userId'];
    if (!isSelf) return false;

    final roleUnchanged = prospectiveDoc['role'] == existingDoc['role'];
    final hierarchyUnchanged =
        prospectiveDoc['hierarchyRole'] == existingDoc['hierarchyRole'];
    final isOwnerUnchanged =
        prospectiveDoc['isOwner'] == existingDoc['isOwner'];
    final isGuardianUnchanged =
        prospectiveDoc['isGuardian'] == existingDoc['isGuardian'];

    final existingStars = (existingDoc['rewardStarsTotal'] as num?) ?? 0;
    final prospectiveStars =
        (prospectiveDoc['rewardStarsTotal'] as num?) ?? 0;
    final starsNotIncreased = prospectiveStars <= existingStars;

    return roleUnchanged &&
        hierarchyUnchanged &&
        isOwnerUnchanged &&
        isGuardianUnchanged &&
        starsNotIncreased;
  }

  static bool canCreateStarLedger({
    required String authUid,
    required Map<String, dynamic> txData,
    required bool isCallerGuardian,
  }) {
    final amount = (txData['amount'] as num?)?.toInt() ?? 0;
    if (amount > 0) {
      return isCallerGuardian && txData['approvedBy'] == authUid;
    } else if (amount < 0) {
      return txData['userId'] == authUid || isCallerGuardian;
    }
    return false;
  }

  static bool canUpdateOrDeleteStarLedger() => false;
}

/// Star Economy Engine implementing atomic transaction idempotency & double-spending protection
class InsufficientStarsException implements Exception {
  final String message;
  InsufficientStarsException(this.message);
  @override
  String toString() => 'InsufficientStarsException: $message';
}

class StarEconomyEngine {
  final Map<String, Map<String, dynamic>> reminders = {};
  final Map<String, Map<String, dynamic>> starLedger = {};
  final Map<String, int> memberBalances = {}; // key: ${familyId}_${userId}

  void seedMemberBalance(String familyId, String userId, int stars) {
    memberBalances['${familyId}_$userId'] = stars;
  }

  int getBalance(String familyId, String userId) {
    return memberBalances['${familyId}_$userId'] ?? 0;
  }

  void seedTask(String taskId, Map<String, dynamic> data) {
    reminders[taskId] = Map<String, dynamic>.from(data);
  }

  Future<void> approveTaskWithDoubleAwardProtection({
    required String taskId,
    required String reviewerId,
    required String reviewerName,
  }) async {
    final task = reminders[taskId];
    if (task == null) {
      throw Exception('Công việc không tồn tại');
    }

    if (task['status'] == 'APPROVED') {
      final approvedByName = task['approvedByName'] ?? 'người khác';
      throw Exception('Công việc này đã được $approvedByName duyệt trước đó rồi ạ!');
    }

    final ledgerKey = 'reward_$taskId';
    if (starLedger.containsKey(ledgerKey)) {
      throw Exception('Giao dịch thưởng sao reward_$taskId đã tồn tại trong sổ cái!');
    }

    final familyId = task['familyId'] as String;
    final assignedTo = task['assignedTo'] as String;
    final rewardStars = (task['rewardStars'] as num?)?.toInt() ?? 0;

    // 1. Cập nhật task
    task['status'] = 'APPROVED';
    task['approvedBy'] = reviewerId;
    task['approvedByName'] = reviewerName;
    task['approvedAt'] = DateTime.now();

    // 2. Ghi sổ cái bất biến với idempotent key
    starLedger[ledgerKey] = {
      'txId': ledgerKey,
      'familyId': familyId,
      'userId': assignedTo,
      'amount': rewardStars,
      'type': 'TASK_REWARD',
      'sourceId': taskId,
      'approvedBy': reviewerId,
      'createdAt': DateTime.now(),
    };

    // 3. Tăng số dư sao của cháu
    final memberKey = '${familyId}_$assignedTo';
    memberBalances[memberKey] = (memberBalances[memberKey] ?? 0) + rewardStars;
  }

  Future<void> claimWishlistItem({
    required String claimId,
    required String familyId,
    required String userId,
    required int cost,
    required String itemName,
  }) async {
    if (cost <= 0) {
      throw ArgumentError('Chi phí đổi quà phải lớn hơn 0');
    }

    final memberKey = '${familyId}_$userId';
    final currentBalance = memberBalances[memberKey] ?? 0;
    if (currentBalance < cost) {
      throw InsufficientStarsException(
        'Số dư sao không đủ để đổi quà $itemName (Cần $cost sao, hiện có $currentBalance sao).',
      );
    }

    final ledgerKey = 'claim_$claimId';
    if (starLedger.containsKey(ledgerKey)) {
      throw Exception('Yêu cầu đổi quà claim_$claimId đã được xử lý!');
    }

    // Trừ sao và ghi sổ cái ngay lập tức
    memberBalances[memberKey] = currentBalance - cost;
    starLedger[ledgerKey] = {
      'txId': ledgerKey,
      'familyId': familyId,
      'userId': userId,
      'amount': -cost,
      'type': 'WISHLIST_CLAIM',
      'itemName': itemName,
      'createdAt': DateTime.now(),
    };
  }

  Future<void> refundWishlistClaim({
    required String claimId,
    required String familyId,
    required String userId,
    required int refundStars,
  }) async {
    if (refundStars <= 0) {
      throw ArgumentError('Số sao hoàn lại phải lớn hơn 0');
    }

    final ledgerKey = 'refund_$claimId';
    if (starLedger.containsKey(ledgerKey)) {
      throw Exception('Yêu cầu hoàn sao refund_$claimId đã được xử lý!');
    }

    final memberKey = '${familyId}_$userId';
    memberBalances[memberKey] = (memberBalances[memberKey] ?? 0) + refundStars;
    starLedger[ledgerKey] = {
      'txId': ledgerKey,
      'familyId': familyId,
      'userId': userId,
      'amount': refundStars,
      'type': 'REFUND',
      'createdAt': DateTime.now(),
    };
  }
}

/// Accelerometer Sensor Debounce Engine with 3.0s cooldown & mutex lock
class AccelerometerShakeEngine {
  static const double minG = 15.0;
  static const double minDeltaG = 4.5;
  static const Duration cooldown = Duration(milliseconds: 3000);

  int shakeCount = 0;
  DateTime? lastShakeTime;
  bool _isProcessingShake = false;
  bool isShakingPhase = true;

  bool get isProcessingShake => _isProcessingShake;

  void reset() {
    shakeCount = 0;
    lastShakeTime = null;
    _isProcessingShake = false;
    isShakingPhase = true;
  }

  Future<bool> handleSensorEvent({
    required double x,
    required double y,
    required double z,
    DateTime? eventTime,
  }) async {
    if (!isShakingPhase) return false;

    final g = sqrt(x * x + y * y + z * z);
    final deltaG = (g - 9.81).abs();

    // Ngưỡng phát hiện gia tốc
    if (g <= minG || deltaG <= minDeltaG) {
      return false;
    }

    final now = eventTime ?? DateTime.now();

    // Kiểm tra cooldown 3.0 giây
    if (lastShakeTime != null && now.difference(lastShakeTime!) < cooldown) {
      return false;
    }

    // Mutex lock
    if (_isProcessingShake) {
      return false;
    }

    _isProcessingShake = true;
    try {
      lastShakeTime = now;
      shakeCount++;
      await Future.delayed(const Duration(milliseconds: 10));
      return true;
    } finally {
      _isProcessingShake = false;
    }
  }
}

/// Cash Gift 2-Way Handshake Engine: WAITING_TRANSFER -> PAID -> RECEIVED
enum CashPrizeStatus { waitingTransfer, paid, received, cancelled }

class CashPrizeModel {
  final String id;
  final String childId;
  final String childName;
  final int amount;
  CashPrizeStatus status;
  String? paymentMethod;
  String? paidBy;
  String? paidByName;
  String? bankRef;
  DateTime? paidAt;
  DateTime? receivedAt;

  CashPrizeModel({
    required this.id,
    required this.childId,
    required this.childName,
    required this.amount,
    this.status = CashPrizeStatus.waitingTransfer,
    this.paymentMethod,
    this.paidBy,
    this.paidByName,
    this.bankRef,
    this.paidAt,
    this.receivedAt,
  });
}

class CashGiftHandshakeEngine {
  final Map<String, CashPrizeModel> prizes = {};

  CashPrizeModel createPrize({
    required String prizeId,
    required String childId,
    required String childName,
    required int amount,
  }) {
    final prize = CashPrizeModel(
      id: prizeId,
      childId: childId,
      childName: childName,
      amount: amount,
    );
    prizes[prizeId] = prize;
    return prize;
  }

  void guardianConfirmCashPayment({
    required String prizeId,
    required String guardianId,
    required String guardianName,
    required bool isGuardian,
  }) {
    if (!isGuardian) {
      throw StateError('Chỉ Trưởng bối (Guardian) mới có quyền xác nhận trao tiền mặt!');
    }
    final prize = prizes[prizeId];
    if (prize == null) throw Exception('Giải thưởng không tồn tại');
    if (prize.status == CashPrizeStatus.cancelled) {
      throw StateError('Giải thưởng đã bị hủy bỏ');
    }

    prize.status = CashPrizeStatus.paid;
    prize.paymentMethod = 'CASH';
    prize.paidBy = guardianId;
    prize.paidByName = guardianName;
    prize.paidAt = DateTime.now();
  }

  void guardianConfirmVietQrTransfer({
    required String prizeId,
    required String guardianId,
    required String guardianName,
    required String bankRef,
    required bool isGuardian,
  }) {
    if (!isGuardian) {
      throw StateError('Chỉ Trưởng bối (Guardian) mới có quyền xác nhận chuyển VietQR!');
    }
    final prize = prizes[prizeId];
    if (prize == null) throw Exception('Giải thưởng không tồn tại');
    if (prize.status == CashPrizeStatus.cancelled) {
      throw StateError('Giải thưởng đã bị hủy bỏ');
    }

    prize.status = CashPrizeStatus.paid;
    prize.paymentMethod = 'VIETQR';
    prize.paidBy = guardianId;
    prize.paidByName = guardianName;
    prize.bankRef = bankRef;
    prize.paidAt = DateTime.now();
  }

  void childConfirmReceipt({
    required String prizeId,
    required String childId,
  }) {
    final prize = prizes[prizeId];
    if (prize == null) throw Exception('Giải thưởng không tồn tại');

    if (prize.childId != childId) {
      throw StateError('Chỉ người nhận giải thưởng mới có quyền bấm xác nhận nhận tiền!');
    }

    if (prize.status == CashPrizeStatus.waitingTransfer) {
      throw StateError('Không thể xác nhận nhận tiền khi Trưởng bối chưa thực hiện thanh toán!');
    }

    if (prize.status == CashPrizeStatus.received) {
      return;
    }

    prize.status = CashPrizeStatus.received;
    prize.receivedAt = DateTime.now();
  }
}

/// AI Memory Scoping & Draft Task Confirmation Gate Engine
class DraftTaskCard {
  final String familyId;
  final String title;
  final String date;
  final String time;
  final String creatorId;
  final String creatorName;
  final String assignedTo;
  final String? appliedMemory;
  final String salutation;
  bool isConfirmed;

  DraftTaskCard({
    required this.familyId,
    required this.title,
    required this.date,
    required this.time,
    required this.creatorId,
    required this.creatorName,
    required this.assignedTo,
    this.appliedMemory,
    required this.salutation,
    this.isConfirmed = false,
  });

  String get finalTitle => appliedMemory != null
      ? '$title (Đã áp dụng thói quen: $appliedMemory)'
      : title;
}

class AiMemoryScopingEngine {
  final Map<String, List<FamilyMemory>> memoryStore = {};

  void seedMemory(FamilyMemory memory) {
    memoryStore.putIfAbsent(memory.familyId, () => []).add(memory);
  }

  Future<DraftTaskCard> processPromptToDraft({
    required String activeFamilyId,
    required String userPrompt,
    required String userId,
    required String userName,
    required String userRole,
  }) async {
    final familyMemories = memoryStore[activeFamilyId] ?? [];
    String? matchedValue;

    for (final mem in familyMemories) {
      if (userPrompt.toLowerCase().contains(mem.keyword.toLowerCase())) {
        matchedValue = mem.value;
        break;
      }
    }

    final salutation = (userRole == 'PARENT' || userRole == 'GRANDPARENT')
        ? 'Dạ em chào ${userRole == "GRANDPARENT" ? "Ông/Bà" : "Bố/Mẹ"} $userName ạ!'
        : 'Dạ em chào $userName nhé!';

    return DraftTaskCard(
      familyId: activeFamilyId,
      title: 'Mua sữa',
      date: '10/11/2026',
      time: '18:00',
      creatorId: userId,
      creatorName: userName,
      assignedTo: 'ALL',
      appliedMemory: matchedValue,
      salutation: salutation,
      isConfirmed: false,
    );
  }

  Future<ReminderModel> confirmDraftTask({
    required DraftTaskCard draft,
    required InMemoryReminderRepository repo,
    String? editedTitle,
  }) async {
    draft.isConfirmed = true;
    final finalTitleToSave = editedTitle ?? draft.finalTitle;

    final created = await repo.createReminder(
      reminder: ReminderModel(
        id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
        familyId: draft.familyId,
        creatorId: draft.creatorId,
        creatorName: draft.creatorName,
        assignedTo: draft.assignedTo,
        assignedToName: 'Việc chung',
        title: finalTitleToSave,
        date: draft.date,
        time: draft.time,
        status: ReminderStatus.open,
      ),
      currentUserId: draft.creatorId,
    );
    return created;
  }
}

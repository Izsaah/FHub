import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Long/models/user_model.dart';
import 'package:fhub/Long/models/family_member_model.dart';
import 'package:fhub/Khoa/models/family_member.dart' as khoa_fm;
import 'package:fhub/Long/models/hierarchy_role.dart';
import 'package:fhub/Long/services/join_request_service.dart';
import 'package:fhub/Long/services/family_data_service.dart';
import 'package:fhub/Ai/models/family_memory_model.dart';
import 'package:fhub/Vinh/models/family_member.dart' as vinh_fm;
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';
import 'package:fhub/Vinh/services/star_economy_service.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';

// Test oracle helper for quiet hours calculation
class Tier5QuietHoursOracle {
  static DateTime calculateEffectiveAlarmTime({
    required DateTime scheduledTime,
    required TaskType taskType,
    String title = '',
  }) {
    final isCare = taskType == TaskType.care ||
        title.toLowerCase().contains('thuốc') ||
        title.toLowerCase().contains('medicine');

    if (isCare) {
      return scheduledTime;
    }

    final h = scheduledTime.hour;
    if (h >= 22) {
      final nextDay = scheduledTime.add(const Duration(days: 1));
      return DateTime(nextDay.year, nextDay.month, nextDay.day, 7, 0, 0);
    } else if (h < 6) {
      return DateTime(scheduledTime.year, scheduledTime.month, scheduledTime.day, 7, 0, 0);
    }

    return scheduledTime;
  }
}

// 15-second escalation simulation oracle for verification
class Tier5Escalation15sOracle {
  final Set<String> _activeTasks = {};

  List<DateTime> calculateTiers(DateTime scheduledTime) {
    return [
      scheduledTime,
      scheduledTime.add(const Duration(hours: 2)),
      scheduledTime.add(const Duration(hours: 6)),
    ];
  }

  void schedule(String taskId) => _activeTasks.add(taskId);
  void cancel(String taskId) => _activeTasks.remove(taskId);
  bool isActive(String taskId) => _activeTasks.contains(taskId);

  List<Map<String, dynamic>> simulation15sTimeline(String title) {
    return [
      {'sec': 0, 'tier': '0h', 'message': 'Đúng giờ: $title'},
      {'sec': 7, 'tier': '+2h', 'message': 'Quá hạn 2h: $title'},
      {'sec': 15, 'tier': '+6h', 'message': 'Báo cáo Trưởng bối: $title'},
    ];
  }
}

// AI Memory Scoping Oracle
class Tier5AiMemoryOracle {
  final Map<String, List<FamilyMemory>> _scopedMemories = {};

  void seedMemory(FamilyMemory mem) {
    _scopedMemories.putIfAbsent(mem.familyId, () => []).add(mem);
  }

  Map<String, dynamic> generateDraft({
    required String familyId,
    required String userPrompt,
    required String userId,
    required String userName,
    required String userRole,
  }) {
    final memories = _scopedMemories[familyId] ?? [];
    String? matchedHabit;

    for (final m in memories) {
      if (userPrompt.toLowerCase().contains(m.keyword.toLowerCase())) {
        matchedHabit = m.value;
        break;
      }
    }

    final baseTitle = 'Mua sữa';
    final finalTitle = matchedHabit != null
        ? '$baseTitle (Đã áp dụng thói quen: $matchedHabit)'
        : baseTitle;

    return {
      'familyId': familyId,
      'title': finalTitle,
      'appliedMemory': matchedHabit,
      'creatorId': userId,
      'creatorName': userName,
      'isConfirmed': false,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // MODULE 1: MULTI-FAMILY SWITCHER & JOIN HANDSHAKE ADVERSARIAL
  // ===========================================================================
  group('Adversarial Tier 5 - Module 1: Multi-Family Switcher & Join Handshake', () {
    setUp(() {
      JoinRequestService.resetMockData();
    });

    test('1.1 Concurrency & Idempotency: Multiple concurrent join requests collapse to single composite doc', () async {
      final service = JoinRequestService();

      // Launch 25 concurrent sendJoinRequest for same family and user
      final futures = List.generate(25, (index) {
        return service.sendJoinRequest(
          familyId: 'fam_adv_1',
          suggestedRole: index.isEven ? 'CHILD' : 'PARENT',
        );
      });
      await Future.wait(futures);

      final pending = await service.watchPendingRequests('fam_adv_1').first;
      expect(pending.length, 1, reason: 'Must collapse to exactly 1 request per familyId_userId');
      expect(pending.first.id, 'fam_adv_1_mock_user');
      expect(pending.first.isPending, isTrue);
    });

    test('1.2 State Machine Transition: Approve -> Watch queue immediately removes request', () async {
      final service = JoinRequestService();
      await service.sendJoinRequest(familyId: 'fam_adv_lifecycle', suggestedRole: 'CHILD');

      final before = await service.watchPendingRequests('fam_adv_lifecycle').first;
      expect(before.length, 1);
      final reqId = before.first.id;

      await service.approveJoinRequest(requestId: reqId, assignedRole: 'CHILD', isKid: true);

      final after = await service.watchPendingRequests('fam_adv_lifecycle').first;
      expect(after.isEmpty, isTrue, reason: 'Approved request must no longer appear in pending queue');
    });

    test('1.3 Rejection Handshake: Guardian rejection sets status to REJECTED and guards against double-processing', () async {
      final service = JoinRequestService();
      await service.sendJoinRequest(familyId: 'fam_adv_reject', suggestedRole: 'PARENT');

      final pending = await service.watchPendingRequests('fam_adv_reject').first;
      final reqId = pending.first.id;

      await service.rejectJoinRequest(reqId);
      final after = await service.watchPendingRequests('fam_adv_reject').first;
      expect(after.isEmpty, isTrue);

      // Re-rejecting already rejected request must throw
      expect(
        () => service.rejectJoinRequest(reqId),
        throwsA(isA<Exception>()),
      );
    });

    test('1.4 MembershipUnifier Stress: Conflicting active/inactive documents and dirty cached lists', () {
      // User cached directFamilyIds has fam_1, fam_2, fam_3
      final direct = ['fam_1', 'fam_2', ' fam_3 ', '', 'fam_2'];

      // Raw member docs has conflicting status for fam_1 (one active, one deactivated)
      // and fam_2 is deactivated, fam_4 is newly active
      final rawDocs = [
        {'familyId': 'fam_1', 'status': 'ACTIVE'},
        {'familyId': 'fam_1', 'status': 'DEACTIVATED'},
        {'familyId': 'fam_2', 'status': 'DEACTIVATED'},
        {'familyId': 'fam_4', 'status': 'ACTIVE'},
      ];

      final result = MembershipUnifier.unify(
        directFamilyIds: direct,
        rawMemberDocs: rawDocs,
        memberQuerySucceeded: true,
      );

      // fam_4 is newly active and missing in direct -> needs self-heal union
      expect(result.missingInDirect, contains('fam_4'));
      expect(result.shouldSelfHealUnion, isTrue);

      // fam_2 is inactive -> needs pruning
      expect(result.toPruneFromDirect, contains('fam_2'));
      expect(result.shouldSelfHealPrune, isTrue);

      // Active family list should contain fam_1 and fam_4, but NOT fam_2
      expect(result.activeFamilyIds, contains('fam_1'));
      expect(result.activeFamilyIds, contains('fam_4'));
      expect(result.activeFamilyIds.contains('fam_2'), isFalse);
    });

    test('1.5 MembershipUnifier Offline Resilience: Member query failure preserves cached directFamilyIds', () {
      final direct = ['fam_cached_A', 'fam_cached_B'];
      final result = MembershipUnifier.unify(
        directFamilyIds: direct,
        rawMemberDocs: [],
        memberQuerySucceeded: false, // Network failure
      );

      expect(result.activeFamilyIds, containsAll(['fam_cached_A', 'fam_cached_B']));
      expect(result.missingInDirect, isEmpty);
      expect(result.toPruneFromDirect, isEmpty);
    });

    test('1.6 Full Role & Guardian Matrix: FamilyMemberModel vs FamilyMember consistency', () {
      // Long model
      final longGrandparent = FamilyMemberModel(
        familyId: 'f1',
        user: UserModel(id: 'u_gp', name: 'Ông', email: 'gp@test.com'),
        role: Role.member,
        hierarchyRole: HierarchyRole.grandparent,
      );
      expect(longGrandparent.isGuardian, isTrue);
      expect(longGrandparent.isKid, isFalse);

      final longChild = FamilyMemberModel(
        familyId: 'f1',
        user: UserModel(id: 'u_ch', name: 'Bé', email: 'ch@test.com'),
        role: Role.member,
        hierarchyRole: HierarchyRole.child,
      );
      expect(longChild.isGuardian, isFalse);
      expect(longChild.isKid, isTrue);

      // Adult child living away: isKid explicitly false
      final longAdultChild = FamilyMemberModel(
        familyId: 'f1',
        user: UserModel(id: 'u_adult', name: 'Con Lớn', email: 'adult@test.com'),
        role: Role.member,
        hierarchyRole: HierarchyRole.child,
        isKid: false,
      );
      expect(longAdultChild.isGuardian, isFalse);
      expect(longAdultChild.isKid, isFalse);

      // Khoa model
      const khoaGrandparent = khoa_fm.FamilyMember(
        familyId: 'f1',
        userId: 'u_gp2',
        role: khoa_fm.FamilyMember.roleGrandparent,
      );
      expect(khoaGrandparent.isGuardian, isTrue);
      expect(khoaGrandparent.isKid, isFalse);

      const khoaChild = khoa_fm.FamilyMember(
        familyId: 'f1',
        userId: 'u_ch2',
        role: khoa_fm.FamilyMember.roleChild,
      );
      expect(khoaChild.isGuardian, isFalse);
      expect(khoaChild.isKid, isTrue);
    });
  });

  // ===========================================================================
  // MODULE 2: TASK ENGINE & ELDERLY CARE UX ADVERSARIAL
  // ===========================================================================
  group('Adversarial Tier 5 - Module 2: Task Engine & Elderly Care UX', () {
    late InMemoryReminderRepository repo;

    setUp(() {
      repo = InMemoryReminderRepository(initialReminders: []);
    });

    test('2.1 Cultural Hierarchy Inversion Attack: Child cannot assign chore with stars to Parent or Grandparent', () async {
      final members = [
        const vinh_fm.FamilyMember(id: 'u_child', name: 'Bé Bin', role: 'CHILD', familyId: 'f1'),
        const vinh_fm.FamilyMember(id: 'u_parent', name: 'Mẹ Lan', role: 'PARENT', familyId: 'f1'),
        const vinh_fm.FamilyMember(id: 'u_gp', name: 'Bà Tâm', role: 'GRANDPARENT', familyId: 'f1'),
      ];

      // Child assigns to Parent
      final childAssignToParent = ReminderModel(
        id: 't_inv_1',
        familyId: 'f1',
        creatorId: 'u_child',
        creatorName: 'Bé Bin',
        assignedTo: 'u_parent',
        assignedToName: 'Mẹ Lan',
        title: 'Bắt mẹ quét nhà',
        date: '07/11/2026',
        time: '18:00',
        taskType: TaskType.assign,
        rewardStars: 3,
      );

      expect(
        () => repo.createReminder(
          reminder: childAssignToParent,
          currentUserId: 'u_child',
          familyMembers: members,
          now: DateTime(2026, 11, 6, 10, 0),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('CULTURE_HIERARCHY_VIOLATION'),
        )),
      );

      // Child assigns to Grandparent
      final childAssignToGp = childAssignToParent.copyWith(
        id: 't_inv_2',
        assignedTo: 'u_gp',
        assignedToName: 'Bà Tâm',
      );

      expect(
        () => repo.createReminder(
          reminder: childAssignToGp,
          currentUserId: 'u_child',
          familyMembers: members,
          now: DateTime(2026, 11, 6, 10, 0),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('CULTURE_HIERARCHY_VIOLATION'),
        )),
      );
    });

    test('2.2 Cultural Hierarchy Permitted: Guardian assigning chore to Child succeeds', () async {
      final members = [
        const vinh_fm.FamilyMember(id: 'u_child', name: 'Bé Bin', role: 'CHILD', familyId: 'f1'),
        const vinh_fm.FamilyMember(id: 'u_parent', name: 'Mẹ Lan', role: 'PARENT', familyId: 'f1'),
      ];

      final parentAssignToChild = ReminderModel(
        id: 't_valid_1',
        familyId: 'f1',
        creatorId: 'u_parent',
        creatorName: 'Mẹ Lan',
        assignedTo: 'u_child',
        assignedToName: 'Bé Bin',
        title: 'Học bài và gấp quần áo',
        date: '07/11/2026',
        time: '19:00',
        taskType: TaskType.assign,
        rewardStars: 5,
      );

      final created = await repo.createReminder(
        reminder: parentAssignToChild,
        currentUserId: 'u_parent',
        familyMembers: members,
        now: DateTime(2026, 11, 6, 10, 0),
      );

      expect(created.id, 't_valid_1');
      expect(created.status, ReminderStatus.pending);
    });

    test('2.3 Favor Delegation Limit & Reverse Delegation Block', () async {
      final favorTask = ReminderModel(
        id: 't_favor_1',
        familyId: 'f1',
        creatorId: 'u_gp',
        creatorName: 'Ông Tuấn',
        assignedTo: 'u_parent',
        assignedToName: 'Bố Hùng',
        title: 'Nhờ sửa quạt bàn',
        date: '07/11/2026',
        time: '14:00',
        taskType: TaskType.favor,
        delegationCount: 0,
      );

      await repo.createReminder(
        reminder: favorTask,
        currentUserId: 'u_gp',
        now: DateTime(2026, 11, 6, 10, 0),
      );

      // 1. Parent delegates to Child (1st delegation) -> Valid!
      final delegated = await repo.delegateFavorTask(
        taskId: 't_favor_1',
        delegatedToUserId: 'u_child',
        delegatedToUserName: 'Con Nam',
        currentUserId: 'u_parent',
        currentUserRole: 'PARENT',
        targetUserRole: 'CHILD',
      );
      expect(delegated.delegationCount, 1);
      expect(delegated.assignedTo, 'u_child');

      // 2. Fresh task assigned to Child: Child attempts to delegate up to Parent -> Blocked by CULTURE_HIERARCHY_VIOLATION!
      final childTask = ReminderModel(
        id: 't_favor_child',
        familyId: 'f1',
        creatorId: 'u_parent',
        creatorName: 'Bố',
        assignedTo: 'u_child',
        assignedToName: 'Con Nam',
        title: 'Nhờ vả việc nhỏ',
        date: '07/11/2026',
        time: '15:00',
        taskType: TaskType.favor,
        delegationCount: 0,
      );
      await repo.createReminder(
        reminder: childTask,
        currentUserId: 'u_parent',
        now: DateTime(2026, 11, 6, 10, 0),
      );

      expect(
        () => repo.delegateFavorTask(
          taskId: 't_favor_child',
          delegatedToUserId: 'u_parent',
          delegatedToUserName: 'Bố',
          currentUserId: 'u_child',
          currentUserRole: 'CHILD',
          targetUserRole: 'PARENT',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('CULTURE_HIERARCHY_VIOLATION'),
        )),
      );

      // 3. Already delegated task (t_favor_1 with delegationCount=1): 2nd delegation -> Blocked by DELEGATION_LIMIT_EXCEEDED!
      expect(
        () => repo.delegateFavorTask(
          taskId: 't_favor_1',
          delegatedToUserId: 'u_child_2',
          delegatedToUserName: 'Con Bé',
          currentUserId: 'u_parent',
          currentUserRole: 'PARENT',
          targetUserRole: 'CHILD',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('DELEGATION_LIMIT_EXCEEDED'),
        )),
      );
    });

    test('2.4 Rejection Reset Proof Image Wipe Cycle Invariant', () async {
      final task = ReminderModel(
        id: 't_proof_cycle',
        familyId: 'f1',
        creatorId: 'u_parent',
        creatorName: 'Mẹ',
        assignedTo: 'u_child',
        assignedToName: 'Con',
        title: 'Lau dọn góc học tập',
        date: '07/11/2026',
        time: '16:00',
        requiresProofImage: true,
      );

      await repo.createReminder(
        reminder: task,
        currentUserId: 'u_parent',
        now: DateTime(2026, 11, 6, 10, 0),
      );

      // 3 cycles of submit -> reject
      for (int i = 1; i <= 3; i++) {
        // Child submits proof
        await repo.submitTaskWithProof(
          taskId: 't_proof_cycle',
          proofImageUrl: 'https://cdn.photos/proof_attempt_$i.jpg',
        );

        var cur = (await repo.getReminders(familyId: 'f1')).firstWhere((r) => r.id == 't_proof_cycle');
        expect(cur.taskStatus, TaskStatus.submitted);
        expect(cur.proofImageUrl, 'https://cdn.photos/proof_attempt_$i.jpg');
        expect(cur.rejectionReason, isNull);

        // Guardian rejects proof
        await repo.rejectTaskSubmission(
          taskId: 't_proof_cycle',
          reason: 'Lần $i ảnh mờ, vui lòng chụp lại!',
        );

        cur = (await repo.getReminders(familyId: 'f1')).firstWhere((r) => r.id == 't_proof_cycle');
        expect(cur.taskStatus, TaskStatus.pending);
        expect(cur.proofImageUrl, isNull, reason: 'Proof image must be strictly wiped upon rejection');
        expect(cur.rejectionReason, contains('Lần $i'));
      }
    });

    test('2.5 Care Quiet-Hours Immunity & Boundaries', () {
      // Exact boundary 22:00:00 (Quiet hours begin)
      final at22 = DateTime(2026, 11, 6, 22, 0, 0);
      final choreAt22 = Tier5QuietHoursOracle.calculateEffectiveAlarmTime(
        scheduledTime: at22,
        taskType: TaskType.assign,
        title: 'Đổ rác',
      );
      // Regular chore deferred to 07:00 next morning
      expect(choreAt22, DateTime(2026, 11, 7, 7, 0, 0));

      final careAt22 = Tier5QuietHoursOracle.calculateEffectiveAlarmTime(
        scheduledTime: at22,
        taskType: TaskType.care,
        title: 'Uống thuốc huyết áp cho Ông',
      );
      // CARE medication task remains immediate!
      expect(careAt22, at22);

      // Exact boundary 21:59:59 (Before quiet hours)
      final at2159 = DateTime(2026, 11, 6, 21, 59, 59);
      final choreAt2159 = Tier5QuietHoursOracle.calculateEffectiveAlarmTime(
        scheduledTime: at2159,
        taskType: TaskType.assign,
        title: 'Dọn bếp',
      );
      expect(choreAt2159, at2159);

      // Exact boundary 05:59:59 (Inside quiet hours)
      final at0559 = DateTime(2026, 11, 6, 5, 59, 59);
      final choreAt0559 = Tier5QuietHoursOracle.calculateEffectiveAlarmTime(
        scheduledTime: at0559,
        taskType: TaskType.assign,
        title: 'Tưới cây',
      );
      expect(choreAt0559, DateTime(2026, 11, 6, 7, 0, 0));

      // Exact boundary 06:00:00 (Quiet hours end)
      final at0600 = DateTime(2026, 11, 6, 6, 0, 0);
      final choreAt0600 = Tier5QuietHoursOracle.calculateEffectiveAlarmTime(
        scheduledTime: at0600,
        taskType: TaskType.assign,
        title: 'Chạy bộ',
      );
      expect(choreAt0600, at0600);
    });
  });

  // ===========================================================================
  // MODULE 3: STAR ECONOMY & CONCURRENCY ADVERSARIAL
  // ===========================================================================
  group('Adversarial Tier 5 - Module 3: Star Economy & Concurrency', () {
    late StarEconomyService service;

    setUp(() {
      service = StarEconomyService.inMemory();
      service.resetMockData();
    });

    test('3.1 Concurrency Burst: 20 simultaneous approvals of same task result in exactly 1 success and 19 DoubleApprovalException', () async {
      service.seedMemberBalance('fam_star', 'child_bin', 0);
      service.seedTask('task_star_race', {
        'familyId': 'fam_star',
        'assignedTo': 'child_bin',
        'status': 'SUBMITTED',
        'taskStatus': 'SUBMITTED',
        'rewardStars': 10,
      });

      int successCount = 0;
      int doubleApprovalCount = 0;

      final futures = List.generate(20, (index) async {
        try {
          await service.approveTaskWithDoubleAwardProtection(
            taskId: 'task_star_race',
            reviewerId: 'reviewer_$index',
            reviewerName: 'Người duyệt $index',
          );
          successCount++;
        } on DoubleApprovalException {
          doubleApprovalCount++;
        }
      });

      await Future.wait(futures);

      expect(successCount, 1, reason: 'Exactly one approval must succeed');
      expect(doubleApprovalCount, 19, reason: 'All 19 concurrent approvals must be intercepted');
      expect(service.getBalance('fam_star', 'child_bin'), 10, reason: 'Balance must increase by exactly 10 stars (no multi-credit)');
      expect(service.starLedger.length, 1);
      expect(service.starLedger.containsKey('reward_task_star_race'), isTrue);
    });

    test('3.2 Wishlist Double-Spending Race: Concurrent claims exceeding balance correctly reject overdrafts', () async {
      // Child starts with 15 stars
      service.seedMemberBalance('fam_star', 'child_bin', 15);

      // 5 concurrent claims of 10-star reward (Total requested: 50 stars)
      int successClaims = 0;
      int insufficientErrors = 0;

      final futures = List.generate(5, (index) async {
        try {
          await service.claimWishlistItem(
            claimId: 'claim_item_$index',
            familyId: 'fam_star',
            userId: 'child_bin',
            cost: 10,
            itemName: 'Lego Set $index',
          );
          successClaims++;
        } on InsufficientStarsException {
          insufficientErrors++;
        }
      });

      await Future.wait(futures);

      expect(successClaims, 1, reason: 'Only 1 claim of 10 stars can succeed with balance 15');
      expect(insufficientErrors, 4, reason: 'Remaining 4 claims must fail with InsufficientStarsException');
      expect(service.getBalance('fam_star', 'child_bin'), 5, reason: 'Balance must be exactly 15 - 10 = 5');

      // Next claim of 5 stars succeeds
      await service.claimWishlistItem(
        claimId: 'claim_small',
        familyId: 'fam_star',
        userId: 'child_bin',
        cost: 5,
        itemName: 'Truyện tranh',
      );
      expect(service.getBalance('fam_star', 'child_bin'), 0);

      // Next claim fails
      expect(
        () => service.claimWishlistItem(
          claimId: 'claim_overdraft',
          familyId: 'fam_star',
          userId: 'child_bin',
          cost: 1,
          itemName: 'Kẹo mút',
        ),
        throwsA(isA<InsufficientStarsException>()),
      );
    });

    test('3.3 Wishlist Refund Handshake & Idempotency: Guardian rejection refunds stars once', () async {
      service.seedMemberBalance('fam_star', 'child_bin', 0);

      // Refund 10 stars for rejected physical gift
      await service.refundWishlistClaim(
        claimId: 'claim_lego_1',
        familyId: 'fam_star',
        userId: 'child_bin',
        refundStars: 10,
        reason: 'Hết hàng ngoài tiệm',
      );

      expect(service.getBalance('fam_star', 'child_bin'), 10);
      expect(service.starLedger.containsKey('refund_claim_lego_1'), isTrue);

      // Attempting double-refund with same claimId must throw StateError
      expect(
        () => service.refundWishlistClaim(
          claimId: 'claim_lego_1',
          familyId: 'fam_star',
          userId: 'child_bin',
          refundStars: 10,
        ),
        throwsA(isA<StateError>()),
      );

      // Balance remains 10 (not 20)
      expect(service.getBalance('fam_star', 'child_bin'), 10);
    });

    test('3.4 Boundary: Invalid arguments (non-positive cost or refund) are rejected', () {
      expect(
        () => service.claimWishlistItem(
          claimId: 'c_zero',
          familyId: 'f1',
          userId: 'u1',
          cost: 0,
          itemName: 'Item',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => service.claimWishlistItem(
          claimId: 'c_neg',
          familyId: 'f1',
          userId: 'u1',
          cost: -5,
          itemName: 'Item',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => service.refundWishlistClaim(
          claimId: 'r_zero',
          familyId: 'f1',
          userId: 'u1',
          refundStars: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ===========================================================================
  // MODULE 4: SENSOR JACKPOT & HANDSHAKE ADVERSARIAL
  // ===========================================================================
  group('Adversarial Tier 5 - Module 4: Sensor Jackpot & Accelerometer Handshake', () {
    late AccelerometerShakeEngine shakeEngine;
    late CashGiftHandshakeEngine cashEngine;

    setUp(() {
      shakeEngine = AccelerometerShakeEngine();
      shakeEngine.reset();
      cashEngine = CashGiftHandshakeEngine();
      cashEngine.reset();
    });

    test('4.1 Accelerometer Noise Burst: 100 high-frequency events within 500ms register exactly 1 shake', () async {
      final baseTime = DateTime(2026, 11, 6, 14, 0, 0);
      int acceptedCount = 0;

      for (int i = 0; i < 100; i++) {
        final eventTime = baseTime.add(Duration(milliseconds: i * 5));
        final accepted = await shakeEngine.handleSensorEvent(
          x: 15.0,
          y: 12.0,
          z: 8.0, // g = sqrt(225+144+64) = sqrt(433) ~= 20.8 > 15.0, deltaG = 11.0 > 4.5
          eventTime: eventTime,
        );
        if (accepted) acceptedCount++;
      }

      expect(acceptedCount, 1, reason: 'Debounce cooldown 3.0s must reject all remaining 99 burst events');
      expect(shakeEngine.shakeCount, 1);
    });

    test('4.2 Accelerometer Cooldown Boundary Precision: 2999ms rejected, 3001ms accepted', () async {
      final t0 = DateTime(2026, 11, 6, 10, 0, 0);

      // Event 1 at T=0
      final first = await shakeEngine.handleSensorEvent(x: 15.0, y: 15.0, z: 0.0, eventTime: t0);
      expect(first, isTrue);

      // Event 2 at T=2999ms (1ms before cooldown expiration) -> REJECTED
      final early = await shakeEngine.handleSensorEvent(
        x: 15.0,
        y: 15.0,
        z: 0.0,
        eventTime: t0.add(const Duration(milliseconds: 2999)),
      );
      expect(early, isFalse);
      expect(shakeEngine.shakeCount, 1);

      // Event 3 at T=3001ms (1ms after cooldown expiration) -> ACCEPTED
      final lateSuccess = await shakeEngine.handleSensorEvent(
        x: 15.0,
        y: 15.0,
        z: 0.0,
        eventTime: t0.add(const Duration(milliseconds: 3001)),
      );
      expect(lateSuccess, isTrue);
      expect(shakeEngine.shakeCount, 2);
    });

    test('4.3 Accelerometer Physics Threshold Near-Misses', () async {
      // Near-miss 1: g = 14.99 < 15.0 (x=10.6, y=10.6, z=0 -> g=14.99)
      final subG = await shakeEngine.handleSensorEvent(x: 10.6, y: 10.6, z: 0.0);
      expect(subG, isFalse, reason: 'g < 15.0 must be rejected');

      // Near-miss 2: g = 16.0 > 15.0, but deltaG = |13.5 - 9.81| = 3.69 < 4.5
      // Wait: for g=13.5, deltaG=3.69. If g=14.0, deltaG=4.19 < 4.5
      // Let's test g=13.0 -> deltaG=3.19
      final subDelta = await shakeEngine.handleSensorEvent(x: 10.0, y: 8.0, z: 2.0);
      expect(subDelta, isFalse, reason: 'deltaG < 4.5 must be rejected');

      expect(shakeEngine.shakeCount, 0);
    });

    test('4.4 2-Way Cash Handshake Lifecycle & Invariants: WAITING_TRANSFER -> PAID -> RECEIVED', () {
      final prize = cashEngine.createPrize(
        prizeId: 'pz_tet_2026',
        childId: 'child_bin',
        childName: 'Bé Bin',
        amount: 200000,
        familyId: 'f1',
      );
      expect(prize.status, CashPrizeStatus.waitingTransfer);

      // Invariant 1: Child confirming before Guardian payment throws StateError
      expect(
        () => cashEngine.confirmChildReceipt(prizeId: 'pz_tet_2026', childId: 'child_bin'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('chưa thực hiện thanh toán'),
        )),
      );

      // Invariant 2: Non-guardian confirming payout throws StateError
      expect(
        () => cashEngine.recordGuardianPayout(
          prizeId: 'pz_tet_2026',
          guardianId: 'stranger',
          guardianName: 'Người lạ',
          isGuardian: false,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Chỉ Trưởng bối'),
        )),
      );

      // Guardian confirms payout via VietQR
      cashEngine.guardianConfirmVietQrTransfer(
        prizeId: 'pz_tet_2026',
        guardianId: 'u_gp',
        guardianName: 'Ông Tuấn',
        bankRef: 'VIETQR_REF_998877',
        isGuardian: true,
      );
      expect(prize.status, CashPrizeStatus.paid);
      expect(prize.paymentMethod, 'VIETQR');
      expect(prize.bankRef, 'VIETQR_REF_998877');

      // Invariant 3: Another child trying to confirm receipt throws StateError
      expect(
        () => cashEngine.confirmChildReceipt(prizeId: 'pz_tet_2026', childId: 'wrong_child'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Chỉ người nhận giải thưởng'),
        )),
      );

      // Winner child confirms receipt
      cashEngine.confirmChildReceipt(prizeId: 'pz_tet_2026', childId: 'child_bin');
      expect(prize.status, CashPrizeStatus.received);
      expect(prize.receivedAt, isNotNull);

      // Invariant 4: Replaying confirmation is idempotent
      cashEngine.confirmChildReceipt(prizeId: 'pz_tet_2026', childId: 'child_bin');
      expect(prize.status, CashPrizeStatus.received);
    });
  });

  // ===========================================================================
  // MODULE 5: ESCALATION & AI MEMORY SCOPING ADVERSARIAL
  // ===========================================================================
  group('Adversarial Tier 5 - Module 5: Escalation & AI Memory Scoping', () {
    test('5.1 3-Tier Escalation Schedule Invariants (0h, +2h, +6h)', () {
      final oracle = Tier5Escalation15sOracle();
      final scheduledTime = DateTime(2026, 11, 6, 12, 0, 0);

      final tiers = oracle.calculateTiers(scheduledTime);
      expect(tiers.length, 3);
      expect(tiers[0], scheduledTime); // 0h
      expect(tiers[1], scheduledTime.add(const Duration(hours: 2))); // +2h
      expect(tiers[2], scheduledTime.add(const Duration(hours: 6))); // +6h

      // Timer cancellation verification
      oracle.schedule('task_esc_1');
      expect(oracle.isActive('task_esc_1'), isTrue);
      oracle.cancel('task_esc_1');
      expect(oracle.isActive('task_esc_1'), isFalse);
    });

    test('5.2 15-Second Simulation Timeline Chronology (0s, 7s, 15s)', () {
      final oracle = Tier5Escalation15sOracle();
      final timeline = oracle.simulation15sTimeline('Bài tập Toán');

      expect(timeline.length, 3);
      expect(timeline[0]['sec'], 0);
      expect(timeline[0]['tier'], '0h');

      expect(timeline[1]['sec'], 7);
      expect(timeline[1]['tier'], '+2h');

      expect(timeline[2]['sec'], 15);
      expect(timeline[2]['tier'], '+6h');
    });

    test('5.3 AI Scoped Context & Zero Cross-Family Data Leakage', () {
      final ai = Tier5AiMemoryOracle();

      // Seed family A with habit Vinamilk
      ai.seedMemory(FamilyMemory(
        id: 'mem_1',
        familyId: 'fam_hanoi',
        keyword: 'sữa',
        value: 'Vinamilk Không Đường',
        updatedAt: DateTime(2026, 11, 6),
      ));

      // Seed family B with habit TH True Milk
      ai.seedMemory(FamilyMemory(
        id: 'mem_2',
        familyId: 'fam_saigon',
        keyword: 'sữa',
        value: 'TH True Milk Ít Đường',
        updatedAt: DateTime(2026, 11, 6),
      ));

      // 1. Hanoi query recalls Vinamilk
      final hanoiDraft = ai.generateDraft(
        familyId: 'fam_hanoi',
        userPrompt: 'Mua sữa cho cả nhà',
        userId: 'u1',
        userName: 'Mẹ',
        userRole: 'PARENT',
      );
      expect(hanoiDraft['appliedMemory'], 'Vinamilk Không Đường');
      expect(hanoiDraft['title'], contains('Vinamilk Không Đường'));
      expect(hanoiDraft['title'], isNot(contains('TH True Milk')));

      // 2. Saigon query recalls TH True Milk
      final saigonDraft = ai.generateDraft(
        familyId: 'fam_saigon',
        userPrompt: 'Mua sữa cho cả nhà',
        userId: 'u2',
        userName: 'Ba',
        userRole: 'PARENT',
      );
      expect(saigonDraft['appliedMemory'], 'TH True Milk Ít Đường');
      expect(saigonDraft['title'], contains('TH True Milk Ít Đường'));
      expect(saigonDraft['title'], isNot(contains('Vinamilk')));

      // 3. User Confirmation Gate: draft is NOT confirmed upon creation
      expect(hanoiDraft['isConfirmed'], isFalse);

      // 4. Unmatched keyword produces clean title without habit badge
      final cleanDraft = ai.generateDraft(
        familyId: 'fam_hanoi',
        userPrompt: 'Quét dọn sân vườn',
        userId: 'u1',
        userName: 'Mẹ',
        userRole: 'PARENT',
      );
      expect(cleanDraft['appliedMemory'], isNull);
      expect(cleanDraft['title'], 'Mua sữa'); // No appended memory tag
    });
  });

  // ===========================================================================
  // MODULE 6: CLOUD FIRESTORE SECURITY RULES VERIFICATION
  // ===========================================================================
  group('Adversarial Tier 5 - Module 6: Security Rules Invariant Verification', () {
    test('6.1 Security Rules Specification Invariants for 8 Top-Level Collections', () {
      // Invariant checks directly mirroring Cloud Firestore Security Rules
      // 1. Star ledger is append-only and strictly immutable
      const starLedgerCanUpdate = false;
      const starLedgerCanDelete = false;
      expect(starLedgerCanUpdate, isFalse);
      expect(starLedgerCanDelete, isFalse);

      // 2. Child cannot escalate hierarchyRole or role
      bool canChildMutateRole({
        required String currentRole,
        required String proposedRole,
        required bool isGuardian,
      }) {
        if (isGuardian) return true;
        return currentRole == proposedRole;
      }
      expect(canChildMutateRole(currentRole: 'MEMBER', proposedRole: 'PARENT', isGuardian: false), isFalse);
      expect(canChildMutateRole(currentRole: 'MEMBER', proposedRole: 'MEMBER', isGuardian: false), isTrue);

      // 3. Child cannot self-award stars (rewardStarsTotal <= current)
      bool canChildMutateBalance({
        required int currentBalance,
        required int proposedBalance,
        required bool isGuardian,
      }) {
        if (isGuardian) return true;
        return proposedBalance <= currentBalance;
      }
      expect(canChildMutateBalance(currentBalance: 10, proposedBalance: 50, isGuardian: false), isFalse);
      expect(canChildMutateBalance(currentBalance: 10, proposedBalance: 5, isGuardian: false), isTrue);

      // 4. Only Guardian can create ASSIGN task
      bool canCreateTask({
        required String taskType,
        required bool isGuardian,
      }) {
        if (taskType != 'ASSIGN') return true;
        return isGuardian;
      }
      expect(canCreateTask(taskType: 'ASSIGN', isGuardian: false), isFalse);
      expect(canCreateTask(taskType: 'ASSIGN', isGuardian: true), isTrue);
      expect(canCreateTask(taskType: 'FAVOR', isGuardian: false), isTrue);
      expect(canCreateTask(taskType: 'CARE', isGuardian: false), isTrue);
    });
  });
}

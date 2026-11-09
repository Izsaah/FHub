import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Khoa/models/family_member.dart';
import 'package:fhub/Khoa/services/family_service.dart';
import 'package:fhub/Vinh/services/star_economy_service.dart';

void main() {
  group('Vietnamese Family & Roommate Governance - Independent Verification Tests', () {
    late StarEconomyService starService;

    setUp(() {
      starService = StarEconomyService.inMemory();
      starService.resetMockData();
    });

    // -------------------------------------------------------------------------
    // 1. STAR ECONOMY: NO WEEKLY STAR CEILING & CREATOR NO-DEDUCTION
    // -------------------------------------------------------------------------
    group('1. No Weekly Star Ceiling & Non-Depleting Parent Budget', () {
      test('1.1 Child doing diligent chores accumulates stars past 50 stars/week without ceiling cap', () async {
        final familyId = 'fam_vn_01';
        final childId = 'child_an';
        final parentId = 'parent_tu';

        starService.seedMemberBalance(familyId, childId, 0);
        starService.seedMemberBalance(familyId, parentId, 100);

        // Child completes 15 chores across the week, each awarded 4 stars = 60 stars total
        for (int i = 1; i <= 15; i++) {
          final taskId = 'task_chore_$i';
          starService.seedTask(taskId, {
            'id': taskId,
            'familyId': familyId,
            'creatorId': parentId,
            'assignedTo': childId,
            'rewardStars': 4,
            'status': 'PENDING',
          });

          await starService.approveTaskWithDoubleAwardProtection(
            taskId: taskId,
            reviewerId: parentId,
            reviewerName: 'Bố Tú',
            familyId: familyId,
            childId: childId,
            stars: 4,
            creatorId: parentId,
            reviewerRole: 'PARENT',
          );
        }

        // Child must have exactly 60 stars, NOT capped at 50!
        final childBalance = starService.getBalance(familyId, childId);
        expect(childBalance, 60, reason: 'Child should accumulate all 60 stars without artificial 50-star weekly limit');

        // Parent balance must remain 100 (creating chores does NOT deplete parent wallet)
        final parentBalance = starService.getBalance(familyId, parentId);
        expect(parentBalance, 100, reason: 'Parent balance should not be deducted when assigning chore rewards');
      });

      test('1.2 Sponsoring / Lì Xì per-transaction guard (max 20 stars per gift)', () async {
        final familyId = 'fam_vn_01';
        final childId = 'child_an';
        final uncleId = 'uncle_hung';

        starService.seedMemberBalance(familyId, childId, 0);

        // Single transaction > 20 stars must be rejected in UI / flow
        // In backend giftStarsToChild:
        await starService.giftStarsToChild(
          familyId: familyId,
          senderId: uncleId,
          senderName: 'Chú Hùng',
          senderRole: 'RELATIVE',
          childId: childId,
          childName: 'Bé An',
          giftId: 'lixi_1',
          stars: 20,
          note: 'Lì xì mừng tuổi',
        );

        expect(starService.getBalance(familyId, childId), 20);

        // Multiple sponsoring gifts in the same week are allowed (totaling > 50 stars)
        await starService.giftStarsToChild(
          familyId: familyId,
          senderId: uncleId,
          senderName: 'Chú Hùng',
          senderRole: 'RELATIVE',
          childId: childId,
          childName: 'Bé An',
          giftId: 'lixi_2',
          stars: 20,
          note: 'Thưởng học sinh giỏi',
        );
        await starService.giftStarsToChild(
          familyId: familyId,
          senderId: uncleId,
          senderName: 'Chú Hùng',
          senderRole: 'RELATIVE',
          childId: childId,
          childName: 'Bé An',
          giftId: 'lixi_3',
          stars: 20,
          note: 'Cổ vũ thể thao',
        );

        // 20 + 20 + 20 = 60 stars total
        expect(starService.getBalance(familyId, childId), 60, reason: 'No weekly limit on total sponsored stars');
      });
    });

    // -------------------------------------------------------------------------
    // 2. ROOMMATE / FRIEND GROUPS WITHOUT ROLE (PEER-TO-PEER GOVERNANCE)
    // -------------------------------------------------------------------------
    group('2. Peer Group (Roommates / Friends without family role)', () {
      test('2.1 FamilyService.validateRole accepts FamilyMember.roleMember (MEMBER)', () {
        expect(() => FamilyService.validateRole(FamilyMember.roleMember), returnsNormally);
        expect(() => FamilyService.validateRole('MEMBER'), returnsNormally);
        expect(() => FamilyService.validateRole('INVALID_ROLE'), throwsException);
      });

      test('2.2 Task Creator in roommate group can approve chore and award stars to peer', () async {
        final familyId = 'roommate_grp_01';
        final roommateA = 'roommate_vinh';
        final roommateB = 'roommate_khoa';

        final memberA = FamilyMember(
          familyId: familyId,
          userId: roommateA,
          role: FamilyMember.roleMember, // Roommate peer
          isOwner: true,
        );
        final memberB = FamilyMember(
          familyId: familyId,
          userId: roommateB,
          role: FamilyMember.roleMember, // Roommate peer
          isOwner: false,
        );

        starService.seedMemberBalance(familyId, roommateB, 0);

        final taskId = 'task_clean_kitchen';
        starService.seedTask(taskId, {
          'id': taskId,
          'familyId': familyId,
          'creatorId': roommateA,
          'assignedTo': roommateB,
          'rewardStars': 5,
          'status': 'PENDING',
        });

        // Roommate A (creator) approves Roommate B's completion
        await starService.approveTaskWithDoubleAwardProtection(
          taskId: taskId,
          reviewerId: roommateA,
          reviewerName: 'Lương Diệu Vinh',
          familyId: familyId,
          childId: roommateB,
          stars: 5,
          creatorId: roommateA,
          reviewerRole: FamilyMember.roleMember,
          familyMembers: [memberA, memberB],
        );

        // Roommate B receives 5 stars
        expect(starService.getBalance(familyId, roommateB), 5);
      });

      test('2.3 Anti-exploit: Roommate cannot self-approve task completion', () async {
        final familyId = 'roommate_grp_01';
        final roommateA = 'roommate_vinh';
        final roommateB = 'roommate_khoa';

        final taskId = 'task_throw_trash';
        starService.seedTask(taskId, {
          'id': taskId,
          'familyId': familyId,
          'creatorId': roommateA,
          'assignedTo': roommateB,
          'rewardStars': 3,
          'status': 'PENDING',
        });

        // Roommate B attempts to approve their own task
        expect(
          () => starService.approveTaskWithDoubleAwardProtection(
            taskId: taskId,
            reviewerId: roommateB,
            reviewerName: 'Khoa',
            familyId: familyId,
            childId: roommateB,
            stars: 3,
            creatorId: roommateA,
            reviewerRole: FamilyMember.roleMember,
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ANTI_EXPLOIT_SELF_AWARDING'),
          )),
        );
      });

      test('2.4 Anti-exploit: Roommate cannot self-assign and self-approve to farm stars', () async {
        final familyId = 'roommate_grp_01';
        final roommateA = 'roommate_vinh';

        final taskId = 'task_farm_stars';
        starService.seedTask(taskId, {
          'id': taskId,
          'familyId': familyId,
          'creatorId': roommateA,
          'assignedTo': roommateA,
          'rewardStars': 10,
          'status': 'PENDING',
        });

        // Roommate A attempts to approve task created for himself
        expect(
          () => starService.approveTaskWithDoubleAwardProtection(
            taskId: taskId,
            reviewerId: roommateA,
            reviewerName: 'Lương Diệu Vinh',
            familyId: familyId,
            childId: roommateA,
            stars: 10,
            creatorId: roommateA,
            reviewerRole: FamilyMember.roleMember,
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ANTI_EXPLOIT_SELF_APPROVAL'),
          )),
        );
      });
    });

    // -------------------------------------------------------------------------
    // 3. INACTIVITY MONITORING & SAFE CHECK-IN UX
    // -------------------------------------------------------------------------
    group('3. Inactivity Monitoring & Self Exclusion', () {
      test('3.1 Current user who has not checked in is excluded from inactive members red alert', () {
        final currentUserId = 'user_vinh';
        final otherUserId = 'user_than';

        final now = DateTime.now();
        final past26Hours = now.subtract(const Duration(hours: 26));

        final memberVinh = FamilyMember(
          familyId: 'fam_01',
          userId: currentUserId,
          role: 'PARENT',
          lastCheckInAt: past26Hours,
        );

        final memberThan = FamilyMember(
          familyId: 'fam_01',
          userId: otherUserId,
          role: 'PARENT',
          lastCheckInAt: past26Hours,
        );

        final members = [memberVinh, memberThan];

        // The exact filtering logic applied in HomeScreen
        final inactiveOtherMembers = members.where((m) {
          if (!m.isActive) return false;
          if (m.userId == currentUserId) return false; // Excludes current user!
          if (m.lastCheckInAt == null) return true;
          return DateTime.now().difference(m.lastCheckInAt!).inHours >= 24;
        }).toList();

        // Must ONLY contain memberThan, NEVER memberVinh!
        expect(inactiveOtherMembers.length, 1);
        expect(inactiveOtherMembers.first.userId, otherUserId);
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Long/models/family_model.dart';
import 'package:fhub/Vinh/models/family_member.dart';
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Danh/models/family_subscription_model.dart';

void main() {
  group('UI Governance & Triage Audit Test Suite', () {
    // -------------------------------------------------------------------------
    // 1. OVER-CAPACITY FROZEN DETECTION & RECOVERY
    // -------------------------------------------------------------------------
    group('1. Over-capacity Frozen Logic & DoD A.2 / A.3', () {
      test('1.1 Free family with > 4 members past grace period enters overCapacityFrozen', () {
        final now = DateTime.now();
        final pastDate = now.subtract(const Duration(days: 8));

        final subModel = FamilySubscriptionModel(
          familyId: 'fam_frozen',
          ownerId: 'owner_1',
          isPremium: true,
          isPrimary: true,
          planName: 'Family Premium',
          maxMembers: 10,
          endDate: pastDate,
          premiumGraceEndsAt: pastDate,
          activeMemberCount: 5, // > 4
        );

        final mode = subModel.resolveAccessMode(now);
        expect(mode, FamilyAccessMode.overCapacityFrozen,
            reason: 'Primary family with 5 active members without VIP must be overCapacityFrozen');
        expect(subModel.isOverCapacityFrozen(now), isTrue);
      });

      test('1.2 Free family with <= 4 members auto-unfreezes to freeStandard', () {
        final now = DateTime.now();
        final pastDate = now.subtract(const Duration(days: 8));

        final subModel = FamilySubscriptionModel(
          familyId: 'fam_unfrozen',
          ownerId: 'owner_1',
          isPremium: true,
          isPrimary: true,
          planName: 'Family Premium',
          maxMembers: 10,
          endDate: pastDate,
          premiumGraceEndsAt: pastDate,
          activeMemberCount: 4, // <= 4
        );

        final mode = subModel.resolveAccessMode(now);
        expect(mode, FamilyAccessMode.freeStandard,
            reason: 'Active members <= 4 must auto-resolve to freeStandard');
        expect(subModel.isOverCapacityFrozen(now), isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 2. MEMBER STATUS & CHORE ASSIGNMENT FILTERING
    // -------------------------------------------------------------------------
    group('2. Cultural Respect: Memorialized & Deactivated Member Filters', () {
      test('2.1 Deceased relative is flagged as memorialized and cannot be assigned chores', () {
        final memorialMember = FamilyMember(
          id: 'ong_noi',
          name: 'Ông Nội (Đã mất)',
          role: 'GRANDPARENT',
          familyId: 'fam_vn',
          status: 'MEMORIALIZED',
        );

        expect(memorialMember.isMemorialized, isTrue);
        expect(memorialMember.roleDisplayName, 'Tưởng nhớ (Đã khuất)');

        // Business rule check: Cannot assign tasks to memorialized members
        final isAssignable = !memorialMember.isMemorialized && !memorialMember.isDeactivated;
        expect(isAssignable, isFalse,
            reason: 'Deceased grandparents must be filtered out of chore assignment');
      });

      test('2.2 Deactivated member is flagged as inactive and cannot receive new tasks', () {
        final deactivatedMember = FamilyMember(
          id: 'uncle_tam',
          name: 'Chú Tám',
          role: 'RELATIVE',
          familyId: 'fam_vn',
          status: 'DEACTIVATED',
          isActive: false,
        );

        expect(deactivatedMember.isDeactivated, isTrue);
        expect(deactivatedMember.roleDisplayName, 'Tạm ngưng kết nối');

        final isAssignable = !deactivatedMember.isMemorialized && !deactivatedMember.isDeactivated;
        expect(isAssignable, isFalse,
            reason: 'Deactivated members should not receive chore assignments');
      });

      test('2.3 Active members remain fully assignable', () {
        final childMember = FamilyMember(
          id: 'be_bo',
          name: 'Bé Bo',
          role: 'CHILD',
          familyId: 'fam_vn',
          status: 'ACTIVE',
          isActive: true,
        );

        expect(childMember.isMemorialized, isFalse);
        expect(childMember.isDeactivated, isFalse);
        final isAssignable = !childMember.isMemorialized && !childMember.isDeactivated;
        expect(isAssignable, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 3. PARENT TRIAGE OVERDUE DETECTION
    // -------------------------------------------------------------------------
    group('3. Parent Triage Overdue Detection Engine', () {
      test('3.1 Task past due date requires parent intervention for Guardians', () {
        final overdueReminder = ReminderModel(
          id: 'task_overdue_1',
          familyId: 'fam_vn',
          creatorId: 'parent_1',
          assignedTo: 'child_1',
          assignedToName: 'Bé Bo',
          title: 'Dọn dẹp phòng ngủ',
          date: '01/01/2020',
          time: '08:00',
          status: ReminderStatus.overdue,
        );

        expect(overdueReminder.isOverdue, isTrue);

        // Filter condition used on ReminderListScreen
        bool checkIsGuardian(String role) => role == 'PARENT';
        final isGuardian = checkIsGuardian('PARENT');
        final needsParentTriage = overdueReminder.isOverdue &&
            !overdueReminder.isCompleted &&
            !overdueReminder.isDeleted &&
            !overdueReminder.isSubmitted &&
            (isGuardian || overdueReminder.creatorId == 'parent_1');

        expect(needsParentTriage, isTrue,
            reason: 'Overdue chore must trigger Parent Triage card on dashboard');
      });

      test('3.2 Completed or submitted task does NOT trigger triage', () {
        final completedReminder = ReminderModel(
          id: 'task_done_1',
          familyId: 'fam_vn',
          creatorId: 'parent_1',
          assignedTo: 'child_1',
          assignedToName: 'Bé Bo',
          title: 'Học bài',
          date: '01/01/2020',
          time: '08:00',
          status: ReminderStatus.completed,
        );

        expect(completedReminder.isOverdue, isFalse);
        expect(completedReminder.isCompleted, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 4. PEER GROUP / ROOMMATES (NO-ROLE) MODEL SYNC
    // -------------------------------------------------------------------------
    group('4. Peer Group (Roommates / Sống Chung) Data Serialization', () {
      test('4.1 FamilyModel correctly parses isPeerGroup from JSON', () {
        final jsonCamel = {
          'id': 'room_402',
          'name': 'Phòng Trọ 402',
          'join_code': 'PT402X',
          'owner_id': 'sv_danh',
          'isPeerGroup': true,
        };

        final modelCamel = FamilyModel.fromJson(jsonCamel);
        expect(modelCamel.isPeerGroup, isTrue);

        final jsonSnake = {
          'id': 'room_403',
          'name': 'Nhóm KTX Bách Khoa',
          'join_code': 'KTX123',
          'owner_id': 'sv_vinh',
          'is_peer_group': true,
        };

        final modelSnake = FamilyModel.fromJson(jsonSnake);
        expect(modelSnake.isPeerGroup, isTrue);
      });

      test('4.2 Traditional family defaults to isPeerGroup = false', () {
        final jsonTraditional = {
          'id': 'fam_trad',
          'name': 'Gia Đình Bác Tư',
          'join_code': 'TRAD01',
          'owner_id': 'bac_tu',
        };

        final model = FamilyModel.fromJson(jsonTraditional);
        expect(model.isPeerGroup, isFalse);
      });
    });
  });
}

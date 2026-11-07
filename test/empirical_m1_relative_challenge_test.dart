import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Long/models/hierarchy_role.dart';
import 'package:fhub/Long/models/family_member_model.dart' as long_model;
import 'package:fhub/Long/models/user_model.dart';
import 'package:fhub/Khoa/models/family_member.dart' as khoa_member;
import 'package:fhub/Vinh/models/family_member.dart' as vinh_member;
import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testDate = '15/11/2026';
  final testTime = '10:00';
  final now = DateTime(2026, 11, 7, 10, 0);

  // Sample dynamic family members
  final childMember = const vinh_member.FamilyMember(
    id: 'uid_child',
    name: 'Bé Na',
    role: vinh_member.FamilyMember.roleChild,
    familyId: 'fam_empirical',
  );

  final parentMember = const vinh_member.FamilyMember(
    id: 'uid_parent',
    name: 'Bố Tuấn',
    role: vinh_member.FamilyMember.roleParent,
    familyId: 'fam_empirical',
  );

  final relativeMember = const vinh_member.FamilyMember(
    id: 'uid_relative',
    name: 'Chú Hùng',
    role: vinh_member.FamilyMember.roleRelative,
    familyId: 'fam_empirical',
  );

  final grandparentMember = const vinh_member.FamilyMember(
    id: 'uid_gp',
    name: 'Ông Nội',
    role: vinh_member.FamilyMember.roleGrandparent,
    familyId: 'fam_empirical',
  );

  final familyMembersList = [
    childMember,
    parentMember,
    relativeMember,
    grandparentMember,
  ];

  // ===========================================================================
  // GROUP 1: Core 6 Permutations on InMemoryReminderRepository
  // ===========================================================================
  group('Empirical Challenge Group 1: Core 6 Permutations (InMemoryReminderRepository)', () {
    late InMemoryReminderRepository repo;

    setUp(() {
      repo = InMemoryReminderRepository(initialReminders: []);
    });

    test('Permutation 1: CHILD (lvl 1) ASSIGN to RELATIVE (lvl 2) -> throws CULTURE_HIERARCHY_VIOLATION', () async {
      final assignTask = ReminderModel(
        id: 'p1_child_assign_relative',
        familyId: 'fam_empirical',
        creatorId: 'uid_child',
        creatorName: 'Bé Na',
        assignedTo: 'uid_relative',
        assignedToName: 'Chú Hùng',
        title: 'Bắt Chú Hùng rửa bát',
        date: testDate,
        time: testTime,
        taskType: TaskType.assign,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'CHILD',
        targetHierarchyRole: 'RELATIVE',
        rewardStars: 2,
      );

      expect(
        () => repo.createReminder(
          reminder: assignTask,
          currentUserId: 'uid_child',
          now: now,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
      );
    });

    test('Permutation 2: CHILD (lvl 1) FAVOR to RELATIVE (lvl 2) -> creation succeeds', () async {
      final favorTask = ReminderModel(
        id: 'p2_child_favor_relative',
        familyId: 'fam_empirical',
        creatorId: 'uid_child',
        creatorName: 'Bé Na',
        assignedTo: 'uid_relative',
        assignedToName: 'Chú Hùng',
        title: 'Nhờ Chú Hùng đón con tan học',
        date: testDate,
        time: testTime,
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'CHILD',
        targetHierarchyRole: 'RELATIVE',
      );

      final created = await repo.createReminder(
        reminder: favorTask,
        currentUserId: 'uid_child',
        now: now,
      );

      expect(created.id, 'p2_child_favor_relative');
      expect(created.taskType, TaskType.favor);
      expect(created.creatorId, 'uid_child');
      expect(created.assignedTo, 'uid_relative');
    });

    test('Permutation 3: RELATIVE (lvl 2) FAVOR to CHILD (lvl 1) -> creation succeeds', () async {
      final favorTask = ReminderModel(
        id: 'p3_relative_favor_child',
        familyId: 'fam_empirical',
        creatorId: 'uid_relative',
        creatorName: 'Chú Hùng',
        assignedTo: 'uid_child',
        assignedToName: 'Bé Na',
        title: 'Nhờ cháu Na lấy hộ kính lão',
        date: testDate,
        time: testTime,
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'RELATIVE',
        targetHierarchyRole: 'CHILD',
      );

      final created = await repo.createReminder(
        reminder: favorTask,
        currentUserId: 'uid_relative',
        now: now,
      );

      expect(created.id, 'p3_relative_favor_child');
      expect(created.taskType, TaskType.favor);
      expect(created.creatorId, 'uid_relative');
      expect(created.assignedTo, 'uid_child');
    });

    test('Permutation 4: RELATIVE (lvl 2) CARE for GRANDPARENT (lvl 3) -> creation succeeds', () async {
      final careTask = ReminderModel(
        id: 'p4_relative_care_gp',
        familyId: 'fam_empirical',
        creatorId: 'uid_relative',
        creatorName: 'Chú Hùng',
        assignedTo: 'uid_gp',
        assignedToName: 'Ông Nội',
        title: 'Nhắc Ông đo huyết áp buổi sáng',
        date: testDate,
        time: testTime,
        taskType: TaskType.care,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'RELATIVE',
        targetHierarchyRole: 'GRANDPARENT',
      );

      final created = await repo.createReminder(
        reminder: careTask,
        currentUserId: 'uid_relative',
        now: now,
      );

      expect(created.id, 'p4_relative_care_gp');
      expect(created.taskType, TaskType.care);
      expect(created.creatorId, 'uid_relative');
      expect(created.assignedTo, 'uid_gp');
    });

    test('Permutation 5: CHILD (lvl 1) ASSIGN to GRANDPARENT (lvl 3) -> throws CULTURE_HIERARCHY_VIOLATION', () async {
      final assignTask = ReminderModel(
        id: 'p5_child_assign_gp',
        familyId: 'fam_empirical',
        creatorId: 'uid_child',
        creatorName: 'Bé Na',
        assignedTo: 'uid_gp',
        assignedToName: 'Ông Nội',
        title: 'Bắt Ông quét sân vườn',
        date: testDate,
        time: testTime,
        taskType: TaskType.assign,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'CHILD',
        targetHierarchyRole: 'GRANDPARENT',
        rewardStars: 3,
      );

      expect(
        () => repo.createReminder(
          reminder: assignTask,
          currentUserId: 'uid_child',
          now: now,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
      );
    });

    test('Permutation 6: PARENT (lvl 2) ASSIGN to CHILD (lvl 1) -> creation succeeds', () async {
      final assignTask = ReminderModel(
        id: 'p6_parent_assign_child',
        familyId: 'fam_empirical',
        creatorId: 'uid_parent',
        creatorName: 'Bố Tuấn',
        assignedTo: 'uid_child',
        assignedToName: 'Bé Na',
        title: 'Giao Na dọn bàn học và gấp quần áo',
        date: testDate,
        time: testTime,
        taskType: TaskType.assign,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'PARENT',
        targetHierarchyRole: 'CHILD',
        rewardStars: 2,
      );

      final created = await repo.createReminder(
        reminder: assignTask,
        currentUserId: 'uid_parent',
        now: now,
      );

      expect(created.id, 'p6_parent_assign_child');
      expect(created.taskType, TaskType.assign);
      expect(created.creatorId, 'uid_parent');
      expect(created.assignedTo, 'uid_child');
      expect(created.rewardStars, 2);
    });
  });

  // ===========================================================================
  // GROUP 2: Core 6 Permutations on FirebaseReminderRepository
  // ===========================================================================
  group('Empirical Challenge Group 2: Core 6 Permutations (FirebaseReminderRepository Fallback)', () {
    late FirebaseReminderRepository fbRepo;

    setUp(() {
      fbRepo = FirebaseReminderRepository(
        fallbackRepository: InMemoryReminderRepository(initialReminders: []),
      );
    });

    test('FB-Permutation 1: CHILD ASSIGN to RELATIVE -> throws CULTURE_HIERARCHY_VIOLATION', () async {
      final assignTask = ReminderModel(
        id: 'fb_p1_child_assign_relative',
        familyId: 'fam_empirical',
        creatorId: 'uid_child',
        creatorName: 'Bé Na',
        assignedTo: 'uid_relative',
        assignedToName: 'Chú Hùng',
        title: 'Bắt Chú Hùng rửa bát',
        date: testDate,
        time: testTime,
        taskType: TaskType.assign,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'CHILD',
        targetHierarchyRole: 'RELATIVE',
        rewardStars: 2,
      );

      expect(
        () => fbRepo.createReminder(
          reminder: assignTask,
          currentUserId: 'uid_child',
          now: now,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
      );
    });

    test('FB-Permutation 2: CHILD FAVOR to RELATIVE -> creation succeeds', () async {
      final favorTask = ReminderModel(
        id: 'fb_p2_child_favor_relative',
        familyId: 'fam_empirical',
        creatorId: 'uid_child',
        creatorName: 'Bé Na',
        assignedTo: 'uid_relative',
        assignedToName: 'Chú Hùng',
        title: 'Nhờ Chú Hùng đón con tan học',
        date: testDate,
        time: testTime,
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'CHILD',
        targetHierarchyRole: 'RELATIVE',
      );

      final created = await fbRepo.createReminder(
        reminder: favorTask,
        currentUserId: 'uid_child',
        now: now,
      );

      expect(created.taskType, TaskType.favor);
      expect(created.assignedTo, 'uid_relative');
    });

    test('FB-Permutation 3: RELATIVE FAVOR to CHILD -> creation succeeds', () async {
      final favorTask = ReminderModel(
        id: 'fb_p3_relative_favor_child',
        familyId: 'fam_empirical',
        creatorId: 'uid_relative',
        creatorName: 'Chú Hùng',
        assignedTo: 'uid_child',
        assignedToName: 'Bé Na',
        title: 'Nhờ cháu Na tưới cây',
        date: testDate,
        time: testTime,
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'RELATIVE',
        targetHierarchyRole: 'CHILD',
      );

      final created = await fbRepo.createReminder(
        reminder: favorTask,
        currentUserId: 'uid_relative',
        now: now,
      );

      expect(created.taskType, TaskType.favor);
      expect(created.assignedTo, 'uid_child');
    });

    test('FB-Permutation 4: RELATIVE CARE for GRANDPARENT -> creation succeeds', () async {
      final careTask = ReminderModel(
        id: 'fb_p4_relative_care_gp',
        familyId: 'fam_empirical',
        creatorId: 'uid_relative',
        creatorName: 'Chú Hùng',
        assignedTo: 'uid_gp',
        assignedToName: 'Ông Nội',
        title: 'Nhắc Ông uống thuốc khớp',
        date: testDate,
        time: testTime,
        taskType: TaskType.care,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'RELATIVE',
        targetHierarchyRole: 'GRANDPARENT',
      );

      final created = await fbRepo.createReminder(
        reminder: careTask,
        currentUserId: 'uid_relative',
        now: now,
      );

      expect(created.taskType, TaskType.care);
      expect(created.assignedTo, 'uid_gp');
    });

    test('FB-Permutation 5: CHILD ASSIGN to GRANDPARENT -> throws CULTURE_HIERARCHY_VIOLATION', () async {
      final assignTask = ReminderModel(
        id: 'fb_p5_child_assign_gp',
        familyId: 'fam_empirical',
        creatorId: 'uid_child',
        creatorName: 'Bé Na',
        assignedTo: 'uid_gp',
        assignedToName: 'Ông Nội',
        title: 'Bắt Ông lau nhà',
        date: testDate,
        time: testTime,
        taskType: TaskType.assign,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'CHILD',
        targetHierarchyRole: 'GRANDPARENT',
      );

      expect(
        () => fbRepo.createReminder(
          reminder: assignTask,
          currentUserId: 'uid_child',
          now: now,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
      );
    });

    test('FB-Permutation 6: PARENT ASSIGN to CHILD -> creation succeeds', () async {
      final assignTask = ReminderModel(
        id: 'fb_p6_parent_assign_child',
        familyId: 'fam_empirical',
        creatorId: 'uid_parent',
        creatorName: 'Bố Tuấn',
        assignedTo: 'uid_child',
        assignedToName: 'Bé Na',
        title: 'Giao Na học bài tiếng Anh',
        date: testDate,
        time: testTime,
        taskType: TaskType.assign,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: 'PARENT',
        targetHierarchyRole: 'CHILD',
        rewardStars: 3,
      );

      final created = await fbRepo.createReminder(
        reminder: assignTask,
        currentUserId: 'uid_parent',
        now: now,
      );

      expect(created.taskType, TaskType.assign);
      expect(created.assignedTo, 'uid_child');
    });
  });

  // ===========================================================================
  // GROUP 3: Dynamic FamilyMembers Lookup (Null Role Strings)
  // ===========================================================================
  group('Empirical Challenge Group 3: Dynamic FamilyMembers Resolution', () {
    late InMemoryReminderRepository repo;

    setUp(() {
      repo = InMemoryReminderRepository(initialReminders: []);
    });

    test('Dynamic Permutation 1: CHILD ASSIGN to RELATIVE (via familyMembers list) -> throws CULTURE_HIERARCHY_VIOLATION', () async {
      final assignTask = ReminderModel(
        id: 'dyn_p1_child_assign_relative',
        familyId: 'fam_empirical',
        creatorId: 'uid_child',
        creatorName: 'Bé Na',
        assignedTo: 'uid_relative',
        assignedToName: 'Chú Hùng',
        title: 'Việc giao cho Chú Hùng',
        date: testDate,
        time: testTime,
        taskType: TaskType.assign,
        taskStatus: TaskStatus.pending,
        // Role strings intentionally null to force dynamic lookup
        creatorHierarchyRole: null,
        targetHierarchyRole: null,
      );

      expect(
        () => repo.createReminder(
          reminder: assignTask,
          currentUserId: 'uid_child',
          familyMembers: familyMembersList,
          now: now,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
      );
    });

    test('Dynamic Permutation 5: CHILD ASSIGN to GRANDPARENT (via familyMembers list) -> throws CULTURE_HIERARCHY_VIOLATION', () async {
      final assignTask = ReminderModel(
        id: 'dyn_p5_child_assign_gp',
        familyId: 'fam_empirical',
        creatorId: 'uid_child',
        creatorName: 'Bé Na',
        assignedTo: 'uid_gp',
        assignedToName: 'Ông Nội',
        title: 'Việc giao cho Ông Nội',
        date: testDate,
        time: testTime,
        taskType: TaskType.assign,
        taskStatus: TaskStatus.pending,
        creatorHierarchyRole: null,
        targetHierarchyRole: null,
      );

      expect(
        () => repo.createReminder(
          reminder: assignTask,
          currentUserId: 'uid_child',
          familyMembers: familyMembersList,
          now: now,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
      );
    });

    test('Dynamic Permutations 2, 3, 4, 6 succeed via dynamic familyMembers lookup', () async {
      // 2. Child FAVOR to Relative
      final p2 = await repo.createReminder(
        reminder: ReminderModel(
          id: 'dyn_p2',
          familyId: 'fam_empirical',
          creatorId: 'uid_child',
          assignedTo: 'uid_relative',
          assignedToName: 'Chú Hùng',
          title: 'Nhờ chú mua kem',
          date: testDate,
          time: testTime,
          taskType: TaskType.favor,
        ),
        currentUserId: 'uid_child',
        familyMembers: familyMembersList,
        now: now,
      );
      expect(p2.taskType, TaskType.favor);

      // 3. Relative FAVOR to Child
      final p3 = await repo.createReminder(
        reminder: ReminderModel(
          id: 'dyn_p3',
          familyId: 'fam_empirical',
          creatorId: 'uid_relative',
          assignedTo: 'uid_child',
          assignedToName: 'Bé Na',
          title: 'Nhờ cháu tưới hoa',
          date: testDate,
          time: testTime,
          taskType: TaskType.favor,
        ),
        currentUserId: 'uid_relative',
        familyMembers: familyMembersList,
        now: now,
      );
      expect(p3.taskType, TaskType.favor);

      // 4. Relative CARE for Grandparent
      final p4 = await repo.createReminder(
        reminder: ReminderModel(
          id: 'dyn_p4',
          familyId: 'fam_empirical',
          creatorId: 'uid_relative',
          assignedTo: 'uid_gp',
          assignedToName: 'Ông Nội',
          title: 'Nhắc ông uống trà thảo mộc',
          date: testDate,
          time: testTime,
          taskType: TaskType.care,
        ),
        currentUserId: 'uid_relative',
        familyMembers: familyMembersList,
        now: now,
      );
      expect(p4.taskType, TaskType.care);

      // 6. Parent ASSIGN to Child
      final p6 = await repo.createReminder(
        reminder: ReminderModel(
          id: 'dyn_p6',
          familyId: 'fam_empirical',
          creatorId: 'uid_parent',
          assignedTo: 'uid_child',
          assignedToName: 'Bé Na',
          title: 'Giao Na quét nhà',
          date: testDate,
          time: testTime,
          taskType: TaskType.assign,
          rewardStars: 2,
        ),
        currentUserId: 'uid_parent',
        familyMembers: familyMembersList,
        now: now,
      );
      expect(p6.taskType, TaskType.assign);
    });
  });

  // ===========================================================================
  // GROUP 4: Vietnamese Role Alias Parsing Resilience for getMemberHierarchyLevel
  // ===========================================================================
  group('Empirical Challenge Group 4: Vietnamese Role Aliases for getMemberHierarchyLevel', () {
    test('Grandparent aliases map strictly to Level 3', () {
      final gpAliases = [
        'GRANDPARENT',
        'TRƯỞNG BỐI',
        'TRUONG BOI',
        'ÔNG NỘI',
        'ÔNG NGOẠI',
        'BÀ NỘI',
        'BÀ NGOẠI',
      ];
      for (final alias in gpAliases) {
        expect(getMemberHierarchyLevel(alias), 3, reason: 'Alias $alias must evaluate to level 3');
      }
    });

    test('Parent & Guardian aliases map strictly to Level 2', () {
      final parentAliases = [
        'PARENT',
        'OWNER',
        'ADMIN',
        'DAD',
        'MOM',
        'BỐ',
        'MẸ',
      ];
      for (final alias in parentAliases) {
        expect(getMemberHierarchyLevel(alias), 2, reason: 'Alias $alias must evaluate to level 2');
      }
    });

    test('Relative aliases map strictly to Level 2', () {
      final relativeAliases = [
        'RELATIVE',
        'UNCLE',
        'AUNT',
        'CÔ',
        'DÌ',
        'CHÚ',
        'BÁC',
        'CẬU',
        'THÍM',
        'MỢ',
        'DƯỢNG',
      ];
      for (final alias in relativeAliases) {
        expect(getMemberHierarchyLevel(alias), 2, reason: 'Alias $alias must evaluate to level 2');
      }
    });

    test('Child aliases map strictly to Level 1', () {
      final childAliases = [
        'CHILD',
        'KID',
        'CON',
        'TRẺ EM',
      ];
      for (final alias in childAliases) {
        expect(getMemberHierarchyLevel(alias), 1, reason: 'Alias $alias must evaluate to level 1');
      }
    });
  });

  // ===========================================================================
  // GROUP 5: Adversarial Boundary & Cultural Invariant Stress Tests
  // ===========================================================================
  group('Empirical Challenge Group 5: Adversarial Boundary & Cultural Invariants', () {
    late InMemoryReminderRepository repo;

    setUp(() {
      repo = InMemoryReminderRepository(initialReminders: []);
    });

    test('Exhaustive 5x5 ASSIGN Matrix (GP=3, Parent=2, Relative=2, Member=1, Child=1)', () async {
      final roles = ['Grandparent', 'Parent', 'Relative', 'Member', 'Child'];
      int successCount = 0;
      int violationCount = 0;

      for (final creator in roles) {
        final creatorLvl = getMemberHierarchyLevel(creator);
        for (final target in roles) {
          final targetLvl = getMemberHierarchyLevel(target);

          final task = ReminderModel(
            id: 'matrix_${creator}_to_$target',
            familyId: 'fam_empirical',
            creatorId: 'uid_$creator',
            creatorName: creator,
            assignedTo: 'uid_$target',
            assignedToName: target,
            title: 'Chore from $creator to $target',
            date: testDate,
            time: testTime,
            taskType: TaskType.assign,
            taskStatus: TaskStatus.pending,
            creatorHierarchyRole: creator,
            targetHierarchyRole: target,
            rewardStars: 1,
          );

          if (creatorLvl < targetLvl) {
            expect(
              () => repo.createReminder(
                reminder: task,
                currentUserId: 'uid_$creator',
                now: now,
              ),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  contains('CULTURE_HIERARCHY_VIOLATION'),
                ),
              ),
              reason: 'Upward assign from $creator (lvl $creatorLvl) to $target (lvl $targetLvl) must fail',
            );
            violationCount++;
          } else {
            final created = await repo.createReminder(
              reminder: task,
              currentUserId: 'uid_$creator',
              now: now,
            );
            expect(created.id, task.id);
            successCount++;
          }
        }
      }

      // Calculations for 5x5:
      // GP (3): 5 combinations (3>=3, 3>=2, 3>=2, 3>=1, 3>=1) -> 5 success
      // Parent (2): 4 combinations (2>=2, 2>=2, 2>=1, 2>=1) -> 4 success, 1 fail (GP)
      // Relative (2): 4 combinations (2>=2, 2>=2, 2>=1, 2>=1) -> 4 success, 1 fail (GP)
      // Member (1): 2 combinations (1>=1, 1>=1) -> 2 success, 3 fail (GP, Parent, Relative)
      // Child (1): 2 combinations (1>=1, 1>=1) -> 2 success, 3 fail (GP, Parent, Relative)
      // Total success = 5 + 4 + 4 + 2 + 2 = 17
      // Total violations = 1 + 1 + 3 + 3 = 8
      expect(successCount, 17, reason: 'Exactly 17 top-down / peer assignments must succeed');
      expect(violationCount, 8, reason: 'Exactly 8 upward assignments must fail with CULTURE_HIERARCHY_VIOLATION');
    });

    test('Adversarial Delegation: CHILD delegating FAVOR up to RELATIVE or GP throws CULTURE_HIERARCHY_VIOLATION', () async {
      // Seed a task assigned to Child
      final initialTask = ReminderModel(
        id: 'task_to_delegate',
        familyId: 'fam_empirical',
        creatorId: 'uid_parent',
        assignedTo: 'uid_child',
        assignedToName: 'Bé Na',
        title: 'Nhờ vả được giao',
        date: testDate,
        time: testTime,
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
      );

      await repo.createReminder(
        reminder: initialTask,
        currentUserId: 'uid_parent',
        now: now,
      );

      // Child tries to delegate up to Relative
      expect(
        () => repo.delegateFavorTask(
          taskId: 'task_to_delegate',
          delegatedToUserId: 'uid_relative',
          delegatedToUserName: 'Chú Hùng',
          currentUserId: 'uid_child',
          currentUserRole: 'CHILD',
          targetUserRole: 'RELATIVE',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
      );

      // Child tries to delegate up to Grandparent
      expect(
        () => repo.delegateFavorTask(
          taskId: 'task_to_delegate',
          delegatedToUserId: 'uid_gp',
          delegatedToUserName: 'Ông Nội',
          currentUserId: 'uid_child',
          currentUserRole: 'CHILD',
          targetUserRole: 'GRANDPARENT',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
      );

      // Relative delegates down to Child -> succeeds!
      final delegated = await repo.delegateFavorTask(
        taskId: 'task_to_delegate',
        delegatedToUserId: 'uid_child',
        delegatedToUserName: 'Bé Na',
        currentUserId: 'uid_relative',
        currentUserRole: 'RELATIVE',
        targetUserRole: 'CHILD',
      );
      expect(delegated.assignedTo, 'uid_child');
      expect(delegated.delegationCount, 1);
    });

    test('Shared/Open tasks (assignedTo == OPEN / ALL) created by CHILD are exempt from hierarchy violation', () async {
      final openTask = ReminderModel(
        id: 'open_task_by_child',
        familyId: 'fam_empirical',
        creatorId: 'uid_child',
        creatorName: 'Bé Na',
        assignedTo: 'OPEN',
        assignedToName: 'Cả nhà',
        title: 'Nhờ cả nhà tưới hoa',
        date: testDate,
        time: testTime,
        taskType: TaskType.assign,
        creatorHierarchyRole: 'CHILD',
      );

      final created = await repo.createReminder(
        reminder: openTask,
        currentUserId: 'uid_child',
        now: now,
      );
      expect(created.id, 'open_task_by_child');
      expect(created.isOpenTask, isTrue);
    });

    test('Model Governance Invariant: RELATIVE role has hierarchyLevel=2, isGuardian=false, canAssignChores=false across all 3 subsystems', () {
      // 1. Long subsystem
      const longRole = HierarchyRole.relative;
      expect(longRole.hierarchyLevel, 2);
      expect(longRole.isGuardian, isFalse);
      expect(longRole.canAssignChores, isFalse);

      final longMember = long_model.FamilyMemberModel(
        familyId: 'fam_l',
        user: UserModel(id: 'u_l', name: 'Chú Hùng', email: 'hung@test.com'),
        role: long_model.Role.member,
        hierarchyRole: HierarchyRole.relative,
      );
      expect(longMember.hierarchyLevel, 2);
      expect(longMember.isGuardian, isFalse);
      expect(longMember.isRelative, isTrue);

      // 2. Khoa subsystem
      const khoaMember = khoa_member.FamilyMember(
        familyId: 'fam_k',
        userId: 'u_k',
        role: khoa_member.FamilyMember.roleRelative,
      );
      expect(khoaMember.hierarchyLevel, 2);
      expect(khoaMember.isGuardian, isFalse);
      expect(khoaMember.isRelative, isTrue);

      // 3. Vinh subsystem
      const vinhMember = vinh_member.FamilyMember(
        id: 'u_v',
        name: 'Chú Hùng',
        role: vinh_member.FamilyMember.roleRelative,
        familyId: 'fam_v',
      );
      expect(vinhMember.hierarchyLevel, 2);
      expect(vinhMember.isGuardian, isFalse);
      expect(vinhMember.canAssignChores, isFalse);
      expect(vinhMember.isRelative, isTrue);
    });
  });
}

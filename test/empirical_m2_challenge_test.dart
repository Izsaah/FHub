import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Vinh/models/reminder_model.dart';
import 'package:fhub/Vinh/services/reminder_repository.dart';
import 'package:fhub/Vinh/widgets/reminder_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 2 Empirical Stress Test 1: TaskType & TaskStatus State Machine', () {
    test('TaskType & TaskStatus enum mapping, dbValue, displayName & fromValue resilience', () {
      // Test all TaskType dbValues and displayNames
      expect(TaskType.assign.dbValue, 'ASSIGN');
      expect(TaskType.favor.dbValue, 'FAVOR');
      expect(TaskType.care.dbValue, 'CARE');
      expect(TaskType.assign.displayName, contains('Giao việc'));
      expect(TaskType.favor.displayName, contains('Nhờ vả'));
      expect(TaskType.care.displayName, contains('Chăm sóc'));

      // Test TaskType.fromValue resilience
      expect(TaskType.fromValue('ASSIGN'), TaskType.assign);
      expect(TaskType.fromValue('assign'), TaskType.assign);
      expect(TaskType.fromValue('FAVOR'), TaskType.favor);
      expect(TaskType.fromValue('favor'), TaskType.favor);
      expect(TaskType.fromValue('CARE'), TaskType.care);
      expect(TaskType.fromValue('care'), TaskType.care);
      expect(TaskType.fromValue(null), TaskType.assign); // default fallback
      expect(TaskType.fromValue('UNKNOWN_XYZ'), TaskType.assign);

      // Test TaskStatus dbValues and displayNames
      for (final status in TaskStatus.values) {
        expect(status.dbValue, isNotEmpty);
        expect(status.displayName, isNotEmpty);
      }
      expect(TaskStatus.pending.dbValue, 'PENDING');
      expect(TaskStatus.submitted.dbValue, 'SUBMITTED');
      expect(TaskStatus.rejected.dbValue, 'REJECTED');
      expect(TaskStatus.completed.dbValue, 'COMPLETED');
      expect(TaskStatus.accepted.dbValue, 'ACCEPTED');
      expect(TaskStatus.declined.dbValue, 'DECLINED');

      // Test TaskStatus.fromValue resilience with legacy strings
      expect(TaskStatus.fromValue('PENDING'), TaskStatus.pending);
      expect(TaskStatus.fromValue('SUBMITTED'), TaskStatus.submitted);
      expect(TaskStatus.fromValue('REJECTED'), TaskStatus.rejected);
      expect(TaskStatus.fromValue('COMPLETED'), TaskStatus.completed);
      expect(TaskStatus.fromValue('APPROVED'), TaskStatus.completed); // mapped to completed
      expect(TaskStatus.fromValue('ACCEPTED'), TaskStatus.accepted);
      expect(TaskStatus.fromValue('DECLINED'), TaskStatus.declined);
      expect(TaskStatus.fromValue('IN_PROGRESS'), TaskStatus.inProgress);
      expect(TaskStatus.fromValue(null), TaskStatus.pending);
      expect(TaskStatus.fromValue(''), TaskStatus.pending);
    });

    test('Rapid 50-cycle State Machine Transitions: SUBMITTED -> REJECTED -> PENDING -> SUBMITTED -> APPROVED', () async {
      final repo = InMemoryReminderRepository(initialReminders: []);
      final now = DateTime(2026, 11, 6, 10, 0);

      const reminder = ReminderModel(
        id: 'stress_task_cycle_1',
        familyId: 'family_stress',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Na',
        title: 'Lau dọn góc học tập mỗi ngày',
        date: '06/11/2026',
        time: '18:00',
        taskType: TaskType.assign,
        taskStatus: TaskStatus.pending,
        requiresProofImage: true,
        rewardStars: 3,
      );

      await repo.createReminder(
        reminder: reminder,
        currentUserId: 'parent_1',
        now: now,
      );

      // Stress loop: 50 cycles of Submit -> Reject -> verify proof wiped
      for (int cycle = 1; cycle <= 50; cycle++) {
        final proofUrl = 'https://storage.googleapis.com/fhub_proofs/cycle_${cycle}_na.jpg';

        // 1. Submit with proof
        await repo.submitTaskWithProof(
          taskId: 'stress_task_cycle_1',
          proofImageUrl: proofUrl,
        );

        var list = await repo.getReminders(familyId: 'family_stress');
        var task = list.firstWhere((r) => r.id == 'stress_task_cycle_1');

        expect(task.taskStatus, TaskStatus.submitted, reason: 'Cycle $cycle submit status');
        expect(task.proofImageUrl, proofUrl, reason: 'Cycle $cycle proof URL preserved');
        expect(task.rejectionReason, isNull, reason: 'Cycle $cycle previous rejection cleared');

        // 2. Reject submission with specific reason
        final rejectionReason = 'Ảnh chụp góc $cycle bị mờ, vui lòng bật đèn chụp lại!';
        await repo.rejectTaskSubmission(
          taskId: 'stress_task_cycle_1',
          reason: rejectionReason,
        );

        list = await repo.getReminders(familyId: 'family_stress');
        task = list.firstWhere((r) => r.id == 'stress_task_cycle_1');

        // Invariant: proofImageUrl MUST be strictly null upon rejection
        expect(task.taskStatus, TaskStatus.pending, reason: 'Cycle $cycle rejected status reset to pending');
        expect(task.proofImageUrl, isNull, reason: 'Cycle $cycle proofImageUrl MUST be wiped to null');
        expect(task.hasProofImage, isFalse, reason: 'Cycle $cycle hasProofImage MUST be false');
        expect(task.rejectionReason, rejectionReason, reason: 'Cycle $cycle rejectionReason stored');
        expect(task.isCompleted, isFalse, reason: 'Cycle $cycle isCompleted must be false');
      }

      // Final 51st submission -> Approval
      const finalProof = 'https://storage.googleapis.com/fhub_proofs/cycle_final_perfect.jpg';
      await repo.submitTaskWithProof(
        taskId: 'stress_task_cycle_1',
        proofImageUrl: finalProof,
      );

      await repo.approveTaskSubmission(
        taskId: 'stress_task_cycle_1',
        reviewerId: 'parent_1',
        reviewerName: 'Bố Tuấn',
      );

      final finalList = await repo.getReminders(familyId: 'family_stress');
      final finalTask = finalList.firstWhere((r) => r.id == 'stress_task_cycle_1');

      expect(finalTask.taskStatus, TaskStatus.completed);
      expect(finalTask.isCompleted, isTrue);
      expect(finalTask.proofImageUrl, finalProof);
      expect(finalTask.completedAt, isNotNull);
    });

    test('Submission and rejection on non-existent or deleted tasks throws ReminderNotFoundException', () async {
      final repo = InMemoryReminderRepository(initialReminders: []);

      expect(
        () => repo.submitTaskWithProof(taskId: 'non_existent_task', proofImageUrl: 'http://img.jpg'),
        throwsA(isA<ReminderNotFoundException>()),
      );

      expect(
        () => repo.rejectTaskSubmission(taskId: 'non_existent_task', reason: 'reason'),
        throwsA(isA<ReminderNotFoundException>()),
      );

      expect(
        () => repo.approveTaskSubmission(taskId: 'non_existent_task', reviewerId: 'u1', reviewerName: 'User 1'),
        throwsA(isA<ReminderNotFoundException>()),
      );
    });
  });

  group('Milestone 2 Empirical Stress Test 2: Cultural Hierarchy Permutations (All 16 Combinations)', () {
    late InMemoryReminderRepository repo;
    final now = DateTime(2026, 11, 6, 10, 0);

    const roles = ['Grandparent', 'Parent', 'Member', 'Child'];

    // Expected hierarchy levels: Grandparent=3, Parent=2, Member=1, Child=1
    final expectedLevels = {
      'Grandparent': 3,
      'Parent': 2,
      'Member': 1,
      'Child': 1,
    };

    setUp(() {
      repo = InMemoryReminderRepository(initialReminders: []);
    });

    test('Verify getMemberHierarchyLevel for standard and Vietnamese synonyms', () {
      expect(getMemberHierarchyLevel('Grandparent'), 3);
      expect(getMemberHierarchyLevel('Ông nội'), 3);
      expect(getMemberHierarchyLevel('Bà ngoại'), 3);
      expect(getMemberHierarchyLevel('Trưởng bối'), 3);

      expect(getMemberHierarchyLevel('Parent'), 2);
      expect(getMemberHierarchyLevel('Bố'), 2);
      expect(getMemberHierarchyLevel('Mẹ'), 2);
      expect(getMemberHierarchyLevel('Owner'), 2);
      expect(getMemberHierarchyLevel('Admin'), 2);

      expect(getMemberHierarchyLevel('Relative'), 2);
      expect(getMemberHierarchyLevel('Cô / Dì / Chú / Bác'), 2);
      expect(getMemberHierarchyLevel('Chú Ba'), 2);
      expect(getMemberHierarchyLevel('Dì Út'), 2);

      expect(getMemberHierarchyLevel('Member'), 1);
      expect(getMemberHierarchyLevel('Thành viên'), 1);
      expect(getMemberHierarchyLevel('Guest'), 1);

      expect(getMemberHierarchyLevel('Child'), 1);
      expect(getMemberHierarchyLevel('Con cái'), 1);
      expect(getMemberHierarchyLevel('Bé Na (Kid)'), 1);
      expect(getMemberHierarchyLevel('Trẻ nhỏ'), 1);
    });

    test('Exhaustive 16 Permutations for ASSIGN: Creator Level >= Target Level succeeds, Creator < Target fails', () async {
      int successCount = 0;
      int violationCount = 0;

      for (final creatorRole in roles) {
        for (final targetRole in roles) {
          final creatorLevel = expectedLevels[creatorRole]!;
          final targetLevel = expectedLevels[targetRole]!;

          final reminder = ReminderModel(
            id: 'assign_${creatorRole}_to_$targetRole',
            familyId: 'family_hierarchy',
            creatorId: 'uid_$creatorRole',
            creatorName: creatorRole,
            assignedTo: 'uid_$targetRole',
            assignedToName: targetRole,
            title: 'Việc $creatorRole giao cho $targetRole',
            date: '06/11/2026',
            time: '19:00',
            taskType: TaskType.assign,
            taskStatus: TaskStatus.pending,
            creatorHierarchyRole: creatorRole,
            targetHierarchyRole: targetRole,
            rewardStars: 2,
          );

          if (creatorLevel >= targetLevel) {
            // Must succeed
            final created = await repo.createReminder(
              reminder: reminder,
              currentUserId: 'uid_$creatorRole',
              now: now,
            );
            expect(created.id, reminder.id);
            expect(created.taskType, TaskType.assign);
            successCount++;
          } else {
            // Must fail with StateError containing CULTURE_HIERARCHY_VIOLATION
            expect(
              () => repo.createReminder(
                reminder: reminder,
                currentUserId: 'uid_$creatorRole',
                now: now,
              ),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  contains('CULTURE_HIERARCHY_VIOLATION'),
                ),
              ),
              reason: 'Assigning upwards from $creatorRole (lvl $creatorLevel) to $targetRole (lvl $targetLevel) MUST fail',
            );
            violationCount++;
          }
        }
      }

      // In a 4x4 matrix:
      // Creator >= Target:
      // Grandparent (3): 4 combinations (3>=3, 3>=2, 3>=1, 3>=1)
      // Parent (2): 3 combinations (2>=2, 2>=1, 2>=1)
      // Member (1): 2 combinations (1>=1, 1>=1)
      // Child (1): 2 combinations (1>=1, 1>=1)
      // Total Success = 4 + 3 + 2 + 2 = 11
      // Total Violations = 16 - 11 = 5
      expect(successCount, 11, reason: 'Exactly 11 top-down or equal level assignments must succeed');
      expect(violationCount, 5, reason: 'Exactly 5 upward assignments must fail with CULTURE_HIERARCHY_VIOLATION');
    });

    test('Exhaustive 16 Permutations for FAVOR: ALL 16 combinations MUST SUCCEED (Voluntary favor)', () async {
      int successCount = 0;

      for (final creatorRole in roles) {
        for (final targetRole in roles) {
          final reminder = ReminderModel(
            id: 'favor_${creatorRole}_to_$targetRole',
            familyId: 'family_hierarchy',
            creatorId: 'uid_$creatorRole',
            creatorName: creatorRole,
            assignedTo: 'uid_$targetRole',
            assignedToName: targetRole,
            title: '$creatorRole nhờ $targetRole giúp đỡ một việc',
            date: '06/11/2026',
            time: '19:30',
            taskType: TaskType.favor,
            taskStatus: TaskStatus.pending,
            creatorHierarchyRole: creatorRole,
            targetHierarchyRole: targetRole,
            rewardStars: 0,
          );

          // All 16 combinations (including Child asking Grandparent or Parent) MUST succeed
          final created = await repo.createReminder(
            reminder: reminder,
            currentUserId: 'uid_$creatorRole',
            now: now,
          );
          expect(created.id, reminder.id);
          expect(created.isFavor, isTrue);
          expect(created.canBeDelegated, isTrue);
          successCount++;
        }
      }

      expect(successCount, 16, reason: 'All 16 FAVOR permutations must succeed without hierarchy restriction');
    });

    test('Exhaustive 16 Permutations for CARE: ALL 16 combinations MUST SUCCEED (Elder care)', () async {
      int successCount = 0;

      for (final creatorRole in roles) {
        for (final targetRole in roles) {
          final reminder = ReminderModel(
            id: 'care_${creatorRole}_for_$targetRole',
            familyId: 'family_hierarchy',
            creatorId: 'uid_$creatorRole',
            creatorName: creatorRole,
            assignedTo: 'uid_$targetRole',
            assignedToName: targetRole,
            title: 'Lịch nhắc uống thuốc huyết áp & đo nhịp tim',
            date: '06/11/2026',
            time: '20:00',
            taskType: TaskType.care,
            taskStatus: TaskStatus.pending,
            creatorHierarchyRole: creatorRole,
            targetHierarchyRole: targetRole,
            rewardStars: 0,
          );

          // All 16 combinations (e.g. Child creating CARE for Grandparent) MUST succeed
          final created = await repo.createReminder(
            reminder: reminder,
            currentUserId: 'uid_$creatorRole',
            now: now,
          );
          expect(created.id, reminder.id);
          expect(created.isCare, isTrue);
          expect(created.isExemptFromQuietHours, isTrue);
          successCount++;
        }
      }

      expect(successCount, 16, reason: 'All 16 CARE permutations must succeed for elder care');
    });

    test('Open task (assignedTo == OPEN / ALL) is exempt from hierarchy constraints', () async {
      final openTask = ReminderModel(
        id: 'open_task_by_child',
        familyId: 'family_hierarchy',
        creatorId: 'uid_Child',
        creatorName: 'Child',
        assignedTo: 'OPEN',
        assignedToName: 'Cả nhà',
        title: 'Cần người tưới cây sân thượng',
        date: '06/11/2026',
        time: '17:00',
        taskType: TaskType.assign,
        creatorHierarchyRole: 'Child',
        targetHierarchyRole: 'Grandparent',
      );

      final created = await repo.createReminder(
        reminder: openTask,
        currentUserId: 'uid_Child',
        now: now,
      );
      expect(created.isOpenTask, isTrue);
    });
  });

  group('Milestone 2 Empirical Stress Test 3: Favor Delegation Boundaries & Hierarchy Restrictions', () {
    late InMemoryReminderRepository repo;
    final now = DateTime(2026, 11, 6, 10, 0);

    setUp(() {
      repo = InMemoryReminderRepository(initialReminders: []);
    });

    test('First delegation succeeds (count == 1); Second delegation attempt fails with DELEGATION_LIMIT_EXCEEDED', () async {
      // 1. Grandparent asks Parent for a favor
      const favorTask = ReminderModel(
        id: 'delegation_test_task_1',
        familyId: 'fam_delegation',
        creatorId: 'grandparent_1',
        creatorName: 'Ông Nội',
        assignedTo: 'parent_1',
        assignedToName: 'Bố Tuấn',
        title: 'Nhờ mua giúp bánh đậu xanh Hải Dương',
        date: '06/11/2026',
        time: '19:00',
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
        delegationCount: 0,
      );

      await repo.createReminder(
        reminder: favorTask,
        currentUserId: 'grandparent_1',
        now: now,
      );

      // Verify initial state
      var task = (await repo.getReminders(familyId: 'fam_delegation')).first;
      expect(task.delegationCount, 0);
      expect(task.canBeDelegated, isTrue);

      // 2. Parent delegates favor down to Child (First delegation: count 0 -> 1)
      final delegatedTask = await repo.delegateFavorTask(
        taskId: 'delegation_test_task_1',
        delegatedToUserId: 'child_1',
        delegatedToUserName: 'Bé Na',
        currentUserId: 'parent_1',
        currentUserRole: 'Parent',
        targetUserRole: 'Child',
      );

      expect(delegatedTask.delegationCount, 1);
      expect(delegatedTask.delegatedFromUserId, 'parent_1');
      expect(delegatedTask.assignedTo, 'child_1');
      expect(delegatedTask.assignedToName, 'Bé Na');
      expect(delegatedTask.canBeDelegated, isFalse);

      // 3. Second delegation attempt (by Child to another child or parent): MUST fail with DELEGATION_LIMIT_EXCEEDED
      expect(
        () => repo.delegateFavorTask(
          taskId: 'delegation_test_task_1',
          delegatedToUserId: 'child_2',
          delegatedToUserName: 'Bé Bo',
          currentUserId: 'child_1',
          currentUserRole: 'Child',
          targetUserRole: 'Child',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('DELEGATION_LIMIT_EXCEEDED'),
          ),
        ),
        reason: 'Second delegation attempt on task with delegationCount == 1 must be strictly rejected',
      );
    });

    test('Re-delegation upwards by Child fails with CULTURE_HIERARCHY_VIOLATION', () async {
      // 1. Task assigned to Child with delegationCount == 0
      const childFavor = ReminderModel(
        id: 'child_favor_task',
        familyId: 'fam_delegation',
        creatorId: 'parent_1',
        creatorName: 'Bố Tuấn',
        assignedTo: 'child_1',
        assignedToName: 'Bé Na',
        title: 'Nhờ nhặt rau muống',
        date: '06/11/2026',
        time: '18:30',
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
        delegationCount: 0,
      );

      await repo.createReminder(
        reminder: childFavor,
        currentUserId: 'parent_1',
        now: now,
      );

      // 2. Child tries to delegate up to Parent
      expect(
        () => repo.delegateFavorTask(
          taskId: 'child_favor_task',
          delegatedToUserId: 'parent_1',
          delegatedToUserName: 'Bố Tuấn',
          currentUserId: 'child_1',
          currentUserRole: 'Child',
          targetUserRole: 'Parent',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
        reason: 'Child cannot delegate task upwards to Parent',
      );

      // 3. Child tries to delegate up to Grandparent
      expect(
        () => repo.delegateFavorTask(
          taskId: 'child_favor_task',
          delegatedToUserId: 'grandparent_1',
          delegatedToUserName: 'Ông Nội',
          currentUserId: 'child_1',
          currentUserRole: 'Child',
          targetUserRole: 'Grandparent',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
        reason: 'Child cannot delegate task upwards to Grandparent',
      );

      // 4. Parent tries to delegate up to Grandparent
      expect(
        () => repo.delegateFavorTask(
          taskId: 'child_favor_task',
          delegatedToUserId: 'grandparent_1',
          delegatedToUserName: 'Ông Nội',
          currentUserId: 'parent_1',
          currentUserRole: 'Parent',
          targetUserRole: 'Grandparent',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CULTURE_HIERARCHY_VIOLATION'),
          ),
        ),
        reason: 'Parent cannot delegate task upwards to Grandparent',
      );
    });

    test('Accept and Decline lifecycle for Favor tasks', () async {
      const favor = ReminderModel(
        id: 'favor_lifecycle_task',
        familyId: 'fam_delegation',
        creatorId: 'child_1',
        creatorName: 'Bé Na',
        assignedTo: 'parent_1',
        assignedToName: 'Bố Tuấn',
        title: 'Nhờ bố sửa giúp chiếc xe đạp',
        date: '06/11/2026',
        time: '17:00',
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
      );

      await repo.createReminder(
        reminder: favor,
        currentUserId: 'child_1',
        now: now,
      );

      // 1. Accept favor
      await repo.acceptFavorTask('favor_lifecycle_task');
      var task = (await repo.getReminders(familyId: 'fam_delegation')).first;
      expect(task.taskStatus, TaskStatus.accepted);
      expect(task.isAccepted, isTrue);
      expect(task.statusDisplayName, 'Đã nhận lời');

      // 2. Decline favor
      await repo.declineFavorTask('favor_lifecycle_task');
      task = (await repo.getReminders(familyId: 'fam_delegation')).first;
      expect(task.taskStatus, TaskStatus.declined);
      expect(task.isDeclined, isTrue);
      expect(task.statusDisplayName, 'Đã từ chối');
    });
  });

  group('Milestone 2 Empirical Stress Test 4: Serialization, Audit & Boundary Invariants', () {
    test('ReminderModel full round-trip serialization with snake_case and camelCase compatibility', () {
      final original = ReminderModel(
        id: 'rem_full_serial_1',
        familyId: 'fam_serial',
        familyName: 'Gia đình mẫu',
        creatorId: 'user_grandpa',
        creatorName: 'Ông Ba',
        assignedTo: 'user_kid',
        assignedToName: 'Bé Bo',
        title: 'Uống thuốc đúng giờ và chụp ảnh nghiệm thu',
        date: '06/11/2026',
        time: '21:00',
        status: 'SUBMITTED',
        taskType: TaskType.care,
        taskStatus: TaskStatus.submitted,
        proofImageUrl: 'https://img.com/p1.png',
        rejectionReason: 'Cần bổ sung',
        delegationCount: 1,
        delegatedFromUserId: 'user_parent',
        originalTaskId: 'rem_orig_1',
        creatorHierarchyRole: 'Grandparent',
        targetHierarchyRole: 'Child',
        rewardStars: 5,
        requiresProofImage: true,
      );

      // 1. toFirestore -> fromFirestore
      final firestoreMap = original.toFirestore();
      expect(firestoreMap['taskType'], 'CARE');
      expect(firestoreMap['taskStatus'], 'SUBMITTED');
      expect(firestoreMap['delegationCount'], 1);
      expect(firestoreMap['delegatedFromUserId'], 'user_parent');

      final fromFirestoreObj = ReminderModel.fromMap('rem_full_serial_1', firestoreMap);
      expect(fromFirestoreObj.taskType, TaskType.care);
      expect(fromFirestoreObj.taskStatus, TaskStatus.submitted);
      expect(fromFirestoreObj.delegationCount, 1);
      expect(fromFirestoreObj.proofImageUrl, 'https://img.com/p1.png');
      expect(fromFirestoreObj.isExemptFromQuietHours, isTrue);

      // 2. toJson (snake_case & camelCase) -> fromJson
      final jsonMap = original.toJson();
      expect(jsonMap['task_type'], 'CARE');
      expect(jsonMap['task_status'], 'SUBMITTED');
      expect(jsonMap['delegation_count'], 1);
      expect(jsonMap['delegated_from_user_id'], 'user_parent');
      expect(jsonMap['proof_image_url'], 'https://img.com/p1.png');

      final fromJsonObj = ReminderModel.fromJson(jsonMap);
      expect(fromJsonObj.taskType, TaskType.care);
      expect(fromJsonObj.taskStatus, TaskStatus.submitted);
      expect(fromJsonObj.delegationCount, 1);
      expect(fromJsonObj.delegatedFromUserId, 'user_parent');
      expect(fromJsonObj.proofImageUrl, 'https://img.com/p1.png');
    });

    test('copyWith clearProofImage and clearRejectionReason atomic resets', () {
      const task = ReminderModel(
        id: 't1',
        familyId: 'f1',
        creatorId: 'c1',
        assignedTo: 'a1',
        assignedToName: 'Name',
        title: 'Title',
        date: '06/11/2026',
        time: '12:00',
        proofImageUrl: 'https://test.com/photo.jpg',
        rejectionReason: 'Previous error message',
      );

      expect(task.proofImageUrl, isNotNull);
      expect(task.rejectionReason, isNotNull);

      // Wiping proof image
      final wipedProof = task.copyWith(clearProofImage: true);
      expect(wipedProof.proofImageUrl, isNull);
      expect(wipedProof.rejectionReason, 'Previous error message');

      // Wiping rejection reason
      final wipedReason = task.copyWith(clearRejectionReason: true);
      expect(wipedReason.proofImageUrl, 'https://test.com/photo.jpg');
      expect(wipedReason.rejectionReason, isNull);

      // Both wiped
      final wipedBoth = task.copyWith(clearProofImage: true, clearRejectionReason: true);
      expect(wipedBoth.proofImageUrl, isNull);
      expect(wipedBoth.rejectionReason, isNull);
    });
  });

  group('Milestone 2 Empirical Stress Test 5: Firebase & Supabase Repository Fallback Engine', () {
    test('FirebaseReminderRepository fallback handles rejection wipe and delegation limit', () async {
      final fallback = InMemoryReminderRepository(initialReminders: []);
      final fbRepo = FirebaseReminderRepository(fallbackRepository: fallback);
      final now = DateTime(2026, 11, 6, 10, 0);

      const reminder = ReminderModel(
        id: 'fb_task_1',
        familyId: 'fam_fb',
        creatorId: 'user_mom',
        assignedTo: 'user_kid',
        assignedToName: 'Bé Na',
        title: 'Chụp ảnh dọn phòng ngủ',
        date: '06/11/2026',
        time: '19:00',
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
      );

      await fallback.createReminder(
        reminder: reminder,
        currentUserId: 'user_mom',
        now: now,
      );

      // Submit via fbRepo
      await fbRepo.submitTaskWithProof(
        taskId: 'fb_task_1',
        proofImageUrl: 'https://fb.com/proof.jpg',
      );

      var list = await fbRepo.getReminders(familyId: 'fam_fb');
      expect(list.first.taskStatus, TaskStatus.submitted);
      expect(list.first.proofImageUrl, 'https://fb.com/proof.jpg');

      // Reject via fbRepo
      await fbRepo.rejectTaskSubmission(
        taskId: 'fb_task_1',
        reason: 'Chưa gấp chăn màn cẩn thận',
      );

      list = await fbRepo.getReminders(familyId: 'fam_fb');
      expect(list.first.taskStatus, TaskStatus.pending);
      expect(list.first.proofImageUrl, isNull);
      expect(list.first.rejectionReason, 'Chưa gấp chăn màn cẩn thận');

      // Delegate via fbRepo (First: succeeds)
      final delegated = await fbRepo.delegateFavorTask(
        taskId: 'fb_task_1',
        delegatedToUserId: 'user_kid_2',
        delegatedToUserName: 'Bé Bo',
        currentUserId: 'user_mom',
        currentUserRole: 'Parent',
        targetUserRole: 'Child',
      );
      expect(delegated.delegationCount, 1);

      // Delegate via fbRepo (Second: fails with DELEGATION_LIMIT_EXCEEDED)
      expect(
        () => fbRepo.delegateFavorTask(
          taskId: 'fb_task_1',
          delegatedToUserId: 'user_kid_3',
          delegatedToUserName: 'Bé Bi',
          currentUserId: 'user_kid_2',
          currentUserRole: 'Child',
          targetUserRole: 'Child',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('DELEGATION_LIMIT_EXCEEDED'),
          ),
        ),
      );
    });
  });

  group('Milestone 2 Empirical Stress Test 6: Elderly Care UX & ReminderCard Visual Badges', () {
    testWidgets('ReminderCard renders CARE badge, large typography, and Vietnamese TTS button', (tester) async {
      const careReminder = ReminderModel(
        id: 'care_card_1',
        familyId: 'fam_ui',
        creatorId: 'child_1',
        assignedTo: 'grandpa_1',
        assignedToName: 'Ông Nội',
        title: 'Uống thuốc huyết áp buổi sáng',
        date: '06/11/2026',
        time: '08:00',
        taskType: TaskType.care,
        taskStatus: TaskStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderCard(
              reminder: careReminder,
              currentUserId: 'grandpa_1',
              onTap: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check for Care Badge
      expect(find.text('👵 Chăm sóc Ông Bà'), findsOneWidget);
      expect(find.text('Uống thuốc huyết áp buổi sáng'), findsOneWidget);

      // Check for TTS speaker button
      final ttsButton = find.byIcon(Icons.volume_up_rounded);
      expect(ttsButton, findsOneWidget);

      // Tap TTS speaker button (should execute gracefully without crashing)
      await tester.tap(ttsButton);
      await tester.pumpAndSettle();
    });

    testWidgets('ReminderCard renders FAVOR badge and ASSIGN star badge', (tester) async {
      const favorReminder = ReminderModel(
        id: 'favor_card_1',
        familyId: 'fam_ui',
        creatorId: 'child_1',
        assignedTo: 'mom_1',
        assignedToName: 'Mẹ Lan',
        title: 'Nhờ mẹ mua vở viết mới',
        date: '06/11/2026',
        time: '17:00',
        taskType: TaskType.favor,
        taskStatus: TaskStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderCard(
              reminder: favorReminder,
              currentUserId: 'mom_1',
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('🤝 Việc nhờ vả'), findsOneWidget);

      const assignReminder = ReminderModel(
        id: 'assign_card_1',
        familyId: 'fam_ui',
        creatorId: 'mom_1',
        assignedTo: 'child_1',
        assignedToName: 'Bé Na',
        title: 'Quét nhà phòng khách',
        date: '06/11/2026',
        time: '18:00',
        taskType: TaskType.assign,
        rewardStars: 3,
        taskStatus: TaskStatus.rejected,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderCard(
              reminder: assignReminder,
              currentUserId: 'child_1',
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('⭐ Giao việc (+3 sao)'), findsOneWidget);
      expect(find.text('❌ Cần làm lại'), findsOneWidget);
    });
  });
}

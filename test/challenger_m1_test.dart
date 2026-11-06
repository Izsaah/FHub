import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Long/models/user_model.dart';
import 'package:fhub/Khoa/models/user_profile.dart';
import 'package:fhub/Long/services/join_request_service.dart';

void main() {
  group('Empirical Challenge 1: JoinRequestService Stress & Boundary Tests', () {
    setUp(() {
      JoinRequestService.resetMockData();
    });

    test('1.1 Boundary: Duplicate join requests from same user to same family (Sequential & Concurrent)', () async {
      final service = JoinRequestService();

      // Sequential duplicate calls with updated role
      await service.sendJoinRequest(familyId: 'fam_dup_1', suggestedRole: 'CHILD');
      await service.sendJoinRequest(familyId: 'fam_dup_1', suggestedRole: 'PARENT');

      final pendingSeq = await service.watchPendingRequests('fam_dup_1').first;
      // Deduplication verification: Exactly 1 record should exist, updated with the latest suggestedRole
      expect(pendingSeq.length, 1, reason: 'Duplicate requests for same family and user must collapse to 1');
      expect(pendingSeq.first.suggestedRole, 'PARENT', reason: 'Subsequent send must update existing pending request');
      expect(pendingSeq.first.id, 'fam_dup_1_mock_user', reason: r'DocId must strictly follow ${familyId}_${userId}');

      // Concurrent stress test: 20 simultaneous sendJoinRequest calls
      final futures = List.generate(20, (index) {
        return service.sendJoinRequest(
          familyId: 'fam_stress_concurrent',
          suggestedRole: index.isEven ? 'CHILD' : 'PARENT',
        );
      });
      await Future.wait(futures);

      final pendingConcurrent = await service.watchPendingRequests('fam_stress_concurrent').first;
      expect(pendingConcurrent.length, 1, reason: '20 concurrent sends must not create duplicate requests');
    });

    test('1.2 Boundary: Approving an already approved or rejected request (State Machine Invariants)', () async {
      final service = JoinRequestService();

      await service.sendJoinRequest(familyId: 'fam_approval_test', suggestedRole: 'CHILD');
      final initialPending = await service.watchPendingRequests('fam_approval_test').first;
      expect(initialPending.length, 1);
      final reqId = initialPending.first.id;

      // First approval
      await service.approveJoinRequest(
        requestId: reqId,
        assignedRole: 'CHILD',
        isKid: true,
      );

      // Verify pending queue is cleared
      final pendingAfterFirst = await service.watchPendingRequests('fam_approval_test').first;
      expect(pendingAfterFirst.isEmpty, isTrue);

      // Second approval attempt on ALREADY APPROVED request
      // In production Firestore, transaction throws Exception('Yêu cầu này đã được xử lý trước đó.').
      // In mock implementation, it mutates silently without error:
      bool secondApprovalThrew = false;
      try {
        await service.approveJoinRequest(
          requestId: reqId,
          assignedRole: 'PARENT',
          isKid: false,
        );
      } catch (_) {
        secondApprovalThrew = true;
      }
      expect(secondApprovalThrew, isFalse, reason: 'Mock mode does not guard against re-approving');

      // Verify pending list remains empty regardless
      final pendingAfterSecond = await service.watchPendingRequests('fam_approval_test').first;
      expect(pendingAfterSecond.isEmpty, isTrue);

      // Now test rejecting an already approved request or approving a rejected request
      await service.sendJoinRequest(familyId: 'fam_reject_test', suggestedRole: 'PARENT');
      final rejectPending = await service.watchPendingRequests('fam_reject_test').first;
      final rejectReqId = rejectPending.first.id;

      await service.rejectJoinRequest(rejectReqId);
      final afterReject = await service.watchPendingRequests('fam_reject_test').first;
      expect(afterReject.isEmpty, isTrue);

      // Attempt to approve an already REJECTED request
      bool approveRejectedThrew = false;
      try {
        await service.approveJoinRequest(
          requestId: rejectReqId,
          assignedRole: 'PARENT',
          isKid: false,
        );
      } catch (_) {
        approveRejectedThrew = true;
      }
      expect(approveRejectedThrew, isFalse, reason: 'Mock mode silently allows approving rejected requests');

      // Pending list must still be empty
      final afterApproveRejected = await service.watchPendingRequests('fam_reject_test').first;
      expect(afterApproveRejected.isEmpty, isTrue);

      // Attempt to approve a completely NON-EXISTENT request ID
      bool nonExistentThrew = false;
      try {
        await service.approveJoinRequest(
          requestId: 'completely_non_existent_request_id_999',
          assignedRole: 'CHILD',
          isKid: true,
        );
      } catch (_) {
        nonExistentThrew = true;
      }
      expect(nonExistentThrew, isFalse, reason: 'Mock mode silently ignores missing request');
    });

    test('1.3 Boundary: Requesting join for non-existent family ID', () async {
      final service = JoinRequestService();

      const nonExistentFamId = 'family_does_not_exist_404';
      await service.sendJoinRequest(familyId: nonExistentFamId, suggestedRole: 'CHILD');

      final pending = await service.watchPendingRequests(nonExistentFamId).first;
      expect(pending.length, 1);
      expect(pending.first.familyId, nonExistentFamId);
      expect(pending.first.id, '${nonExistentFamId}_mock_user');

      // Unrelated family streams must NOT receive this request
      final otherFamStream = await service.watchPendingRequests('other_valid_family').first;
      expect(otherFamStream.isEmpty, isTrue);
    });
  });

  group('Empirical Challenge 2: familyIds Synchronization & Edge Cases', () {
    test('2.1 Empty lists handling across UserModel and UserProfile', () {
      // 1. UserModel with empty familyIds
      final userEmpty1 = UserModel(
        id: 'u_empty_1',
        name: 'Empty User',
        email: 'empty@example.com',
        familyIds: const [],
      );
      expect(userEmpty1.familyIds, isEmpty);

      // JSON roundtrip
      final jsonEmpty = userEmpty1.toJson();
      expect(jsonEmpty['familyIds'], isEmpty);
      final parsedFromJson = UserModel.fromJson(jsonEmpty);
      expect(parsedFromJson.familyIds, isEmpty);

      // Map without familyIds key at all (null safety & default fallback)
      final legacyUser = UserModel.fromJson({
        'id': 'u_legacy',
        'name': 'Legacy User',
        'email': 'legacy@example.com',
      });
      expect(legacyUser.familyIds, isEmpty);

      // 2. UserProfile (Khoa) with empty familyIds
      const profileEmpty = UserProfile(
        id: 'u_p_empty',
        name: 'Empty Profile',
        email: 'profile@example.com',
        familyIds: [],
      );
      expect(profileEmpty.familyIds, isEmpty);

      final mapEmpty = profileEmpty.toMap();
      expect(mapEmpty['familyIds'], isEmpty);
      final parsedProfile = UserProfile.fromMap(mapEmpty);
      expect(parsedProfile.familyIds, isEmpty);

      // Legacy map without familyIds
      final legacyProfile = UserProfile.fromMap({
        'uid': 'u_p_legacy',
        'name': 'Legacy Profile',
        'email': 'p_legacy@example.com',
      });
      expect(legacyProfile.familyIds, isEmpty);
    });

    test('2.2 Single element handling in familyIds', () {
      final userSingle = UserModel(
        id: 'u_single',
        name: 'Single Family User',
        email: 'single@example.com',
        familyIds: const ['family_alpha'],
      );
      expect(userSingle.familyIds.length, 1);
      expect(userSingle.familyIds.first, 'family_alpha');

      final json = userSingle.toJson();
      expect(json['familyIds'], ['family_alpha']);
      final restored = UserModel.fromJson(json);
      expect(restored.familyIds, ['family_alpha']);

      const profileSingle = UserProfile(
        id: 'u_p_single',
        name: 'Single Family Profile',
        email: 'single@example.com',
        familyIds: ['family_alpha'],
      );
      expect(profileSingle.familyIds, ['family_alpha']);
      final restoredProfile = UserProfile.fromMap(profileSingle.toMap());
      expect(restoredProfile.familyIds, ['family_alpha']);
    });

    test('2.3 Duplicate elements & dirty data in familyIds serialization', () {
      // Input containing duplicates, nulls, whitespace, and empty strings
      final dirtyData = {
        'id': 'u_dirty',
        'name': 'Dirty Data User',
        'email': 'dirty@example.com',
        'familyIds': [
          'fam_1',
          'fam_1', // duplicate
          null, // null element
          '  ', // empty whitespace
          ' fam_2 ', // trailing whitespace
          'fam_2', // duplicate after trimming
        ],
      };

      final cleanedUser = UserModel.fromJson(dirtyData);
      // UserModel.fromJson cleans nulls and trims whitespace
      expect(cleanedUser.familyIds, containsAll(['fam_1', 'fam_2']));
      expect(cleanedUser.familyIds.contains(''), isFalse);

      // Check UserProfile (Khoa) dirty data handling
      final dirtyProfileData = {
        'uid': 'u_p_dirty',
        'name': 'Dirty Profile',
        'email': 'dirty_p@example.com',
        'family_ids': ['fam_A', 'fam_A', 'fam_B'],
      };
      final profile = UserProfile.fromMap(dirtyProfileData);
      expect(profile.familyIds.length, 3);
      expect(profile.familyIds.toSet().toList(), ['fam_A', 'fam_B']);
    });

    test('2.4 Self-healing fallbacks: Dual keys resolution (familyIds vs family_ids)', () {
      // When incoming JSON uses snake_case 'family_ids'
      final userSnake = UserModel.fromJson({
        'id': 'u_snake',
        'name': 'Snake Case',
        'email': 'snake@example.com',
        'family_ids': ['fam_10', 'fam_20'],
      });
      expect(userSnake.familyIds, ['fam_10', 'fam_20']);

      // When incoming JSON uses camelCase 'familyIds'
      final userCamel = UserModel.fromJson({
        'id': 'u_camel',
        'name': 'Camel Case',
        'email': 'camel@example.com',
        'familyIds': ['fam_30', 'fam_40'],
      });
      expect(userCamel.familyIds, ['fam_30', 'fam_40']);

      // Priority check: camelCase should take precedence over snake_case if both present
      final userBoth = UserModel.fromJson({
        'id': 'u_both',
        'name': 'Both Cases',
        'email': 'both@example.com',
        'familyIds': ['primary_fam'],
        'family_ids': ['secondary_fam'],
      });
      expect(userBoth.familyIds, ['primary_fam']);
    });
  });
}

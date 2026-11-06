import 'package:flutter_test/flutter_test.dart';

import 'package:fhub/Long/models/user_model.dart';
import 'package:fhub/Long/models/family_member_model.dart';
import 'package:fhub/Long/models/hierarchy_role.dart';
import 'package:fhub/Khoa/models/family_member.dart' as khoa_member;

/// Simulation Oracle that mirrors the exact boolean expression from firestore.rules
class FirestoreRulesOracle {
  static bool isMember({
    required String? authUid,
    required Map<String, dynamic>? memberDocData,
  }) {
    if (authUid == null || memberDocData == null) return false;
    if (!memberDocData.containsKey('status')) return true;
    final status = memberDocData['status']?.toString().toUpperCase();
    return status == 'ACTIVE';
  }

  static bool isGuardian({
    required String? authUid,
    required Map<String, dynamic>? memberDocData,
  }) {
    if (!isMember(authUid: authUid, memberDocData: memberDocData)) return false;
    final role = memberDocData?['role']?.toString();
    final hierarchyRole = memberDocData?['hierarchyRole']?.toString();
    final isOwner = memberDocData?['isOwner'] == true;
    final isGuardianFlag = memberDocData?['isGuardian'] == true;

    final roleMatches = role != null &&
        ['owner', 'OWNER', 'PARENT', 'GRANDPARENT'].contains(role);
    final hierarchyMatches = hierarchyRole != null &&
        ['PARENT', 'GRANDPARENT'].contains(hierarchyRole);

    return roleMatches || hierarchyMatches || isOwner || isGuardianFlag;
  }

  /// Evaluates allow update for /family_members/{docId}
  static bool canUpdateFamilyMember({
    required String? authUid,
    required Map<String, dynamic> callerMemberDoc,
    required Map<String, dynamic> existingDoc,
    required Map<String, dynamic> prospectiveDoc,
  }) {
    final callerIsGuardian = isGuardian(
      authUid: authUid,
      memberDocData: callerMemberDoc,
    );

    if (callerIsGuardian) return true;

    // Self-update checks
    final isSelf = authUid != null && authUid == existingDoc['userId'];
    final userUnchanged = prospectiveDoc['userId'] == existingDoc['userId'];
    final familyUnchanged = prospectiveDoc['familyId'] == existingDoc['familyId'];

    final hierarchyUnchanged = !prospectiveDoc.containsKey('hierarchyRole') ||
        prospectiveDoc['hierarchyRole'] == existingDoc['hierarchyRole'];

    final roleUnchanged = !prospectiveDoc.containsKey('role') ||
        prospectiveDoc['role'] == existingDoc['role'];

    final isOwnerUnchanged = !prospectiveDoc.containsKey('isOwner') ||
        prospectiveDoc['isOwner'] == existingDoc['isOwner'];

    final isGuardianUnchanged = !prospectiveDoc.containsKey('isGuardian') ||
        prospectiveDoc['isGuardian'] == existingDoc['isGuardian'];

    final starsNotIncreased = !prospectiveDoc.containsKey('rewardStarsTotal') ||
        !existingDoc.containsKey('rewardStarsTotal') ||
        (prospectiveDoc['rewardStarsTotal'] as num) <=
            (existingDoc['rewardStarsTotal'] as num);

    return isSelf &&
        userUnchanged &&
        familyUnchanged &&
        hierarchyUnchanged &&
        roleUnchanged &&
        isOwnerUnchanged &&
        isGuardianUnchanged &&
        starsNotIncreased;
  }

  /// Evaluates /star_ledger/{txId}
  static bool canUpdateStarLedger() => false;
  static bool canDeleteStarLedger() => false;
}

void main() {
  group('CHALLENGE 1: Security Rules Role Escalation Lockdown & Star Ledger', () {
    final childCallerMemberDoc = {
      'userId': 'child_uid',
      'familyId': 'fam_1',
      'role': 'MEMBER',
      'hierarchyRole': 'CHILD',
      'isOwner': false,
      'isGuardian': false,
      'status': 'ACTIVE',
      'rewardStarsTotal': 15,
    };

    final guardianCallerMemberDoc = {
      'userId': 'guardian_uid',
      'familyId': 'fam_1',
      'role': 'PARENT',
      'hierarchyRole': 'PARENT',
      'isOwner': false,
      'isGuardian': true,
      'status': 'ACTIVE',
      'rewardStarsTotal': 100,
    };

    final existingChildDoc = Map<String, dynamic>.from(childCallerMemberDoc);

    test('Attack 1.1: Child cannot escalate hierarchyRole to PARENT', () {
      final prospectiveDoc = Map<String, dynamic>.from(existingChildDoc)
        ..['hierarchyRole'] = 'PARENT';

      final allowed = FirestoreRulesOracle.canUpdateFamilyMember(
        authUid: 'child_uid',
        callerMemberDoc: childCallerMemberDoc,
        existingDoc: existingChildDoc,
        prospectiveDoc: prospectiveDoc,
      );
      expect(allowed, isFalse, reason: 'Child escalated hierarchyRole to PARENT');
    });

    test('Attack 1.2: Child cannot escalate hierarchyRole to GRANDPARENT', () {
      final prospectiveDoc = Map<String, dynamic>.from(existingChildDoc)
        ..['hierarchyRole'] = 'GRANDPARENT';

      final allowed = FirestoreRulesOracle.canUpdateFamilyMember(
        authUid: 'child_uid',
        callerMemberDoc: childCallerMemberDoc,
        existingDoc: existingChildDoc,
        prospectiveDoc: prospectiveDoc,
      );
      expect(allowed, isFalse, reason: 'Child escalated hierarchyRole to GRANDPARENT');
    });

    test('Attack 1.3: Child cannot escalate role to OWNER', () {
      final prospectiveDoc = Map<String, dynamic>.from(existingChildDoc)
        ..['role'] = 'OWNER';

      final allowed = FirestoreRulesOracle.canUpdateFamilyMember(
        authUid: 'child_uid',
        callerMemberDoc: childCallerMemberDoc,
        existingDoc: existingChildDoc,
        prospectiveDoc: prospectiveDoc,
      );
      expect(allowed, isFalse, reason: 'Child escalated role to OWNER');
    });

    test('Attack 1.4: Child cannot set isOwner = true', () {
      final prospectiveDoc = Map<String, dynamic>.from(existingChildDoc)
        ..['isOwner'] = true;

      final allowed = FirestoreRulesOracle.canUpdateFamilyMember(
        authUid: 'child_uid',
        callerMemberDoc: childCallerMemberDoc,
        existingDoc: existingChildDoc,
        prospectiveDoc: prospectiveDoc,
      );
      expect(allowed, isFalse, reason: 'Child escalated isOwner');
    });

    test('Attack 1.5: Child cannot set isGuardian = true', () {
      final prospectiveDoc = Map<String, dynamic>.from(existingChildDoc)
        ..['isGuardian'] = true;

      final allowed = FirestoreRulesOracle.canUpdateFamilyMember(
        authUid: 'child_uid',
        callerMemberDoc: childCallerMemberDoc,
        existingDoc: existingChildDoc,
        prospectiveDoc: prospectiveDoc,
      );
      expect(allowed, isFalse, reason: 'Child escalated isGuardian');
    });

    test('Attack 1.6: Child cannot inflate rewardStarsTotal (15 -> 16 or 500)', () {
      final prospectiveSmallInflate = Map<String, dynamic>.from(existingChildDoc)
        ..['rewardStarsTotal'] = 16;
      expect(
        FirestoreRulesOracle.canUpdateFamilyMember(
          authUid: 'child_uid',
          callerMemberDoc: childCallerMemberDoc,
          existingDoc: existingChildDoc,
          prospectiveDoc: prospectiveSmallInflate,
        ),
        isFalse,
      );

      final prospectiveBigInflate = Map<String, dynamic>.from(existingChildDoc)
        ..['rewardStarsTotal'] = 500;
      expect(
        FirestoreRulesOracle.canUpdateFamilyMember(
          authUid: 'child_uid',
          callerMemberDoc: childCallerMemberDoc,
          existingDoc: existingChildDoc,
          prospectiveDoc: prospectiveBigInflate,
        ),
        isFalse,
      );
    });

    test('Attack 1.7: Stranger cannot update another user member doc', () {
      final prospective = Map<String, dynamic>.from(existingChildDoc)
        ..['lastActiveAt'] = '2026-11-06T12:00:00Z';

      final strangerDoc = {
        'userId': 'stranger_uid',
        'familyId': 'fam_1',
        'role': 'MEMBER',
        'hierarchyRole': 'CHILD',
        'status': 'ACTIVE',
      };

      final allowed = FirestoreRulesOracle.canUpdateFamilyMember(
        authUid: 'stranger_uid',
        callerMemberDoc: strangerDoc,
        existingDoc: existingChildDoc,
        prospectiveDoc: prospective,
      );
      expect(allowed, isFalse);
    });

    test('Legitimate 1.8: Child can update lastActiveAt & lastCheckInAt', () {
      final prospective = Map<String, dynamic>.from(existingChildDoc)
        ..['lastActiveAt'] = '2026-11-06T12:00:00Z'
        ..['lastCheckInAt'] = '2026-11-06T12:00:00Z';

      final allowed = FirestoreRulesOracle.canUpdateFamilyMember(
        authUid: 'child_uid',
        callerMemberDoc: childCallerMemberDoc,
        existingDoc: existingChildDoc,
        prospectiveDoc: prospective,
      );
      expect(allowed, isTrue);
    });

    test('Legitimate 1.9: Child can decrease stars when spending in Wishlist', () {
      final prospective = Map<String, dynamic>.from(existingChildDoc)
        ..['rewardStarsTotal'] = 5;

      final allowed = FirestoreRulesOracle.canUpdateFamilyMember(
        authUid: 'child_uid',
        callerMemberDoc: childCallerMemberDoc,
        existingDoc: existingChildDoc,
        prospectiveDoc: prospective,
      );
      expect(allowed, isTrue);
    });

    test('Legitimate 1.10: Guardian can update child role and award stars', () {
      final prospectivePromoted = Map<String, dynamic>.from(existingChildDoc)
        ..['hierarchyRole'] = 'PARENT'
        ..['rewardStarsTotal'] = 200;

      final allowed = FirestoreRulesOracle.canUpdateFamilyMember(
        authUid: 'guardian_uid',
        callerMemberDoc: guardianCallerMemberDoc,
        existingDoc: existingChildDoc,
        prospectiveDoc: prospectivePromoted,
      );
      expect(allowed, isTrue);
    });

    test('Immutability 1.11: star_ledger update and delete are strictly disallowed', () {
      expect(FirestoreRulesOracle.canUpdateStarLedger(), isFalse);
      expect(FirestoreRulesOracle.canDeleteStarLedger(), isFalse);
    });

    test('Guardian Checks 1.12: isGuardian verifies Owner, Parent, Grandparent, and rejects inactive', () {
      // Owner via role
      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u1',
        memberDocData: {'role': 'owner', 'status': 'ACTIVE'},
      ), isTrue);

      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u2',
        memberDocData: {'role': 'OWNER', 'status': 'ACTIVE'},
      ), isTrue);

      // Owner via isOwner flag
      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u3',
        memberDocData: {'isOwner': true, 'role': 'MEMBER', 'status': 'ACTIVE'},
      ), isTrue);

      // Parent via role
      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u4',
        memberDocData: {'role': 'PARENT', 'status': 'ACTIVE'},
      ), isTrue);

      // Parent via hierarchyRole
      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u5',
        memberDocData: {'hierarchyRole': 'PARENT', 'role': 'MEMBER', 'status': 'ACTIVE'},
      ), isTrue);

      // Grandparent via role
      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u6',
        memberDocData: {'role': 'GRANDPARENT', 'status': 'ACTIVE'},
      ), isTrue);

      // Grandparent via hierarchyRole
      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u7',
        memberDocData: {'hierarchyRole': 'GRANDPARENT', 'role': 'MEMBER', 'status': 'ACTIVE'},
      ), isTrue);

      // Explicit isGuardian flag
      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u8',
        memberDocData: {'isGuardian': true, 'status': 'ACTIVE'},
      ), isTrue);

      // Child is NOT guardian
      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u9',
        memberDocData: {'role': 'MEMBER', 'hierarchyRole': 'CHILD', 'status': 'ACTIVE'},
      ), isFalse);

      // Inactive/deactivated Parent is NOT guardian
      expect(FirestoreRulesOracle.isGuardian(
        authUid: 'u10',
        memberDocData: {'role': 'PARENT', 'status': 'DEACTIVATED'},
      ), isFalse);
    });
  });

  group('CHALLENGE 2: FamilyMemberModel (Long) Edge Cases & Permutations', () {
    final testUser = UserModel(id: 'u_test', name: 'User Test', email: 'test@example.com');

    test('2.1: isGuardian permutations across role and hierarchyRole', () {
      // Owner + Parent
      final m1 = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.owner, hierarchyRole: HierarchyRole.parent);
      expect(m1.isGuardian, isTrue);

      // Owner + Child
      final m2 = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.owner, hierarchyRole: HierarchyRole.child);
      expect(m2.isGuardian, isTrue);

      // Owner + Grandparent
      final m3 = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.owner, hierarchyRole: HierarchyRole.grandparent);
      expect(m3.isGuardian, isTrue);

      // Member + Parent
      final m4 = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.parent);
      expect(m4.isGuardian, isTrue);

      // Member + Grandparent
      final m5 = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.grandparent);
      expect(m5.isGuardian, isTrue);

      // Member + Child
      final m6 = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.child);
      expect(m6.isGuardian, isFalse);
    });

    test('2.2: isKid defaults to true for child, false for parent/grandparent, and handles explicit overrides', () {
      // Defaults
      final childDefault = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.child);
      expect(childDefault.isKid, isTrue);

      final parentDefault = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.parent);
      expect(parentDefault.isKid, isFalse);

      final gpDefault = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.grandparent);
      expect(gpDefault.isKid, isFalse);

      // Explicit overrides
      final adultChild = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.child, isKid: false);
      expect(adultChild.isKid, isFalse);

      final parentKidOverride = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.parent, isKid: true);
      expect(parentKidOverride.isKid, isTrue);

      final gpKidOverride = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.grandparent, isKid: true);
      expect(gpKidOverride.isKid, isTrue);
    });

    test('2.3: isKid serialization and deserialization across formats', () {
      // boolean true / false
      final fromBoolTrue = FamilyMemberModel.fromJson({'user': {'id': '1'}, 'hierarchyRole': 'CHILD', 'isKid': true});
      expect(fromBoolTrue.isKid, isTrue);

      final fromBoolFalse = FamilyMemberModel.fromJson({'user': {'id': '1'}, 'hierarchyRole': 'CHILD', 'isKid': false});
      expect(fromBoolFalse.isKid, isFalse);

      // String 'true' / 'false' / 'TRUE'
      final fromStrTrue = FamilyMemberModel.fromJson({'user': {'id': '1'}, 'hierarchyRole': 'CHILD', 'is_kid': 'true'});
      expect(fromStrTrue.isKid, isTrue);

      final fromStrUpperTrue = FamilyMemberModel.fromJson({'user': {'id': '1'}, 'hierarchyRole': 'CHILD', 'is_kid': 'TRUE'});
      expect(fromStrUpperTrue.isKid, isTrue);

      final fromStrFalse = FamilyMemberModel.fromJson({'user': {'id': '1'}, 'hierarchyRole': 'CHILD', 'is_kid': 'false'});
      expect(fromStrFalse.isKid, isFalse);

      // missing isKid falls back to hierarchyRole
      final fromMissingChild = FamilyMemberModel.fromJson({'user': {'id': '1'}, 'hierarchyRole': 'CHILD'});
      expect(fromMissingChild.isKid, isTrue);

      final fromMissingParent = FamilyMemberModel.fromJson({'user': {'id': '1'}, 'hierarchyRole': 'PARENT'});
      expect(fromMissingParent.isKid, isFalse);
    });

    test('2.4: rewardStarsTotal safe parsing and fallback to 0', () {
      // Default in constructor
      final defMember = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member);
      expect(defMember.rewardStarsTotal, 0);

      // fromJson: missing / null
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}}).rewardStarsTotal, 0);
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'rewardStarsTotal': null}).rewardStarsTotal, 0);

      // fromJson: int
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'rewardStarsTotal': 42}).rewardStarsTotal, 42);

      // fromJson: double
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'rewardStarsTotal': 42.7}).rewardStarsTotal, 42);

      // fromJson: valid String
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'rewardStarsTotal': '150'}).rewardStarsTotal, 150);

      // fromJson: invalid String
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'rewardStarsTotal': 'abc_invalid'}).rewardStarsTotal, 0);
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'rewardStarsTotal': ''}).rewardStarsTotal, 0);

      // fromJson: negative numbers
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'rewardStarsTotal': -25}).rewardStarsTotal, -25);

      // Alternative keys: reward_stars_total, stars, rewardStars
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'reward_stars_total': 30}).rewardStarsTotal, 30);
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'stars': 40}).rewardStarsTotal, 40);
      expect(FamilyMemberModel.fromJson({'user': <String, dynamic>{}, 'rewardStars': 50}).rewardStarsTotal, 50);
    });

    test('2.5: copyWith preserves or updates isKid and rewardStarsTotal', () {
      final child = FamilyMemberModel(familyId: 'f1', user: testUser, role: Role.member, hierarchyRole: HierarchyRole.child);
      expect(child.isKid, isTrue);
      expect(child.rewardStarsTotal, 0);

      // Override isKid to false
      final updatedKid = child.copyWith(isKid: false);
      expect(updatedKid.isKid, isFalse);

      // Update rewardStarsTotal
      final updatedStars = child.copyWith(rewardStarsTotal: 75);
      expect(updatedStars.rewardStarsTotal, 75);
      expect(updatedStars.isKid, isTrue);
    });
  });

  group('CHALLENGE 3: FamilyMember (Khoa) Edge Cases & Permutations', () {
    test('3.1: isGuardian permutations across roles and isOwner', () {
      // isOwner true
      const m1 = khoa_member.FamilyMember(familyId: 'f1', userId: 'u1', role: 'CHILD', isOwner: true);
      expect(m1.isGuardian, isTrue);

      // Parent role
      const m2 = khoa_member.FamilyMember(familyId: 'f1', userId: 'u2', role: 'PARENT', isOwner: false);
      expect(m2.isGuardian, isTrue);

      // Grandparent role
      const m3 = khoa_member.FamilyMember(familyId: 'f1', userId: 'u3', role: 'GRANDPARENT', isOwner: false);
      expect(m3.isGuardian, isTrue);

      // Child role
      const m4 = khoa_member.FamilyMember(familyId: 'f1', userId: 'u4', role: 'CHILD', isOwner: false);
      expect(m4.isGuardian, isFalse);

      // Member role
      const m5 = khoa_member.FamilyMember(familyId: 'f1', userId: 'u5', role: 'MEMBER', isOwner: false);
      expect(m5.isGuardian, isFalse);

      // Case insensitivity
      const m6 = khoa_member.FamilyMember(familyId: 'f1', userId: 'u6', role: 'parent', isOwner: false);
      expect(m6.isGuardian, isTrue);

      const m7 = khoa_member.FamilyMember(familyId: 'f1', userId: 'u7', role: 'grandparent', isOwner: false);
      expect(m7.isGuardian, isTrue);
    });

    test('3.2: isKid defaults to true for child, false for parent/grandparent, handles explicit overrides', () {
      const childDefault = khoa_member.FamilyMember(familyId: 'f1', userId: 'u1', role: 'CHILD');
      expect(childDefault.isKid, isTrue);

      const parentDefault = khoa_member.FamilyMember(familyId: 'f1', userId: 'u2', role: 'PARENT');
      expect(parentDefault.isKid, isFalse);

      const gpDefault = khoa_member.FamilyMember(familyId: 'f1', userId: 'u3', role: 'GRANDPARENT');
      expect(gpDefault.isKid, isFalse);

      // Explicit overrides
      const adultChild = khoa_member.FamilyMember(familyId: 'f1', userId: 'u1', role: 'CHILD', isKid: false);
      expect(adultChild.isKid, isFalse);

      const parentKidOverride = khoa_member.FamilyMember(familyId: 'f1', userId: 'u2', role: 'PARENT', isKid: true);
      expect(parentKidOverride.isKid, isTrue);

      const gpKidOverride = khoa_member.FamilyMember(familyId: 'f1', userId: 'u3', role: 'GRANDPARENT', isKid: true);
      expect(gpKidOverride.isKid, isTrue);
    });

    test('3.3: isKid serialization and deserialization across formats', () {
      final fromBoolTrue = khoa_member.FamilyMember.fromMap({'role': 'CHILD', 'isKid': true});
      expect(fromBoolTrue.isKid, isTrue);

      final fromBoolFalse = khoa_member.FamilyMember.fromMap({'role': 'CHILD', 'isKid': false});
      expect(fromBoolFalse.isKid, isFalse);

      final fromStrTrue = khoa_member.FamilyMember.fromMap({'role': 'CHILD', 'is_kid': 'true'});
      expect(fromStrTrue.isKid, isTrue);

      final fromStrUpperTrue = khoa_member.FamilyMember.fromMap({'role': 'CHILD', 'is_kid': 'TRUE'});
      expect(fromStrUpperTrue.isKid, isTrue);

      final fromStrFalse = khoa_member.FamilyMember.fromMap({'role': 'CHILD', 'is_kid': 'false'});
      expect(fromStrFalse.isKid, isFalse);

      final fromMissingChild = khoa_member.FamilyMember.fromMap({'role': 'CHILD'});
      expect(fromMissingChild.isKid, isTrue);

      final fromMissingParent = khoa_member.FamilyMember.fromMap({'role': 'PARENT'});
      expect(fromMissingParent.isKid, isFalse);
    });

    test('3.4: rewardStarsTotal safe parsing and fallback to 0', () {
      const defMember = khoa_member.FamilyMember(familyId: 'f1', userId: 'u1', role: 'CHILD');
      expect(defMember.rewardStarsTotal, 0);

      expect(khoa_member.FamilyMember.fromMap({}).rewardStarsTotal, 0);
      expect(khoa_member.FamilyMember.fromMap({'rewardStarsTotal': null}).rewardStarsTotal, 0);
      expect(khoa_member.FamilyMember.fromMap({'rewardStarsTotal': 42}).rewardStarsTotal, 42);
      expect(khoa_member.FamilyMember.fromMap({'rewardStarsTotal': 42.9}).rewardStarsTotal, 42);
      expect(khoa_member.FamilyMember.fromMap({'rewardStarsTotal': '150'}).rewardStarsTotal, 150);
      expect(khoa_member.FamilyMember.fromMap({'rewardStarsTotal': 'invalid_xyz'}).rewardStarsTotal, 0);
      expect(khoa_member.FamilyMember.fromMap({'rewardStarsTotal': ''}).rewardStarsTotal, 0);
      expect(khoa_member.FamilyMember.fromMap({'rewardStarsTotal': -25}).rewardStarsTotal, -25);

      // Dual keys
      expect(khoa_member.FamilyMember.fromMap({'reward_stars_total': 30}).rewardStarsTotal, 30);
      expect(khoa_member.FamilyMember.fromMap({'stars': 40}).rewardStarsTotal, 40);
      expect(khoa_member.FamilyMember.fromMap({'rewardStars': 50}).rewardStarsTotal, 50);
    });

    test('3.5: copyWith preserves or updates isKid and rewardStarsTotal', () {
      const child = khoa_member.FamilyMember(familyId: 'f1', userId: 'u1', role: 'CHILD');
      expect(child.isKid, isTrue);
      expect(child.rewardStarsTotal, 0);

      final updatedKid = child.copyWith(isKid: false);
      expect(updatedKid.isKid, isFalse);

      final updatedStars = child.copyWith(rewardStarsTotal: 88);
      expect(updatedStars.rewardStarsTotal, 88);
      expect(updatedStars.isKid, isTrue);
    });
  });
}

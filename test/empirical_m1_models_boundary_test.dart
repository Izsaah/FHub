import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';

import 'package:fhub/Long/models/hierarchy_role.dart';
import 'package:fhub/Long/models/family_member_model.dart';
import 'package:fhub/Long/models/user_model.dart';
import 'package:fhub/Khoa/models/family_member.dart' as khoa_member;
import 'package:fhub/Khoa/services/family_service.dart';
import 'package:fhub/Khoa/screens/join_family_screen.dart';
import 'package:fhub/Khoa/screens/create_family_screen.dart';
import 'package:fhub/Vinh/models/family_member.dart' as vinh_member;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('Empirical Milestone 1 Models & Boundary Stress Test Suite', () {
    test('1. HierarchyRole.relative serialization and deserialization round-trip', () {
      expect(HierarchyRole.relative.toJson(), equals('RELATIVE'));
      expect(HierarchyRole.relative.code, equals('RELATIVE'));
      expect(HierarchyRole.fromString('RELATIVE'), equals(HierarchyRole.relative));
      expect(HierarchyRole.fromString(HierarchyRole.relative.toJson()), equals(HierarchyRole.relative));
      
      // Case-insensitivity and whitespace resilience
      expect(HierarchyRole.fromString('relative'), equals(HierarchyRole.relative));
      expect(HierarchyRole.fromString('  RELATIVE  '), equals(HierarchyRole.relative));
      expect(HierarchyRole.fromString('rElAtIvE'), equals(HierarchyRole.relative));
      
      // All enum values round-trip
      for (final role in HierarchyRole.values) {
        expect(HierarchyRole.fromString(role.toJson()), equals(role));
        expect(HierarchyRole.fromString(role.code), equals(role));
      }
      
      // Fallbacks
      expect(HierarchyRole.fromString(null), equals(HierarchyRole.parent));
      expect(HierarchyRole.fromString('UNKNOWN_ROLE'), equals(HierarchyRole.parent));
      expect(HierarchyRole.fromString(''), equals(HierarchyRole.parent));
    });

    test('2. HierarchyRole.fromString() synonyms stress test', () {
      const synonyms = [
        'NGUOI_THAN',
        'CO_DI_CHU_BAC',
        'UNCLE_AUNT',
        'UNCLE',
        'AUNT',
      ];

      for (final syn in synonyms) {
        // Uppercase exact
        expect(HierarchyRole.fromString(syn), equals(HierarchyRole.relative),
            reason: 'Synonym $syn should resolve to HierarchyRole.relative');
        // Lowercase
        expect(HierarchyRole.fromString(syn.toLowerCase()), equals(HierarchyRole.relative),
            reason: 'Lowercase $syn should resolve to HierarchyRole.relative');
        // With leading and trailing whitespace
        expect(HierarchyRole.fromString('  $syn  '), equals(HierarchyRole.relative),
            reason: 'Padded $syn should resolve to HierarchyRole.relative');
      }
    });

    test('3. FamilyService.validateRole with RELATIVE and synonyms', () {
      // Must not throw for RELATIVE and roleRelative constant
      expect(() => FamilyService.validateRole('RELATIVE'), returnsNormally);
      expect(() => FamilyService.validateRole(khoa_member.FamilyMember.roleRelative), returnsNormally);
      
      // Valid roles
      expect(() => FamilyService.validateRole(khoa_member.FamilyMember.roleGrandparent), returnsNormally);
      expect(() => FamilyService.validateRole(khoa_member.FamilyMember.roleParent), returnsNormally);
      expect(() => FamilyService.validateRole(khoa_member.FamilyMember.roleChild), returnsNormally);

      // Invalid roles must throw Exception
      expect(() => FamilyService.validateRole('INVALID_ROLE'), throwsException);
      expect(() => FamilyService.validateRole('STRANGER'), throwsException);
      expect(() => FamilyService.validateRole(''), throwsException);
      expect(() => FamilyService.validateRole('GUEST'), throwsException);
    });

    test('4. FamilyMember models with RELATIVE: isGuardian == false, canAssignChores == false, hierarchyLevel == 2', () {
      // 4a. HierarchyRole.relative properties
      expect(HierarchyRole.relative.hierarchyLevel, equals(2));
      expect(HierarchyRole.relative.isGuardian, isFalse);
      expect(HierarchyRole.relative.canAssignChores, isFalse);

      // 4b. Long's FamilyMemberModel
      final longMember = FamilyMemberModel(
        familyId: 'fam_123',
        user: UserModel(id: 'usr_rel_1', name: 'Chú Ba', email: 'chuba@family.vn'),
        role: Role.member,
        hierarchyRole: HierarchyRole.relative,
      );
      expect(longMember.isRelative, isTrue);
      expect(longMember.isGuardian, isFalse);
      expect(longMember.hierarchyLevel, equals(2));
      expect(longMember.hierarchyRole.canAssignChores, isFalse);
      expect(longMember.roleLabel, equals('Cô / Dì / Chú / Bác'));

      // Long's FamilyMemberModel JSON round-trip
      final longJson = longMember.toJson();
      expect(longJson['hierarchy_role'], equals('RELATIVE'));
      expect(longJson['hierarchyRole'], equals('RELATIVE'));
      final longParsed = FamilyMemberModel.fromJson(longJson);
      expect(longParsed.isRelative, isTrue);
      expect(longParsed.isGuardian, isFalse);
      expect(longParsed.hierarchyLevel, equals(2));
      expect(longParsed.hierarchyRole.canAssignChores, isFalse);

      // 4c. Khoa's FamilyMember
      const khoaMember = khoa_member.FamilyMember(
        familyId: 'fam_123',
        userId: 'usr_rel_2',
        role: khoa_member.FamilyMember.roleRelative,
        isOwner: false,
      );
      expect(khoaMember.isRelative, isTrue);
      expect(khoaMember.isGuardian, isFalse);
      expect(khoaMember.hierarchyLevel, equals(2));

      // Khoa's FamilyMember fromMap / toJson
      final khoaMap = khoaMember.toMap();
      expect(khoaMap['role'], equals('RELATIVE'));
      final khoaParsed = khoa_member.FamilyMember.fromMap({
        'familyId': 'fam_123',
        'userId': 'usr_rel_2',
        'role': 'RELATIVE',
        'isOwner': false,
      });
      expect(khoaParsed.isRelative, isTrue);
      expect(khoaParsed.isGuardian, isFalse);
      expect(khoaParsed.hierarchyLevel, equals(2));

      // 4d. Vinh's FamilyMember
      const vinhMember = vinh_member.FamilyMember(
        id: 'usr_rel_3',
        name: 'Bác Tư',
        role: vinh_member.FamilyMember.roleRelative,
        familyId: 'fam_123',
      );
      expect(vinhMember.isRelative, isTrue);
      expect(vinhMember.isGuardian, isFalse);
      expect(vinhMember.canAssignChores, isFalse);
      expect(vinhMember.hierarchyLevel, equals(2));
      expect(vinhMember.roleDisplayName, equals('Cô / Dì / Chú / Bác'));

      // Vinh's FamilyMember fromJson / toJson
      final vinhJson = vinhMember.toJson();
      expect(vinhJson['role'], equals('RELATIVE'));
      final vinhParsed = vinh_member.FamilyMember.fromJson(vinhJson);
      expect(vinhParsed.isRelative, isTrue);
      expect(vinhParsed.isGuardian, isFalse);
      expect(vinhParsed.canAssignChores, isFalse);
      expect(vinhParsed.hierarchyLevel, equals(2));
      expect(vinhParsed.roleDisplayName, equals('Cô / Dì / Chú / Bác'));
    });

    test('3b. FamilyService.validateRole boundary and case-sensitivity stress test', () {
      // Exact allowed strings
      expect(() => FamilyService.validateRole('GRANDPARENT'), returnsNormally);
      expect(() => FamilyService.validateRole('PARENT'), returnsNormally);
      expect(() => FamilyService.validateRole('RELATIVE'), returnsNormally);
      expect(() => FamilyService.validateRole('CHILD'), returnsNormally);

      // Lowercase is rejected by strict whitelist
      expect(() => FamilyService.validateRole('relative'), throwsException);
      expect(() => FamilyService.validateRole('parent'), throwsException);
      expect(() => FamilyService.validateRole('child'), throwsException);
      expect(() => FamilyService.validateRole('grandparent'), throwsException);

      // Whitespace and variations rejected
      expect(() => FamilyService.validateRole(' RELATIVE '), throwsException);
      expect(() => FamilyService.validateRole('UNCLE'), throwsException);
      expect(() => FamilyService.validateRole('CO_DI_CHU_BAC'), throwsException);
    });

    test('4e. Vinh.FamilyMember kinship title name heuristics stress test', () {
      const titles = [
        'Cô Út',
        'Dì Bảy',
        'Chú Hùng',
        'Bác Năm',
        'Cậu Ba',
        'Thím Mười',
        'Mợ Hai',
        'Dượng Bảy',
      ];

      for (final title in titles) {
        final member = vinh_member.FamilyMember(
          id: 'usr_$title',
          name: title,
          role: 'Member',
          familyId: 'fam_123',
        );
        expect(member.isRelative, isTrue, reason: 'Title $title should be detected as relative');
        expect(member.isGuardian, isFalse, reason: '$title must not be guardian');
        expect(member.canAssignChores, isFalse, reason: '$title must not assign chores');
        expect(member.hierarchyLevel, equals(2), reason: '$title hierarchyLevel must be 2');
        expect(member.roleDisplayName, equals('Cô / Dì / Chú / Bác'));
      }
    });

    test('4f. Model invariant: RELATIVE cannot be escalated to Guardian even if isOwner is set', () {
      // In Khoa's FamilyMember: isGuardian => (isOwner || isParent || isGrandparent) && !isRelative;
      const khoaOwnerRelative = khoa_member.FamilyMember(
        familyId: 'fam_123',
        userId: 'usr_owner_rel',
        role: khoa_member.FamilyMember.roleRelative,
        isOwner: true,
      );
      expect(khoaOwnerRelative.isRelative, isTrue);
      expect(khoaOwnerRelative.isGuardian, isFalse,
          reason: 'Khoa.FamilyMember enforces !isRelative guardrail even when isOwner is true');
      expect(khoaOwnerRelative.hierarchyLevel, equals(2));

      // In Vinh's FamilyMember: isGuardian => (isParent || isGrandparent || isOwner) && !isRelative;
      const vinhOwnerRelative = vinh_member.FamilyMember(
        id: 'usr_owner_rel_vinh',
        name: 'Chú Owner',
        role: vinh_member.FamilyMember.roleRelative,
        familyId: 'fam_123',
      );
      expect(vinhOwnerRelative.isRelative, isTrue);
      expect(vinhOwnerRelative.isGuardian, isFalse,
          reason: 'Vinh.FamilyMember enforces !isRelative guardrail');
      expect(vinhOwnerRelative.canAssignChores, isFalse);
      expect(vinhOwnerRelative.hierarchyLevel, equals(2));
    });

    test('4g. Model invariant: isKid defaults to false for RELATIVE role', () {
      // Long's FamilyMemberModel: isKid = isKid ?? (hierarchyRole == HierarchyRole.child);
      final longMember = FamilyMemberModel(
        familyId: 'fam_123',
        user: UserModel(id: 'usr_rel', name: 'Cô Ba', email: 'coba@family.vn'),
        role: Role.member,
        hierarchyRole: HierarchyRole.relative,
      );
      expect(longMember.isKid, isFalse, reason: 'Long FamilyMemberModel must default isKid to false for RELATIVE');

      // Khoa's FamilyMember: isKid => _rawIsKid ?? isChild;
      const khoaMember = khoa_member.FamilyMember(
        familyId: 'fam_123',
        userId: 'usr_rel',
        role: khoa_member.FamilyMember.roleRelative,
      );
      expect(khoaMember.isKid, isFalse, reason: 'Khoa FamilyMember must default isKid to false for RELATIVE');
    });

    testWidgets('5a. JoinFamilyScreen renders role dropdown with Cô / Dì / Chú / Bác without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: JoinFamilyScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify dropdown is present
      final dropdownFinder = find.byType(DropdownButtonFormField<String>);
      expect(dropdownFinder, findsOneWidget);

      // Tap to open dropdown menu overlay
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Verify the dropdown contains the relative role text
      expect(find.text('Cô / Dì / Chú / Bác'), findsWidgets);

      // Select 'Cô / Dì / Chú / Bác'
      await tester.tap(find.text('Cô / Dì / Chú / Bác').last);
      await tester.pumpAndSettle();

      // Verify dropdown displays the selected relative role
      expect(find.text('Cô / Dì / Chú / Bác'), findsOneWidget);
    });

    testWidgets('5b. CreateFamilyScreen renders role dropdown with Cô / Dì / Chú / Bác without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CreateFamilyScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify dropdown is present
      final dropdownFinder = find.byType(DropdownButtonFormField<String>);
      expect(dropdownFinder, findsOneWidget);

      // Tap to open dropdown menu overlay
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Verify the dropdown contains the relative role text
      expect(find.text('Cô / Dì / Chú / Bác'), findsWidgets);

      // Select 'Cô / Dì / Chú / Bác'
      await tester.tap(find.text('Cô / Dì / Chú / Bác').last);
      await tester.pumpAndSettle();

      // Verify dropdown displays the selected relative role
      expect(find.text('Cô / Dì / Chú / Bác'), findsOneWidget);
    });
  });
}

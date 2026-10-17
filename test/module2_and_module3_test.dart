import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Long/models/family_model.dart';
import 'package:fhub/Long/models/family_member_model.dart';
import 'package:fhub/Long/models/hierarchy_role.dart';
import 'package:fhub/Long/models/member_status.dart';
import 'package:fhub/Long/models/user_model.dart';
import 'package:fhub/Long/services/mock_data_service.dart';
import 'package:fhub/Long/services/family_state_manager.dart';
import 'package:fhub/Long/widgets/check_in_button.dart';
import 'package:fhub/Long/widgets/family_member_tile.dart';
import 'package:fhub/Long/widgets/family_switcher_bar.dart';

void main() {
  group('Module 2 - Multi-Family, Roles & Ownership Tests', () {
    late MockDataService service;

    setUp(() {
      service = MockDataService();
    });

    test('User can belong to multiple families and switch between them', () async {
      final families = await service.getMyFamilies();
      expect(families.length, greaterThanOrEqualTo(2));

      final initialFam = await service.getCurrentFamily();
      expect(initialFam, isNotNull);

      // Switch to second family
      final secondFam = families.firstWhere((f) => f.id != initialFam!.id);
      await service.switchFamily(secondFam.id);

      final currentFam = await service.getCurrentFamily();
      expect(currentFam?.id, equals(secondFam.id));

      final members = await service.getFamilyMembers();
      expect(members.any((m) => m.familyId == secondFam.id), isTrue);
    });

    test('Creating a family generates 6-character code and makes creator Owner', () async {
      final created = await service.createFamily(
        name: 'Gia đình Hạnh Phúc',
        hierarchyRole: HierarchyRole.parent,
      );

      expect(created.name, equals('Gia đình Hạnh Phúc'));
      expect(created.joinCode.length, equals(6));
      expect(created.ownerId, equals(service.currentUserId));

      final members = await service.getFamilyMembers(familyId: created.id);
      final myMember = members.firstWhere((m) => m.user.id == service.currentUserId);
      expect(myMember.role, equals(Role.owner));
      expect(myMember.hierarchyRole, equals(HierarchyRole.parent));
    });

    test('Joining a family validates 6-character code and prevents duplicates', () async {
      // First family has join code A8K29D; user is already member
      expect(
        () => service.joinFamily(joinCode: 'A8K29D'),
        throwsA(isA<Exception>()),
      );

      // Invalid format length
      expect(
        () => service.joinFamily(joinCode: '123'),
        throwsA(isA<Exception>()),
      );

      // Nonexistent code
      expect(
        () => service.joinFamily(joinCode: 'ZZZZZZ'),
        throwsA(isA<Exception>()),
      );
    });

    test('Owner can update member status to DEACTIVATED or MEMORIALIZED', () async {
      // User u1 is Owner of f1
      await service.switchFamily('f1');
      final members = await service.getFamilyMembers(familyId: 'f1');
      final target = members.firstWhere((m) => m.user.id != service.currentUserId);

      await service.updateMemberStatus(target.user.id, MemberStatus.deactivated, familyId: 'f1');
      var updated = (await service.getFamilyMembers(familyId: 'f1'))
          .firstWhere((m) => m.user.id == target.user.id);
      expect(updated.status, equals(MemberStatus.deactivated));
      expect(updated.isDeactivated, isTrue);

      await service.updateMemberStatus(target.user.id, MemberStatus.memorialized, familyId: 'f1');
      updated = (await service.getFamilyMembers(familyId: 'f1'))
          .firstWhere((m) => m.user.id == target.user.id);
      expect(updated.status, equals(MemberStatus.memorialized));
      expect(updated.isMemorialized, isTrue);
    });

    test('Owner transfer allows only active PARENT members', () async {
      await service.switchFamily('f1');
      final members = await service.getFamilyMembers(familyId: 'f1');

      // Grandparent cannot receive owner role
      final gp = members.firstWhere((m) => m.hierarchyRole == HierarchyRole.grandparent);
      expect(
        () => service.transferOwnership(gp.user.id, familyId: 'f1'),
        throwsA(isA<Exception>()),
      );
    });

    test('Passive Owner takeover is eligible when Owner inactive > 30 days', () async {
      // In Family 2, Owner u6 has been inactive for 35 days
      await service.switchFamily('f2');
      final isEligible = service.isTakeoverEligible(familyId: 'f2');
      expect(isEligible, isTrue);

      // PARENT user u1 claims ownership
      await service.claimOwnership(familyId: 'f2');

      final members = await service.getFamilyMembers(familyId: 'f2');
      final myMember = members.firstWhere((m) => m.user.id == service.currentUserId);
      expect(myMember.isOwner, isTrue);

      final oldOwner = members.firstWhere((m) => m.user.id == 'u6');
      expect(oldOwner.isOwner, isFalse);
    });
  });

  group('Module 3 - Check-in An toàn & Giám sát Ngoại lệ Tests', () {
    late MockDataService service;

    setUp(() {
      service = MockDataService();
    });

    test('Check-in prevents duplicate check-in on the same day', () async {
      await service.switchFamily('f1');
      final userId = service.currentUserId;

      // 1st Check-in succeeds
      await service.checkIn(userId, familyId: 'f1');

      final members = await service.getFamilyMembers(familyId: 'f1');
      final myMember = members.firstWhere((m) => m.user.id == userId);
      expect(myMember.isCheckedInToday, isTrue);

      // 2nd Check-in on same day fails with duplicate message
      expect(
        () => service.checkIn(userId, familyId: 'f1'),
        throwsA(predicate((e) => e.toString().contains("already checked in"))),
      );
    });

    test('Check-in for another user is prohibited', () async {
      await service.switchFamily('f1');
      expect(
        () => service.checkIn('other_user_id', familyId: 'f1'),
        throwsA(isA<Exception>()),
      );
    });

    test('Check-in with photo attaches to family feed', () async {
      await service.switchFamily('f1');
      final userId = service.currentUserId;

      final initialFeeds = await service.getCheckInFeeds(familyId: 'f1');
      final initialCount = initialFeeds.length;

      // If not checked in, check in with photo
      final members = await service.getFamilyMembers(familyId: 'f1');
      final me = members.firstWhere((m) => m.user.id == userId);
      if (!me.isCheckedInToday) {
        await service.checkIn(
          userId,
          imageUrl: 'https://example.com/breakfast.jpg',
          caption: 'Bữa sáng đầy đủ dinh dưỡng!',
          familyId: 'f1',
        );

        final newFeeds = await service.getCheckInFeeds(familyId: 'f1');
        expect(newFeeds.length, equals(initialCount + 1));
        expect(newFeeds.first.caption, equals('Bữa sáng đầy đủ dinh dưỡng!'));
      }
    });

    test('Simulated reminders: 08:00, 14:00, 20:00 slots are cancelled on check-in', () async {
      await service.switchFamily('f1');
      final reminders = service.getSimulatedReminders(familyId: 'f1');

      expect(reminders, isNotEmpty);
      // Member u2 (Mẹ Lan) has already checked in -> reminders are cancelled
      final u2Reminders = reminders.where((r) => r.targetMemberId == 'u2');
      for (var r in u2Reminders) {
        expect(r.isCancelled, isTrue);
      }

      // Member u3 (Bố Hùng) has NOT checked in -> reminders are active
      final u3Reminders = reminders.where((r) => r.targetMemberId == 'u3');
      for (var r in u3Reminders) {
        expect(r.isCancelled, isFalse);
      }
    });
  });

  group('Module 2 & 3 - Widget Render Tests', () {
    testWidgets('FamilyMemberTile displays memorial styling for MEMORIALIZED member', (tester) async {
      final memorialMember = FamilyMemberModel(
        familyId: 'f1',
        user: UserModel(id: 'm1', name: 'Bà Cố', email: 'baco@gmail.com'),
        role: Role.member,
        hierarchyRole: HierarchyRole.grandparent,
        status: MemberStatus.memorialized,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyMemberTile(member: memorialMember),
          ),
        ),
      );

      expect(find.text('Bà Cố'), findsOneWidget);
      expect(find.text('Tưởng niệm'), findsOneWidget);
      expect(find.text('Not checked in'), findsNothing);
    });

    testWidgets('FamilyMemberTile displays deactivated badge and hides check-in status', (tester) async {
      final deactivatedMember = FamilyMemberModel(
        familyId: 'f1',
        user: UserModel(id: 'd1', name: 'Chú Ba', email: 'chuba@gmail.com'),
        role: Role.member,
        hierarchyRole: HierarchyRole.parent,
        status: MemberStatus.deactivated,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyMemberTile(member: deactivatedMember),
          ),
        ),
      );

      expect(find.text('Chú Ba'), findsOneWidget);
      expect(find.text('Tạm ngưng kết nối'), findsOneWidget);
      expect(find.text('Not checked in'), findsNothing);
    });

    testWidgets('CheckInButton renders correctly for checked-in and not checked-in states', (tester) async {
      bool tapped = false;

      // Not checked in state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckInButton(
              isCheckedIn: false,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text("✓ I'M OK"), findsOneWidget);
      await tester.tap(find.text("✓ I'M OK"));
      expect(tapped, isTrue);

      // Checked in state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckInButton(
              isCheckedIn: true,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text("You're already checked in"), findsOneWidget);
    });

    testWidgets('FamilySwitcherBar renders current family and copy code pill', (tester) async {
      final fam = FamilyModel(
        id: 'f1',
        name: 'Gia đình Nguyễn',
        joinCode: 'A8K29D',
        ownerId: 'u1',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilySwitcherBar(
              currentFamily: fam,
              families: [fam],
              onFamilyChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Gia đình Nguyễn'), findsOneWidget);
      expect(find.text('A8K29D'), findsOneWidget);
    });
  });
}

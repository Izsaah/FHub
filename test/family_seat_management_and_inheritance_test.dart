import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/models/family_subscription_model.dart';
import 'package:fhub/Long/models/member_status.dart';
import 'package:fhub/Long/services/mock_data_service.dart';

void main() {
  group('Phase 5 (Module C) - Family Seat Management & VIP Inheritance Tests', () {
    late MockDataService mockService;

    setUp(() {
      mockService = MockDataService();
    });

    test('5.1 Owner Immunity: Owner cannot deactivate themselves', () async {
      // In MockDataService, current user is the owner (user_dad)
      expect(
        () async => await mockService.updateMemberStatus(
          mockService.currentUserId,
          MemberStatus.deactivated,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('5.2 Deactivating member updates status to deactivated', () async {
      final members = await mockService.getFamilyMembers();
      // Find a non-owner member
      final nonOwner = members.firstWhere((m) => m.user.id != mockService.currentUserId);

      await mockService.updateMemberStatus(nonOwner.user.id, MemberStatus.deactivated);

      final updatedMembers = await mockService.getFamilyMembers();
      final target = updatedMembers.firstWhere((m) => m.user.id == nonOwner.user.id);
      expect(target.status, MemberStatus.deactivated);
      expect(target.isDeactivated, true);
    });

    test('5.3 Reactivating member updates status back to active', () async {
      final members = await mockService.getFamilyMembers();
      final nonOwner = members.firstWhere((m) => m.user.id != mockService.currentUserId);

      // Reactivate
      await mockService.updateMemberStatus(nonOwner.user.id, MemberStatus.active);

      final updatedMembers = await mockService.getFamilyMembers();
      final target = updatedMembers.firstWhere((m) => m.user.id == nonOwner.user.id);
      expect(target.status, MemberStatus.active);
      expect(target.isActive, true);
    });

    test('5.4 Over-Capacity Unfreeze: Reducing active count to <= 4 unfreezes family', () {
      final now = DateTime(2026, 11, 9, 12, 0);
      final expiredLongAgo = now.subtract(const Duration(days: 30));

      // With 5 active members: Over-capacity frozen
      final frozenFamily = FamilySubscriptionModel(
        familyId: 'fam_big',
        ownerId: 'owner_1',
        isPremium: true,
        planName: 'Family Plan',
        maxMembers: 10,
        endDate: expiredLongAgo,
        activeMemberCount: 5,
      );
      expect(frozenFamily.resolveAccessMode(now), FamilyAccessMode.overCapacityFrozen);

      // Owner deactivates 1 member -> activeMemberCount becomes 4: Automatically unfreezes to freeStandard!
      final unfrozenFamily = frozenFamily.copyWith(activeMemberCount: 4);
      expect(unfrozenFamily.resolveAccessMode(now), FamilyAccessMode.freeStandard);
      expect(unfrozenFamily.isOverCapacityFrozen(now), false);
    });

    test('5.5 VIP Inheritance: New family inherits active Premium from owner', () {
      final now = DateTime(2026, 11, 9, 12, 0);
      final futureExpiry = now.add(const Duration(days: 90));

      final userProfile = {
        'uid': 'owner_123',
        'isPremium': true,
        'planName': 'Family Hub Premium (1 Year)',
        'maxMembers': 10,
        'subscriptionEndDate': futureExpiry,
      };

      // When owner creates family:
      final inheritedFamily = FamilySubscriptionModel(
        familyId: 'fam_new',
        ownerId: userProfile['uid'] as String,
        isPremium: userProfile['isPremium'] as bool,
        planName: userProfile['planName'] as String,
        maxMembers: userProfile['maxMembers'] as int,
        endDate: userProfile['subscriptionEndDate'] as DateTime?,
        activeMemberCount: 1,
      );

      expect(inheritedFamily.isPremium, true);
      expect(inheritedFamily.resolveAccessMode(now), FamilyAccessMode.fullPremium);
      expect(inheritedFamily.maxMembers, 10);
    });
  });
}

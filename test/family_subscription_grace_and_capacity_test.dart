import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/models/family_subscription_model.dart';

void main() {
  group('Phase 1 (Module A) - Family Subscription, 7-Day Grace Period & Over-Capacity Tests', () {
    final now = DateTime(2026, 11, 9, 12, 0);

    test('1.1 fullPremium: When ownerPremiumExpiresAt is in the future', () {
      final sub = FamilySubscriptionModel(
        familyId: 'fam_1',
        ownerId: 'owner_1',
        isPremium: true,
        isPrimary: true,
        planName: 'Family Hub Premium',
        maxMembers: 10,
        activeMemberCount: 6,
        endDate: now.add(const Duration(days: 10)),
        premiumGraceEndsAt: now.add(const Duration(days: 17)),
      );

      expect(sub.resolveAccessMode(now), FamilyAccessMode.fullPremium);
      expect(sub.graceDaysRemaining(now), 0); // Not in grace period yet
    });

    test('1.2 gracePeriodWarning: When expired 2 days ago but within 7 days grace', () {
      final expiredAt = now.subtract(const Duration(days: 2));
      final graceEnd = expiredAt.add(const Duration(days: 7)); // 5 days left

      final sub = FamilySubscriptionModel(
        familyId: 'fam_1',
        ownerId: 'owner_1',
        isPremium: true,
        isPrimary: true,
        planName: 'Family Hub Premium',
        maxMembers: 10,
        activeMemberCount: 6,
        endDate: expiredAt,
        premiumGraceEndsAt: graceEnd,
      );

      expect(sub.resolveAccessMode(now), FamilyAccessMode.gracePeriodWarning);
      expect(sub.graceDaysRemaining(now), 5);
    });

    test('1.3 overCapacityFrozen: Grace period expired, primary family has > 4 active members (6 members)', () {
      final expiredAt = now.subtract(const Duration(days: 8));
      final graceEnd = expiredAt.add(const Duration(days: 7)); // Expired 1 day ago

      final sub = FamilySubscriptionModel(
        familyId: 'fam_1',
        ownerId: 'owner_1',
        isPremium: false,
        isPrimary: true,
        planName: 'Gói Cơ Bản (Free)',
        maxMembers: 4,
        activeMemberCount: 6,
        endDate: expiredAt,
        premiumGraceEndsAt: graceEnd,
      );

      expect(sub.resolveAccessMode(now), FamilyAccessMode.overCapacityFrozen);
      expect(sub.graceDaysRemaining(now), 0);
    });

    test('1.4 freeStandard: Grace period expired, primary family has <= 4 active members (4 members)', () {
      final expiredAt = now.subtract(const Duration(days: 10));
      final graceEnd = expiredAt.add(const Duration(days: 7));

      final sub = FamilySubscriptionModel(
        familyId: 'fam_1',
        ownerId: 'owner_1',
        isPremium: false,
        isPrimary: true,
        planName: 'Gói Cơ Bản (Free)',
        maxMembers: 4,
        activeMemberCount: 4, // Exactly 4 members (Free capacity limit)
        endDate: expiredAt,
        premiumGraceEndsAt: graceEnd,
      );

      expect(sub.resolveAccessMode(now), FamilyAccessMode.freeStandard);
      expect(sub.graceDaysRemaining(now), 0);
    });

    test('1.5 readOnlyFrozen: Grace period expired, secondary family (isPrimary = false) is frozen read-only', () {
      final expiredAt = now.subtract(const Duration(days: 9));
      final graceEnd = expiredAt.add(const Duration(days: 7));

      final sub = FamilySubscriptionModel(
        familyId: 'fam_2',
        ownerId: 'owner_1',
        isPremium: false,
        isPrimary: false, // Secondary family
        planName: 'Gói Cơ Bản (Free)',
        maxMembers: 4,
        activeMemberCount: 3,
        endDate: expiredAt,
        premiumGraceEndsAt: graceEnd,
      );

      expect(sub.resolveAccessMode(now), FamilyAccessMode.readOnlyFrozen);
    });

    test('1.6 graceDaysRemaining precision: Truncating division bug in Dart is patched (ceil hours)', () {
      // Expired 5 hours ago (6 days and 19 hours remaining)
      final graceEnd = now.add(const Duration(days: 6, hours: 19));
      final sub = FamilySubscriptionModel(
        familyId: 'fam_1',
        ownerId: 'owner_1',
        isPremium: true,
        isPrimary: true,
        planName: 'Family Hub Premium',
        maxMembers: 10,
        activeMemberCount: 4,
        endDate: now.subtract(const Duration(hours: 5)),
        premiumGraceEndsAt: graceEnd,
      );

      expect(sub.graceDaysRemaining(now), 7); // 6.79 days ceil to 7 days
    });

    test('1.7 Serialization roundtrip fromMap and toMap preserves grace and capacity attributes', () {
      final sub = FamilySubscriptionModel(
        familyId: 'fam_test',
        ownerId: 'owner_123',
        isPremium: true,
        isPrimary: true,
        planName: 'Family Hub Premium',
        maxMembers: 10,
        activeMemberCount: 5,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 1),
        premiumGraceEndsAt: DateTime(2026, 12, 8),
      );

      final map = sub.toMap();
      final restored = FamilySubscriptionModel.fromMap('fam_test', map);

      expect(restored.familyId, 'fam_test');
      expect(restored.ownerId, 'owner_123');
      expect(restored.isPrimary, true);
      expect(restored.isPremium, true);
      expect(restored.maxMembers, 10);
      expect(restored.activeMemberCount, 5);
      expect(restored.endDate, isNotNull);
      expect(restored.premiumGraceEndsAt, isNotNull);
    });
  });
}

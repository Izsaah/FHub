import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import '../models/hierarchy_role.dart';
import '../models/member_status.dart';
import '../models/check_in_feed_model.dart';
import '../models/check_in_reminder_model.dart';

abstract class IFamilyService {
  String get currentUserId;
  Future<UserModel> getCurrentUser();

  // Multi-family & Switcher
  Future<List<FamilyModel>> getMyFamilies();
  Future<FamilyModel?> getCurrentFamily();
  Future<void> switchFamily(String familyId);

  // Creation & Joining
  Future<FamilyModel> createFamily({
    required String name,
    HierarchyRole hierarchyRole = HierarchyRole.parent,
  });

  Future<FamilyModel> joinFamily({
    required String joinCode,
    HierarchyRole hierarchyRole = HierarchyRole.child,
  });

  // Members
  Future<List<FamilyMemberModel>> getFamilyMembers({String? familyId});
  Stream<List<FamilyMemberModel>> streamFamilyMembers({String? familyId});

  // Status & Ownership Management
  Future<void> updateMemberStatus(
    String targetUserId,
    MemberStatus newStatus, {
    String? familyId,
  });

  Future<void> transferOwnership(
    String newOwnerUserId, {
    String? familyId,
  });

  bool isTakeoverEligible({String? familyId});
  Future<void> claimOwnership({String? familyId});
  Future<void> updateOwnerLastActive();

  // Check-In & Feed
  Future<void> checkIn(
    String userId, {
    String? imageUrl,
    String? caption,
    String? familyId,
  });

  Future<List<CheckInFeedModel>> getCheckInFeeds({String? familyId});

  // Simulated Reminder Rules (08:00, 14:00, 20:00)
  List<CheckInReminderItem> getSimulatedReminders({String? familyId});
  void cancelRemindersForUser(String userId, {String? familyId});
}

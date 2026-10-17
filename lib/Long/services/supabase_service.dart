import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';
import '../models/hierarchy_role.dart';
import '../models/member_status.dart';
import '../models/check_in_feed_model.dart';
import '../models/check_in_reminder_model.dart';
import 'family_service_interface.dart';
import 'mock_data_service.dart';

class SupabaseService implements IFamilyService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final _supabase = Supabase.instance.client;
  final _mock = MockDataService();

  @override
  String get currentUserId => _supabase.auth.currentUser?.id ?? _mock.currentUser.id;

  Future<String?> _getCurrentFamilyId() async {
    if (_supabase.auth.currentUser == null) return _mock.currentFamily.id;
    try {
      final response = await _supabase
          .from('family_members')
          .select('family_id')
          .eq('user_id', currentUserId)
          .maybeSingle();
      
      return response?['family_id'] as String? ?? _mock.currentFamily.id;
    } catch (_) {
      return _mock.currentFamily.id;
    }
  }

  Future<bool> hasFamily() async {
    final familyId = await _getCurrentFamilyId();
    return familyId != null;
  }

  @override
  Future<UserModel> getCurrentUser() async {
    if (_supabase.auth.currentUser == null) return _mock.currentUser;
    try {
      final response = await _supabase.from('users').select().eq('id', currentUserId).maybeSingle();
      if (response == null) return _mock.currentUser;
      return UserModel.fromJson(response);
    } catch (_) {
      return _mock.currentUser;
    }
  }

  @override
  Future<List<FamilyModel>> getMyFamilies() async {
    // Current DB schema does not have multi-family support yet; delegate to mock service
    return _mock.getMyFamilies();
  }

  @override
  Future<FamilyModel?> getCurrentFamily() async {
    final familyId = await _getCurrentFamilyId();
    if (familyId == null) return null;
    if (_supabase.auth.currentUser == null) return _mock.currentFamily;
    try {
      final response = await _supabase.from('families').select().eq('id', familyId).maybeSingle();
      if (response == null) return _mock.currentFamily;
      return FamilyModel.fromJson(response);
    } catch (_) {
      return _mock.currentFamily;
    }
  }

  @override
  Future<void> switchFamily(String familyId) async {
    await _mock.switchFamily(familyId);
  }

  @override
  Future<FamilyModel> createFamily({
    required String name,
    HierarchyRole hierarchyRole = HierarchyRole.parent,
  }) async {
    return _mock.createFamily(name: name, hierarchyRole: hierarchyRole);
  }

  @override
  Future<FamilyModel> joinFamily({
    required String joinCode,
    HierarchyRole hierarchyRole = HierarchyRole.child,
  }) async {
    return _mock.joinFamily(joinCode: joinCode, hierarchyRole: hierarchyRole);
  }

  @override
  Future<List<FamilyMemberModel>> getFamilyMembers({String? familyId}) async {
    final targetId = familyId ?? await _getCurrentFamilyId();
    if (targetId == null) return [];
    if (_supabase.auth.currentUser == null) return _mock.getFamilyMembers(familyId: targetId);
    try {
      final response = await _supabase.from('family_members').select('''
        *,
        user:users(*)
      ''').eq('family_id', targetId);
      
      return (response as List).map((e) => FamilyMemberModel.fromJson(e)).toList();
    } catch (_) {
      return _mock.getFamilyMembers(familyId: targetId);
    }
  }

  @override
  Stream<List<FamilyMemberModel>> streamFamilyMembers({String? familyId}) {
    return _mock.streamFamilyMembers(familyId: familyId);
  }

  @override
  Future<void> updateOwnerLastActive() async {
    await _mock.updateOwnerLastActive();
  }

  @override
  Future<void> updateMemberStatus(
    String targetUserId,
    MemberStatus newStatus, {
    String? familyId,
  }) async {
    await _mock.updateMemberStatus(targetUserId, newStatus, familyId: familyId);
  }

  @override
  Future<void> transferOwnership(
    String newOwnerUserId, {
    String? familyId,
  }) async {
    await _mock.transferOwnership(newOwnerUserId, familyId: familyId);
  }

  @override
  bool isTakeoverEligible({String? familyId}) {
    return _mock.isTakeoverEligible(familyId: familyId);
  }

  @override
  Future<void> claimOwnership({String? familyId}) async {
    await _mock.claimOwnership(familyId: familyId);
  }

  Future<List<ReminderModel>> getMyPendingReminders() async {
    if (_supabase.auth.currentUser == null) return _mock.getMyPendingReminders();
    try {
      final response = await _supabase.from('reminders')
          .select()
          .eq('assigned_to', currentUserId)
          .eq('status', 'PENDING');
      
      return (response as List).map((e) => ReminderModel.fromJson(e)).toList();
    } catch (_) {
      return _mock.getMyPendingReminders();
    }
  }

  @override
  Future<void> checkIn(
    String userId, {
    String? imageUrl,
    String? caption,
    String? familyId,
  }) async {
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (targetFamId == null) throw Exception('No family to check into');

    // Always run through mock logic for duplicate prevention, feeds, and reminder cancellation
    await _mock.checkIn(userId, imageUrl: imageUrl, caption: caption, familyId: targetFamId);

    // If connected to Supabase and authenticated, also mirror to current table safely
    if (_supabase.auth.currentUser != null) {
      try {
        final now = DateTime.now();
        await _supabase.from('family_members')
            .update({
              'last_check_in_at': now.toIso8601String(),
              'last_check_in_date': "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
            })
            .eq('family_id', targetFamId)
            .eq('user_id', userId);
      } catch (_) {
        // Fallback silently without throwing to keep UI responsive
      }
    }
  }

  @override
  Future<List<CheckInFeedModel>> getCheckInFeeds({String? familyId}) async {
    return _mock.getCheckInFeeds(familyId: familyId);
  }

  @override
  List<CheckInReminderItem> getSimulatedReminders({String? familyId}) {
    return _mock.getSimulatedReminders(familyId: familyId);
  }

  @override
  void cancelRemindersForUser(String userId, {String? familyId}) {
    _mock.cancelRemindersForUser(userId, familyId: familyId);
  }

  Future<void> completeReminder(String reminderId) async {
    if (_supabase.auth.currentUser == null) {
      _mock.completeReminder(reminderId);
      return;
    }
    try {
      await _supabase.from('reminders')
          .update({
            'status': 'COMPLETED',
            'completed_at': DateTime.now().toIso8601String()
          })
          .eq('id', reminderId);
    } catch (_) {
      _mock.completeReminder(reminderId);
    }
  }
}

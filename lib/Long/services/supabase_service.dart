import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';
import 'mock_data_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final _supabase = Supabase.instance.client;
  final _mock = MockDataService();

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

  Future<List<FamilyMemberModel>> getFamilyMembers() async {
    final familyId = await _getCurrentFamilyId();
    if (familyId == null) return [];
    if (_supabase.auth.currentUser == null) return _mock.members;
    try {
      final response = await _supabase.from('family_members').select('''
        *,
        user:users(*)
      ''').eq('family_id', familyId);
      
      return (response as List).map((e) => FamilyMemberModel.fromJson(e)).toList();
    } catch (_) {
      return _mock.members;
    }
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

  Future<void> checkIn(String userId) async {
    final familyId = await _getCurrentFamilyId();
    if (familyId == null) throw Exception('No family to check into');
    if (_supabase.auth.currentUser == null) {
      _mock.checkIn(userId);
      return;
    }
    try {
      final now = DateTime.now();
      await _supabase.from('family_members')
          .update({
            'last_check_in_at': now.toIso8601String(),
            'last_check_in_date': "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
          })
          .eq('family_id', familyId)
          .eq('user_id', userId);
    } catch (_) {
      _mock.checkIn(userId);
    }
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

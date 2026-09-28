import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final _supabase = Supabase.instance.client;

  String get currentUserId => _supabase.auth.currentUser?.id ?? '';

  Future<String?> _getCurrentFamilyId() async {
    if (currentUserId.isEmpty) return null;
    final response = await _supabase
        .from('family_members')
        .select('family_id')
        .eq('user_id', currentUserId)
        .maybeSingle();
    
    return response?['family_id'] as String?;
  }

  Future<bool> hasFamily() async {
    final familyId = await _getCurrentFamilyId();
    return familyId != null;
  }

  Future<UserModel> getCurrentUser() async {
    final response = await _supabase.from('users').select().eq('id', currentUserId).maybeSingle();
    if (response == null) {
      return UserModel(
        id: currentUserId,
        name: 'Unknown User',
        email: _supabase.auth.currentUser?.email ?? 'No Email',
      );
    }
    return UserModel.fromJson(response);
  }

  Future<FamilyModel?> getCurrentFamily() async {
    final familyId = await _getCurrentFamilyId();
    if (familyId == null) return null;
    final response = await _supabase.from('families').select().eq('id', familyId).maybeSingle();
    if (response == null) return null;
    return FamilyModel.fromJson(response);
  }

  Future<List<FamilyMemberModel>> getFamilyMembers() async {
    final familyId = await _getCurrentFamilyId();
    if (familyId == null) return [];
    final response = await _supabase.from('family_members').select('''
      *,
      user:users(*)
    ''').eq('family_id', familyId);
    
    return (response as List).map((e) => FamilyMemberModel.fromJson(e)).toList();
  }

  Future<List<ReminderModel>> getMyPendingReminders() async {
    final response = await _supabase.from('reminders')
        .select()
        .eq('assigned_to', currentUserId)
        .eq('status', 'PENDING');
    
    return (response as List).map((e) => ReminderModel.fromJson(e)).toList();
  }

  Future<void> checkIn(String userId) async {
    final familyId = await _getCurrentFamilyId();
    if (familyId == null) throw Exception('No family to check into');
    final now = DateTime.now();
    await _supabase.from('family_members')
        .update({
          'last_check_in_at': now.toIso8601String(),
          'last_check_in_date': "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
        })
        .eq('family_id', familyId)
        .eq('user_id', userId);
  }

  Future<void> completeReminder(String reminderId) async {
    await _supabase.from('reminders')
        .update({
          'status': 'COMPLETED',
          'completed_at': DateTime.now().toIso8601String()
        })
        .eq('id', reminderId);
  }
}

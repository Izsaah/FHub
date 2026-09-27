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

  // Force mock IDs for testing, as stale Supabase Auth sessions might return
  // a currentUser.id that doesn't exist in our mock public.users table.
  String get currentUserId => '11111111-1111-1111-1111-111111111111';
  String get currentFamilyId => 'ffffffff-ffff-ffff-ffff-ffffffffffff';

  Future<UserModel> getCurrentUser() async {
    final response = await _supabase.from('users').select().eq('id', currentUserId).single();
    return UserModel.fromJson(response);
  }

  Future<FamilyModel> getCurrentFamily() async {
    final response = await _supabase.from('families').select().eq('id', currentFamilyId).single();
    return FamilyModel.fromJson(response);
  }

  Future<List<FamilyMemberModel>> getFamilyMembers() async {
    // In Supabase, we would join the users table
    final response = await _supabase.from('family_members').select('''
      *,
      user:users(*)
    ''').eq('family_id', currentFamilyId);
    
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
    final now = DateTime.now();
    await _supabase.from('family_members')
        .update({
          'last_check_in_at': now.toIso8601String(),
          'last_check_in_date': "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
        })
        .eq('family_id', currentFamilyId)
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

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get currentUserId {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Chưa đăng nhập.');
    }

    return user.id;
  }

  Future<UserProfile?> getCurrentUserProfile() async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', currentUserId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return UserProfile.fromMap(response);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<UserProfile?> getUserById(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return UserProfile.fromMap(response);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }
}

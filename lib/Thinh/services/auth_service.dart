import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static const String androidGoogleRedirectUrl =
      'io.supabase.fhub://login-callback/';
  static const String webRedirectUrl = 'http://localhost:3000';
  static bool googleSignInInProgress = false;
  static bool passwordRecoveryInProgress = false;
  static bool passwordRecoveryNavigationHandled = false;

  static bool get isPasswordRecoveryRedirect {
    if (!kIsWeb) return false;
    return Uri.base.fragment.contains('type=recovery') ||
        Uri.base.queryParameters['type'] == 'recovery';
  }

  // Use a singleton pattern or just instance methods. Let's use standard instance methods.
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<AuthResponse> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': name,
        }, // Lưu tên người dùng vào metadata của Supabase
      );

      // Manually insert into public.users if sign up succeeded
      if (response.user != null) {
        await _supabase.from('users').insert({
          'id': response.user!.id,
          'name': name,
          'email': email,
          'avatar_type': 'default',
        });
      }

      // Registration must not leave the new account signed in.
      if (response.session != null) {
        await _supabase.auth.signOut();
      }

      return response;
    } catch (e) {
      // Có thể bọc Exception để handle lỗi ở UI
      rethrow;
    }
  }

  /// Đăng nhập bằng Email và Mật khẩu
  Future<AuthResponse> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Gửi email reset mật khẩu
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? webRedirectUrl : androidGoogleRedirectUrl,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Cập nhật mật khẩu mới (Dùng sau khi click link reset)
  Future<void> updatePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      rethrow;
    }
  }

  /// Đăng nhập bằng Google thông qua Supabase OAuth
  Future<bool> signInWithGoogle() async {
    try {
      googleSignInInProgress = true;
      // Lưu ý: Cần cấu hình Google OAuth trong Dashboard Supabase (Client ID, Secret, v.v.)
      return await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? webRedirectUrl : androidGoogleRedirectUrl,
      );
    } catch (e) {
      googleSignInInProgress = false;
      rethrow;
    }
  }

  /// Đăng xuất
  Future<void> logout() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  /// Lấy thông tin user hiện tại
  User? getCurrentUser() {
    return _supabase.auth.currentUser;
  }

  Future<bool> hasValidSession() async {
    if (_supabase.auth.currentSession == null) return false;

    try {
      await _supabase.auth.getUser();
      return true;
    } on AuthException {
      await _supabase.auth.signOut();
      return false;
    }
  }

  Future<bool> hasUserProfile(User user) async {
    final profile = await _supabase
        .from('users')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    return profile != null;
  }

  Future<void> completeGoogleRegistration({
    required User user,
    required String name,
    required String password,
  }) async {
    await _supabase.auth.updateUser(
      UserAttributes(password: password, data: {'full_name': name}),
    );
    await _supabase.from('users').upsert({
      'id': user.id,
      'name': name,
      'email': user.email,
      'avatar_type': 'default',
    }, onConflict: 'id');
  }
}

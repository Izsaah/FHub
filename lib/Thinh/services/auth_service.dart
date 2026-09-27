import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  // Use a singleton pattern or just instance methods. Let's use standard instance methods.
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Đăng ký tài khoản mới bằng Email và Mật khẩu (Kèm tên người dùng)
  Future<AuthResponse> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name}, // Lưu tên người dùng vào metadata của Supabase
      );
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
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      rethrow;
    }
  }

  /// Đăng nhập bằng Google thông qua Supabase OAuth
  Future<bool> signInWithGoogle() async {
    try {
      // Lưu ý: Cần cấu hình Google OAuth trong Dashboard Supabase (Client ID, Secret, v.v.)
      return await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
      );
    } catch (e) {
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
}

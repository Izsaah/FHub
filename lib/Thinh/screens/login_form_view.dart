import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../Long/screens/main_navigation.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_language.dart';
import 'forgot_password_view.dart';
import 'register_view.dart';

class LoginFormView extends StatefulWidget {
  const LoginFormView({super.key});

  @override
  State<LoginFormView> createState() => _LoginFormViewState();
}

class _LoginFormViewState extends State<LoginFormView> {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;
  String? _formError;

  String _t(String vietnamese, String english) =>
      AppLanguage.text(vietnamese, english);

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _emailError = email.isEmpty
          ? _t('Email là bắt buộc.', 'Email is required.')
          : !_emailPattern.hasMatch(email)
          ? _t('Vui lòng nhập email hợp lệ.', 'Enter a valid email.')
          : null;
      _passwordError = password.isEmpty
          ? _t('Mật khẩu là bắt buộc.', 'Password is required.')
          : null;
      _formError = null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _isLoading = true);
    try {
      await _authService.loginWithEmail(email: email, password: password);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _formError = _t(
            'Đăng nhập thất bại. Vui lòng kiểm tra lại thông tin.',
            'Login failed. Please check your credentials.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final started = await _authService.signInWithGoogle();
      if (mounted && !started) {
        AuthService.googleSignInInProgress = false;
        setState(
          () => _formError = _t(
            'Không thể khởi động Google Sign-In.',
            'Could not start Google Sign-In.',
          ),
        );
      }
    } catch (error) {
      AuthService.googleSignInInProgress = false;
      if (!mounted) return;
      final message =
          error is AuthException &&
              error.code == 'validation_failed' &&
              error.message.contains('provider is not enabled')
          ? _t(
              'Google Sign-In chưa được bật trong Supabase Dashboard.',
              'Google Sign-In is not enabled in Supabase Dashboard.',
            )
          : _t('Google Sign-In thất bại.', 'Google Sign-In failed.');
      setState(() => _formError = message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.brand50),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140D7A68),
                blurRadius: 30,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('Chào mừng trở về Nhà! 👋', 'Welcome home! 👋'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  'Đăng nhập để xem cập nhật của con cháu & ông bà',
                  'Sign in to see family updates',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _buildEmailField(),
              const SizedBox(height: 16),
              _buildPasswordField(),
              const SizedBox(height: 12),
              _buildRememberForgotRow(),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                _buildInlineError(_formError!),
              ],
              const SizedBox(height: 16),
              _buildLoginButton(),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildGoogleButton(),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _t('Chưa có tài khoản? ', 'No account yet? '),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterView()),
              ),
              child: Text(
                _t('Đăng ký ngay', 'Register now'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return _buildField(
      label: _t('Email', 'Email'),
      hint: _t('Nhập email của bạn...', 'Enter your email...'),
      controller: _emailController,
      errorText: _emailError,
      icon: Icons.email_outlined,
      keyboardType: TextInputType.emailAddress,
    );
  }

  Widget _buildPasswordField() {
    return _buildField(
      label: _t('Mật khẩu', 'Password'),
      hint: _t('Nhập mật khẩu...', 'Enter your password...'),
      controller: _passwordController,
      errorText: _passwordError,
      icon: Icons.lock_outline,
      obscureText: _obscurePassword,
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword ? Icons.visibility_off : Icons.visibility,
          color: Colors.grey[400],
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required String? errorText,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: Icon(icon, color: AppColors.brand700),
            suffixIcon: suffixIcon,
            errorText: errorText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.brand600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRememberForgotRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Checkbox(
              value: true,
              onChanged: (_) {},
              activeColor: AppColors.brand600,
            ),
            Text(
              _t('Ghi nhớ đăng nhập', 'Remember me'),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ForgotPasswordView()),
          ),
          child: Text(
            _t('Quên mật khẩu?', 'Forgot password?'),
            style: const TextStyle(fontSize: 12, color: AppColors.brand700),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand600,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(_t('Đăng nhập vào Tổ Ấm', 'Sign in to Family Hub')),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _handleGoogleSignIn,
      icon: const Icon(Icons.g_mobiledata),
      label: Text(_t('Đăng nhập bằng Google', 'Continue with Google')),
    );
  }

  Widget _buildInlineError(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

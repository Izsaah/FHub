import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../screens/register_view.dart';
import '../../Long/screens/main_navigation.dart';

class LoginFormView extends StatefulWidget {
  const LoginFormView({Key? key}) : super(key: key);

  @override
  State<LoginFormView> createState() => _LoginFormViewState();
}

class _LoginFormViewState extends State<LoginFormView> {
  bool _obscureText = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  final _emailController = TextEditingController(text: 'email@example.com');
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  Future<void> _handleLogin() async {
    // Validate inputs
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập Email và Mật khẩu.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      await _authService.loginWithEmail(email: email, password: password);
      if (!mounted) return;
      
      // Success workflow -> Navigate to Home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đăng nhập thất bại: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final success = await _authService.signInWithGoogle();
      if (!mounted) return;
      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigation()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đăng nhập Google thất bại: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
              _buildFormHeader(),
              const SizedBox(height: 16),
              _buildEmailField(),
              const SizedBox(height: 16),
              _buildPasswordField(),
              const SizedBox(height: 12),
              _buildRememberForgotRow(),
              const SizedBox(height: 16),
              _buildLoginBtn(),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSocialLogin(),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Chưa có tài khoản? ',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterView()),
                );
              },
              child: const Text(
                'Đăng ký ngay',
                style: TextStyle(
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

  Widget _buildFormHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chào mừng trở về Nhà! 👋',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textMain,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Đăng nhập để xem cập nhật của con cháu & ông bà',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
            hintText: 'Nhập email của bạn...',
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: const Icon(Icons.email_outlined, color: AppColors.brand700),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.brand600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Mật khẩu',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: _obscureText,
          decoration: InputDecoration(
            hintText: 'Nhập mật khẩu...',
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.brand700),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureText ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[400],
              ),
              onPressed: () {
                setState(() {
                  _obscureText = !_obscureText;
                });
              },
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
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
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _rememberMe,
                onChanged: (val) {
                  setState(() => _rememberMe = val ?? true);
                },
                activeColor: AppColors.brand600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Ghi nhớ đăng nhập',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const Text(
          'Quên mật khẩu?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.brand700,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginBtn() {
    return InkWell(
      onTap: _handleLogin,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [AppColors.brand700, AppColors.brand600, AppColors.brand700],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brand600.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _isLoading 
          ? [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
            ]
          : [
              const Icon(Icons.home, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Đăng nhập vào Tổ Ấm',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
        ),
      ),
    );
  }

  Widget _buildBiometricOption() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brand50.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.brand100),
                ),
                child: const Icon(Icons.fingerprint, size: 18, color: AppColors.brand600),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mở khóa FaceID / Vân tay',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand900,
                    ),
                  ),
                  Text(
                    'Dành cho Bố Tuấn, Mẹ Lan',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brand600,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Xác thực',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSocialLogin() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey[300])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(
                'Hoặc đăng nhập nhanh bằng',
                style: TextStyle(fontSize: 12, color: Colors.grey[400], fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(child: Divider(color: Colors.grey[300])),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            GestureDetector(
              onTap: _handleGoogleSignIn,
              child: _buildSocialBtn('Google', Colors.white, Colors.black87, Icons.g_mobiledata, isOutlined: true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSocialBtn(String text, Color bgColor, Color textColor, IconData icon, {bool isOutlined = false}) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: isOutlined ? Border.all(color: Colors.grey[300]!) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

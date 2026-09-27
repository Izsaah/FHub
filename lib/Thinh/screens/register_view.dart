import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({Key? key}) : super(key: key);

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  
  final AuthService _authService = AuthService();

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Workflow 02 Validation
    if (name.isEmpty) {
      _showError('Name is required.');
      return;
    }
    if (email.isEmpty) { // simplistic email validation
      _showError('Email is required.');
      return;
    }
    if (!email.contains('@')) {
      _showError('Valid email format is required.');
      return;
    }
    if (password.isEmpty || password.length < 6) { // generic length check
      _showError('Password must be at least 6 characters.');
      return;
    }
    if (password != confirmPassword) {
      _showError('Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.registerWithEmail(
        email: email, 
        password: password, 
        name: name
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tạo tài khoản thành công! Vui lòng đăng nhập.'), backgroundColor: Colors.green),
      );
      // Quay lại màn hình đăng nhập
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showError('Lỗi đăng ký: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo tài khoản mới', style: TextStyle(color: AppColors.brand900, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.brand700),
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Gia nhập Tổ Ấm Yêu Thương',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.brand900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tạo tài khoản để kết nối với các thành viên trong gia đình bạn.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            _buildField('Họ và Tên', 'Nguyễn Văn A', _nameController, Icons.person_outline),
            const SizedBox(height: 16),
            _buildField('Email', 'email@example.com', _emailController, Icons.email_outlined),
            const SizedBox(height: 16),
            _buildPasswordField('Mật khẩu', _passwordController, _obscurePassword, () {
              setState(() => _obscurePassword = !_obscurePassword);
            }),
            const SizedBox(height: 16),
            _buildPasswordField('Xác nhận mật khẩu', _confirmPasswordController, _obscureConfirmPassword, () {
              setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
            }),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand600,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Create Account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String hint, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: Icon(icon, color: AppColors.brand700),
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

  Widget _buildPasswordField(String label, TextEditingController controller, bool isObscure, VoidCallback toggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: isObscure,
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.brand700),
            suffixIcon: IconButton(
              icon: Icon(isObscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey[400]),
              onPressed: toggle,
            ),
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
}

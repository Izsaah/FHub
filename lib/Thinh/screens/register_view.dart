import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../theme/app_language.dart';
import '../../Long/screens/main_navigation.dart';

class RegisterView extends StatefulWidget {
  final String? initialEmail;
  final String? initialName;
  final String? initialPhotoUrl;
  final bool isGoogleRegistration;

  const RegisterView({
    super.key,
    this.initialEmail,
    this.initialName,
    this.initialPhotoUrl,
    this.isGoogleRegistration = false,
  });

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _formError;

  final AuthService _authService = AuthService();

  String _t(String vietnamese, String english) =>
      AppLanguage.text(vietnamese, english);

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      _emailController.text = widget.initialEmail!;
    }
    if (widget.initialName != null) {
      _nameController.text = widget.initialName!;
    }
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    setState(() {
      _nameError = name.isEmpty
          ? _t('Tên là bắt buộc.', 'Name is required.')
          : name.length > 100
          ? _t(
              'Tên không được quá 100 ký tự.',
              'Name must be 100 characters or fewer.',
            )
          : null;
      _emailError = email.isEmpty
          ? _t('Email là bắt buộc.', 'Email is required.')
          : !_emailPattern.hasMatch(email)
          ? _t('Vui lòng nhập email hợp lệ.', 'Enter a valid email.')
          : null;
      _passwordError = (password.isEmpty || password.length < 6)
          ? _t(
              'Mật khẩu phải có ít nhất 6 ký tự.',
              'Password must be at least 6 characters.',
            )
          : null;
      _confirmPasswordError = password != confirmPassword
          ? _t('Mật khẩu xác nhận không khớp.', 'Passwords do not match.')
          : null;
      _formError = null;
    });
    if (_nameError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmPasswordError != null) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.isGoogleRegistration) {
        final user = _authService.getCurrentUser();
        if (user == null) {
          setState(
            () => _formError = _t(
              'Google session đã hết hạn. Vui lòng đăng nhập lại.',
              'Google session expired. Please sign in again.',
            ),
          );
          return;
        }
        await _authService.completeGoogleRegistration(
          user: user,
          name: name,
          password: password,
        );
      } else {
        await _authService.registerWithEmail(
          email: email,
          password: password,
          name: name,
        );
      }

      if (!mounted) return;
      if (widget.isGoogleRegistration) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigation()),
          (route) => false,
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      if (!mounted) return;
      String errorMsg = _t(
        'Đăng ký thất bại. Vui lòng thử lại.',
        'Registration failed. Please try again.',
      );
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'email-already-in-use':
            errorMsg = _t('Email này đã được sử dụng.', 'Email already in use.');
            break;
          case 'invalid-email':
            errorMsg = _t('Email không hợp lệ.', 'Invalid email address.');
            break;
          case 'operation-not-allowed':
            errorMsg = _t(
              'Chưa bật đăng nhập Email/Password trong Firebase Console (Authentication > Sign-in method).',
              'Email/Password sign-in is disabled in Firebase Console.',
            );
            break;
          case 'weak-password':
            errorMsg = _t('Mật khẩu quá yếu (tối thiểu 6 ký tự).', 'Password is too weak.');
            break;
          default:
            errorMsg = e.message ?? errorMsg;
        }
      } else if (e is FirebaseException) {
        if (e.code == 'permission-denied') {
          errorMsg = _t(
            'Lỗi phân quyền Firestore. Vui lòng kiểm tra Firestore Rules trên Firebase Console.',
            'Firestore permission denied. Check Firestore security rules.',
          );
        } else {
          errorMsg = e.message ?? errorMsg;
        }
      } else {
        final err = e.toString();
        if (err.contains('network') || err.contains('failed to fetch')) {
          errorMsg = _t('Lỗi kết nối mạng. Vui lòng thử lại.', 'Network error. Please try again.');
        } else {
          errorMsg = err.replaceFirst('Exception: ', '');
        }
      }
      setState(() => _formError = errorMsg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('Tạo tài khoản mới', 'Create account'),
          style: TextStyle(color: AppColors.brand900, fontSize: 16),
        ),
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
            if (widget.isGoogleRegistration) ...[
              Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.brand600,
                              width: 3.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.brand900.withValues(alpha: 0.1),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: (widget.initialPhotoUrl != null &&
                                    widget.initialPhotoUrl!.isNotEmpty)
                                ? Image.network(
                                    widget.initialPhotoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Icon(
                                      Icons.person,
                                      size: 52,
                                      color: AppColors.brand700,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person,
                                    size: 52,
                                    color: AppColors.brand700,
                                  ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/google-logo.webp',
                            width: 18,
                            height: 18,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.check_circle, size: 18, color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brand50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.brand200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/google-logo.webp',
                            width: 14,
                            height: 14,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _t(
                              'Tài khoản Google đã kết nối',
                              'Google Account Connected',
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.brand800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              widget.isGoogleRegistration
                  ? _t('Hoàn tất thông tin cá nhân', 'Complete your profile')
                  : _t('Gia nhập Tổ Ấm Yêu Thương', 'Join A Loving Home'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.brand900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isGoogleRegistration
                  ? _t(
                      'Xác nhận thông tin từ Google để vào ứng dụng ngay.',
                      'Confirm your Google information to enter the app.',
                    )
                  : _t(
                      'Tạo tài khoản để kết nối với các thành viên trong gia đình bạn.',
                      'Create an account to connect with your family.',
                    ),
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            _buildField(
              _t('Họ và Tên', 'Full name'),
              _t('Nguyễn Văn A', 'Jane Doe'),
              _nameController,
              Icons.person_outline,
            ),
            const SizedBox(height: 16),
            _buildField(
              _t('Email', 'Email'),
              'email@example.com',
              _emailController,
              Icons.email_outlined,
            ),
            const SizedBox(height: 16),
            _buildPasswordField(
              _t('Mật khẩu', 'Password'),
              _passwordController,
              _obscurePassword,
              () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            const SizedBox(height: 16),
            _buildPasswordField(
              _t('Xác nhận mật khẩu', 'Confirm password'),
              _confirmPasswordController,
              _obscureConfirmPassword,
              () {
                setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                );
              },
            ),
            const SizedBox(height: 32),
            if (_formError != null) ...[
              _buildInlineError(_formError!),
              const SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed: _isLoading ? null : _handleRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand600,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      widget.isGoogleRegistration
                          ? _t('Vào ứng dụng ngay', 'Enter App Now')
                          : _t('Tạo tài khoản', 'Create Account'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    String hint,
    TextEditingController controller,
    IconData icon,
  ) {
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
          readOnly:
              widget.isGoogleRegistration && controller == _emailController,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: Icon(icon, color: AppColors.brand700),
            errorText: controller == _nameController ? _nameError : _emailError,
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

  Widget _buildPasswordField(
    String label,
    TextEditingController controller,
    bool isObscure,
    VoidCallback toggle,
  ) {
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
          obscureText: isObscure,
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: AppColors.brand700,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                isObscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[400],
              ),
              onPressed: toggle,
            ),
            errorText: controller == _passwordController
                ? _passwordError
                : _confirmPasswordError,
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

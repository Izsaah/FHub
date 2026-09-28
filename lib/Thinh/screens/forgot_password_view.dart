import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../theme/app_language.dart';

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  final _emailController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _emailError;
  String? _formError;

  String _t(String vietnamese, String english) =>
      AppLanguage.text(vietnamese, english);

  Future<void> _handleResetPassword() async {
    final email = _emailController.text.trim();
    setState(() {
      _emailError = email.isEmpty
          ? _t('Email là bắt buộc.', 'Email is required.')
          : !_emailPattern.hasMatch(email)
          ? _t('Vui lòng nhập email hợp lệ.', 'Enter a valid email.')
          : null;
      _formError = null;
    });
    if (_emailError != null) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.resetPassword(email);
      if (!mounted) return;
      setState(() => _emailSent = true);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _formError = _t(
          'Không thể gửi liên kết. Vui lòng thử lại.',
          'Could not send the link. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('Quên mật khẩu', 'Forgot password'),
          style: TextStyle(color: AppColors.brand900, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.brand700),
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              _emailSent ? Icons.mark_email_read : Icons.lock_reset,
              size: 64,
              color: AppColors.brand600,
            ),
            const SizedBox(height: 24),
            Text(
              _emailSent
                  ? _t('Kiểm tra Email', 'Check your email')
                  : _t('Lấy lại mật khẩu', 'Reset password'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.brand900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _emailSent
                  ? _t(
                      'Chúng tôi đã gửi Link đến email của bạn.\n\nVui lòng mở email và click vào liên kết đó để thiết lập mật khẩu mới.',
                      'We sent a link to your email.\n\nOpen it to set a new password.',
                    )
                  : _t(
                      'Nhập email của bạn và chúng tôi sẽ gửi một liên kết để đặt lại mật khẩu.',
                      'Enter your email and we will send a password reset link.',
                    ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),

            if (!_emailSent) ...[
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: _t('Nhập email của bạn...', 'Enter your email...'),
                  prefixIcon: const Icon(
                    Icons.email_outlined,
                    color: AppColors.brand700,
                  ),
                  errorText: _emailError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.brand600),
                  ),
                ),
              ),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                _buildInlineError(_formError!),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleResetPassword,
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
                        _t('Gửi liên kết khôi phục', 'Send reset link'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                label: Text(
                  _t('Quay lại Đăng nhập', 'Back to Login'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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

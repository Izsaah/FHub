import 'package:firebase_auth/firebase_auth.dart';
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
      debugPrint('resetPassword error: $e');
      if (!mounted) return;
      String errorMsg = _t(
        'Không thể gửi liên kết. Vui lòng thử lại.',
        'Could not send the link. Please try again.',
      );
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            errorMsg = _t(
              'Không tìm thấy tài khoản với email này trong hệ thống. Vui lòng kiểm tra lại hoặc tạo tài khoản mới.',
              'No account found with this email. Please check or register a new account.',
            );
            break;
          case 'invalid-email':
            errorMsg = _t(
              'Địa chỉ email không đúng định dạng.',
              'Invalid email address format.',
            );
            break;
          case 'too-many-requests':
            errorMsg = _t(
              'Bạn đã gửi quá nhiều yêu cầu. Vui lòng đợi vài phút rồi thử lại.',
              'Too many requests. Please wait a few minutes and try again.',
            );
            break;
          case 'operation-not-allowed':
            errorMsg = _t(
              'Phương thức đăng nhập bằng Email/Password chưa được bật trên Firebase Console (Authentication > Sign-in method).',
              'Email/Password sign-in is disabled in Firebase Console.',
            );
            break;
          default:
            errorMsg = e.message ?? errorMsg;
        }
      } else {
        errorMsg = e.toString().replaceFirst('Exception: ', '');
      }
      setState(() => _formError = errorMsg);
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
                      'Chúng tôi đã gửi link đặt lại mật khẩu đến:\n${_emailController.text.trim()}\n\n'
                      '📌 Lưu ý quan trọng:\n'
                      '1. Kiểm tra cả hộp thư Spam / Thư rác hoặc tab Quảng cáo.\n'
                      '2. Nếu tài khoản chưa từng đăng ký, Firebase sẽ không gửi thư để bảo mật.\n'
                      '3. Nhấp vào liên kết trong email để đặt mật khẩu mới, sau đó quay lại app đăng nhập.',
                      'We sent a password reset link to:\n${_emailController.text.trim()}\n\n'
                      'Important notes:\n'
                      '1. Check your Spam/Junk or Promotions folder.\n'
                      '2. If the email is not registered yet, Firebase will not send an email.\n'
                      '3. Click the link in the email to set a new password, then log in here.',
                    )
                  : _t(
                      'Nhập email của bạn và chúng tôi sẽ gửi một liên kết để đặt lại mật khẩu.',
                      'Enter your email and we will send a password reset link.',
                    ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
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
                        style: const TextStyle(
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
                  style: const TextStyle(
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
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() {
                    _emailSent = false;
                    _formError = null;
                  });
                },
                child: Text(
                  _t('Gửi lại hoặc thử email khác', 'Resend or try another email'),
                  style: const TextStyle(
                    color: AppColors.brand600,
                    fontWeight: FontWeight.w600,
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

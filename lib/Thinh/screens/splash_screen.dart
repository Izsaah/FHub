import 'package:flutter/material.dart';

import '../../Long/screens/main_navigation.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_language.dart';
import 'auth_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _checkSessionAndNavigate();
  }

  void _setupAnimation() {
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();
  }

  /// Tự động kiểm tra phiên đăng nhập (Auto-login) qua FirebaseAuth
  /// AC2: Đóng hoàn toàn ứng dụng và mở lại phải tự động vào thẳng màn hình chính nếu phiên đăng nhập còn hạn
  Future<void> _checkSessionAndNavigate() async {
    // Đảm bảo hiệu ứng splash hiển thị mượt mà
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    final bool hasValidSession = await _authService.hasValidSession();
    if (!mounted) return;

    if (hasValidSession) {
      // Phiên hợp lệ -> Vào thẳng Home
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const MainNavigation(),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } else {
      // Không hợp lệ hoặc chưa có -> Xóa phiên cũ và chuyển tới màn hình Login
      await _authService.logout();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const AuthScreen(),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.brand50,
              Color(0xFFF7FAF8),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Animated Logo & Icon
              ScaleTransition(
                scale: _scaleAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.brand600,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brand600.withValues(alpha: 0.35),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 52,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Title
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    Text(
                      AppLanguage.text('Tổ Ấm Yêu Thương', 'Family Hub'),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMain,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLanguage.text(
                        'Bình yên từng khoảnh khắc • Gắn kết gia đình',
                        'Peace in every moment • Connecting families',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // Loading indicator
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.brand600),
                ),
              ),

              const SizedBox(height: 16),
              Text(
                AppLanguage.text(
                  'Đang đồng bộ phiên đăng nhập...',
                  'Checking session...',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

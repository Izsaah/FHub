import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_language.dart';
import 'login_form_view.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, isEnglish, child) => Scaffold(
        backgroundColor: Colors.white,
        body: Container(
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
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBar(),
                    const SizedBox(height: 12),
                    _buildHeroSection(),
                    const SizedBox(height: 24),

                    // Login card đầy đủ: Email/Password + Google + Register + Forgot Password
                    const LoginFormView(),

                    const SizedBox(height: 24),
                    _buildFooter(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.brand600,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand600.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLanguage.text('Gia Đình Việt', 'Family Hub'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand900,
                    ),
                  ),
                  Text(
                    AppLanguage.text(
                      'Bình yên từng khoảnh khắc',
                      'Peace in every moment',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              _buildLangButton('VI', false),
              const SizedBox(width: 6),
              _buildLangButton('EN', true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLangButton(String label, bool isEnglishValue) {
    final bool isActive = AppLanguage.isEnglish.value == isEnglishValue;
    return GestureDetector(
      onTap: () => AppLanguage.isEnglish.value = isEnglishValue,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.brand600 : AppColors.brand50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppColors.brand600 : AppColors.brand200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : AppColors.brand700,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.brand100),
        image: const DecorationImage(
          image: NetworkImage(
            'https://lh3.googleusercontent.com/aida-public/AB6AXuBkvMLWdv3MazKdLh0fZtr8WdM5jGy9kYRmvBvAx2qWRwnjzX4B8d39Zk2qJQIU7t9Z2Exi3MKp1Q7F5M2Zs-pPiLnmB-LP1xJQ6gelEQ591McE1WeCrmdWUP3flWwYceRb7ARmGL9tTTT4b2GqLQSM7jKXE0MVWWWdy3O4BFCj-rpFeJap2VYAwnmL9Mb82GItxp7xXJDjJkcVp8t7I4EtbxOBSBUWJWIn28fqXmxLaLRBrZSYhTdC',
          ),
          fit: BoxFit.cover,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140D7A68),
            blurRadius: 30,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  AppColors.brand900.withValues(alpha: 0.92),
                  AppColors.brand900.withValues(alpha: 0.4),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 18,
            right: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentAmber,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.home_filled, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        AppLanguage.text(
                          'Phiên bản Gia Đình',
                          'Family Edition',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLanguage.text('Tổ Ấm Yêu Thương', 'A Loving Home'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  AppLanguage.text(
                    'Gắn kết yêu thương • Sẻ chia từng khoảnh khắc',
                    'Connect with love • Share every moment',
                  ),
                  style: TextStyle(
                    color: AppColors.brand100.withValues(alpha: 0.95),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.brand100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined,
                  color: AppColors.brand600, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  AppLanguage.text(
                    'Dữ liệu định vị & sức khỏe gia đình được mã hóa an toàn',
                    'Family health & location data are encrypted and safe',
                  ),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.brand800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLanguage.text('Chính sách bảo mật', 'Privacy Policy'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('•', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Text(
              AppLanguage.text('Điều khoản dịch vụ', 'Terms of Service'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('•', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Text(
              AppLanguage.text(
                '© Tổ Ấm Yêu Thương 2026',
                '© Family Hub 2026',
              ),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }
}

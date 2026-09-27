import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'login_form_view.dart';
import 'join_family_view.dart';
import 'register_view.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // In HTML it's a gradient, let's use a solid close to it
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.brand50,
              Color(0xFFf7faf8),
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
                  const SizedBox(height: 20),
                  // Content based on tab
                  const LoginFormView(),
                  
                  const SizedBox(height: 20),
                  _buildFooter(),
                  const SizedBox(height: 20),
                ],
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.brand600,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand600.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.favorite, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 8),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gia Đình Việt',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand600,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Text(
                    'Bình yên từng khoảnh khắc',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.brand100),
            ),
            child: Row(
              children: [
                _buildLangBtn('VI', true),
                _buildLangBtn('EN', false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLangBtn(String lang, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: isActive
          ? BoxDecoration(
              color: AppColors.brand600,
              borderRadius: BorderRadius.circular(16),
            )
          : null,
      child: Text(
        lang,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.white : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.brand100),
        image: const DecorationImage(
          image: NetworkImage(
              'https://lh3.googleusercontent.com/aida-public/AB6AXuBkvMLWdv3MazKdLh0fZtr8WdM5jGy9kYRmvBvAx2qWRwnjzX4B8d39Zk2qJQIU7t9Z2Exi3MKp1Q7F5M2Zs-pPiLnmB-LP1xJQ6gelEQ591McE1WeCrmdWUP3flWwYceRb7ARmGL9tTTT4b2GqLQSM7jKXE0MVWWWdy3O4BFCj-rpFeJap2VYAwnmL9Mb82GItxp7xXJDjJkcVp8t7I4EtbxOBSBUWJWIn28fqXmxLaLRBrZSYhTdC'),
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
                  AppColors.brand900.withOpacity(0.9),
                  AppColors.brand900.withOpacity(0.4),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 14,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentAmber,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_filled, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Phiên bản Gia Đình',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tổ Ấm Yêu Thương',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Gắn kết yêu thương • Sẻ chia từng khoảnh khắc',
                  style: TextStyle(
                    color: AppColors.brand100.withOpacity(0.9),
                    fontSize: 12,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.brand100),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.security, color: AppColors.brand600, size: 14),
              SizedBox(width: 6),
              Text(
                'Vị trí & dữ liệu sức khỏe gia đình được bảo mật 100%',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.brand800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Chính sách bảo mật', style: TextStyle(fontSize: 10, color: Colors.grey)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('•', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ),
            Text('Điều khoản dịch vụ', style: TextStyle(fontSize: 10, color: Colors.grey)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('•', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ),
            Text('© Tổ Ấm Yêu Thương 2024', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        )
      ],
    );
  }
}

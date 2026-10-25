import 'package:flutter/material.dart';

import '../../widgets/custom_app_bar.dart';
import '../../../Danh/danh_payment_entry.dart';
import '../../../Khoa/services/family_service.dart';
import '../../../Thinh/services/auth_service.dart';

class CreateFamilyScreen extends StatefulWidget {
  const CreateFamilyScreen({super.key});

  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  final _nameController = TextEditingController();
  final _familyService = FamilyService();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên gia đình!')),
      );
      return;
    }
    if (name.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tên gia đình cần ít nhất 3 ký tự.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final family = await _familyService.createFamily(name: name);
      DanhPaymentEntry.onFamilyCreatedOrJoined(family.id);

      // Update user's familyId in Firestore
      try {
        await AuthService().updateLazyOnboardingInfo(
          role: 'PARENT',
          familyId: family.id,
        );
      } catch (e) {
        debugPrint('Update lazy onboarding error: $e');
      }

      if (!mounted) return;
      Navigator.pop(context, true); // Return true to signal refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            DanhPaymentEntry.service.isPremium
                ? 'Tạo gia đình "${family.name}" thành công! Gói Premium đã kích hoạt (10 người).'
                : 'Tạo gia đình "${family.name}" thành công! Mã mời: ${family.joinCode}',
          ),
          backgroundColor: const Color(0xFF005F50),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Create Family'),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Family Name',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter family name',
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF005F50),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isLoading ? null : _handleCreate,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Create', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

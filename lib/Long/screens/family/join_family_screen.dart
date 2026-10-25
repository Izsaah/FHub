import 'package:flutter/material.dart';

import '../../widgets/custom_app_bar.dart';
import '../../../Danh/danh_payment_entry.dart';
import '../../../Khoa/services/family_service.dart';
import '../../../Thinh/services/auth_service.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _codeController = TextEditingController();
  final _familyService = FamilyService();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã gia đình!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // First check if the family exists
      final family = await _familyService.findFamilyByJoinCode(code);
      if (family == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không tìm thấy gia đình với mã "$code".'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Check member limit via DanhPaymentEntry
      final existingMembers = await _familyService.getFamilyMembers(family.id);
      final activeMemberCount =
          existingMembers.where((m) => m.isActive).length;

      if (!DanhPaymentEntry.canAddMember(activeMemberCount)) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Gia Đình Đã Đầy'),
            content: Text(
              DanhPaymentEntry.getMemberLimitMessage(activeMemberCount),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005F50),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  DanhPaymentEntry.openPremiumPlans(context);
                },
                child: const Text('Nâng cấp Premium'),
              ),
            ],
          ),
        );
        return;
      }

      // Actually join the family in Firestore
      final joinedFamily = await _familyService.joinFamily(
        joinCode: code,
        role: 'PARENT',
      );

      DanhPaymentEntry.onFamilyCreatedOrJoined(joinedFamily.id);

      // Update user's familyId in Firestore
      try {
        await AuthService().updateLazyOnboardingInfo(
          role: 'PARENT',
          familyId: joinedFamily.id,
        );
      } catch (e) {
        debugPrint('Update lazy onboarding error: $e');
      }

      if (!mounted) return;
      Navigator.pop(context, true); // Return true to signal refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gia nhập "${joinedFamily.name}" thành công!'),
          backgroundColor: const Color(0xFF005F50),
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
      appBar: const CustomAppBar(title: 'Gia Nhập Tổ Ấm'),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Mã Tổ Ấm (Family Code)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Nhập mã gia đình (VD: ABCD-1234)',
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
              onPressed: _isLoading ? null : _handleJoin,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Gia nhập', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

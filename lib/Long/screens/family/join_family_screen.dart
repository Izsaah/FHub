import 'package:flutter/material.dart';

import '../../widgets/custom_app_bar.dart';
import '../../models/hierarchy_role.dart';
import '../../services/family_state_manager.dart';
import '../../../Danh/danh_payment_entry.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _codeController = TextEditingController();
  HierarchyRole _selectedRole = HierarchyRole.child;
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã gia đình 6 ký tự!')),
      );
      return;
    }

    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mã gia đình phải gồm đúng 6 ký tự (VD: A8K29D)!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final service = FamilyStateManager().service;
      final joinedFamily = await service.joinFamily(
        joinCode: code,
        hierarchyRole: _selectedRole,
      );

      // Check payment limit if needed
      final members = await service.getFamilyMembers(familyId: joinedFamily.id);
      if (!DanhPaymentEntry.canAddMember(members.length)) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Gia Đình Đã Đầy'),
            content: Text(
              DanhPaymentEntry.getMemberLimitMessage(members.length),
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

      DanhPaymentEntry.onFamilyCreatedOrJoined(joinedFamily.id);
      await FamilyStateManager().reload();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gia nhập tổ ấm "${joinedFamily.name}" thành công!'),
          backgroundColor: const Color(0xFF005F50),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const CustomAppBar(title: 'Gia Nhập Tổ Ấm'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Mã Tổ Ấm (6 Ký tự)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF151D1B),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                fontSize: 20,
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
                color: Color(0xFF005F50),
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'VD: A8K29D',
                hintStyle: const TextStyle(letterSpacing: 1, fontSize: 16, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFFF7FAF9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFBDC9C4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: const Color(0xFFBDC9C4).withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Vai vế của bạn trong gia đình này:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF151D1B),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: HierarchyRole.values.map((role) {
                final isSelected = _selectedRole == role;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: InkWell(
                      onTap: () => setState(() => _selectedRole = role),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF005F50)
                              : const Color(0xFFEDF5F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF005F50)
                                : const Color(0xFFBDC9C4),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          role.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF2B3633),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF005F50),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isLoading ? null : _handleJoin,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Gia Nhập Ngay',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

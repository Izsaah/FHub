import 'package:flutter/material.dart';

import '../../widgets/custom_app_bar.dart';
import '../../../Danh/danh_payment_entry.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _handleJoin() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã gia đình!')),
      );
      return;
    }

    // Giả lập kiểm tra số lượng thành viên hiện tại của gia đình cần gia nhập
    // Ví dụ gia đình đang có 4/4 người (Gói Free)
    const mockTargetFamilyMemberCount = 3; // Ví dụ gia đình đang có 3 người
    if (!DanhPaymentEntry.canAddMember(mockTargetFamilyMemberCount)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Gia Đình Đã Đầy'),
          content: Text(
            DanhPaymentEntry.getMemberLimitMessage(mockTargetFamilyMemberCount),
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

    DanhPaymentEntry.onFamilyCreatedOrJoined('f_joined');
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gia nhập tổ ấm thành công!'),
        backgroundColor: Color(0xFF005F50),
      ),
    );
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
                hintText: 'Nhập mã 6 ký tự (VD: A8K29D)',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF005F50),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _handleJoin,
              child: const Text('Gia nhập', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../widgets/custom_app_bar.dart';
import '../../../Danh/danh_payment_entry.dart';

class CreateFamilyScreen extends StatelessWidget {
  const CreateFamilyScreen({super.key});

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
            const TextField(
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter family name',
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
              onPressed: () {
                final newFamilyId = 'f_${DateTime.now().millisecondsSinceEpoch}';
                DanhPaymentEntry.onFamilyCreatedOrJoined(newFamilyId);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      DanhPaymentEntry.service.isPremium
                          ? 'Tạo gia đình thành công! Gói Premium của bạn đã được kích hoạt cho tổ ấm mới (10 người).'
                          : 'Tạo gia đình thành công!',
                    ),
                    backgroundColor: const Color(0xFF005F50),
                  ),
                );
              },
              child: const Text('Create', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

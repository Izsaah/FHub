import 'package:flutter/material.dart';

/// Trạng thái khi chưa có bất kỳ lời nhắc nào trong gia đình
class ReminderEmptyState extends StatelessWidget {
  final VoidCallback onCreatePressed;

  const ReminderEmptyState({
    super.key,
    required this.onCreatePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F0EC),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(
                Icons.notifications_none_outlined,
                size: 40,
                color: Color(0xFF0D7A68),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No reminders yet.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF151D1B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a reminder to help your family stay organized and connected.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6E7A75),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D7A68),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: const Icon(Icons.add),
              label: const Text(
                'Create Reminder',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: onCreatePressed,
            ),
          ],
        ),
      ),
    );
  }
}

/// Trạng thái khi không có việc nào trong ngày đang được chọn trên lịch
class ReminderDayEmptyState extends StatelessWidget {
  final String dateStr;
  final VoidCallback onShowAllPressed;

  const ReminderDayEmptyState({
    super.key,
    required this.dateStr,
    required this.onShowAllPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F0EC),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.event_available_outlined,
                size: 32,
                color: Color(0xFF0D7A68),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có việc cho ngày $dateStr',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF151D1B),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Nhấn "Tạo lời nhắc" để thêm mới, hoặc xem "Tất cả" trên lịch.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6E7A75),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              icon: const Icon(Icons.list_alt, color: Color(0xFF0D7A68)),
              label: const Text(
                'Xem tất cả nhắc nhở',
                style: TextStyle(
                  color: Color(0xFF0D7A68),
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: onShowAllPressed,
            ),
          ],
        ),
      ),
    );
  }
}

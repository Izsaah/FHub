import 'package:flutter/material.dart';
import '../../Thinh/theme/app_language.dart';

/// Trạng thái khi chưa có bất kỳ lời nhắc nào trong gia đình
class ReminderEmptyState extends StatelessWidget {
  final VoidCallback onCreatePressed;

  const ReminderEmptyState({
    super.key,
    required this.onCreatePressed,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F0EC),
                    borderRadius: BorderRadius.circular(34),
                  ),
                  child: const Icon(
                    Icons.notifications_none_outlined,
                    size: 34,
                    color: Color(0xFF0D7A68),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppLanguage.text('Chưa có lời nhắc nào.', 'No reminders yet.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF151D1B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLanguage.text(
                    'Hãy tạo lời nhắc để giúp gia đình bạn phân chia việc nhà ngăn nắp và gắn kết hơn.',
                    'Create reminders to help your family organize chores and stay connected.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF6E7A75),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D7A68),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(
                    AppLanguage.text('Tạo lời nhắc mới', 'Create new reminder'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: onCreatePressed,
                ),
              ],
            ),
          ),
        );
      },
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
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 110),
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
                  AppLanguage.text(
                    'Chưa có việc cho ngày $dateStr',
                    'No tasks for $dateStr',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF151D1B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLanguage.text(
                    'Nhấn "Tạo lời nhắc" để thêm mới, hoặc xem "Tất cả" trên lịch.',
                    'Tap "Create reminder" to add, or view "All" on calendar.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6E7A75),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  icon: const Icon(Icons.list_alt, color: Color(0xFF0D7A68)),
                  label: Text(
                    AppLanguage.text('Xem tất cả nhắc nhở', 'View all reminders'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
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
      },
    );
  }
}

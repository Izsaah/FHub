import 'package:flutter/material.dart';
import '../../models/reminder_model.dart';
import '../../widgets/monthly_calendar_grid.dart';

/// Widget chuyên dụng cho Calendar View: hiển thị lưới tháng trực quan,
/// số lượng chấm màu của từng ngày, và thanh điều khiển bộ lọc ngày.
class ReminderCalendarView extends StatelessWidget {
  final DateTime currentMonth;
  final DateTime selectedDate;
  final bool showAll;
  final List<ReminderModel> reminders;
  final String selectedDateFormatted;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onMonthChanged;
  final VoidCallback onShowAllPressed;

  const ReminderCalendarView({
    super.key,
    required this.currentMonth,
    required this.selectedDate,
    required this.showAll,
    required this.reminders,
    required this.selectedDateFormatted,
    required this.onDateSelected,
    required this.onMonthChanged,
    required this.onShowAllPressed,
  });

  static const Color primaryColor = Color(0xFF005F50);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MonthlyCalendarGrid(
          currentMonth: currentMonth,
          selectedDate: selectedDate,
          reminders: reminders,
          onDateSelected: onDateSelected,
          onMonthChanged: onMonthChanged,
        ),
        if (!showAll)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.filter_alt_outlined,
                      size: 16,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Đang lọc theo ngày: $selectedDateFormatted',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: onShowAllPressed,
                  child: const Text(
                    'Xem tất cả',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

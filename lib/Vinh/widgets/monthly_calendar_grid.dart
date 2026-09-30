import 'package:flutter/material.dart';
import '../models/reminder_model.dart';

class MonthlyCalendarGrid extends StatefulWidget {
  final DateTime currentMonth;
  final DateTime selectedDate;
  final List<ReminderModel> reminders;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onMonthChanged;

  const MonthlyCalendarGrid({
    super.key,
    required this.currentMonth,
    required this.selectedDate,
    required this.reminders,
    required this.onDateSelected,
    required this.onMonthChanged,
  });

  @override
  State<MonthlyCalendarGrid> createState() => _MonthlyCalendarGridState();
}

class _MonthlyCalendarGridState extends State<MonthlyCalendarGrid> {
  String _getMonthName(int month) {
    const months = [
      'Tháng 1',
      'Tháng 2',
      'Tháng 3',
      'Tháng 4',
      'Tháng 5',
      'Tháng 6',
      'Tháng 7',
      'Tháng 8',
      'Tháng 9',
      'Tháng 10',
      'Tháng 11',
      'Tháng 12'
    ];
    return months[month - 1];
  }

  void _prevMonth() {
    final prev = DateTime(widget.currentMonth.year, widget.currentMonth.month - 1, 1);
    widget.onMonthChanged(prev);
  }

  void _nextMonth() {
    final next = DateTime(widget.currentMonth.year, widget.currentMonth.month + 1, 1);
    widget.onMonthChanged(next);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<ReminderModel> _getRemindersForDay(DateTime day) {
    final dayStr =
        '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
    return widget.reminders.where((r) => r.date == dayStr).toList();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    const textPrimary = Color(0xFF151D1B);
    const textMuted = Color(0xFF6E7A75);
    final today = DateTime.now();

    final firstDayOfMonth =
        DateTime(widget.currentMonth.year, widget.currentMonth.month, 1);
    final daysInMonth =
        DateTime(widget.currentMonth.year, widget.currentMonth.month + 1, 0).day;
    // Weekday: Monday is 1, Sunday is 7
    final firstWeekday = firstDayOfMonth.weekday; // 1 to 7

    const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2EAE7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0D7A68),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Month navigation bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_getMonthName(widget.currentMonth.month)} ${widget.currentMonth.year}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 22),
                    color: textPrimary,
                    visualDensity: VisualDensity.compact,
                    onPressed: _prevMonth,
                  ),
                  IconButton(
                    icon: const Icon(Icons.today, size: 20),
                    tooltip: 'Về hôm nay',
                    color: primaryColor,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final now = DateTime.now();
                      widget.onMonthChanged(DateTime(now.year, now.month, 1));
                      widget.onDateSelected(now);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 22),
                    color: textPrimary,
                    visualDensity: VisualDensity.compact,
                    onPressed: _nextMonth,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Weekday header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((w) {
              return Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Month days grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: (firstWeekday - 1) + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              if (index < firstWeekday - 1) {
                return const SizedBox.shrink();
              }

              final dayNum = index - (firstWeekday - 1) + 1;
              final dayDate = DateTime(
                  widget.currentMonth.year, widget.currentMonth.month, dayNum);

              final isSelected = _isSameDay(dayDate, widget.selectedDate);
              final isToday = _isSameDay(dayDate, today);

              final dayReminders = _getRemindersForDay(dayDate);
              final hasPending = dayReminders.any((r) => r.isPending);
              final hasCompleted = dayReminders.any((r) => r.isCompleted);

              return InkWell(
                onTap: () => widget.onDateSelected(dayDate),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryColor
                        : (isToday ? const Color(0xFFE7F5F2) : Colors.transparent),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? primaryColor
                          : (isToday ? primaryColor : Colors.transparent),
                      width: isToday && !isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected || isToday
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isToday ? primaryColor : textPrimary),
                        ),
                      ),
                      if (dayReminders.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasPending)
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFF49D37)
                                      : const Color(0xFF0D7A68),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (hasPending && hasCompleted)
                              const SizedBox(width: 2),
                            if (hasCompleted)
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white70
                                      : const Color(0xFFBDC9C4),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

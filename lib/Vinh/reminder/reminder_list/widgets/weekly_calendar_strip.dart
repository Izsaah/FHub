import 'package:flutter/material.dart';
import '../../models/reminder_model.dart';

class WeeklyCalendarStrip extends StatefulWidget {
  final DateTime selectedDate;
  final bool showAll;
  final List<ReminderModel> reminders;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onSelectAll;

  const WeeklyCalendarStrip({
    super.key,
    required this.selectedDate,
    required this.showAll,
    required this.reminders,
    required this.onDateSelected,
    required this.onSelectAll,
  });

  @override
  State<WeeklyCalendarStrip> createState() => _WeeklyCalendarStripState();
}

class _WeeklyCalendarStripState extends State<WeeklyCalendarStrip> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _calculateWeekStart(widget.selectedDate);
  }

  @override
  void didUpdateWidget(covariant WeeklyCalendarStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showAll &&
        (widget.selectedDate.isBefore(_weekStart) ||
            widget.selectedDate.isAfter(_weekStart.add(const Duration(days: 6))))) {
      _weekStart = _calculateWeekStart(widget.selectedDate);
    }
  }

  DateTime _calculateWeekStart(DateTime date) {
    // Week starts on Monday (1)
    final diff = date.weekday - 1;
    final monday = date.subtract(Duration(days: diff));
    return DateTime(monday.year, monday.month, monday.day);
  }

  void _previousWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _weekStart = _calculateWeekStart(now);
    });
    widget.onDateSelected(DateTime(now.year, now.month, now.day));
  }

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

  String _getDayOfWeek(int weekday) {
    const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return days[weekday - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Checks if a day has reminders in the list
  List<ReminderModel> _getRemindersForDay(DateTime day) {
    final dayStr =
        '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
    return widget.reminders.where((r) => r.date == dayStr).toList();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    const textPrimary = Color(0xFF151D1B);
    final today = DateTime.now();

    final weekDays = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final currentMonthLabel =
        '${_getMonthName(_weekStart.month)}, ${_weekStart.year}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          // Month Header & Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_month,
                      color: primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    currentMonthLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // "Tất cả" chip
                  InkWell(
                    onTap: widget.onSelectAll,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.showAll
                            ? primaryColor
                            : const Color(0xFFF3FBF8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.showAll
                              ? primaryColor
                              : const Color(0xFFBDC9C4),
                        ),
                      ),
                      child: Text(
                        'Tất cả',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: widget.showAll ? Colors.white : primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // "Hôm nay" button
                  IconButton(
                    icon: const Icon(Icons.today_outlined, size: 20),
                    tooltip: 'Hôm nay',
                    color: primaryColor,
                    visualDensity: VisualDensity.compact,
                    onPressed: _goToToday,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 22),
                    tooltip: 'Tuần trước',
                    color: textPrimary,
                    visualDensity: VisualDensity.compact,
                    onPressed: _previousWeek,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 22),
                    tooltip: 'Tuần sau',
                    color: textPrimary,
                    visualDensity: VisualDensity.compact,
                    onPressed: _nextWeek,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 7 Days Strip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weekDays.map((day) {
              final isSelected = !widget.showAll && _isSameDay(day, widget.selectedDate);
              final isToday = _isSameDay(day, today);
              final dayReminders = _getRemindersForDay(day);
              final hasPending = dayReminders.any((r) => r.isPending);
              final hasCompleted = dayReminders.any((r) => r.isCompleted);

              return Expanded(
                child: GestureDetector(
                  onTap: () => widget.onDateSelected(day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primaryColor
                          : (isToday ? const Color(0xFFE7F5F2) : Colors.transparent),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? primaryColor
                            : (isToday ? primaryColor : Colors.transparent),
                        width: isToday && !isSelected ? 1.5 : 1,
                      ),
                      boxShadow: isSelected
                          ? const [
                              BoxShadow(
                                color: Color(0x330D7A68),
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              )
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        // Day of week
                        Text(
                          _getDayOfWeek(day.weekday),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white70
                                : (isToday ? primaryColor : const Color(0xFF6E7A75)),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Day number
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : (isToday ? primaryColor : textPrimary),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Dots indicators
                        SizedBox(
                          height: 6,
                          child: Row(
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
                                        ? Colors.white60
                                        : const Color(0xFFBDC9C4),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

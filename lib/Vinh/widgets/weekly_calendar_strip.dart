import 'package:flutter/material.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/reminder_model.dart';

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
    if (oldWidget.selectedDate != widget.selectedDate &&
        !widget.showAll &&
        (widget.selectedDate.isBefore(_weekStart) ||
            widget.selectedDate
                .isAfter(_weekStart.add(const Duration(days: 6))))) {
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

  String _getMonthName(int month, bool isEn) {
    if (isEn) {
      const monthsEn = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      return monthsEn[month - 1];
    }
    return 'Tháng $month';
  }

  String _getDayOfWeek(int weekday, bool isEn) {
    if (isEn) {
      const daysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return daysEn[weekday - 1];
    }
    const daysVn = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return daysVn[weekday - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Checks if a day has active reminders in the list
  List<ReminderModel> _getRemindersForDay(DateTime day) {
    final dayStr =
        '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
    return widget.reminders
        .where((r) => !r.isDeleted && r.date == dayStr)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, isEn, child) {
        const primaryColor = Color(0xFF0D7A68);
        const textPrimary = Color(0xFF151D1B);
        final today = DateTime.now();

        final weekDays =
            List.generate(7, (i) => _weekStart.add(Duration(days: i)));
        final currentMonthLabel = isEn
            ? '${_getMonthName(_weekStart.month, true)} ${_weekStart.year}'
            : '${_getMonthName(_weekStart.month, false)}, ${_weekStart.year}';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month,
                            color: primaryColor, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              currentMonthLabel,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // "Tất cả" chip
                      InkWell(
                        onTap: widget.onSelectAll,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
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
                            AppLanguage.text('Tất cả', 'All'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: widget.showAll ? Colors.white : primaryColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // "Hôm nay" button
                      IconButton(
                        icon: const Icon(Icons.today_outlined, size: 18),
                        tooltip: AppLanguage.text('Hôm nay', 'Today'),
                        color: primaryColor,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 26, minHeight: 28),
                        visualDensity: VisualDensity.compact,
                        onPressed: _goToToday,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 20),
                        tooltip: AppLanguage.text('Tuần trước', 'Prev week'),
                        color: textPrimary,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 24, minHeight: 28),
                        visualDensity: VisualDensity.compact,
                        onPressed: _previousWeek,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 20),
                        tooltip: AppLanguage.text('Tuần sau', 'Next week'),
                        color: textPrimary,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 24, minHeight: 28),
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
                  final isSelected =
                      !widget.showAll && _isSameDay(day, widget.selectedDate);
                  final isToday = _isSameDay(day, today);
                  final dayReminders = _getRemindersForDay(day);
                  final hasOverdue =
                      dayReminders.any((r) => r.isOverdue && !r.isCompleted);
                  final hasPending = dayReminders.any((r) =>
                      (r.isPending || r.isOpen) &&
                      !r.isOverdue &&
                      !r.isCompleted);
                  final hasCompleted = dayReminders.any((r) => r.isCompleted);

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onDateSelected(day),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryColor
                              : (isToday
                                  ? const Color(0xFFE7F5F2)
                                  : Colors.transparent),
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
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Day of week
                              Text(
                                _getDayOfWeek(day.weekday, isEn),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white70
                                      : (isToday
                                          ? primaryColor
                                          : const Color(0xFF6E7A75)),
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
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (hasOverdue)
                                      Container(
                                        width: 5,
                                        height: 5,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 1),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFBA1A1A),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    if (hasPending)
                                      Container(
                                        width: 5,
                                        height: 5,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 1),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFFF49D37)
                                              : const Color(0xFF0D7A68),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    if (hasCompleted)
                                      Container(
                                        width: 5,
                                        height: 5,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 1),
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
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

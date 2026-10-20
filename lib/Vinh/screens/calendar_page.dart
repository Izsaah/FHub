import 'package:flutter/material.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/reminder_repository.dart';
import '../widgets/family_progress_card.dart';
import '../widgets/monthly_calendar_grid.dart';
import '../widgets/reminder_card.dart';
import '../widgets/reminder_detail_bottom_sheet.dart';
import '../widgets/reminder_section_header.dart';
import 'create_reminder_screen.dart';

class CalendarPage extends StatefulWidget {
  final String familyId;
  final String currentUserId;
  final String currentUserName;
  final List<FamilyMember> familyMembers;
  final ReminderRepository repository;

  const CalendarPage({
    super.key,
    required this.familyId,
    required this.currentUserId,
    this.currentUserName = 'Minh',
    required this.familyMembers,
    required this.repository,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDate = DateTime.now();

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  Future<void> _openCreateReminder() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CreateReminderScreen(
          familyId: widget.familyId,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          familyMembers: widget.familyMembers,
          repository: widget.repository,
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _completeReminder(ReminderModel reminder) async {
    try {
      await widget.repository.completeReminder(
        reminderId: reminder.id,
        currentUserId: widget.currentUserId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã hoàn thành nhắc nhở!'),
            backgroundColor: Color(0xFF005F50),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  Future<void> _confirmAndDelete(ReminderModel reminder) async {
    if (reminder.creatorId != widget.currentUserId) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Reminder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Delete this reminder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.repository.deleteReminder(
          reminderId: reminder.id,
          currentUserId: widget.currentUserId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xóa "${reminder.title}".'),
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: const Color(0xFFBA1A1A),
            ),
          );
        }
      }
    }
  }

  void _showDetailBottomSheet(ReminderModel reminder) {
    ReminderDetailBottomSheet.show(
      context,
      reminder: reminder,
      currentUserId: widget.currentUserId,
      repository: widget.repository,
      familyMembers: widget.familyMembers,
      onReminderUpdated: () => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    const textPrimary = Color(0xFF151D1B);
    final selectedDateStr = _formatDate(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBF8),
      appBar: AppBar(
        title: const Text(
          'Lịch Gia Đình (Calendar)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2EAE7), height: 1),
        ),
      ),
      body: StreamBuilder<List<ReminderModel>>(
        stream: widget.repository.watchReminders(familyId: widget.familyId),
        builder: (context, snapshot) {
          final allReminders = snapshot.data ?? [];
          final dayReminders =
              allReminders.where((r) => r.date == selectedDateStr && !r.isDeleted).toList();

          final overdueList = dayReminders
              .where((r) => r.isOverdue && !r.isCompleted)
              .toList();

          final openList = dayReminders
              .where((r) => r.isOpen && !r.isOverdue && !r.isCompleted)
              .toList();

          final pendingList = dayReminders
              .where((r) => r.isPending && !r.isOverdue && !r.isOpen && !r.isCompleted)
              .toList();

          final completedList =
              dayReminders.where((r) => r.isCompleted).toList();

          return CustomScrollView(
            slivers: [
              // 1. Monthly Calendar Grid
              SliverToBoxAdapter(
                child: MonthlyCalendarGrid(
                  currentMonth: _currentMonth,
                  selectedDate: _selectedDate,
                  reminders: allReminders,
                  onDateSelected: (date) {
                    setState(() => _selectedDate = date);
                  },
                  onMonthChanged: (month) {
                    setState(() => _currentMonth = month);
                  },
                ),
              ),

              // 2. Day Progress Card
              if (dayReminders.isNotEmpty)
                SliverToBoxAdapter(
                  child: FamilyProgressCard(
                    reminders: dayReminders,
                    dateTitle: selectedDateStr,
                  ),
                ),

              // 3. Section Title for Selected Date
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Việc ngày $selectedDateStr',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        '${dayReminders.length} nhắc nhở',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6E7A75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Reminders for Selected Date
              if (dayReminders.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_note_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Chưa có nhắc nhở cho ngày $selectedDateStr',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF6E7A75),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: _openCreateReminder,
                            child: const Text('Thêm nhắc nhở cho ngày này'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // 1. OVERDUE
                      if (overdueList.isNotEmpty) ...[
                        ReminderSectionHeader(
                          title: 'QUÁ HẠN (OVERDUE)',
                          count: overdueList.length,
                          color: const Color(0xFFBA1A1A),
                          icon: Icons.warning_amber_rounded,
                        ),
                        ...overdueList.map(
                          (reminder) => ReminderCard(
                            reminder: reminder,
                            currentUserId: widget.currentUserId,
                            onTap: () => _showDetailBottomSheet(reminder),
                            onComplete: reminder.assignedTo == widget.currentUserId
                                ? () => _completeReminder(reminder)
                                : null,
                            onDelete: reminder.creatorId == widget.currentUserId
                                ? () => _confirmAndDelete(reminder)
                                : null,
                          ),
                        ),
                      ],

                      // 2. OPEN
                      if (openList.isNotEmpty) ...[
                        ReminderSectionHeader(
                          title: 'ĐANG MỞ (OPEN)',
                          count: openList.length,
                          color: const Color(0xFF006A6A),
                          icon: Icons.lock_open_rounded,
                        ),
                        ...openList.map(
                          (reminder) => ReminderCard(
                            reminder: reminder,
                            currentUserId: widget.currentUserId,
                            onTap: () => _showDetailBottomSheet(reminder),
                            onComplete: reminder.assignedTo == widget.currentUserId
                                ? () => _completeReminder(reminder)
                                : null,
                            onDelete: reminder.creatorId == widget.currentUserId
                                ? () => _confirmAndDelete(reminder)
                                : null,
                          ),
                        ),
                      ],

                      // 3. PENDING
                      if (pendingList.isNotEmpty) ...[
                        ReminderSectionHeader(
                          title: 'CHỜ XỬ LÝ (PENDING)',
                          count: pendingList.length,
                          color: const Color(0xFF49454F),
                          icon: Icons.hourglass_top_rounded,
                        ),
                        ...pendingList.map(
                          (reminder) => ReminderCard(
                            reminder: reminder,
                            currentUserId: widget.currentUserId,
                            onTap: () => _showDetailBottomSheet(reminder),
                            onComplete: reminder.assignedTo == widget.currentUserId
                                ? () => _completeReminder(reminder)
                                : null,
                            onDelete: reminder.creatorId == widget.currentUserId
                                ? () => _confirmAndDelete(reminder)
                                : null,
                          ),
                        ),
                      ],

                      // 4. COMPLETED
                      if (completedList.isNotEmpty) ...[
                        ReminderSectionHeader(
                          title: 'ĐÃ HOÀN THÀNH (COMPLETED)',
                          count: completedList.length,
                          color: const Color(0xFF005F50),
                          icon: Icons.check_circle_outline_rounded,
                        ),
                        ...completedList.map(
                          (reminder) => ReminderCard(
                            reminder: reminder,
                            currentUserId: widget.currentUserId,
                            onTap: () => _showDetailBottomSheet(reminder),
                            onDelete: reminder.creatorId == widget.currentUserId
                                ? () => _confirmAndDelete(reminder)
                                : null,
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateReminder,
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Tạo nhắc nhở',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

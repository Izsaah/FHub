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

  void _showDetailBottomSheet(ReminderModel reminder) {
    ReminderDetailBottomSheet.show(
      context,
      reminder: reminder,
      currentUserId: widget.currentUserId,
      repository: widget.repository,
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
              allReminders.where((r) => r.date == selectedDateStr).toList();

          final pendingList = dayReminders.where((r) => r.isPending).toList();
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
                      if (pendingList.isNotEmpty) ...[
                        ReminderSectionHeader(
                          title: 'PENDING',
                          count: pendingList.length,
                        ),
                        ...pendingList.map(
                          (reminder) => ReminderCard(
                            reminder: reminder,
                            currentUserId: widget.currentUserId,
                            onTap: () => _showDetailBottomSheet(reminder),
                          ),
                        ),
                      ],
                      if (completedList.isNotEmpty) ...[
                        ReminderSectionHeader(
                          title: 'COMPLETED',
                          count: completedList.length,
                        ),
                        ...completedList.map(
                          (reminder) => ReminderCard(
                            reminder: reminder,
                            currentUserId: widget.currentUserId,
                            onTap: () => _showDetailBottomSheet(reminder),
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

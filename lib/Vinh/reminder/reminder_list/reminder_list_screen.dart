import 'package:flutter/material.dart';
import '../create_reminder/create_reminder_screen.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../reminder_detail/reminder_detail_bottom_sheet.dart';
import '../reminder_repository/reminder_repository.dart';
import 'widgets/family_progress_card.dart';
import 'widgets/reminder_card.dart';
import 'widgets/reminder_section_header.dart';
import 'widgets/weekly_calendar_strip.dart';

class ReminderListScreen extends StatefulWidget {
  final String familyId;
  final String currentUserId;
  final String currentUserName;
  final List<FamilyMember> familyMembers;
  final ReminderRepository repository;
  final ValueChanged<String>? onUserChanged;

  const ReminderListScreen({
    super.key,
    required this.familyId,
    required this.currentUserId,
    this.currentUserName = 'Minh',
    required this.familyMembers,
    required this.repository,
    this.onUserChanged,
  });

  @override
  State<ReminderListScreen> createState() => _ReminderListScreenState();
}

class _ReminderListScreenState extends State<ReminderListScreen> {
  late String _currentUserId;
  late String _currentUserName;
  DateTime _selectedDate = DateTime.now();
  bool _showAll = true;

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  @override
  void initState() {
    super.initState();
    _currentUserId = widget.currentUserId;
    _currentUserName = widget.currentUserName;
  }

  void _switchUser(FamilyMember member) {
    setState(() {
      _currentUserId = member.id;
      _currentUserName = member.name;
    });
    widget.onUserChanged?.call(member.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched view to ${member.name} (${member.role})'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _openCreateReminder() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CreateReminderScreen(
          familyId: widget.familyId,
          currentUserId: _currentUserId,
          currentUserName: _currentUserName,
          familyMembers: widget.familyMembers,
          repository: widget.repository,
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _confirmAndDelete(ReminderModel reminder) async {
    if (reminder.creatorId != _currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the creator can delete this reminder.'),
          backgroundColor: Color(0xFFBA1A1A),
        ),
      );
      return;
    }

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
          currentUserId: _currentUserId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reminder deleted successfully.')),
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

  Future<void> _completeReminder(ReminderModel reminder) async {
    try {
      await widget.repository.completeReminder(
        reminderId: reminder.id,
        currentUserId: _currentUserId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder marked as COMPLETED!'),
            backgroundColor: Color(0xFF0D7A68),
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

  void _showDetailBottomSheet(ReminderModel reminder) {
    ReminderDetailBottomSheet.show(
      context,
      reminder: reminder,
      currentUserId: _currentUserId,
      repository: widget.repository,
      onReminderUpdated: () => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    const textPrimary = Color(0xFF151D1B);

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBF8),
      appBar: AppBar(
        title: const Text(
          'Reminders',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Switch user for testing permissions
          PopupMenuButton<FamilyMember>(
            tooltip: 'Switch Active User',
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: primaryColor,
                  child: Text(
                    _currentUserName.isNotEmpty
                        ? _currentUserName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _currentUserName,
                  style: const TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: textPrimary, size: 18),
              ],
            ),
            onSelected: _switchUser,
            itemBuilder: (ctx) => widget.familyMembers.map((member) {
              final isCurrent = member.id == _currentUserId;
              return PopupMenuItem<FamilyMember>(
                value: member,
                child: Row(
                  children: [
                    Icon(
                      isCurrent
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isCurrent ? primaryColor : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text('${member.name} (${member.role})'),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2EAE7), height: 1),
        ),
      ),
      body: StreamBuilder<List<ReminderModel>>(
        stream: widget.repository.watchReminders(familyId: widget.familyId),
        builder: (context, snapshot) {
          final allReminders = snapshot.data ?? [];
          final selectedDateStr = _formatDate(_selectedDate);
          final displayedReminders = _showAll
              ? allReminders
              : allReminders.where((r) => r.date == selectedDateStr).toList();

          final pendingList =
              displayedReminders.where((r) => r.isPending).toList();
          final completedList =
              displayedReminders.where((r) => r.isCompleted).toList();

          return Column(
            children: [
              // 1. Weekly Calendar Strip
              WeeklyCalendarStrip(
                selectedDate: _selectedDate,
                showAll: _showAll,
                reminders: allReminders,
                onDateSelected: (date) {
                  setState(() {
                    _selectedDate = date;
                    _showAll = false;
                  });
                },
                onSelectAll: () {
                  setState(() {
                    _showAll = true;
                  });
                },
              ),

              // 2. Family Daily Progress Card
              FamilyProgressCard(
                reminders: _showAll ? allReminders : displayedReminders,
                dateTitle: _showAll ? 'Tất cả' : selectedDateStr,
              ),

              // 3. Reminder List
              Expanded(
                child: allReminders.isEmpty
                    ? _buildEmptyState()
                    : (displayedReminders.isEmpty
                        ? _buildDayEmptyState(selectedDateStr)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                            children: [
                              // PENDING SECTION
                              if (pendingList.isNotEmpty) ...[
                                ReminderSectionHeader(
                                  title: 'PENDING',
                                  count: pendingList.length,
                                ),
                                ...pendingList.map(
                                  (reminder) => ReminderCard(
                                    reminder: reminder,
                                    currentUserId: _currentUserId,
                                    onTap: () =>
                                        _showDetailBottomSheet(reminder),
                                    onComplete:
                                        reminder.assignedTo == _currentUserId
                                            ? () => _completeReminder(reminder)
                                            : null,
                                    onDelete:
                                        reminder.creatorId == _currentUserId
                                            ? () => _confirmAndDelete(reminder)
                                            : null,
                                  ),
                                ),
                              ],

                              // COMPLETED SECTION
                              if (completedList.isNotEmpty) ...[
                                ReminderSectionHeader(
                                  title: 'COMPLETED',
                                  count: completedList.length,
                                ),
                                ...completedList.map(
                                  (reminder) => ReminderCard(
                                    reminder: reminder,
                                    currentUserId: _currentUserId,
                                    onTap: () =>
                                        _showDetailBottomSheet(reminder),
                                    onDelete:
                                        reminder.creatorId == _currentUserId
                                            ? () => _confirmAndDelete(reminder)
                                            : null,
                                  ),
                                ),
                              ],
                            ],
                          )),
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
          'Create Reminder',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildDayEmptyState(String dateStr) {
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
              'Nhấn "Tạo nhắc nhở" để thêm mới, hoặc xem "Tất cả" trên lịch.',
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
              onPressed: () {
                setState(() => _showAll = true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
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
              onPressed: _openCreateReminder,
            ),
          ],
        ),
      ),
    );
  }
}

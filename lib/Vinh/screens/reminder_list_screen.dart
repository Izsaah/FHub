import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/reminder_repository.dart';
import '../services/supabase_config.dart';
import '../widgets/family_progress_card.dart';
import '../widgets/reminder_card.dart';
import '../widgets/reminder_detail_bottom_sheet.dart';
import '../widgets/reminder_section_header.dart';
import '../widgets/weekly_calendar_strip.dart';
import 'calendar_page.dart';
import 'create_reminder_screen.dart';

class ReminderListScreen extends StatefulWidget {
  final String? familyId;
  final String? currentUserId;
  final String? currentUserName;
  final List<FamilyMember>? familyMembers;
  final ReminderRepository? repository;
  final ValueChanged<String>? onUserChanged;

  const ReminderListScreen({
    super.key,
    this.familyId,
    this.currentUserId,
    this.currentUserName,
    this.familyMembers,
    this.repository,
    this.onUserChanged,
  });

  @override
  State<ReminderListScreen> createState() => _ReminderListScreenState();
}

class _ReminderListScreenState extends State<ReminderListScreen> {
  late String _familyId;
  late String _currentUserId;
  late String _currentUserName;
  late List<FamilyMember> _familyMembers;
  late ReminderRepository _repository;
  bool _isLoading = true;

  DateTime _selectedDate = DateTime.now();
  bool _showAll = true;
  bool _filterOnlyMine = false;
  bool _isSearchOpen = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.familyId != null &&
        widget.currentUserId != null &&
        widget.familyMembers != null) {
      _familyId = widget.familyId!;
      _currentUserId = widget.currentUserId!;
      _currentUserName = widget.currentUserName ?? 'Minh';
      _familyMembers = widget.familyMembers!;
      _repository = widget.repository ?? SupabaseReminderRepository();
      _isLoading = false;
    } else {
      _resolveContext();
    }
  }

  Future<void> _resolveContext() async {
    try {
      final client = SupabaseConfig.client;
      final currentUser = client?.auth.currentUser;
      final userId = widget.currentUserId ?? currentUser?.id ?? 'user_minh';
      final userName = widget.currentUserName ??
          currentUser?.userMetadata?['name'] as String? ??
          currentUser?.email?.split('@').first ??
          'Minh';

      String resolvedFamilyId = widget.familyId ?? 'family_1';
      List<FamilyMember> resolvedMembers = widget.familyMembers ?? [];

      if (widget.familyMembers == null && client != null && currentUser != null) {
        final membership = await client
            .from('family_members')
            .select('family_id')
            .eq('user_id', userId)
            .maybeSingle();

        if (membership != null && membership['family_id'] != null) {
          resolvedFamilyId = membership['family_id'].toString();

          final membersRes = await client
              .from('family_members')
              .select('user_id, role, users(name)')
              .eq('family_id', resolvedFamilyId);

          if (membersRes.isNotEmpty) {
            resolvedMembers = membersRes.map<FamilyMember>((json) {
              final userMap = json['users'] as Map<String, dynamic>?;
              final name = userMap?['name'] as String? ?? 'Member';
              return FamilyMember(
                id: (json['user_id'] ?? '').toString(),
                name: name,
                role: (json['role'] ?? 'Member').toString(),
                familyId: resolvedFamilyId,
              );
            }).toList();
          }
        }
      }

      if (resolvedMembers.isEmpty) {
        resolvedMembers = [
          FamilyMember(
            id: userId,
            name: userName,
            role: 'Owner',
            familyId: resolvedFamilyId,
          ),
          FamilyMember(
            id: 'user_mom',
            name: 'Mom',
            role: 'Member',
            familyId: resolvedFamilyId,
          ),
          FamilyMember(
            id: 'user_dad',
            name: 'Dad',
            role: 'Member',
            familyId: resolvedFamilyId,
          ),
        ];
      }

      if (mounted) {
        setState(() {
          _familyId = resolvedFamilyId;
          _currentUserId = userId;
          _currentUserName = userName;
          _familyMembers = resolvedMembers;
          _repository = widget.repository ?? SupabaseReminderRepository();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _familyId = widget.familyId ?? 'family_1';
          _currentUserId = widget.currentUserId ?? 'user_minh';
          _currentUserName = widget.currentUserName ?? 'Minh';
          _familyMembers = widget.familyMembers ??
              const [
                FamilyMember(
                  id: 'user_minh',
                  name: 'Minh',
                  role: 'Owner',
                  familyId: 'family_1',
                ),
                FamilyMember(
                  id: 'user_mom',
                  name: 'Mom',
                  role: 'Member',
                  familyId: 'family_1',
                ),
                FamilyMember(
                  id: 'user_dad',
                  name: 'Dad',
                  role: 'Member',
                  familyId: 'family_1',
                ),
              ];
          _repository = widget.repository ?? SupabaseReminderRepository();
          _isLoading = false;
        });
      }
    }
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
          familyId: _familyId,
          currentUserId: _currentUserId,
          currentUserName: _currentUserName,
          familyMembers: _familyMembers,
          repository: _repository,
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
        await _repository.deleteReminder(
          reminderId: reminder.id,
          currentUserId: _currentUserId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xóa "${reminder.title}".'),
              action: SnackBarAction(
                label: 'HOÀN TÁC (UNDO)',
                textColor: const Color(0xFFaaffe9),
                onPressed: () async {
                  await _repository.restoreReminder(
                    reminderId: reminder.id,
                    currentUserId: _currentUserId,
                  );
                },
              ),
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

  Future<void> _completeReminder(ReminderModel reminder) async {
    try {
      HapticFeedback.mediumImpact();
      await _repository.completeReminder(
        reminderId: reminder.id,
        currentUserId: _currentUserId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder marked as COMPLETED!'),
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

  void _showDetailBottomSheet(ReminderModel reminder) {
    ReminderDetailBottomSheet.show(
      context,
      reminder: reminder,
      currentUserId: _currentUserId,
      repository: _repository,
      onReminderUpdated: () => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF005F50);
    const textPrimary = Color(0xFF151D1B);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3FBF8),
        body: Center(
          child: CircularProgressIndicator(
            color: primaryColor,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBF8),
      appBar: AppBar(
        title: _isSearchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm nhắc nhở...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reminders',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: primaryColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    _showAll
                        ? 'Tất cả nhắc việc gia đình'
                        : 'Việc ngày ${_formatDate(_selectedDate)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF3E4946),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
        backgroundColor: const Color(0xFFEDF5F2),
        elevation: 1,
        shadowColor: Colors.black12,
        actions: [
          // Search toggle
          IconButton(
            icon: Icon(
              _isSearchOpen ? Icons.close : Icons.search,
              color: primaryColor,
            ),
            tooltip: _isSearchOpen ? 'Đóng tìm kiếm' : 'Tìm kiếm nhắc nhở',
            onPressed: () {
              setState(() {
                _isSearchOpen = !_isSearchOpen;
                if (!_isSearchOpen) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
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
            itemBuilder: (ctx) => _familyMembers.map((member) {
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
          IconButton(
            icon: const Icon(Icons.calendar_month, color: primaryColor),
            tooltip: 'Xem trang Lịch (Calendar Page)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => CalendarPage(
                    familyId: _familyId,
                    currentUserId: _currentUserId,
                    currentUserName: _currentUserName,
                    familyMembers: _familyMembers,
                    repository: _repository,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFDCE8E3), height: 1),
        ),
      ),
      body: StreamBuilder<List<ReminderModel>>(
        stream: _repository.watchReminders(familyId: _familyId),
        builder: (context, snapshot) {
          final allReminders = snapshot.data ?? [];

          // 1. Filter by Scope: All vs Mine
          final scopedReminders = _filterOnlyMine
              ? allReminders.where((r) => r.assignedTo == _currentUserId).toList()
              : allReminders;

          // 2. Filter by Search Query
          final searchedReminders = _searchQuery.isEmpty
              ? scopedReminders
              : scopedReminders.where((r) {
                  final titleMatch = r.title
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase());
                  final member = _familyMembers.firstWhere(
                    (m) => m.id == r.assignedTo,
                    orElse: () => const FamilyMember(
                      id: '',
                      name: '',
                      role: '',
                      familyId: '',
                    ),
                  );
                  final assigneeMatch = member.name
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()) ||
                      member.role
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase());
                  return titleMatch || assigneeMatch;
                }).toList();

          final selectedDateStr = _formatDate(_selectedDate);
          final displayedReminders = _showAll
              ? searchedReminders
              : searchedReminders.where((r) => r.date == selectedDateStr).toList();

          final pendingList =
              displayedReminders.where((r) => r.isPending).toList();
          final completedList =
              displayedReminders.where((r) => r.isCompleted).toList();

          return Column(
            children: [
              // 0. Scope Filter Chips ([ Cả nhà ] vs [ Việc của tôi ])
              Container(
                color: const Color(0xFFEDF5F2),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.groups_rounded,
                          size: 18,
                          color: !_filterOnlyMine
                              ? primaryColor
                              : const Color(0xFF49454F),
                        ),
                        label: const Center(
                          child: Text(
                            '👨‍👩‍👧 Cả nhà',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        selected: !_filterOnlyMine,
                        selectedColor: const Color(0xFFD4ECE5),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: !_filterOnlyMine
                              ? primaryColor
                              : const Color(0xFF49454F),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: !_filterOnlyMine
                                ? primaryColor
                                : const Color(0xFFC4C7C5),
                          ),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _filterOnlyMine = false);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.person_rounded,
                          size: 18,
                          color: _filterOnlyMine
                              ? primaryColor
                              : const Color(0xFF49454F),
                        ),
                        label: const Center(
                          child: Text(
                            '👤 Việc của tôi',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        selected: _filterOnlyMine,
                        selectedColor: const Color(0xFFD4ECE5),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _filterOnlyMine
                              ? primaryColor
                              : const Color(0xFF49454F),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: _filterOnlyMine
                                ? primaryColor
                                : const Color(0xFFC4C7C5),
                          ),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _filterOnlyMine = true);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // 1. Weekly Calendar Strip
              WeeklyCalendarStrip(
                selectedDate: _selectedDate,
                showAll: _showAll,
                reminders: scopedReminders,
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
                reminders: _showAll ? searchedReminders : displayedReminders,
                dateTitle: _showAll ? 'Tất cả' : selectedDateStr,
              ),

              // 3. Reminder List
              Expanded(
                child: allReminders.isEmpty
                    ? _buildEmptyState()
                    : (displayedReminders.isEmpty
                        ? _buildDayEmptyState(selectedDateStr)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
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
          'Tạo lời nhắc',
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

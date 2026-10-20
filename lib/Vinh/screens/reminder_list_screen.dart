import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/reminder_repository.dart';
import '../services/supabase_config.dart';
import '../widgets/camera_proof_dialog.dart';
import '../widgets/family_progress_card.dart';
import '../widgets/reminder_detail_bottom_sheet.dart';
import '../widgets/reminder_scope_filter_chips.dart';
import '../widgets/weekly_calendar_strip.dart';
import 'calendar_page.dart';
import 'create_reminder_screen.dart';
import 'views/reminder_calendar_view.dart';
import 'views/reminder_list_view.dart';

/// Coordinator Screen quản lý màn hình chính của tính năng Lời nhắc (Reminders).
/// Điều phối giữa List View và Calendar View, tìm kiếm, lọc theo người và ngày.
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

  bool _isCalendarView = false;
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
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
            id: 'user_mom',
            name: 'Mom',
            role: FamilyMember.roleParent,
            familyId: resolvedFamilyId,
          ),
          FamilyMember(
            id: 'user_dad',
            name: 'Dad',
            role: FamilyMember.roleParent,
            familyId: resolvedFamilyId,
          ),
          FamilyMember(
            id: 'user_minh',
            name: 'Minh',
            role: FamilyMember.roleChild,
            familyId: resolvedFamilyId,
          ),
          FamilyMember(
            id: 'user_grandma',
            name: 'Bà Ngoại',
            role: FamilyMember.roleGrandparent,
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
                  id: 'user_mom',
                  name: 'Mom',
                  role: FamilyMember.roleParent,
                  familyId: 'family_1',
                ),
                FamilyMember(
                  id: 'user_dad',
                  name: 'Dad',
                  role: FamilyMember.roleParent,
                  familyId: 'family_1',
                ),
                FamilyMember(
                  id: 'user_minh',
                  name: 'Minh',
                  role: FamilyMember.roleChild,
                  familyId: 'family_1',
                ),
                FamilyMember(
                  id: 'user_grandma',
                  name: 'Bà Ngoại',
                  role: FamilyMember.roleGrandparent,
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
        content: Text('Đã chuyển góc nhìn sang ${member.name} (${member.role})'),
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
    final isCreator = reminder.creatorId == _currentUserId;
    final currentMember = _familyMembers.firstWhere(
      (m) => m.id == _currentUserId,
      orElse: () => const FamilyMember(id: '', name: '', role: '', familyId: ''),
    );
    final isParentOrOwner = currentMember.isParent || currentMember.isGrandparent;

    if (!isCreator && !isParentOrOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chỉ người tạo hoặc Bố Mẹ/Chủ nhà mới có thể xóa lời nhắc này.'),
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
          'Xóa lời nhắc',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Bạn có chắc chắn muốn xóa lời nhắc này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _repository.deleteReminder(
          reminderId: reminder.id,
          currentUserId: _currentUserId,
          familyMembers: _familyMembers,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xóa "${reminder.title}".'),
              action: SnackBarAction(
                label: 'HOÀN TÁC',
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
      String? proofUrl;
      if (reminder.requiresProofImage) {
        proofUrl = await CameraProofDialog.show(
          context,
          reminder: reminder,
          currentUserName: _currentUserName,
        );
        if (proofUrl == null) {
          // User canceled without taking photo
          return;
        }
      }

      HapticFeedback.mediumImpact();
      await _repository.completeReminder(
        reminderId: reminder.id,
        currentUserId: _currentUserId,
        proofImageUrl: proofUrl,
      );
      if (mounted) {
        const successMsg = 'Đã hoàn thành công việc!';
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(successMsg),
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

  Future<void> _claimReminder(ReminderModel reminder) async {
    try {
      HapticFeedback.mediumImpact();
      await _repository.claimOpenTask(
        reminderId: reminder.id,
        currentUserId: _currentUserId,
        currentUserName: _currentUserName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 Bạn đã xung phong nhận việc "${reminder.title}" thành công!',
            ),
            backgroundColor: const Color(0xFF005F50),
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

  Future<void> _claimAndCompleteReminder(ReminderModel reminder) async {
    try {
      String? proofUrl;
      if (reminder.requiresProofImage) {
        proofUrl = await CameraProofDialog.show(
          context,
          reminder: reminder,
          currentUserName: _currentUserName,
        );
        if (proofUrl == null) {
          // Người dùng hủy chụp ảnh
          return;
        }
      }

      HapticFeedback.mediumImpact();
      await _repository.claimAndCompleteOpenTask(
        reminderId: reminder.id,
        currentUserId: _currentUserId,
        currentUserName: _currentUserName,
        proofImageUrl: proofUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 Bạn đã hoàn thành việc chung "${reminder.title}" xuất sắc!',
            ),
            backgroundColor: const Color(0xFF005F50),
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
      currentUserName: _currentUserName,
      repository: _repository,
      familyMembers: _familyMembers,
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
                    'Nhắc việc gia đình',
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
          // Tìm kiếm
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
          // Chuyển đổi thành viên người dùng chủ động
          PopupMenuButton<FamilyMember>(
            tooltip: 'Chuyển đổi góc nhìn thành viên',
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
          // Chuyển đổi qua lại giữa List View và Calendar View
          IconButton(
            icon: Icon(
              _isCalendarView
                  ? Icons.format_list_bulleted_rounded
                  : Icons.calendar_month_rounded,
              color: primaryColor,
            ),
            tooltip: _isCalendarView
                ? 'Chuyển sang chế độ Danh sách (List View)'
                : 'Chuyển sang chế độ Lịch (Calendar View)',
            onPressed: () {
              setState(() {
                _isCalendarView = !_isCalendarView;
              });
            },
          ),
          // Menu mở toàn trang Calendar
          PopupMenuButton<String>(
            tooltip: 'Tùy chọn khác',
            icon: const Icon(Icons.more_vert, color: primaryColor),
            onSelected: (val) {
              if (val == 'full_calendar') {
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
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'full_calendar',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new_rounded,
                        size: 18, color: primaryColor),
                    SizedBox(width: 8),
                    Text('Mở trang Lịch toàn màn hình'),
                  ],
                ),
              ),
            ],
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

          // 1. Lọc theo Scope: Tất cả vs Việc của tôi
          final scopedReminders = _filterOnlyMine
              ? allReminders.where((r) => r.assignedTo == _currentUserId).toList()
              : allReminders;

          // 2. Lọc theo từ khóa tìm kiếm (Title hoặc Tên/Vai trò người nhận)
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
              : searchedReminders
                  .where((r) => r.date == selectedDateStr)
                  .toList();

          return Column(
            children: [
              // Thanh lọc phạm vi: [👨‍👩‍👧 Cả nhà] vs [👤 Việc của tôi]
              ReminderScopeFilterChips(
                filterOnlyMine: _filterOnlyMine,
                onScopeChanged: (val) => setState(() => _filterOnlyMine = val),
              ),

              // Calendar View hoặc Weekly Strip
              if (_isCalendarView) ...[
                ReminderCalendarView(
                  currentMonth: _currentMonth,
                  selectedDate: _selectedDate,
                  showAll: _showAll,
                  reminders: scopedReminders,
                  selectedDateFormatted: selectedDateStr,
                  onDateSelected: (date) {
                    setState(() {
                      _selectedDate = date;
                      _showAll = false;
                    });
                  },
                  onMonthChanged: (newMonth) {
                    setState(() {
                      _currentMonth = newMonth;
                    });
                  },
                  onShowAllPressed: () => setState(() => _showAll = true),
                ),
              ] else
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

              // Family Daily Progress Card
              FamilyProgressCard(
                reminders: _showAll ? searchedReminders : displayedReminders,
                dateTitle: _showAll ? 'Tất cả' : selectedDateStr,
              ),

              // List View phân nhóm theo 4 mức ưu tiên
              Expanded(
                child: ReminderListView(
                  allReminders: allReminders,
                  displayedReminders: displayedReminders,
                  currentUserId: _currentUserId,
                  selectedDateStr: selectedDateStr,
                  isShowingAll: _showAll,
                  isParentOrOwner: _familyMembers.any(
                    (m) =>
                        m.id == _currentUserId &&
                        (m.isParent || m.isGrandparent),
                  ),
                  onCreatePressed: _openCreateReminder,
                  onShowAllPressed: () => setState(() => _showAll = true),
                  onTapReminder: _showDetailBottomSheet,
                  onCompleteReminder: _completeReminder,
                  onDeleteReminder: _confirmAndDelete,
                  onClaimReminder: _claimReminder,
                  onClaimAndCompleteReminder: _claimAndCompleteReminder,
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
}

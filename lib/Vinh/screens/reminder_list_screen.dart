import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/reminder_repository.dart';
import '../widgets/camera_proof_dialog.dart';
import '../widgets/family_progress_card.dart';
import '../widgets/reminder_detail_bottom_sheet.dart';
import '../widgets/reminder_scope_filter_chips.dart';
import '../widgets/weekly_calendar_strip.dart';
import 'calendar_page.dart';
import 'create_reminder_screen.dart';
import 'family_ai_chat_screen.dart';
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
  bool _hasFamily = false;

  bool _isCalendarView = false;
  DateTime _currentMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
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
        widget.familyId!.isNotEmpty &&
        widget.currentUserId != null &&
        widget.familyMembers != null) {
      _hasFamily = true;
      _familyId = widget.familyId!;
      _currentUserId = widget.currentUserId!;
      _currentUserName = widget.currentUserName ?? 'Minh';
      _familyMembers = widget.familyMembers!;
      _repository = widget.repository ?? FirebaseReminderRepository();
      _isLoading = false;
    } else {
      _resolveContext();
    }
  }

  Future<void> _resolveContext() async {
    try {
      String? userId = widget.currentUserId;
      String? userName = widget.currentUserName;
      String? resolvedFamilyId = widget.familyId;
      List<FamilyMember> resolvedMembers = widget.familyMembers != null
          ? List<FamilyMember>.from(widget.familyMembers!)
          : [];

      // 1. Resolve Current User from Firebase Auth
      if (Firebase.apps.isNotEmpty) {
        try {
          final fbAuth = FirebaseAuth.instance;
          final fbUser = fbAuth.currentUser;
          if (fbUser != null) {
            userId ??= fbUser.uid;
            userName ??=
                (fbUser.displayName != null && fbUser.displayName!.isNotEmpty)
                    ? fbUser.displayName
                    : (fbUser.email?.split('@').first ?? 'Người dùng');
          }
        } catch (_) {}
      }

      userId ??= 'current_user';
      userName ??= 'Tôi';

      // 2. Resolve Family ID and Members from Cloud Firestore
      if (Firebase.apps.isNotEmpty &&
          (resolvedFamilyId == null || resolvedMembers.isEmpty)) {
        final firestore = FirebaseFirestore.instance;

        // Try getting familyId from user doc
        if (resolvedFamilyId == null) {
          try {
            final userDoc = await firestore
                .collection('users')
                .doc(userId)
                .get()
                .timeout(const Duration(seconds: 3));
            if (userDoc.exists && userDoc.data() != null) {
              final fid = userDoc.data()!['familyId']?.toString();
              if (fid != null && fid.isNotEmpty) {
                resolvedFamilyId = fid;
              }
            }
          } catch (_) {}
        }

        // Try getting familyId from family_members collection
        if (resolvedFamilyId == null) {
          try {
            final memberDocs = await firestore
                .collection('family_members')
                .where('userId', isEqualTo: userId)
                .where('status', isEqualTo: 'ACTIVE')
                .limit(1)
                .get()
                .timeout(const Duration(seconds: 3));
            if (memberDocs.docs.isNotEmpty) {
              resolvedFamilyId = (memberDocs.docs.first.data()['familyId'] ??
                      memberDocs.docs.first.data()['family_id'])
                  ?.toString();
            }
          } catch (_) {}
        }

        // Load real members of this family from Firestore
        if (resolvedFamilyId != null && resolvedMembers.isEmpty) {
          try {
            final membersSnap = await firestore
                .collection('family_members')
                .where('familyId', isEqualTo: resolvedFamilyId)
                .get()
                .timeout(const Duration(seconds: 3));

            for (final mDoc in membersSnap.docs) {
              final mData = mDoc.data();
              final memberUid =
                  (mData['userId'] ?? mData['user_id'] ?? '').toString();
              final role = (mData['role'] ?? 'Member').toString();
              String memberName =
                  (mData['name'] ?? mData['userName'] ?? '').toString();
              String? avatarType = mData['avatarType']?.toString();

              if (memberName.isEmpty && memberUid.isNotEmpty) {
                try {
                  final uDoc = await firestore
                      .collection('users')
                      .doc(memberUid)
                      .get()
                      .timeout(const Duration(seconds: 2));
                  if (uDoc.exists && uDoc.data() != null) {
                    memberName = uDoc.data()!['name']?.toString() ??
                        uDoc.data()!['displayName']?.toString() ??
                        '';
                    avatarType ??= uDoc.data()!['avatar_type']?.toString();
                  }
                } catch (_) {}
              }

              if (memberName.isEmpty) {
                memberName = memberUid == userId ? userName : 'Thành viên';
              }

              resolvedMembers.add(FamilyMember(
                id: memberUid.isNotEmpty ? memberUid : mDoc.id,
                name: memberName,
                role: role,
                avatarType: avatarType,
                familyId: resolvedFamilyId,
                rewardStarsTotal: (mData['rewardStarsTotal'] ??
                    mData['reward_stars_total'] ??
                    0) as int,
              ));
            }
          } catch (_) {}
        }
      }

      final bool hasFamily = resolvedFamilyId != null &&
          resolvedFamilyId.isNotEmpty &&
          !resolvedFamilyId.startsWith('family_current_user');

      if (mounted) {
        setState(() {
          _hasFamily = hasFamily;
          _familyId = resolvedFamilyId ?? '';
          _currentUserId = userId!;
          _currentUserName = userName!;
          _familyMembers = resolvedMembers;
          _repository = widget.repository ?? FirebaseReminderRepository();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ReminderListScreen _resolveContext error: $e');
      final fallbackUserId = widget.currentUserId ?? 'current_user';
      final fallbackUserName = widget.currentUserName ?? 'Tôi';
      final hasFamily = widget.familyId != null && widget.familyId!.isNotEmpty;

      if (mounted) {
        setState(() {
          _hasFamily = hasFamily;
          _familyId = widget.familyId ?? '';
          _currentUserId = fallbackUserId;
          _currentUserName = fallbackUserName;
          _familyMembers = widget.familyMembers ?? [];
          _repository = widget.repository ?? FirebaseReminderRepository();
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
        content:
            Text('Đã chuyển góc nhìn sang ${member.name} (${member.role})'),
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
      orElse: () =>
          const FamilyMember(id: '', name: '', role: '', familyId: ''),
    );
    final isParentOrOwner =
        currentMember.isParent || currentMember.isGrandparent;

    if (!isCreator && !isParentOrOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Chỉ người tạo hoặc Bố Mẹ/Chủ nhà mới có thể xóa lời nhắc này.'),
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
                  try {
                    await _repository.restoreReminder(
                      reminderId: reminder.id,
                      currentUserId: _currentUserId,
                      familyMembers: _familyMembers,
                    );
                    if (mounted) {
                      setState(() {});
                    }
                  } catch (_) {}
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

  void _openAiAssistant() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => FamilyAiChatScreen(
          familyId: _familyId,
          currentUserId: _currentUserId,
          currentUserName: _currentUserName,
          familyMembers: _familyMembers,
          repository: _repository,
        ),
      ),
    );
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

    if (!_hasFamily) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3FBF8),
        appBar: AppBar(
          title: const Text(
            'Lời nhắc gia đình',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0F2EC),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.family_restroom_rounded,
                      size: 64,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Cần tham gia Gia đình để sử dụng',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF151D1B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tính năng Lời nhắc và Phân công việc nhà hoạt động dựa trên không gian gia đình chung. Bạn chưa tham gia gia đình nào trên hệ thống.\n\nVui lòng tạo gia đình mới hoặc tham gia bằng mã mời để bắt đầu quản lý lời nhắc cùng người thân!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6E7A75),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'Kiểm tra lại trạng thái gia đình',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      setState(() => _isLoading = true);
                      _resolveContext();
                    },
                  ),
                ],
              ),
            ),
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
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Nhắc việc gia đình',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: primaryColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      _showAll
                          ? 'Tất cả nhắc việc gia đình'
                          : 'Việc ngày ${_formatDate(_selectedDate)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF3E4946),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
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
              size: 22,
            ),
            tooltip: _isSearchOpen ? 'Đóng tìm kiếm' : 'Tìm kiếm nhắc nhở',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
          // Chuyển đổi thành viên người dùng chủ động (gọn gàng, không tràn tên)
          PopupMenuButton<FamilyMember>(
            tooltip: 'Chuyển đổi góc nhìn thành viên',
            padding: EdgeInsets.zero,
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: primaryColor,
                  child: Text(
                    _currentUserName.isNotEmpty
                        ? _currentUserName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 65),
                  child: Text(
                    _currentUserName,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: textPrimary, size: 16),
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
                    Flexible(
                      child: Text(
                        '${member.name} (${member.role})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
              size: 22,
            ),
            tooltip: _isCalendarView
                ? 'Chuyển sang chế độ Danh sách (List View)'
                : 'Chuyển sang chế độ Lịch (Calendar View)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              setState(() {
                _isCalendarView = !_isCalendarView;
              });
            },
          ),
          // Menu mở rộng: Trợ lý AI, Tạo lời nhắc, Lịch toàn màn hình
          PopupMenuButton<String>(
            tooltip: 'Tùy chọn khác',
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert, color: primaryColor, size: 22),
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
              } else if (val == 'ai_assistant') {
                _openAiAssistant();
              } else if (val == 'create_reminder') {
                _openCreateReminder();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'ai_assistant',
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 18, color: Color(0xFF0D7A68)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Trợ lý AI Gia đình (Gemini)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'create_reminder',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded,
                        size: 18, color: primaryColor),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Tạo lời nhắc mới',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'full_calendar',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new_rounded,
                        size: 18, color: primaryColor),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Mở trang Lịch toàn màn hình',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
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
              ? allReminders
                  .where((r) => r.assignedTo == _currentUserId)
                  .toList()
              : allReminders;

          // 2. Lọc theo từ khóa tìm kiếm (Title, Ghi chú giọng nói, hoặc Tên/Vai trò người nhận)
          final searchedReminders = _searchQuery.isEmpty
              ? scopedReminders
              : scopedReminders.where((r) {
                  final q = _searchQuery.toLowerCase();
                  final titleMatch = r.title.toLowerCase().contains(q);
                  final voiceDescMatch =
                      (r.voiceNoteDescription ?? '').toLowerCase().contains(q);
                  final directAssigneeMatch =
                      r.assignedToName.toLowerCase().contains(q);
                  final member = _familyMembers.firstWhere(
                    (m) => m.id == r.assignedTo,
                    orElse: () => const FamilyMember(
                      id: '',
                      name: '',
                      role: '',
                      familyId: '',
                    ),
                  );
                  final assigneeMatch = directAssigneeMatch ||
                      member.name.toLowerCase().contains(q) ||
                      member.role.toLowerCase().contains(q);
                  return titleMatch || voiceDescMatch || assigneeMatch;
                }).toList();

          final selectedDateStr = _formatDate(_selectedDate);
          final displayedReminders = _showAll
              ? searchedReminders
              : searchedReminders
                  .where((r) => r.date == selectedDateStr)
                  .toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                children: [
                  // Thanh lọc phạm vi: [👨‍👩‍👧 Cả nhà] vs [👤 Việc của tôi]
                  ReminderScopeFilterChips(
                    filterOnlyMine: _filterOnlyMine,
                    onScopeChanged: (val) =>
                        setState(() => _filterOnlyMine = val),
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
              ),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FloatingActionButton.extended(
                  heroTag: 'fab_create_reminder',
                  onPressed: _openCreateReminder,
                  backgroundColor: primaryColor,
                  elevation: 4,
                  icon: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  label: const Text(
                    'Tạo lời nhắc',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: FloatingActionButton.extended(
                  heroTag: 'fab_ai_assistant',
                  onPressed: _openAiAssistant,
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  icon: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: const Text(
                    'Trợ lý AI',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

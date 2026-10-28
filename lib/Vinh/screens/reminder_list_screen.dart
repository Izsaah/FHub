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
  final List<FamilyOption>? families;
  final Map<String, List<FamilyMember>>? membersByFamilyId;
  final String? currentUserId;
  final String? currentUserName;
  final List<FamilyMember>? familyMembers;
  final ReminderRepository? repository;
  final ValueChanged<String>? onUserChanged;

  const ReminderListScreen({
    super.key,
    this.familyId,
    this.families,
    this.membersByFamilyId,
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
  String _familyId = '';
  List<FamilyOption> _families = [];
  Map<String, String> _familyNamesById = {};
  Map<String, List<FamilyMember>> _membersByFamilyId = {};
  late String _currentUserId;
  late String _currentUserName;
  late List<FamilyMember> _familyMembers;
  late ReminderRepository _repository;
  bool _isLoading = true;
  bool _hasFamily = false;

  String get _currentFamilyName =>
      _familyNamesById[_familyId] ??
      (_families.where((f) => f.id == _familyId).map((f) => f.name).firstOrNull ??
          'Gia đình của tôi');

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
    if (widget.families != null &&
        widget.families!.isNotEmpty &&
        widget.currentUserId != null) {
      _hasFamily = true;
      _families = FamilyOption.sortAlphabetically(widget.families!);
      _familyNamesById = {for (final f in _families) f.id: f.name};
      if (widget.familyId != null &&
          widget.familyId!.isNotEmpty &&
          _families.any((f) => f.id == widget.familyId)) {
        _familyId = widget.familyId!;
      } else {
        // Mặc định chọn family đầu tiên theo bảng chữ cái (Alphabet A -> Z)
        _familyId = _families.first.id;
      }
      _currentUserId = widget.currentUserId!;
      _currentUserName = widget.currentUserName ?? 'Minh';
      _membersByFamilyId = widget.membersByFamilyId != null
          ? Map<String, List<FamilyMember>>.from(widget.membersByFamilyId!)
          : {};
      if (widget.familyMembers != null &&
          !_membersByFamilyId.containsKey(_familyId)) {
        _membersByFamilyId[_familyId] =
            List<FamilyMember>.from(widget.familyMembers!);
      }
      _familyMembers =
          _membersByFamilyId[_familyId] ?? widget.familyMembers ?? [];
      _repository = widget.repository ?? FirebaseReminderRepository();
      _isLoading = false;
    } else if (widget.familyId != null &&
        widget.familyId!.isNotEmpty &&
        widget.currentUserId != null &&
        widget.familyMembers != null) {
      _hasFamily = true;
      _familyId = widget.familyId!;
      _families = [
        FamilyOption(id: _familyId, name: 'Gia đình của tôi'),
      ];
      _familyNamesById = {_familyId: 'Gia đình của tôi'};
      _membersByFamilyId = {
        _familyId: List<FamilyMember>.from(widget.familyMembers!),
      };
      _currentUserId = widget.currentUserId!;
      _currentUserName = widget.currentUserName ?? 'Minh';
      _familyMembers = widget.familyMembers!;
      _repository = widget.repository ?? FirebaseReminderRepository();
      _isLoading = false;
    } else {
      _resolveContext();
    }
  }

  Future<List<FamilyMember>> _loadMembersForFamilyFromFirestore(
    FirebaseFirestore firestore,
    String famId,
    String currentUid,
    String currentUname,
  ) async {
    final List<FamilyMember> members = [];
    try {
      final membersSnap = await firestore
          .collection('family_members')
          .where('familyId', isEqualTo: famId)
          .get()
          .timeout(const Duration(seconds: 3));

      for (final mDoc in membersSnap.docs) {
        final mData = mDoc.data();
        final status = (mData['status'] ?? 'ACTIVE').toString();
        if (status != 'ACTIVE') continue;

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
          memberName = memberUid == currentUid ? currentUname : 'Thành viên';
        }

        members.add(FamilyMember(
          id: memberUid.isNotEmpty ? memberUid : mDoc.id,
          name: memberName,
          role: role,
          avatarType: avatarType,
          familyId: famId,
          rewardStarsTotal: (mData['rewardStarsTotal'] ??
              mData['reward_stars_total'] ??
              0) as int,
        ));
      }
    } catch (_) {}
    return members;
  }

  Future<void> _resolveContext() async {
    try {
      String? userId = widget.currentUserId;
      String? userName = widget.currentUserName;
      List<FamilyOption> resolvedFamilies = widget.families != null
          ? List<FamilyOption>.from(widget.families!)
          : [];
      Map<String, List<FamilyMember>> resolvedMembersByFam =
          widget.membersByFamilyId != null
              ? Map<String, List<FamilyMember>>.from(widget.membersByFamilyId!)
              : {};

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

      // 2. Resolve ALL Families (1 người có thể tham gia N gia đình) and Members from Cloud Firestore
      if (Firebase.apps.isNotEmpty && resolvedFamilies.isEmpty) {
        final firestore = FirebaseFirestore.instance;
        final Map<String, String> familyIdToRole = {};

        // 2a. Lấy tất cả các family_members đang ACTIVE của người dùng
        try {
          final memberDocs = await firestore
              .collection('family_members')
              .where('userId', isEqualTo: userId)
              .get()
              .timeout(const Duration(seconds: 3));
          for (final doc in memberDocs.docs) {
            final data = doc.data();
            final status = (data['status'] ?? 'ACTIVE').toString();
            if (status != 'ACTIVE') continue;
            final fid = (data['familyId'] ?? data['family_id'])?.toString();
            if (fid != null && fid.isNotEmpty) {
              familyIdToRole[fid] = (data['role'] ?? 'Member').toString();
            }
          }
        } catch (_) {}

        // 2b. Kiểm tra thêm trường familyId trong users/{userId} (nếu có)
        try {
          final userDoc = await firestore
              .collection('users')
              .doc(userId)
              .get()
              .timeout(const Duration(seconds: 3));
          if (userDoc.exists && userDoc.data() != null) {
            final uName = userDoc.data()!['name']?.toString();
            if (uName != null && uName.isNotEmpty && widget.currentUserName == null) {
              userName = uName;
            }
            final fid = userDoc.data()!['familyId']?.toString();
            if (fid != null &&
                fid.isNotEmpty &&
                !familyIdToRole.containsKey(fid)) {
              familyIdToRole[fid] = 'Member';
            }
          }
        } catch (_) {}

        if (widget.familyId != null &&
            widget.familyId!.isNotEmpty &&
            !familyIdToRole.containsKey(widget.familyId)) {
          familyIdToRole[widget.familyId!] = 'Member';
        }

        // 2c. Tải thông tin chi tiết (tên gia đình, mã mời) của từng family
        for (final entry in familyIdToRole.entries) {
          final fid = entry.key;
          String famName = 'Gia đình';
          String? joinCode;
          try {
            final famDoc = await firestore
                .collection('families')
                .doc(fid)
                .get()
                .timeout(const Duration(seconds: 3));
            if (famDoc.exists && famDoc.data() != null) {
              famName = famDoc.data()!['name']?.toString() ?? 'Gia đình';
              joinCode = (famDoc.data()!['joinCode'] ??
                      famDoc.data()!['join_code'])
                  ?.toString();
            }
          } catch (_) {}

          resolvedFamilies.add(
            FamilyOption(
              id: fid,
              name: famName,
              joinCode: joinCode,
              role: entry.value,
            ),
          );
        }

        // 2d. Sắp xếp danh sách gia đình theo thứ tự bảng chữ cái (A -> Z)
        resolvedFamilies = FamilyOption.sortAlphabetically(resolvedFamilies);

        // 2e. Tải danh sách thành viên cho các gia đình của người dùng
        for (final fam in resolvedFamilies) {
          if (!resolvedMembersByFam.containsKey(fam.id)) {
            final members = await _loadMembersForFamilyFromFirestore(
              firestore,
              fam.id,
              userId,
              userName!,
            );
            resolvedMembersByFam[fam.id] = members;
          }
        }
      }

      if (resolvedFamilies.isEmpty &&
          widget.familyId != null &&
          widget.familyId!.isNotEmpty) {
        resolvedFamilies = [
          FamilyOption(id: widget.familyId!, name: 'Gia đình của tôi'),
        ];
        if (widget.familyMembers != null) {
          resolvedMembersByFam[widget.familyId!] =
              List<FamilyMember>.from(widget.familyMembers!);
        }
      }

      resolvedFamilies = FamilyOption.sortAlphabetically(resolvedFamilies);

      // Mặc định chọn family đầu tiên theo bảng chữ cái (hoặc familyId được truyền vào nếu hợp lệ)
      String selectedFamilyId = '';
      if (widget.familyId != null &&
          widget.familyId!.isNotEmpty &&
          resolvedFamilies.any((f) => f.id == widget.familyId)) {
        selectedFamilyId = widget.familyId!;
      } else if (_familyId.isNotEmpty &&
          resolvedFamilies.any((f) => f.id == _familyId)) {
        selectedFamilyId = _familyId;
      } else if (resolvedFamilies.isNotEmpty) {
        selectedFamilyId = resolvedFamilies.first.id;
      }

      final bool hasFamily = selectedFamilyId.isNotEmpty &&
          !selectedFamilyId.startsWith('family_current_user');

      final resolvedMembers = resolvedMembersByFam[selectedFamilyId] ??
          (widget.familyMembers != null
              ? List<FamilyMember>.from(widget.familyMembers!)
              : <FamilyMember>[]);

      if (mounted) {
        setState(() {
          _hasFamily = hasFamily;
          _families = resolvedFamilies;
          _familyNamesById = {
            for (final f in resolvedFamilies) f.id: f.name,
          };
          _membersByFamilyId = resolvedMembersByFam;
          _familyId = selectedFamilyId;
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

  Future<void> _selectFamily(FamilyOption family) async {
    if (_familyId == family.id) return;
    HapticFeedback.selectionClick();
    setState(() {
      _familyId = family.id;
      _familyMembers = _membersByFamilyId[family.id] ?? [];
    });

    if (_familyMembers.isEmpty && Firebase.apps.isNotEmpty) {
      final loaded = await _loadMembersForFamilyFromFirestore(
        FirebaseFirestore.instance,
        family.id,
        _currentUserId,
        _currentUserName,
      );
      if (mounted) {
        setState(() {
          _membersByFamilyId[family.id] = loaded;
          if (_familyId == family.id) {
            _familyMembers = loaded;
          }
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
          familyName: _currentFamilyName,
          families: _families,
          membersByFamilyId: _membersByFamilyId,
          currentUserId: _currentUserId,
          currentUserName: _currentUserName,
          familyMembers: _familyMembers,
          repository: _repository,
        ),
      ),
    );
    setState(() {});
  }

  List<FamilyMember> _getMembersForReminder(ReminderModel reminder) {
    return _membersByFamilyId[reminder.familyId] ?? _familyMembers;
  }

  bool _canDeleteReminder(ReminderModel reminder) {
    if (reminder.creatorId == _currentUserId) return true;
    final members = _getMembersForReminder(reminder);
    final currentMember = members.firstWhere(
      (m) => m.id == _currentUserId,
      orElse: () =>
          const FamilyMember(id: '', name: '', role: '', familyId: ''),
    );
    return currentMember.isParent || currentMember.isGrandparent;
  }

  Future<void> _confirmAndDelete(ReminderModel reminder) async {
    final targetMembers = _getMembersForReminder(reminder);
    if (!_canDeleteReminder(reminder)) {
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
          familyMembers: targetMembers,
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
                      familyMembers: targetMembers,
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
    final resolvedFamName =
        (reminder.familyName != null && reminder.familyName!.trim().isNotEmpty)
            ? reminder.familyName!
            : (_familyNamesById[reminder.familyId] ?? _currentFamilyName);
    ReminderDetailBottomSheet.show(
      context,
      reminder: reminder,
      currentUserId: _currentUserId,
      currentUserName: _currentUserName,
      familyName: resolvedFamName,
      repository: _repository,
      familyMembers: _getMembersForReminder(reminder),
      onReminderUpdated: () => setState(() {}),
    );
  }

  void _showFamilyPickerBottomSheet() {
    showModalBottomSheet<FamilyOption>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(
                          Icons.home_work_rounded,
                          color: Color(0xFF005F50),
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Chọn gia đình hiển thị',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF151D1B),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE4F6EF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'A → Z (${_families.length})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF005F50),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Danh sách lời nhắc tổng (Cả nhà) sẽ chỉ hiển thị các lời nhắc thuộc gia đình bạn chọn bên dưới.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6E7A75),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _families.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final fam = _families[index];
                          final isSelected = fam.id == _familyId;
                          final memberCount =
                              _membersByFamilyId[fam.id]?.length ?? 0;
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.of(ctx).pop(fam);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFE4F6EF)
                                    : const Color(0xFFF7FBF9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF005F50)
                                      : const Color(0xFFDCE8E3),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: isSelected
                                        ? const Color(0xFF005F50)
                                        : const Color(0xFFDCE8E3),
                                    child: Text(
                                      fam.name.isNotEmpty
                                          ? fam.name[0].toUpperCase()
                                          : 'G',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? Colors.white
                                            : const Color(0xFF005F50),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fam.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? const Color(0xFF005F50)
                                                : const Color(0xFF151D1B),
                                          ),
                                        ),
                                        if (memberCount > 0 ||
                                            (fam.role != null &&
                                                fam.role!.isNotEmpty))
                                          Text(
                                            [
                                              if (memberCount > 0)
                                                '$memberCount thành viên',
                                              if (fam.role != null &&
                                                  fam.role!.isNotEmpty)
                                                'Vai trò: ${fam.role}',
                                            ].join(' • '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF6E7A75),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF005F50),
                                      size: 22,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).then((picked) {
      if (picked != null) {
        _selectFamily(picked);
      }
    });
  }

  Widget _buildFamilyContextBar() {
    if (_filterOnlyMine) {
      // Phần cá nhân: Mỗi ReminderCard đã hiển thị trực tiếp huy hiệu 🏠 <Tên Gia đình>
      return const SizedBox.shrink();
    }

    // Phần list remind tổng (Cả nhà): Có mục Chọn Family (mặc định family đầu tiên theo alphabet)
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: InkWell(
        onTap: _showFamilyPickerBottomSheet,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBDC9C4)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.home_work_rounded,
                size: 15,
                color: Color(0xFF005F50),
              ),
              const SizedBox(width: 6),
              const Text(
                'Chọn gia đình:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6E7A75),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _currentFamilyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF005F50),
                  ),
                ),
              ),
              if (_families.length > 1)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F6EF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_families.length} nhà',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF005F50),
                    ),
                  ),
                ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF005F50),
                size: 18,
              ),
            ],
          ),
        ),
      ),
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
        stream: _filterOnlyMine
            ? _repository.watchRemindersForFamilies(
                familyIds: _families.isNotEmpty
                    ? _families.map((f) => f.id).toList()
                    : [_familyId],
              )
            : _repository.watchReminders(familyId: _familyId),
        builder: (context, snapshot) {
          final allReminders = snapshot.data ?? [];

          // 1. Lọc theo Scope:
          // - Cả nhà (!_filterOnlyMine): Chỉ hiện lời nhắc thuộc family đang được chọn (_familyId)
          // - Việc của tôi (_filterOnlyMine): Hiện việc cá nhân của tôi trên các family kèm nhãn family
          final scopedReminders = _filterOnlyMine
              ? allReminders
                  .where((r) => r.assignedTo == _currentUserId)
                  .toList()
              : allReminders
                  .where((r) => r.familyId == _familyId)
                  .toList();

          // 2. Lọc theo từ khóa tìm kiếm (Title, Ghi chú giọng nói, Gia đình, hoặc Tên/Vai trò người nhận)
          final searchedReminders = _searchQuery.isEmpty
              ? scopedReminders
              : scopedReminders.where((r) {
                  final q = _searchQuery.toLowerCase();
                  final titleMatch = r.title.toLowerCase().contains(q);
                  final voiceDescMatch =
                      (r.voiceNoteDescription ?? '').toLowerCase().contains(q);
                  final famName =
                      (r.familyName ?? _familyNamesById[r.familyId] ?? '')
                          .toLowerCase();
                  final familyMatch = famName.contains(q);
                  final directAssigneeMatch =
                      r.assignedToName.toLowerCase().contains(q);
                  final famMembers = _getMembersForReminder(r);
                  final member = famMembers.firstWhere(
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
                  return titleMatch ||
                      voiceDescMatch ||
                      familyMatch ||
                      assigneeMatch;
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

                  // Thanh chọn Family (ở chế độ Cả nhà) hoặc hiển thị ngữ cảnh đa gia đình (ở chế độ Việc của tôi)
                  _buildFamilyContextBar(),

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
                      allReminders: scopedReminders,
                      displayedReminders: displayedReminders,
                      currentUserId: _currentUserId,
                      selectedDateStr: selectedDateStr,
                      isShowingAll: _showAll,
                      isParentOrOwner: _familyMembers.any(
                        (m) =>
                            m.id == _currentUserId &&
                            (m.isParent || m.isGrandparent),
                      ),
                      familyNamesById: _familyNamesById,
                      showFamilyBadge: _filterOnlyMine,
                      canDeletePredicate: _canDeleteReminder,
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

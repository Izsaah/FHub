import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Khoa/screens/family_setup_screen.dart';
import '../../Long/screens/family/family_screen.dart';
import '../../Long/services/family_data_service.dart';
import '../../Thinh/theme/app_language.dart';
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
import 'wishlist_and_ledger_screen.dart';
import '../../Danh/danh_payment_entry.dart';
import '../widgets/multi_tier_simulation_dialog.dart';
import '../widgets/parent_triage_actions_widget.dart';
import 'views/reminder_calendar_view.dart';
import 'views/reminder_list_view.dart';

/// Coordinator Screen quản lý màn hình chính của tính năng Lời nhắc (Reminders).
/// Điều phối giữa List View và Calendar View, tìm kiếm, lọc theo ngày và cá nhân.
/// Hỗ trợ realtime đồng bộ khi gia đình bị xóa/rời, đa ngôn ngữ VN/EN, và phản hồi mượt mà trên mọi thiết bị.
/// Chỉ cho phép sử dụng tính năng khi đang tham gia gia đình hợp lệ.
class ReminderListScreen extends StatefulWidget {
  final String? familyId;
  final List<FamilyOption>? families;
  final Map<String, List<FamilyMember>>? membersByFamilyId;
  final String? currentUserId;
  final String? currentUserName;
  final List<FamilyMember>? familyMembers;
  final ReminderRepository? repository;
  final ValueChanged<String>? onUserChanged;
  final VoidCallback? onNavigateToFamily;
  final bool initialShowAll;
  final bool isActive;

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
    this.onNavigateToFamily,
    this.initialShowAll = false,
    this.isActive = true,
  });

  @override
  State<ReminderListScreen> createState() => _ReminderListScreenState();
}

class _ReminderListScreenState extends State<ReminderListScreen>
    with WidgetsBindingObserver {
  String _familyId = '';
  List<FamilyOption> _families = [];
  Map<String, String> _familyNamesById = {};
  Map<String, List<FamilyMember>> _membersByFamilyId = {};
  String _currentUserId = '';
  String _currentUserName = '';
  List<FamilyMember> _familyMembers = [];
  ReminderRepository _repository = FirebaseReminderRepository();
  bool _isLoading = true;
  bool _hasFamily = false;

  String get _currentFamilyName =>
      _familyNamesById[_familyId] ??
      (_families.where((f) => f.id == _familyId).map((f) => f.name).firstOrNull ??
          AppLanguage.text('Gia đình của tôi', 'My Family'));

  bool _isCalendarView = false;
  DateTime _currentMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDate = DateTime.now();
  late bool _showAll;
  bool _filterOnlyMine = false;
  bool _isSearchOpen = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Timer? _deleteSnackBarTimer;
  Timer? _clockTicker;
  List<ReminderModel> _lastLoadedReminders = [];
  Stream<List<ReminderModel>>? _remindersStream;
  String? _cachedStreamFamilyId;
  bool? _cachedStreamFilterOnlyMine;

  Stream<List<ReminderModel>> _getRemindersStream() {
    if (_remindersStream == null ||
        _cachedStreamFamilyId != _familyId ||
        _cachedStreamFilterOnlyMine != _filterOnlyMine) {
      _cachedStreamFamilyId = _familyId;
      _cachedStreamFilterOnlyMine = _filterOnlyMine;
      _remindersStream = _filterOnlyMine
          ? _repository.watchRemindersForFamilies(
              familyIds: _families.isNotEmpty
                  ? _families.map((f) => f.id).toList()
                  : [_familyId],
            )
          : _repository.watchReminders(familyId: _familyId);
    }
    return _remindersStream!;
  }

  String _normalizeName(String s) {
    var res = s.trim().toLowerCase();
    const accents = {
      'à|á|ạ|ả|ã|â|ầ|ấ|ậ|ẩ|ẫ|ă|ằ|ắ|ặ|ẳ|ẵ': 'a',
      'è|é|ề|ẻ|ẽ|ê|ề|ế|ệ|ể|ễ': 'e',
      'ì|í|ị|ỉ|ĩ': 'i',
      'ò|ó|ọ|ỏ|õ|ô|ồ|ố|ộ|ổ|ỗ|ơ|ờ|ớ|ợ|ở|ỡ': 'o',
      'ù|ú|ụ|ủ|ũ|ư|ừ|ứ|ự|ử|ữ': 'u',
      'ỳ|ý|ỵ|ỷ|ỹ': 'y',
      'đ': 'd',
    };
    for (final entry in accents.entries) {
      res = res.replaceAll(RegExp(entry.key), entry.value);
    }
    return res.replaceAll(RegExp(r'\s+'), ' ');
  }

  void _checkDueReminders() {
    if (_lastLoadedReminders.isEmpty || !mounted) return;
    String memberId = '';
    String memberName = '';
    for (final m in _familyMembers) {
      if (m.id == _currentUserId ||
          _normalizeName(m.name) == _normalizeName(_currentUserName)) {
        memberId = m.id;
        memberName = m.name;
        break;
      }
    }
    MultiTierEscalationService.instance.syncReminders(
      _lastLoadedReminders,
      currentUserId: _currentUserId,
      currentUserName: _currentUserName,
      currentUserMemberId: memberId,
      currentUserFamilyName: memberName,
      context: context,
      onOpenDetail: _showDetailBottomSheet,
    );
  }

  // Realtime listeners
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _familyMembersSub;
  String? _lastMembersSubSignature;

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  void initState() {
    super.initState();
    _showAll = widget.initialShowAll;
    // 1. Lắng nghe thay đổi gia đình toàn cục từ FamilyDataService
    FamilyDataService().selectedFamilyIdNotifier.addListener(_onGlobalFamilyNotifierChanged);

    // 2. Khởi tạo dữ liệu người dùng & gia đình
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
        FamilyOption(id: _familyId, name: AppLanguage.text('Gia đình của tôi', 'My Family')),
      ];
      _familyNamesById = {_familyId: AppLanguage.text('Gia đình của tôi', 'My Family')};
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

    // 3. Đăng ký lắng nghe sự kiện thay đổi family_members từ Firestore theo thời gian thực (Realtime)
    _listenToFirestoreFamilyMembers();

    // 4. Lắng nghe Lifecycle và sự kiện Ticker toàn cục
    WidgetsBinding.instance.addObserver(this);
    MultiTierEscalationService.instance.clockTick.addListener(_onClockTick);

    // 5. Ticker đồng hồ thời gian thực mỗi 1 giây: Tự động đổi trạng thái Quá hạn và Bật chuông/thông báo khi tới giờ
    _startClockTicker();
  }

  void _startClockTicker() {
    _clockTicker?.cancel();
    MultiTierEscalationService.instance.ensureClockRunning();
    _clockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      try {
        _checkDueReminders();
      } catch (e) {
        debugPrint('ReminderListScreen clock ticker error: $e');
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MultiTierEscalationService.instance.ensureClockRunning(forceRestart: true);
      _checkDueReminders();
      if (mounted) setState(() {});
    }
  }

  void _onClockTick() {
    if (!mounted) return;
    try {
      _checkDueReminders();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void reassemble() {
    super.reassemble();
    _startClockTicker();
  }

  @override
  void didUpdateWidget(covariant ReminderListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = widget.isActive && !oldWidget.isActive;
    if (becameActive ||
        oldWidget.familyId != widget.familyId ||
        oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.families != widget.families) {
      _resolveContext();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MultiTierEscalationService.instance.clockTick.removeListener(_onClockTick);
    FamilyDataService().selectedFamilyIdNotifier.removeListener(_onGlobalFamilyNotifierChanged);
    _clockTicker?.cancel();
    _clockTicker = null;
    // Global escalation service continues running in background for active family members
    _familyMembersSub?.cancel();
    _deleteSnackBarTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToFirestoreFamilyMembers() {
    if (Firebase.apps.isNotEmpty) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          _familyMembersSub?.cancel();
          _lastMembersSubSignature = null;
          _familyMembersSub = FirebaseFirestore.instance
              .collection('family_members')
              .where('userId', isEqualTo: user.uid)
              .snapshots()
              .listen((snapshot) {
            final parts = <String>[];
            for (final doc in snapshot.docs) {
              final d = doc.data();
              final fid = (d['familyId'] ?? d['family_id'])?.toString() ?? '';
              if (fid.isEmpty) continue;
              final status = (d['status'] ?? 'ACTIVE').toString().toUpperCase();
              final role = (d['role'] ?? '').toString();
              parts.add('$fid:$status:$role');
            }
            parts.sort();
            final sig = parts.join('|');
            if (_lastMembersSubSignature == sig) return;
            final isFirst = _lastMembersSubSignature == null;
            _lastMembersSubSignature = sig;
            if (isFirst && !_isLoading) {
              final activeIds = snapshot.docs
                  .where((d) =>
                      (d.data()['status'] ?? 'ACTIVE')
                          .toString()
                          .toUpperCase() ==
                      'ACTIVE')
                  .map((d) =>
                      (d.data()['familyId'] ?? d.data()['family_id'])
                          ?.toString() ??
                      '')
                  .where((id) => id.isNotEmpty)
                  .toSet();
              final currentIds = _families.map((f) => f.id).toSet();
              if (activeIds.length == currentIds.length &&
                  activeIds.containsAll(currentIds)) {
                return;
              }
            }
            // Khi người dùng tham gia / rời / bị xóa khỏi gia đình -> cập nhật realtime
            if (mounted) {
              _resolveContext();
            }
          });
        }
      } catch (_) {}
    }
  }

  void _onGlobalFamilyNotifierChanged() {
    final newFamilyId = FamilyDataService().selectedFamilyIdNotifier.value;
    if (newFamilyId == null || newFamilyId.isEmpty) {
      // Chỉ reload khi trạng thái hiện tại vẫn đang giữ gia đình cũ
      if (_hasFamily || _familyId.isNotEmpty) {
        _resolveContext();
      }
    } else if (newFamilyId != _familyId) {
      if (_families.any((f) => f.id == newFamilyId)) {
        final fam = _families.firstWhere((f) => f.id == newFamilyId);
        _selectFamily(fam, syncToService: false);
      } else {
        _resolveContext(forcedFamilyId: newFamilyId);
      }
    }
  }

  Future<void> _manualRefresh() async {
    HapticFeedback.lightImpact();
    FamilyDataService().clearCache();
    await _resolveContext();
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Đã cập nhật dữ liệu mới nhất!',
              'Data updated successfully!',
            ),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF005F50),
        ),
      );
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
        final status = (mData['status'] ?? 'ACTIVE').toString().toUpperCase();
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
          memberName = memberUid == currentUid ? currentUname : AppLanguage.text('Thành viên', 'Member');
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

  Future<void> _resolveContext({String? forcedFamilyId}) async {
    try {
      String? userId = widget.currentUserId;
      String? userName = widget.currentUserName;
      List<FamilyOption> resolvedFamilies = [];
      Map<String, List<FamilyMember>> resolvedMembersByFam = {};

      // 1. Resolve Current User from Firebase Auth (Tài khoản chính đang sử dụng)
      if (Firebase.apps.isNotEmpty) {
        try {
          final fbAuth = FirebaseAuth.instance;
          final fbUser = fbAuth.currentUser;
          if (fbUser != null) {
            userId = fbUser.uid;
            userName =
                (fbUser.displayName != null && fbUser.displayName!.isNotEmpty)
                    ? fbUser.displayName!
                    : (fbUser.email?.split('@').first ?? AppLanguage.text('Người dùng', 'User'));

            // Tải thêm tên từ users collection nếu có
            try {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(fbUser.uid)
                  .get()
                  .timeout(const Duration(seconds: 2));
              if (userDoc.exists && userDoc.data() != null) {
                final uName = userDoc.data()!['name']?.toString() ??
                    userDoc.data()!['displayName']?.toString();
                if (uName != null && uName.trim().isNotEmpty) {
                  userName = uName.trim();
                }
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      userId ??= widget.currentUserId ?? 'current_user';
      userName ??= widget.currentUserName ?? AppLanguage.text('Tôi', 'Me');

      // 2. Resolve Active Families - CHỈ LẤY GIA ĐÌNH MÀ USER ĐANG LÀ THÀNH VIÊN ACTIVE
      if (Firebase.apps.isNotEmpty) {
        final firestore = FirebaseFirestore.instance;
        final Map<String, String> familyIdToRole = {};

        // 2a. Lấy tất cả các membership có trạng thái ACTIVE của user
        try {
          final memberDocs = await firestore
              .collection('family_members')
              .where('userId', isEqualTo: userId)
              .get()
              .timeout(const Duration(seconds: 3));
          for (final doc in memberDocs.docs) {
            final data = doc.data();
            final status = (data['status'] ?? 'ACTIVE').toString().toUpperCase();
            if (status != 'ACTIVE') continue;
            final fid = (data['familyId'] ?? data['family_id'])?.toString();
            if (fid != null && fid.isNotEmpty) {
              familyIdToRole[fid] = (data['role'] ?? 'Member').toString();
            }
          }
        } catch (_) {}

        // 2b. Tải thông tin chi tiết của từng family còn tồn tại và KHÔNG bị xóa (deleting != true)
        for (final entry in familyIdToRole.entries) {
          final fid = entry.key;
          try {
            final famDoc = await firestore
                .collection('families')
                .doc(fid)
                .get()
                .timeout(const Duration(seconds: 3));
            if (famDoc.exists && famDoc.data() != null) {
              final famData = famDoc.data()!;
              if (famData['deleting'] == true) continue;
              final famName = famData['name']?.toString() ?? AppLanguage.text('Gia đình', 'Family');
              final joinCode = (famData['joinCode'] ?? famData['join_code'])?.toString();
              resolvedFamilies.add(
                FamilyOption(
                  id: fid,
                  name: famName,
                  joinCode: joinCode,
                  role: entry.value,
                ),
              );
            }
          } catch (_) {}
        }

        // 2c. Sắp xếp danh sách gia đình theo thứ tự bảng chữ cái (A -> Z)
        resolvedFamilies = FamilyOption.sortAlphabetically(resolvedFamilies);

        // 2d. Tải danh sách thành viên cho các gia đình của người dùng
        for (final fam in resolvedFamilies) {
          final members = await _loadMembersForFamilyFromFirestore(
            firestore,
            fam.id,
            userId,
            userName,
          );
          resolvedMembersByFam[fam.id] = members;
        }
      }

      // Xử lý fallback cho test / mock nếu không có Firebase
      if (resolvedFamilies.isEmpty && Firebase.apps.isEmpty) {
        if (widget.families != null && widget.families!.isNotEmpty) {
          resolvedFamilies = List<FamilyOption>.from(widget.families!);
          if (widget.membersByFamilyId != null) {
            resolvedMembersByFam =
                Map<String, List<FamilyMember>>.from(widget.membersByFamilyId!);
          }
        } else if (widget.familyId != null && widget.familyId!.isNotEmpty) {
          resolvedFamilies = [
            FamilyOption(id: widget.familyId!, name: AppLanguage.text('Gia đình của tôi', 'My Family')),
          ];
          if (widget.familyMembers != null) {
            resolvedMembersByFam[widget.familyId!] =
                List<FamilyMember>.from(widget.familyMembers!);
          }
        }
      }

      resolvedFamilies = FamilyOption.sortAlphabetically(resolvedFamilies);

      // 3. Quyết định Active Family:
      // - Nếu không còn gia đình nào (User đã xóa hoặc out hết): hasFamily = false -> Hiện Empty State
      // - Nếu gia đình hiện tại bị xóa, tự động chuyển về gia đình đầu tiên còn lại hoặc forcedFamilyId
      final bool hasFamily = resolvedFamilies.isNotEmpty;
      String selectedFamilyId = '';

      if (hasFamily) {
        final globalSelected = FamilyDataService().selectedFamilyIdNotifier.value;
        if (forcedFamilyId != null &&
            forcedFamilyId.isNotEmpty &&
            resolvedFamilies.any((f) => f.id == forcedFamilyId)) {
          selectedFamilyId = forcedFamilyId;
        } else if (globalSelected != null &&
            globalSelected.isNotEmpty &&
            resolvedFamilies.any((f) => f.id == globalSelected)) {
          selectedFamilyId = globalSelected;
        } else if (_familyId.isNotEmpty &&
            resolvedFamilies.any((f) => f.id == _familyId)) {
          selectedFamilyId = _familyId;
        } else {
          selectedFamilyId = resolvedFamilies.first.id;
        }
      }

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

        // Đồng bộ ngược lại vào FamilyDataService & dọn con trỏ familyId cũ nếu không còn gia đình
        if (hasFamily && selectedFamilyId.isNotEmpty) {
          if (FamilyDataService().selectedFamilyId != selectedFamilyId) {
            FamilyDataService().selectFamily(selectedFamilyId);
          }
        } else {
          if (Firebase.apps.isNotEmpty) {
            try {
              final fbUser = FirebaseAuth.instance.currentUser;
              if (fbUser != null) {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(fbUser.uid)
                    .update({
                  'familyId': FieldValue.delete(),
                  'family_id': FieldValue.delete(),
                }).catchError((_) {});
              }
            } catch (_) {}
          }
          if (FamilyDataService().selectedFamilyId != null) {
            FamilyDataService().resetAll();
          }
        }
      }
    } catch (e) {
      debugPrint('ReminderListScreen _resolveContext error: $e');
      final fallbackUserId = widget.currentUserId ?? 'current_user';
      final fallbackUserName = widget.currentUserName ?? AppLanguage.text('Tôi', 'Me');

      if (mounted) {
        setState(() {
          _hasFamily = false;
          _familyId = '';
          _families = [];
          _currentUserId = fallbackUserId;
          _currentUserName = fallbackUserName;
          _familyMembers = widget.familyMembers ?? [];
          _repository = widget.repository ?? FirebaseReminderRepository();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectFamily(FamilyOption family, {bool syncToService = true}) async {
    if (_familyId == family.id) return;
    HapticFeedback.selectionClick();
    setState(() {
      _familyId = family.id;
      _familyMembers = _membersByFamilyId[family.id] ?? [];
    });
    if (syncToService) {
      FamilyDataService().selectFamily(family.id);
    }

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

  Future<void> _openCreateReminder() async {
    if (!_hasFamily || _familyId.trim().isEmpty) return;
    if (DanhPaymentEntry.isOverCapacityFrozen) {
      await DanhPaymentEntry.showOverCapacityFrozenDialog(context);
      return;
    }
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

  Future<void> _openWishlistShop() async {
    final currentRole = _familyMembers
            .where((m) => m.id == _currentUserId)
            .map((m) => m.role)
            .firstOrNull ??
        'PARENT';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => WishlistAndLedgerScreen(
          familyId: _familyId.isNotEmpty ? _familyId : 'f1',
          currentUserId: _currentUserId,
          currentUserName: _currentUserName,
          currentUserRole: currentRole,
          familyMembers: _familyMembers,
        ),
      ),
    );
    if (mounted) setState(() {});
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
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Chỉ người tạo hoặc Bố Mẹ/Chủ nhà mới có thể xóa lời nhắc này.',
              'Only the creator or Parents/Owner can delete this reminder.',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
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
        title: Text(
          AppLanguage.text('Xóa lời nhắc', 'Delete reminder'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          AppLanguage.text(
            'Bạn có chắc chắn muốn xóa lời nhắc "${reminder.title}"? (Hành động này có thể hoàn tác trong 10 giây).',
            'Are you sure you want to delete "${reminder.title}"? (Can be undone within 10 seconds).',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(AppLanguage.text('Hủy', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(AppLanguage.text('Xóa', 'Delete')),
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
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          final controller = messenger.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 10),
              content: Text(
                AppLanguage.text(
                  'Đã xóa "${reminder.title}".',
                  'Deleted "${reminder.title}".',
                ),
              ),
              action: SnackBarAction(
                label: AppLanguage.text('HOÀN TÁC', 'UNDO'),
                textColor: const Color(0xFFaaffe9),
                onPressed: () async {
                  _deleteSnackBarTimer?.cancel();
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
          _deleteSnackBarTimer?.cancel();
          _deleteSnackBarTimer = Timer(const Duration(seconds: 10), () {
            try {
              controller.close();
            } catch (_) {}
          });
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
          return;
        }
      }

      HapticFeedback.mediumImpact();
      if (reminder.requiresProofImage && proofUrl != null) {
        await _repository.submitTaskWithProof(
          taskId: reminder.id,
          proofImageUrl: proofUrl,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLanguage.text(
                  '📸 Đã nộp ảnh nghiệm thu! Đang chờ Bố Mẹ/Ông Bà duyệt sao.',
                  '📸 Proof submitted! Waiting for Guardian approval and stars.',
                ),
              ),
              backgroundColor: const Color(0xFF0D7A68),
            ),
          );
          setState(() {});
        }
        return;
      }

      await _repository.completeReminder(
        reminderId: reminder.id,
        currentUserId: _currentUserId,
        proofImageUrl: proofUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text('Đã hoàn thành công việc!', 'Task completed successfully!'),
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
              AppLanguage.text(
                '🎉 Bạn đã xung phong nhận việc "${reminder.title}" thành công!',
                '🎉 You claimed "${reminder.title}" successfully!',
              ),
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
          return;
        }
      }

      HapticFeedback.mediumImpact();
      if (reminder.requiresProofImage && proofUrl != null) {
        await _repository.claimOpenTask(
          reminderId: reminder.id,
          currentUserId: _currentUserId,
          currentUserName: _currentUserName,
        );
        await _repository.submitTaskWithProof(
          taskId: reminder.id,
          proofImageUrl: proofUrl,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLanguage.text(
                  '📸 Đã nhận việc và nộp ảnh nghiệm thu! Đang chờ Bố Mẹ/Ông Bà duyệt sao.',
                  '📸 Claimed and proof submitted! Waiting for Guardian approval and stars.',
                ),
              ),
              backgroundColor: const Color(0xFF0D7A68),
            ),
          );
          setState(() {});
        }
        return;
      }

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
              AppLanguage.text(
                '🎉 Bạn đã hoàn thành việc chung "${reminder.title}" xuất sắc!',
                '🎉 You completed the shared task "${reminder.title}"!',
              ),
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
    if (!_hasFamily || _familyId.trim().isEmpty) return;
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
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thanh kéo (handle bar)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Header
              Row(
                children: [
                  const Icon(
                    Icons.home_work_rounded,
                    color: Color(0xFF005F50),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLanguage.text('Chọn gia đình hiển thị', 'Select Active Family'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF151D1B),
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              Text(
                AppLanguage.text(
                  'Danh sách lời nhắc tổng (Cả nhà) sẽ chỉ hiển thị các lời nhắc thuộc gia đình bạn chọn bên dưới.',
                  'The all-family reminder list will only show reminders from the family you select below.',
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF6E7A75),
                ),
              ),
              const SizedBox(height: 14),

              // Danh sách gia đình: Giới hạn tối đa 5 mục hiển thị, nếu > 5 thì cuộn
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(_families.length, 5) * 58.0,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: _families.length > 5
                      ? const AlwaysScrollableScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: _families.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final fam = _families[index];
                    final isSelected = fam.id == _familyId;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(ctx).pop(fam);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFE4F6EF)
                              : const Color(0xFFF7FBF9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF005F50)
                                : const Color(0xFFDCE8E3),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF005F50)
                                    : const Color(0xFFE4F6EF),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.cottage_rounded,
                                size: 16,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF005F50),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                fam.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? const Color(0xFF005F50)
                                      : const Color(0xFF151D1B),
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF005F50),
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              // Nút Tạo / Tham gia thêm gia đình
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: Color(0xFF005F50)),
                  foregroundColor: const Color(0xFF005F50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_home_work_outlined, size: 18),
                label: Text(
                  AppLanguage.text(
                    '+ Tạo hoặc tham gia gia đình khác',
                    '+ Create or join another family',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FamilySetupScreen(),
                    ),
                  );
                  _resolveContext();
                },
              ),
            ],
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

    // Phần list remind tổng (Cả nhà):
    // Phía trái là cụm "Chọn gia đình: <Tên Gia Đình> ⌄"
    // Phía phải neo chặt các icon hành động: Số nhà, Nút reload, Nút mở trang gia đình (Lấy phải làm gốc dời vào trái)
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBDC9C4)),
        ),
        child: Row(
          children: [
            // Cụm Chọn Gia đình bên trái (Có thể bấm để mở BottomSheet chọn family)
            Expanded(
              child: InkWell(
                onTap: _showFamilyPickerBottomSheet,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.home_work_rounded,
                      size: 16,
                      color: Color(0xFF005F50),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppLanguage.text('Chọn gia đình:', 'Select family:'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6E7A75),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
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
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF005F50),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),

            // Các nút tiện ích neo chặt vào mép phải (lấy phải làm gốc rồi dời vào trái)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_families.length > 1)
                  InkWell(
                    onTap: _showFamilyPickerBottomSheet,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4F6EF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        AppLanguage.text(
                          '${_families.length} nhà',
                          '${_families.length} families',
                        ),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF005F50),
                        ),
                      ),
                    ),
                  ),

                // Nút Làm mới danh sách
                Tooltip(
                  message: AppLanguage.text('Làm mới danh sách', 'Refresh list'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _manualRefresh,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 16,
                        color: Color(0xFF005F50),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Nút Xem trang gia đình (nằm ở vị trí ngoài cùng bên phải)
                Tooltip(
                  message: AppLanguage.text('Xem trang gia đình', 'Go to family screen'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      if (widget.onNavigateToFamily != null) {
                        widget.onNavigateToFamily!();
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FamilyScreen(),
                          ),
                        );
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: Color(0xFF005F50),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        const primaryColor = Color(0xFF005F50);
        const textPrimary = Color(0xFF151D1B);
        final screenWidth = MediaQuery.of(context).size.width;
        final isSmallScreen = screenWidth < 360;
        final horizontalPad = isSmallScreen ? 10.0 : 16.0;

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
              title: Text(
                AppLanguage.text('Lời nhắc gia đình', 'Family Reminders'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.white,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: primaryColor),
                  tooltip: AppLanguage.text('Làm mới', 'Refresh'),
                  onPressed: _manualRefresh,
                ),
              ],
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
                      Text(
                        AppLanguage.text(
                          'Bạn chưa tham gia gia đình nào.',
                          "You haven't joined a family yet.",
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF151D1B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppLanguage.text(
                          'Tính năng Lời nhắc và Phân công việc nhà hoạt động dựa trên không gian gia đình chung.\n\nVui lòng tạo gia đình mới hoặc tham gia bằng mã mời để bắt đầu quản lý lời nhắc cùng người thân!',
                          'Family Reminders and Chores require a shared family space.\n\nPlease create a new family or join with an invitation code to manage reminders with your loved ones!',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6E7A75),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.group_add_rounded),
                          label: Text(
                            AppLanguage.text(
                              'Tạo hoặc tham gia gia đình',
                              'Create or Join Family',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const FamilySetupScreen(),
                              ),
                            );
                            FamilyDataService().clearCache();
                            setState(() => _isLoading = true);
                            _resolveContext();
                          },
                        ),
                      ),
                      if (widget.onNavigateToFamily != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: const BorderSide(color: primaryColor),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.family_restroom_rounded),
                            label: Text(
                              AppLanguage.text('Đến mục Gia đình', 'Go to Family'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: widget.onNavigateToFamily,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF6E7A75),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          AppLanguage.text(
                            'Kiểm tra lại trạng thái',
                            'Check status again',
                          ),
                          style: const TextStyle(fontSize: 13),
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
                      hintText: AppLanguage.text('Tìm kiếm nhắc nhở...', 'Search reminders...'),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLanguage.text('Tổ Ấm Yêu Thương', 'Family Hub'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: primaryColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (_currentFamilyName.isNotEmpty)
                        Text(
                          _currentFamilyName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: primaryColor.withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  size: 22,
                ),
                tooltip: _isSearchOpen
                    ? AppLanguage.text('Đóng tìm kiếm', 'Close search')
                    : AppLanguage.text('Tìm kiếm nhắc nhở', 'Search reminders'),
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
              // Nút làm mới dữ liệu nhanh (Realtime Sync Trigger)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: primaryColor, size: 22),
                tooltip: AppLanguage.text('Làm mới dữ liệu', 'Refresh data'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _manualRefresh,
              ),
              // Chuyển đổi qua lại giữa List View và Calendar View
              IconButton(
                key: const Key('btn_open_wishlist_shop'),
                icon: const Icon(
                  Icons.stars_rounded,
                  color: Color(0xFFE65100),
                  size: 22,
                ),
                tooltip: AppLanguage.text(
                  'Cửa hàng Đổi Sao & Sổ cái ⭐',
                  'Star Shop & Ledger ⭐',
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _openWishlistShop,
              ),
              IconButton(
                icon: Icon(
                  _isCalendarView
                      ? Icons.format_list_bulleted_rounded
                      : Icons.calendar_month_rounded,
                  color: primaryColor,
                  size: 22,
                ),
                tooltip: _isCalendarView
                    ? AppLanguage.text('Chuyển sang chế độ Danh sách (List View)', 'Switch to List View')
                    : AppLanguage.text('Chuyển sang chế độ Lịch (Calendar View)', 'Switch to Calendar View'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () {
                  setState(() {
                    _isCalendarView = !_isCalendarView;
                  });
                },
              ),
              // Menu mở rộng: Trợ lý AI, Tạo lời nhắc, Lịch toàn màn hình, Làm mới
              PopupMenuButton<String>(
                tooltip: AppLanguage.text('Tùy chọn khác', 'More options'),
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
                  } else if (val == 'demo_simulation') {
                    final targetTask = _lastLoadedReminders.firstWhere(
                      (task) => !task.isCompleted && !task.isDeleted,
                      orElse: () => _lastLoadedReminders.isNotEmpty
                          ? _lastLoadedReminders.first
                          : ReminderModel(
                              id: 'demo_simulation_task',
                              familyId: _familyId,
                              creatorId: _currentUserId,
                              assignedTo: _currentUserId,
                              assignedToName: _currentUserName,
                              title: AppLanguage.text('Rửa bát (Demo 10s)', 'Wash dishes (Demo 10s)'),
                              date: '01/01/2026',
                              time: '08:00',
                            ),
                    );
                    MultiTierSimulationDialog.show(
                      context,
                      reminder: targetTask,
                      repository: _repository,
                      currentUserId: _currentUserId,
                      onReminderCompleted: _manualRefresh,
                    );
                  } else if (val == 'wishlist_shop') {
                    _openWishlistShop();
                  } else if (val == 'create_reminder') {
                    _openCreateReminder();
                  } else if (val == 'refresh') {
                    _manualRefresh();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'demo_simulation',
                    child: Row(
                      children: [
                        const Icon(Icons.speed_rounded, size: 18, color: Color(0xFF005F50)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            AppLanguage.text('Mô phỏng leo thang 10s (Demo)', 'Simulate 10s Escalation (Demo)'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'wishlist_shop',
                    child: Row(
                      children: [
                        const Icon(Icons.stars_rounded,
                            size: 18, color: Color(0xFFE65100)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            AppLanguage.text('Cửa hàng Đổi Sao & Sổ cái ⭐', 'Star Shop & Ledger ⭐'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'ai_assistant',
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded,
                            size: 18, color: Color(0xFF0D7A68)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            AppLanguage.text('Trợ lý AI Gia đình', 'Family AI Assistant'),
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
                        const Icon(Icons.add_circle_outline_rounded,
                            size: 18, color: primaryColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            AppLanguage.text('Tạo lời nhắc mới', 'Create new reminder'),
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
                        const Icon(Icons.open_in_new_rounded,
                            size: 18, color: primaryColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            AppLanguage.text('Mở trang Lịch toàn màn hình', 'Open full calendar'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        const Icon(Icons.refresh_rounded,
                            size: 18, color: primaryColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            AppLanguage.text('Làm mới dữ liệu', 'Refresh data'),
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
          body: RefreshIndicator(
            color: primaryColor,
            onRefresh: _manualRefresh,
            child: StreamBuilder<List<ReminderModel>>(
              stream: _getRemindersStream(),
              builder: (context, snapshot) {
                final allReminders = snapshot.data ?? [];
                _lastLoadedReminders = allReminders;
                String memberId = '';
                String memberName = '';
                for (final m in _familyMembers) {
                  if (m.id == _currentUserId ||
                      _normalizeName(m.name) == _normalizeName(_currentUserName)) {
                    memberId = m.id;
                    memberName = m.name;
                    break;
                  }
                }
                MultiTierEscalationService.instance.syncReminders(
                  allReminders,
                  currentUserId: _currentUserId,
                  currentUserName: _currentUserName,
                  currentUserMemberId: memberId,
                  currentUserFamilyName: memberName,
                  context: context,
                  onOpenDetail: _showDetailBottomSheet,
                );

                return ValueListenableBuilder<DateTime>(
                  valueListenable: MultiTierEscalationService.instance.clockTick,
                  builder: (context, nowTick, _) {
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
                        .where((r) =>
                            r.date == selectedDateStr ||
                            (r.dueDateTime != null &&
                                _isSameDay(r.dueDateTime!, _selectedDate)))
                        .toList();

                if (_isCalendarView) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ReminderScopeFilterChips(
                              filterOnlyMine: _filterOnlyMine,
                              onScopeChanged: (val) =>
                                  setState(() => _filterOnlyMine = val),
                            ),
                            _buildFamilyContextBar(),
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
                            FamilyProgressCard(
                              reminders: _showAll ? searchedReminders : displayedReminders,
                              dateTitle: _showAll ? AppLanguage.text('Tất cả', 'All') : selectedDateStr,
                            ),
                            ReminderListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
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
                          ],
                        ),
                      ),
                    ),
                  );
                }

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

                        // Weekly Strip
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
                          dateTitle: _showAll ? AppLanguage.text('Tất cả', 'All') : selectedDateStr,
                        ),

                        // Urgent Parent Triage Alert Card if tasks are escalated overdue
                        Builder(
                          builder: (context) {
                            final overdueNeedingTriage = scopedReminders.where((r) {
                              if (!r.isOverdue || r.isCompleted || r.isDeleted || r.isSubmitted) return false;
                              final isGuardian = _familyMembers.any(
                                (m) => m.id == _currentUserId && (m.isParent || m.isGrandparent || m.isOwner),
                              );
                              return isGuardian || r.creatorId == _currentUserId;
                            }).toList();

                            if (overdueNeedingTriage.isEmpty) return const SizedBox.shrink();
                            return _buildParentTriageUrgentBanner(overdueNeedingTriage);
                          },
                        ),

                        // List View phân nhóm theo các mức ưu tiên
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
                );
              },
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPad),
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
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          AppLanguage.text('Tạo lời nhắc', 'Create reminder'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallScreen ? 12.5 : 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 8 : 12),
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
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          AppLanguage.text('Trợ lý AI', 'AI Assistant'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallScreen ? 12 : 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _buildParentTriageUrgentBanner(List<ReminderModel> overdueTasks) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE57373), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLanguage.text(
                    '🚨 Cần Phụ Huynh Can Thiệp (${overdueTasks.length} việc quá hạn)',
                    '🚨 Needs Parent Intervention (${overdueTasks.length} overdue)',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: Color(0xFFC62828),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppLanguage.text(
              'Thành viên chưa hoàn thành việc nhà đúng hẹn. Hãy chọn giải pháp xử lý ngay:',
              'Members have not completed chores on time. Please choose an action below:',
            ),
            style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037)),
          ),
          const SizedBox(height: 10),
          ...overdueTasks.take(3).map((task) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        Text(
                          task.assignedToName,
                          style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ParentTriageActionsWidget(
                      reminder: task,
                      onActionCompleted: () {
                        _manualRefresh();
                      },
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

}

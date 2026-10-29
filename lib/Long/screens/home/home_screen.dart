import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/family_data_service.dart';
import '../../models/user_model.dart';
import '../../models/family_model.dart';
import '../../models/family_member_model.dart';
import '../../models/reminder_model.dart';
import '../../utils/long_strings.dart';
import '../../widgets/check_in_button.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/family_member_tile.dart';
import '../../widgets/family_selector_bar.dart';
import '../family/family_screen.dart';
import '../../../Khoa/screens/family_setup_screen.dart';
import '../../../Thinh/theme/app_language.dart';
import '../../../Vinh/models/reminder_model.dart' as vinh;
import '../../../Vinh/screens/reminder_list_screen.dart';
import '../../../Vinh/services/firebase_reminder_repository.dart';
import '../../../Vinh/widgets/reminder_detail_bottom_sheet.dart' as vinh_sheet;

class HomeScreen extends StatefulWidget {
  final VoidCallback? onNavigateToFamily;
  final VoidCallback? onNavigateToReminders;

  const HomeScreen({
    super.key,
    this.onNavigateToFamily,
    this.onNavigateToReminders,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _familydataService = FamilyDataService();

  late Future<Map<String, dynamic>> _homeDataFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
    _familydataService.selectedFamilyIdNotifier.addListener(
      _onSelectedFamilyChanged,
    );
  }

  @override
  void dispose() {
    _familydataService.selectedFamilyIdNotifier.removeListener(
      _onSelectedFamilyChanged,
    );
    super.dispose();
  }

  void _onSelectedFamilyChanged() {
    if (mounted) {
      setState(_loadData);
    }
  }

  void _loadData() {
    _homeDataFuture = _fetchHomeData();
  }

  Future<Map<String, dynamic>> _fetchHomeData() async {
    final user = await _familydataService.getCurrentUser();
    final families = await _familydataService.getMyFamilies();
    final family = await _familydataService.getCurrentFamily();
    final members = await _familydataService.getFamilyMembers(
      familyId: family?.id,
    );
    final allReminders = await _familydataService.getMyPendingReminders(
      acrossAllFamilies: true,
    );

    // Chỉ hiển thị các tác vụ chưa xong (PENDING) mà thôi
    final pendingReminders = allReminders
        .where((r) => r.status == ReminderStatus.pending)
        .toList();

    return {
      'user': user,
      'families': families,
      'family': family,
      'members': members,
      'reminders': pendingReminders,
    };
  }

  Future<void> _handleSelectFamily(FamilyModel selected) async {
    await _familydataService.selectFamily(selected.id);
    if (mounted) {
      setState(_loadData);
    }
  }

  Future<void> _openFamilySetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FamilySetupScreen(),
      ),
    );
    if (mounted) {
      _familydataService.clearCache();
      setState(_loadData);
    }
  }

  void _navigateToFamily() {
    if (widget.onNavigateToFamily != null) {
      widget.onNavigateToFamily!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const FamilyScreen(),
        ),
      );
    }
  }

  Future<void> _handleCheckIn(String? familyId) async {
    try {
      await _familydataService.checkIn(
        _familydataService.currentUserId,
        familyId: familyId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LongStrings.checkInSuccess),
            backgroundColor: const Color(0xFF005F50),
          ),
        );
        setState(_loadData);
      }
    } catch (e) {
      debugPrint('Check-in error: $e');
    }
  }

  Future<void> _handleCompleteReminder(String reminderId) async {
    try {
      await _familydataService.completeReminder(reminderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LongStrings.completeTaskSuccess),
            backgroundColor: const Color(0xFF005F50),
          ),
        );
        setState(_loadData);
      }
    } catch (e) {
      debugPrint('Complete reminder error: $e');
    }
  }

  /// Mở chi tiết lời nhắc tương ứng khi nhấn vào từng lời nhắc trên trang Home
  Future<void> _handleOpenReminderDetail(
    ReminderModel reminder,
    String? familyName,
    UserModel currentUser,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reminders')
          .doc(reminder.id)
          .get();

      final vinh.ReminderModel vinhModel;
      if (doc.exists && doc.data() != null) {
        final data = Map<String, dynamic>.from(doc.data()!);
        data['id'] = doc.id;
        vinhModel = vinh.ReminderModel.fromJson(data);
      } else {
        vinhModel = vinh.ReminderModel(
          id: reminder.id,
          familyId: reminder.familyId,
          familyName: familyName ?? reminder.familyName,
          creatorId: reminder.creatorId,
          assignedTo: reminder.assignedTo,
          assignedToName: currentUser.name,
          title: reminder.title,
          date:
              '${reminder.date.day.toString().padLeft(2, '0')}/${reminder.date.month.toString().padLeft(2, '0')}/${reminder.date.year}',
          time:
              '${reminder.date.hour.toString().padLeft(2, '0')}:${reminder.date.minute.toString().padLeft(2, '0')}',
          status: 'PENDING',
        );
      }

      if (!mounted) return;

      await vinh_sheet.ReminderDetailBottomSheet.show(
        context,
        reminder: vinhModel,
        currentUserId: _familydataService.currentUserId,
        currentUserName: currentUser.name,
        familyName: familyName ?? reminder.familyName,
        repository: FirebaseReminderRepository(),
        onReminderUpdated: () {
          if (mounted) setState(_loadData);
        },
      );
    } catch (e) {
      debugPrint('Open reminder detail error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _homeDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Colors.white,
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Scaffold(
                backgroundColor: Colors.white,
                body: Center(child: Text('Error: ${snapshot.error}')),
              );
            }

            final data = snapshot.data!;
            final UserModel user = data['user'];
            final List<FamilyModel> families =
                (data['families'] as List<FamilyModel>?) ?? [];
            final FamilyModel? family = data['family'];
            final List<FamilyMemberModel> members = data['members'];
            final List<ReminderModel> myReminders = data['reminders'];

            final currentMember =
                members.where((m) => m.user.id == user.id).firstOrNull;
            final isCheckedIn = currentMember?.isCheckedInToday ?? false;

            return Scaffold(
              backgroundColor: Colors.white,
              appBar: CustomAppBar(
                title: LongStrings.goodMorning(user.name),
                actions: [
                  // Lối tắt trên thanh AppBar dẫn nhanh sang trang Family tương ứng
                  Tooltip(
                    message: LongStrings.familyShortcutTooltip,
                    child: IconButton(
                      icon: const Icon(
                        Icons.family_restroom_rounded,
                        color: Color(0xFF005F50),
                      ),
                      onPressed: _navigateToFamily,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: family == null
                    ? Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE0F2EC),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.family_restroom_rounded,
                                  size: 64,
                                  color: Color(0xFF005F50),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                LongStrings.notJoinedFamilyYet,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF151D1B),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                LongStrings.askFamilyOwner,
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
                                    backgroundColor: const Color(0xFF005F50),
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
                                    LongStrings.joinOrCreateFamily,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: _openFamilySetup,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF005F50),
                                    side: const BorderSide(
                                      color: Color(0xFF005F50),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.family_restroom_rounded,
                                  ),
                                  label: Text(
                                    LongStrings.goToFamilyTab,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: _navigateToFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Thanh chọn gia đình dạng select chuẩn (giống trang Reminder)
                          // Giới hạn hiển thị tối đa 5 gia đình, nếu > 5 thì cuộn
                          FamilySelectorBar(
                            families: families,
                            currentFamily: family,
                            onFamilySelected: _handleSelectFamily,
                            onAddFamily: _openFamilySetup,
                            onQuickNavigateToFamily: _navigateToFamily,
                          ),

                          const SizedBox(height: 20),
                          CheckInButton(
                            isCheckedIn: isCheckedIn,
                            onPressed: () => _handleCheckIn(family.id),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  families.length > 1
                                      ? '${LongStrings.familyToday} · ${family.name}'
                                      : LongStrings.familyToday,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                LongStrings.membersCount(members.length),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF6E7A75),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ...members.map(
                            (member) => FamilyMemberTile(member: member),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                LongStrings.myReminders,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (myReminders.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE4F6EF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${myReminders.length}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF005F50),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Danh sách lời nhắc chưa xong
                          if (myReminders.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                LongStrings.noPendingReminders,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            )
                          else
                            ...myReminders.map((reminder) {
                              final timeString =
                                  '${reminder.date.hour.toString().padLeft(2, '0')}:${reminder.date.minute.toString().padLeft(2, '0')}';
                              final remFamName = reminder.familyName ??
                                  families
                                      .where((f) => f.id == reminder.familyId)
                                      .map((f) => f.name)
                                      .firstOrNull ??
                                  family.name;

                              return Card(
                                elevation: 0,
                                color: const Color(0xFFF3F8F6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: const Color(0xFFBDC9C4)
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  // Nhấn vào reminder mở trực tiếp chi tiết reminder tương ứng
                                  onTap: () => _handleOpenReminderDetail(
                                    reminder,
                                    remFamName,
                                    user,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFD7EFE6),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.assignment_outlined,
                                            color: Color(0xFF005F50),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${reminder.title} · $timeString',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                  color: Color(0xFF151D1B),
                                                ),
                                              ),
                                              const SizedBox(height: 5),

                                              // Huy hiệu hiện rõ thông tin tác vụ đó ở gia đình nào
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFE4F6EF),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.cottage_rounded,
                                                      size: 13,
                                                      color: Color(0xFF005F50),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        remFamName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              Color(0xFF005F50),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip:
                                              LongStrings.completeTaskSuccess,
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                            color: Color(0xFF005F50),
                                            size: 24,
                                          ),
                                          onPressed: () =>
                                              _handleCompleteReminder(
                                            reminder.id,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),

                          const SizedBox(height: 8),

                          // View all reminders: Mở sang ReminderListScreen riêng (không có thanh dưới, có nút quay lại)
                          Center(
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF005F50),
                              ),
                              icon: const Icon(Icons.arrow_forward, size: 16),
                              label: Text(
                                LongStrings.viewAllReminders,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              onPressed: () {
                                if (widget.onNavigateToReminders != null) {
                                  widget.onNavigateToReminders!();
                                } else {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ReminderListScreen(
                                        familyId: family.id,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

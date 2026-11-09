import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/family_data_service.dart';
import '../../models/user_model.dart';
import '../../models/family_model.dart';
import '../../models/family_member_model.dart';
import '../../models/reminder_model.dart';
import '../../utils/long_strings.dart';
import '../../widgets/check_in_button.dart';
import '../../../Danh/danh_payment_entry.dart';
import '../../widgets/check_in_sheet.dart';
import '../../widgets/check_in_feed_view.dart';
import '../../widgets/check_in_reminder_card.dart';
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
  String? _currentFamilyName;

  @override
  void initState() {
    super.initState();
    _familydataService.ensureRealtimeSync();
    _loadData();
    _familydataService.selectedFamilyIdNotifier.addListener(
      _onSelectedFamilyChanged,
    );
    _familydataService.membershipRevisionNotifier.addListener(
      _onSelectedFamilyChanged,
    );
  }

  @override
  void dispose() {
    _familydataService.selectedFamilyIdNotifier.removeListener(
      _onSelectedFamilyChanged,
    );
    _familydataService.membershipRevisionNotifier.removeListener(
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
    _homeDataFuture = _fetchHomeData().then((data) {
      final family = data['family'] as FamilyModel?;
      if (mounted && _currentFamilyName != family?.name) {
        setState(() {
          _currentFamilyName = family?.name;
        });
      }
      return data;
    });
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

    // Update owner lastActiveAt in background (throttled in FamilyDataService)
    unawaited(_familydataService.updateOwnerLastActive());

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

  void _handleCheckInPress(bool isAlreadyCheckedIn) {
    if (DanhPaymentEntry.isOverCapacityFrozen) {
      DanhPaymentEntry.showOverCapacityFrozenDialog(context);
      return;
    }

    if (isAlreadyCheckedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LongStrings.t(
              "You're already checked in today!",
              "You're already checked in today!",
            ),
          ),
          backgroundColor: const Color(0xFF005F50),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    CheckInSheet.show(
      context,
      onSuccess: () {
        _familydataService.clearCache();
        setState(_loadData);
      },
    );
  }

  Future<void> _handleCompleteReminder(
    String reminderId, [
    DateTime? reminderDate,
  ]) async {
    try {
      if (reminderDate != null) {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final taskDay =
            DateTime(reminderDate.year, reminderDate.month, reminderDate.day);
        if (taskDay.isAfter(todayStart)) {
          final dStr =
              '${reminderDate.day.toString().padLeft(2, '0')}/${reminderDate.month.toString().padLeft(2, '0')}/${reminderDate.year}';
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLanguage.text(
                    'Công việc này chỉ có thể hoàn thành vào đúng ngày hẹn ($dStr)!',
                    'This task can only be completed on its scheduled date ($dStr)!',
                  ),
                ),
                backgroundColor: const Color(0xFF455A64),
              ),
            );
          }
          return;
        }
      }

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
          familyName: familyName ?? reminder.familyName ?? '',
          creatorId: reminder.creatorId,
          assignedTo: reminder.assignedTo,
          assignedToName: currentUser.name,
          title: reminder.title,
          date:
              '${reminder.date.day.toString().padLeft(2, '0')}/${reminder.date.month.toString().padLeft(2, '0')}/${reminder.date.year}',
          time:
              '${reminder.date.hour.toString().padLeft(2, '0')}:${reminder.date.minute.toString().padLeft(2, '0')}',
          status: 'PENDING',
          requiresProofImage: reminder.requiresProofImage,
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFEDF5F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.family_restroom,
                size: 40,
                color: Color(0xFF005F50),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              LongStrings.noFamilyTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF151D1B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LongStrings.noFamilySubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6E7A75),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005F50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _openFamilySetup,
              icon: const Icon(Icons.add, size: 20),
              label: Text(
                LongStrings.createOrJoinAction,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: CustomAppBar(
            title: LongStrings.tabHome,
            subtitle: _currentFamilyName,
            actions: [
              IconButton(
                icon: const Icon(Icons.group_add_outlined),
                tooltip: LongStrings.familySetupTooltip,
                onPressed: _openFamilySetup,
              ),
            ],
          ),
          body: FutureBuilder<Map<String, dynamic>>(
            future: _homeDataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final user = snapshot.data?['user'] as UserModel?;
              final families =
                  snapshot.data?['families'] as List<FamilyModel>? ?? [];
              final family = snapshot.data?['family'] as FamilyModel?;
              final members = snapshot.data?['members']
                      as List<FamilyMemberModel>? ??
                  [];
              final reminders = snapshot.data?['reminders']
                      as List<ReminderModel>? ??
                  [];

              if (user == null || family == null || families.isEmpty) {
                return _buildEmptyState();
              }

              final currentUserId = _familydataService.currentUserId;
              final me = members.cast<FamilyMemberModel?>().firstWhere(
                    (m) => m?.user.id == currentUserId,
                    orElse: () => null,
                  );
              final isCheckedInToday = me?.isCheckedInToday ?? false;

              final isTakeoverEligible =
                  _familydataService.isTakeoverEligible(familyId: family.id);
              final isOwner = family.ownerId.isNotEmpty &&
                  (family.ownerId == currentUserId || (me?.isOwner ?? false));

              // Inactivity monitoring: look for any members inactive for > 24 hours
              final inactiveMembers = members.where((m) {
                if (!m.isActive || m.isMemorialized) return false;
                if (m.user.id == currentUserId) return false;
                if (m.lastCheckInAt == null) return true;
                return DateTime.now().difference(m.lastCheckInAt!).inHours >= 24;
              }).toList();

              return RefreshIndicator(
                onRefresh: () async {
                  _familydataService.clearCache();
                  setState(_loadData);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    // Welcome greeting
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${LongStrings.welcomeBack},',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF6E7A75),
                          ),
                        ),
                        Text(
                          user.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF151D1B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Multi-family selector bar
                    FamilySelectorBar(
                      families: families,
                      currentFamily: family,
                      onFamilySelected: _handleSelectFamily,
                      onAddFamily: _openFamilySetup,
                      onQuickNavigateToFamily: _navigateToFamily,
                    ),
                    const SizedBox(height: 16),



                    // Passive Takeover Banner (if eligible)
                    if (isTakeoverEligible && !isOwner) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFC107)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shield_outlined,
                                color: Color(0xFF856404), size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    LongStrings.t(
                                      'Chủ gia đình đã không hoạt động > 30 ngày',
                                      'Owner inactive > 30 days',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: Color(0xFF856404),
                                    ),
                                  ),
                                  Text(
                                    LongStrings.t(
                                      'Bạn có thể tiếp quản quyền Chủ gia đình ngay bây giờ.',
                                      'You can claim ownership takeover now.',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF856404),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF005F50),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                              ),
                              onPressed: () async {
                                try {
                                  await _familydataService.claimOwnership(
                                    familyId: family.id,
                                  );
                                  setState(_loadData);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        LongStrings.t(
                                          '🎉 Bạn đã tiếp quản quyền Owner thành công!',
                                          '🎉 You claimed ownership successfully!',
                                        ),
                                      ),
                                      backgroundColor: const Color(0xFF005F50),
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              },
                              child: Text(
                                LongStrings.t('Tiếp quản', 'Take Over'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Inactivity alert for family members (> 24 hours)
                    if (inactiveMembers.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBE9E7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFCCBC)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFD84315), size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    LongStrings.t(
                                      'Cảnh báo an toàn (Safe Check-in)',
                                      'Safety Warning (Safe Check-in)',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: Color(0xFFD84315),
                                    ),
                                  ),
                                  Text(
                                    LongStrings.t(
                                      '${inactiveMembers.map((m) => m.user.name).join(', ')} chưa điểm danh hơn 24 giờ. Vui lòng liên hệ!',
                                      '${inactiveMembers.map((m) => m.user.name).join(', ')} haven\'t checked in for 24+ hours. Please check in on them!',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFBF360C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (!isCheckedInToday) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFC8E6C9)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shield_outlined,
                                color: Color(0xFF2E7D32), size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                LongStrings.t(
                                  'Hôm nay bạn chưa điểm danh. Hãy điểm danh để báo an toàn cho gia đình nhé!',
                                  'You haven\'t checked in today. Check in now to notify your family!',
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1B5E20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Quick Action Cards: Heo Đất Gia Đình & Cửa Hàng Đổi Sao
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => DanhPaymentEntry.openFamilyJackpot(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFFFD54F)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFECB3),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.savings_rounded, color: Color(0xFFE65100), size: 20),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          LongStrings.t('Heo Đất', 'Piggy Bank'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFBF360C)),
                                        ),
                                        Text(
                                          LongStrings.t('Tiết kiệm & Lắc hũ', 'Save & Shake'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF8D6E63)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => DanhPaymentEntry.openWishlistShop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFA5D6A7)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFC8E6C9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.stars_rounded, color: Color(0xFF2E7D32), size: 20),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          LongStrings.t('Đổi Sao ⭐', 'Star Shop ⭐'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B5E20)),
                                        ),
                                        Text(
                                          LongStrings.t('Đổi quà & Lì xì', 'Redeem & Gifts'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF558B2F)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Module 3: CheckInButton
                    CheckInButton(
                      isCheckedIn: isCheckedInToday,
                      onPressed: () => _handleCheckInPress(isCheckedInToday),
                    ),
                    const SizedBox(height: 16),

                    // Module 3: Check-in Photo Feed
                    CheckInFeedView(familyId: family.id),
                    const SizedBox(height: 8),

                    // Module 3: Simulated Reminder Card (08:00, 14:00, 20:00)
                    CheckInReminderCard(familyId: family.id),
                    const SizedBox(height: 16),

                    // Family members header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            LongStrings.familyMembersHeader(members.length),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6E7A75),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _navigateToFamily,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  LongStrings.manageFamilyAction,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF005F50),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 14,
                                  color: Color(0xFF005F50),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Up to 3 member tiles on home
                    ...members.take(3).map(
                          (m) => FamilyMemberTile(
                            member: m,
                            onTap: _navigateToFamily,
                          ),
                        ),

                    const SizedBox(height: 16),

                    // Pending reminders section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            LongStrings.pendingRemindersTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6E7A75),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${reminders.length}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF005F50),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (reminders.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FAF9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2EAE7)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.task_alt,
                              color: Color(0xFF005F50),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                LongStrings.noPendingReminders,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF6E7A75),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...reminders.take(5).map((reminder) {
                        final remFamName = (reminder.familyName != null &&
                                reminder.familyName!.isNotEmpty)
                            ? reminder.familyName!
                            : family.name;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF5F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFBDC9C4)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _handleOpenReminderDetail(
                              reminder,
                              remFamName,
                              user,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          reminder.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: Color(0xFF151D1B),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              '${reminder.date.hour.toString().padLeft(2, '0')}:${reminder.date.minute.toString().padLeft(2, '0')}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF6E7A75),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
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
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (DateTime(reminder.date.year,
                                          reminder.date.month,
                                          reminder.date.day)
                                      .isAfter(DateTime(
                                          DateTime.now().year,
                                          DateTime.now().month,
                                          DateTime.now().day)))
                                    IconButton(
                                      tooltip: AppLanguage.text(
                                        'Khóa đến ngày ${reminder.date.day.toString().padLeft(2, '0')}/${reminder.date.month.toString().padLeft(2, '0')}/${reminder.date.year}',
                                        'Locked until ${reminder.date.day.toString().padLeft(2, '0')}/${reminder.date.month.toString().padLeft(2, '0')}/${reminder.date.year}',
                                      ),
                                      icon: const Icon(
                                        Icons.lock_clock_outlined,
                                        color: Color(0xFF8E9B96),
                                        size: 24,
                                      ),
                                      onPressed: () {
                                        final dStr =
                                            '${reminder.date.day.toString().padLeft(2, '0')}/${reminder.date.month.toString().padLeft(2, '0')}/${reminder.date.year}';
                                        ScaffoldMessenger.of(context)
                                            .hideCurrentSnackBar();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                const Icon(
                                                    Icons.lock_clock_rounded,
                                                    color: Colors.white,
                                                    size: 20),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    AppLanguage.text(
                                                      'Công việc này chỉ có thể hoàn thành vào đúng ngày hẹn ($dStr)!',
                                                      'This task can only be completed on its scheduled date ($dStr)!',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor:
                                                const Color(0xFF455A64),
                                            behavior:
                                                SnackBarBehavior.floating,
                                            duration:
                                                const Duration(seconds: 3),
                                          ),
                                        );
                                      },
                                    )
                                   else
                                     IconButton(
                                       tooltip: reminder.requiresProofImage
                                           ? AppLanguage.text(
                                               'Chụp ảnh nghiệm thu & Hoàn thành',
                                               'Take photo proof & Complete',
                                             )
                                           : LongStrings.completeTaskSuccess,
                                       icon: Icon(
                                         reminder.requiresProofImage
                                             ? Icons.camera_alt_outlined
                                             : Icons.check_circle_outline,
                                         color: const Color(0xFF005F50),
                                         size: 24,
                                       ),
                                       onPressed: () {
                                         if (reminder.requiresProofImage) {
                                           ScaffoldMessenger.of(context).showSnackBar(
                                             SnackBar(
                                               content: Text(AppLanguage.text(
                                                 'Công việc này bắt buộc chụp ảnh nghiệm thu! Vui lòng chạm vào việc để chụp ảnh.',
                                                 'This task requires proof photo! Please tap the task to take photo.',
                                               )),
                                               backgroundColor: Colors.amber[800],
                                             ),
                                           );
                                           _handleOpenReminderDetail(
                                             reminder,
                                             family.name,
                                             user,
                                           );
                                           return;
                                         }
                                         _handleCompleteReminder(
                                           reminder.id,
                                           reminder.date,
                                         );
                                       },
                                     ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),

                    const SizedBox(height: 8),

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
              );
            },
          ),
        );
      },
    );
  }
}

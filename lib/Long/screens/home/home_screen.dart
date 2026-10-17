import 'package:flutter/material.dart';

import '../../services/family_state_manager.dart';
import '../../models/user_model.dart';
import '../../models/family_model.dart';
import '../../models/family_member_model.dart';
import '../../models/reminder_model.dart';
import '../../widgets/check_in_button.dart';
import '../../widgets/check_in_sheet.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/family_member_tile.dart';
import '../../widgets/family_switcher_bar.dart';
import '../../widgets/check_in_reminder_card.dart';
import '../../widgets/check_in_feed_view.dart';
import '../family/create_family_screen.dart';
import '../family/join_family_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _stateManager = FamilyStateManager();
  UserModel? _currentUser;
  List<ReminderModel> _myReminders = [];

  @override
  void initState() {
    super.initState();
    _stateManager.addListener(_onStateChanged);
    _initData();
  }

  @override
  void dispose() {
    _stateManager.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initData() async {
    await _stateManager.initialize();
    _currentUser = await _stateManager.service.getCurrentUser();
    // Update owner lastActiveAt whenever app is opened
    await _stateManager.service.updateOwnerLastActive();
    await _loadReminders();
    if (mounted) setState(() {});
  }

  Future<void> _loadReminders() async {
    final reminders = await _stateManager.service.getFamilyMembers();
    // Fetch pending reminders
    final myPending = (_stateManager.service as dynamic).getMyPendingReminders?.call();
    if (myPending is List<ReminderModel>) {
      _myReminders = myPending;
    } else if (reminders.isNotEmpty) {
      _myReminders = [];
    }
    if (mounted) setState(() {});
  }

  void _handleCheckInPress(bool isAlreadyCheckedIn) {
    if (isAlreadyCheckedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You're already checked in today!"),
          backgroundColor: Color(0xFF005F50),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    CheckInSheet.show(
      context,
      onSuccess: () {
        _stateManager.reload();
      },
    );
  }

  Future<void> _handleTakeoverClaim(String familyId) async {
    try {
      await _stateManager.service.claimOwnership(familyId: familyId);
      await _stateManager.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Bạn đã tiếp quản quyền Owner thành công!'),
          backgroundColor: Color(0xFF005F50),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  Future<void> _handleCompleteReminder(String reminderId) async {
    try {
      (_stateManager.service as dynamic).completeReminder?.call(reminderId);
      await _loadReminders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Đã hoàn thành nhắc nhở.'),
          backgroundColor: Color(0xFF005F50),
        ),
      );
    } catch (e) {
      debugPrint('Complete reminder error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stateManager.isLoading && _stateManager.currentFamily == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = _currentUser ??
        UserModel(id: 'u1', name: 'Minh', email: 'minh@gmail.com', avatarType: 'boy');
    final FamilyModel? currentFamily = _stateManager.currentFamily;
    final List<FamilyMemberModel> members = _stateManager.currentMembers;

    // Check-in status of current user
    final currentMember = members.where((m) => m.user.id == user.id).firstOrNull;
    final isCheckedIn = currentMember?.isCheckedInToday ?? false;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: 'Xin chào, ${user.name}',
        subtitle: currentFamily != null ? 'Tổ ấm: ${currentFamily.name}' : null,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _stateManager.reload();
          await _loadReminders();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: currentFamily == null
              ? _buildNoFamilyView(context)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Family Switcher Header
                    FamilySwitcherBar(
                      currentFamily: currentFamily,
                      families: _stateManager.myFamilies,
                      onFamilyChanged: (famId) {
                        _stateManager.switchFamily(famId);
                      },
                      onTakeoverClaimed: () => _handleTakeoverClaim(currentFamily.id),
                    ),
                    const SizedBox(height: 16),

                    // Big Prominent Check-In Button
                    CheckInButton(
                      isCheckedIn: isCheckedIn,
                      onPressed: () => _handleCheckInPress(isCheckedIn),
                    ),
                    const SizedBox(height: 16),

                    // Simulated 08:00 / 14:00 / 20:00 Reminder Rule card
                    CheckInReminderCard(familyId: currentFamily.id),

                    // Photo feed for check-in moments
                    CheckInFeedView(familyId: currentFamily.id),
                    const SizedBox(height: 20),

                    // Family Today Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Family Today',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF151D1B),
                          ),
                        ),
                        Text(
                          '${members.where((m) => m.isCheckedInToday).length}/${members.where((m) => m.isActive).length} đã an toàn',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF005F50),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...members.map(
                      (member) => FamilyMemberTile(member: member),
                    ),

                    const SizedBox(height: 24),

                    // My Reminders Section
                    const Text(
                      'Việc cần làm hôm nay',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF151D1B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_myReminders.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FAF9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFBDC9C4).withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: Color(0xFF005F50), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Không có việc nào đang chờ xử lý.',
                              style: TextStyle(
                                color: Color(0xFF6E7A75),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._myReminders.map((reminder) {
                        final timeString =
                            '${reminder.date.hour.toString().padLeft(2, '0')}:${reminder.date.minute.toString().padLeft(2, '0')}';
                        return Card(
                          elevation: 0,
                          color: const Color(0xFFEDF5F2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: const Color(0xFFBDC9C4).withValues(alpha: 0.4),
                            ),
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(
                              Icons.medication,
                              color: Color(0xFF005F50),
                            ),
                            title: Text(
                              '${reminder.title} · $timeString',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Color(0xFF151D1B),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.check_circle_outline,
                                color: Color(0xFF005F50),
                              ),
                              onPressed: () => _handleCompleteReminder(reminder.id),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildNoFamilyView(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.family_restroom, size: 80, color: Colors.grey),
        const SizedBox(height: 24),
        const Text(
          "Bạn chưa tham gia gia đình nào.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          "Nhập mã mời của người thân hoặc tạo tổ ấm mới cho gia đình bạn.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF005F50),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JoinFamilyScreen()),
            );
            _stateManager.reload();
          },
          child: const Text(
            'Tham gia bằng mã',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF005F50),
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Color(0xFF005F50)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateFamilyScreen()),
            );
            _stateManager.reload();
          },
          child: const Text(
            'Tạo gia đình mới',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

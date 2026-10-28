import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/family_data_service.dart';
import '../../models/family_model.dart';
import '../../models/family_member_model.dart';
import '../../models/user_model.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/family_member_tile.dart';
import '../../widgets/family_selector_bar.dart';
import '../../utils/long_strings.dart';
import '../../../Thinh/theme/app_language.dart';
import '../../../Khoa/screens/family_setup_screen.dart';
import '../../../Khoa/services/family_service.dart';
import '../../../Danh/danh_payment_entry.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _familyDataService = FamilyDataService();
  final _familyService = FamilyService();

  late Future<Map<String, dynamic>> _familyDataFuture;
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _familyDataService.selectedFamilyIdNotifier.addListener(
      _onSelectedFamilyChanged,
    );
  }

  @override
  void dispose() {
    _familyDataService.selectedFamilyIdNotifier.removeListener(
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
    _familyDataFuture = _fetchFamilyData();
  }

  Future<Map<String, dynamic>> _fetchFamilyData() async {
    final families = await _familyDataService.getMyFamilies();
    final family = await _familyDataService.getCurrentFamily();
    final members = await _familyDataService.getFamilyMembers(
      familyId: family?.id,
    );
    if (family != null) {
      DanhPaymentEntry.onFamilyCreatedOrJoined(family.id);
    }
    return {
      'families': families,
      'family': family,
      'members': members,
    };
  }

  Future<void> _selectFamily(FamilyModel family) async {
    await _familyDataService.selectFamily(family.id);
    if (mounted) {
      setState(_loadData);
    }
  }

  Future<void> _openFamilySetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FamilySetupScreen()),
    );
    if (!mounted) return;
    _familyDataService.clearCache();
    setState(_loadData);
  }

  Future<void> _leaveFamily(FamilyModel family, {required bool isOwner}) async {
    if (_isLeaving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isOwner ? 'Delete family?' : 'Leave family?'),
        content: Text(
          isOwner
              ? 'Deleting "${family.name}" will remove the family and its memberships. Reminders and historical data will be kept.'
              : 'You will be removed from "${family.name}". You can join again later with an invitation code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: Text(isOwner ? 'Delete family' : 'Leave family'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLeaving = true);
    try {
      final result = await _familyService.leaveFamily(
        familyId: family.id,
        expectedOwner: isOwner,
      );
      if (!mounted) return;
      _familyDataService.resetAll();
      setState(_loadData);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == LeaveFamilyResult.familyDeleted
                ? 'Family deleted. Reminders and historical data were kept.'
                : 'You have left the family.',
          ),
          backgroundColor: const Color(0xFF005F50),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  void _handleInviteMember(String code, int currentMemberCount) {
    if (!DanhPaymentEntry.canAddMember(currentMemberCount)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(child: Text('Giới Hạn Thành Viên')),
            ],
          ),
          content: Text(
            DanhPaymentEntry.getMemberLimitMessage(currentMemberCount),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005F50),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                DanhPaymentEntry.openPremiumPlans(context);
              },
              child: const Text('Nâng cấp Premium (10 người)'),
            ),
          ],
        ),
      );
      return;
    }

    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mã $code đã được sao chép! Hãy gửi cho thành viên mới.'),
        backgroundColor: const Color(0xFF005F50),
      ),
    );
  }

  /// Hiển thị thanh chọn gia đình dạng select (khớp giao diện ReminderListScreen),
  /// giới hạn hiển thị tối đa 5 gia đình, nếu > 5 thì cuộn
  Widget _buildFamilySwitcherSection(
    List<FamilyModel> families,
    FamilyModel currentFamily,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: FamilySelectorBar(
        families: families,
        currentFamily: currentFamily,
        onFamilySelected: _selectFamily,
        onAddFamily: _openFamilySetup,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        return Scaffold(
          appBar: CustomAppBar(title: LongStrings.lovingHome),
          body: FutureBuilder<Map<String, dynamic>>(
            future: _familyDataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final data = snapshot.data!;
              final List<FamilyModel> families =
                  (data['families'] as List<FamilyModel>?) ?? [];
              final FamilyModel? family = data['family'];
              final List<FamilyMemberModel> members = data['members'];

              if (family == null) {
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.family_restroom,
                        size: 80,
                        color: Color(0xFF005F50),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        LongStrings.welcomeFamilyHub,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF151D1B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        LongStrings.notInFamilyDesc,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(fontSize: 16, color: Color(0xFF3E4946)),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFF005F50),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _openFamilySetup,
                        child: Text(
                          LongStrings.setUpYourFamily,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

          final currentMember = members.firstWhere(
            (m) => m.user.id == _familyDataService.currentUserId,
            orElse: () => FamilyMemberModel(
              familyId: family.id,
              user: members.isNotEmpty
                  ? members.first.user
                  : UserModel(
                      id: '11111111-1111-1111-1111-111111111111',
                      name: '?',
                      email: '?',
                    ),
              role: family.ownerId == _familyDataService.currentUserId
                  ? Role.owner
                  : Role.member,
            ),
          );
          final isOwner = currentMember.role == Role.owner ||
              family.ownerId == _familyDataService.currentUserId;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Thanh chuyển đổi gia đình (hiển thị khác nhau cho 1 vs N gia đình)
                _buildFamilySwitcherSection(families, family),

                // Widget hiển thị gói Premium & hạn mức thành viên (dành cho mọi thành viên)
                DanhPaymentEntry.buildFamilyPremiumStatus(members.length),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFBDC9C4).withValues(alpha: 0.6),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120D7A68),
                        offset: Offset(0, 10),
                        blurRadius: 24,
                        spreadRadius: -4,
                      ),
                      BoxShadow(
                        color: Color(0x0DF49D37),
                        offset: Offset(0, 4),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.cottage,
                                  color: Color(0xFF0D7A68),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    family.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF151D1B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _handleInviteMember(
                              family.joinCode,
                              members.length,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2EAE7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Mã: ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6E7A75),
                                    ),
                                  ),
                                  Text(
                                    family.joinCode,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF005F50),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.content_copy,
                                    size: 14,
                                    color: Color(0xFF005F50),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Thành viên trong tổ ấm (${members.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6E7A75),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...members.map(
                        (member) => FamilyMemberTile(member: member),
                      ),

                      if (isOwner) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(
                                color: Color(0xFFBDC9C4),
                                style: BorderStyle.solid,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              foregroundColor: const Color(0xFF005F50),
                              backgroundColor: const Color(0xFFE7F0EC)
                                  .withValues(alpha: 0.3),
                            ),
                            onPressed: () => _handleInviteMember(
                              family.joinCode,
                              members.length,
                            ),
                            icon: const Icon(Icons.person_add, size: 20),
                            label: const Text(
                              'Thêm thành viên mới',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.red.shade300),
                            foregroundColor: Colors.red.shade700,
                          ),
                          onPressed: _isLeaving
                              ? null
                              : () => _leaveFamily(family, isOwner: isOwner),
                          icon: _isLeaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  isOwner ? Icons.delete_outline : Icons.logout,
                                  size: 20,
                                ),
                          label: Text(
                            _isLeaving
                                ? 'Please wait...'
                                : isOwner
                                    ? 'Delete Family'
                                    : 'Leave Family',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
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

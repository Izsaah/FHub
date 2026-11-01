import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/family_data_service.dart';
// import family_state_manager
import '../../models/family_model.dart';
import '../../models/family_member_model.dart';
import '../../models/hierarchy_role.dart';
import '../../models/member_status.dart';
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
        title: Text(
          isOwner
              ? LongStrings.t('Xóa gia đình?', 'Delete family?')
              : LongStrings.t('Rời gia đình?', 'Leave family?'),
        ),
        content: Text(
          isOwner
              ? LongStrings.t(
                  'Xóa "${family.name}" sẽ xóa gia đình và tư cách thành viên. Lời nhắc và dữ liệu lịch sử sẽ được giữ lại.',
                  'Deleting "${family.name}" will remove the family and its memberships. Reminders and historical data will be kept.',
                )
              : LongStrings.t(
                  'Bạn sẽ rời khỏi "${family.name}". Bạn có thể tham gia lại sau bằng mã mời.',
                  'You will be removed from "${family.name}". You can join again later with an invitation code.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(LongStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: Text(isOwner ? LongStrings.deleteFamily : LongStrings.leaveFamily),
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
                ? LongStrings.t(
                    'Đã xóa gia đình. Lời nhắc và dữ liệu lịch sử được giữ lại.',
                    'Family deleted. Reminders and historical data were kept.',
                  )
                : LongStrings.t(
                    'Bạn đã rời khỏi gia đình.',
                    'You have left the family.',
                  ),
          ),
          backgroundColor: const Color(0xFF005F50),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
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
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 8),
              Text(LongStrings.t('Giới Hạn Thành Viên', 'Member Limit')),
            ],
          ),
          content: Text(
            DanhPaymentEntry.getMemberLimitMessage(currentMemberCount),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(LongStrings.close),
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
              child: Text(LongStrings.t(
                'Nâng cấp Premium (10 người)',
                'Upgrade to Premium (10 members)',
              )),
            ),
          ],
        ),
      );
      return;
    }

    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          LongStrings.t(
            'Mã $code đã được sao chép! Hãy gửi cho thành viên mới.',
            'Code $code copied! Share it with family members.',
          ),
        ),
        backgroundColor: const Color(0xFF005F50),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showMemberActionDialog(
    FamilyMemberModel targetMember,
    bool isCurrentUserOwner,
    String familyId,
  ) {
    final currentUserId = _familyDataService.currentUserId;
    final isSelf = targetMember.user.id == currentUserId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      targetMember.user.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF151D1B),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Text(
                  '${LongStrings.t("Vai vế", "Role")}: ${targetMember.hierarchyRole.displayName} · ${LongStrings.t("Trạng thái", "Status")}: ${targetMember.status.displayName}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF6E7A75)),
                ),
                if (targetMember.lastActiveAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${LongStrings.t("Hoạt động gần nhất", "Last active")}: ${targetMember.lastActiveAt!.day}/${targetMember.lastActiveAt!.month}/${targetMember.lastActiveAt!.year} '
                    '(${DateTime.now().difference(targetMember.lastActiveAt!).inDays} ${LongStrings.t("ngày trước", "days ago")})',
                    style: TextStyle(
                      fontSize: 12,
                      color: DateTime.now().difference(targetMember.lastActiveAt!).inDays >= 30
                          ? Colors.red[700]
                          : const Color(0xFF6E7A75),
                      fontWeight: DateTime.now().difference(targetMember.lastActiveAt!).inDays >= 30
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
                const Divider(height: 24),

                // Passive Takeover Option: If Owner inactive > 30 days and current user is PARENT
                if (targetMember.isOwner &&
                    !isSelf &&
                    _familyDataService.isTakeoverEligible(familyId: familyId)) ...[
                  ListTile(
                    leading: const Icon(Icons.shield, color: Colors.orange),
                    title: Text(
                      LongStrings.t(
                        'Tiếp quản quyền Chủ gia đình (Takeover)',
                        'Claim Ownership (Takeover)',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    subtitle: Text(
                      LongStrings.t(
                        'Chủ nhà đã không hoạt động hơn 30 ngày. Thành viên Bố/Mẹ có quyền tiếp quản.',
                        'Owner inactive > 30 days. Parent members are eligible to take over.',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await _familyDataService.claimOwnership(familyId: familyId);
                        setState(_loadData);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              LongStrings.t(
                                '🎉 Bạn đã tiếp quản quyền Chủ gia đình thành công!',
                                '🎉 You have successfully claimed ownership!',
                              ),
                            ),
                            backgroundColor: const Color(0xFF005F50),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    },
                  ),
                  const Divider(),
                ],

                // Owner-only Actions
                if (isCurrentUserOwner && !isSelf) ...[
                  // Transfer Ownership
                  ListTile(
                    leading: const Icon(Icons.swap_horiz, color: Color(0xFF005F50)),
                    title: Text(
                      LongStrings.t('Chuyển quyền Chủ phòng', 'Transfer Ownership'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      LongStrings.t(
                        'Chỉ có thể chuyển cho thành viên vai vế Bố / Mẹ đang hoạt động.',
                        'Can only transfer to an active Parent member.',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (targetMember.hierarchyRole != HierarchyRole.parent) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              LongStrings.t(
                                'Chỉ có thể chuyển quyền Chủ phòng cho thành viên vai vế Bố / Mẹ!',
                                'Can only transfer ownership to active Parent members!',
                              ),
                            ),
                            backgroundColor: Colors.red[700],
                          ),
                        );
                        return;
                      }

                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: Text(LongStrings.t('Xác nhận chuyển quyền', 'Confirm Transfer')),
                          content: Text(
                            LongStrings.t(
                              'Bạn có chắc chắn muốn chuyển quyền Chủ gia đình cho "${targetMember.user.name}"?',
                              'Are you sure you want to transfer ownership to "${targetMember.user.name}"?',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: Text(LongStrings.cancel),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF005F50),
                              ),
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: Text(LongStrings.confirm),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          await _familyDataService.transferOwnership(
                            targetMember.user.id,
                            familyId: familyId,
                          );
                          setState(_loadData);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                LongStrings.t(
                                  'Đã chuyển quyền Chủ gia đình cho "${targetMember.user.name}"!',
                                  'Ownership transferred to "${targetMember.user.name}"!',
                                ),
                              ),
                              backgroundColor: const Color(0xFF005F50),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                        }
                      }
                    },
                  ),

                  // Toggle Status (Active / Deactivated / Memorialized)
                  ListTile(
                    leading: Icon(
                      targetMember.isDeactivated
                          ? Icons.play_arrow
                          : Icons.pause_circle_outline,
                      color: Colors.orange[800],
                    ),
                    title: Text(
                      targetMember.isDeactivated
                          ? LongStrings.t('Kích hoạt lại kết nối', 'Reactivate Connection')
                          : LongStrings.t('Tạm ngưng kết nối (Deactivate)', 'Deactivate Member'),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final nextStatus = targetMember.isDeactivated
                          ? MemberStatus.active
                          : MemberStatus.deactivated;
                      await _familyDataService.updateMemberStatus(
                        targetMember.user.id,
                        nextStatus,
                        familyId: familyId,
                      );
                      setState(_loadData);
                    },
                  ),

                  ListTile(
                    leading: const Icon(Icons.spa, color: Color(0xFF8D7B68)),
                    title: Text(
                      targetMember.isMemorialized
                          ? LongStrings.t('Bỏ chế độ Tưởng niệm', 'Remove Memorial Status')
                          : LongStrings.t('Đặt chế độ Tưởng niệm (Memorial)', 'Set Memorial Status'),
                    ),
                    subtitle: Text(
                      LongStrings.t(
                        'Chế độ tưởng nhớ người đã khuất, tôn vinh kỷ niệm gia đình.',
                        'Honor deceased relatives and preserve family memories.',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final nextStatus = targetMember.isMemorialized
                          ? MemberStatus.active
                          : MemberStatus.memorialized;
                      await _familyDataService.updateMemberStatus(
                        targetMember.user.id,
                        nextStatus,
                        familyId: familyId,
                      );
                      setState(_loadData);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
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
            title: LongStrings.tabFamily,
            actions: [
              IconButton(
                icon: const Icon(Icons.group_add_outlined),
                tooltip: LongStrings.familySetupTooltip,
                onPressed: _openFamilySetup,
              ),
            ],
          ),
          body: FutureBuilder<Map<String, dynamic>>(
            future: _familyDataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final families =
                  snapshot.data?['families'] as List<FamilyModel>? ?? [];
              final family = snapshot.data?['family'] as FamilyModel?;
              final members = snapshot.data?['members']
                      as List<FamilyMemberModel>? ??
                  [];

              if (family == null || families.isEmpty) {
                return _buildEmptyState();
              }

              final currentUserId = _familyDataService.currentUserId;
              final isOwner = family.ownerId.isNotEmpty &&
                  (family.ownerId == currentUserId ||
                      members.any((m) =>
                          m.user.id == currentUserId && m.role == Role.owner));

              final isTakeoverEligible =
                  _familyDataService.isTakeoverEligible(familyId: family.id);

              return RefreshIndicator(
                onRefresh: () async {
                  _familyDataService.clearCache();
                  setState(_loadData);
                },
                child: ListView(
                  padding: const EdgeInsets.all(20.0),
                  children: [
                    FamilySelectorBar(
                      families: families,
                      currentFamily: family,
                      onFamilySelected: _selectFamily,
                      onAddFamily: _openFamilySetup,
                    ),
                    const SizedBox(height: 16),

                    // Inactive Owner Alert / Passive Takeover Banner
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
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFF856404), size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    LongStrings.t(
                                      'Chủ gia đình đã không hoạt động > 30 ngày',
                                      'Owner inactive for more than 30 days',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: Color(0xFF856404),
                                    ),
                                  ),
                                  Text(
                                    LongStrings.t(
                                      'Thành viên vai vế Bố / Mẹ có thể tiếp quản quyền Chủ gia đình.',
                                      'Active Parent members can take over family ownership.',
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
                                textStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () async {
                                try {
                                  await _familyDataService.claimOwnership(
                                    familyId: family.id,
                                  );
                                  setState(_loadData);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        LongStrings.t(
                                          '🎉 Bạn đã tiếp quản quyền Owner thành công!',
                                          '🎉 You successfully claimed ownership!',
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
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFBDC9C4).withValues(alpha: 0.6),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0C000000),
                            offset: Offset(0, 4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.family_restroom,
                                    color: Color(0xFF005F50),
                                    size: 26,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    family.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF151D1B),
                                    ),
                                  ),
                                ],
                              ),
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
                                    children: [
                                      Text(
                                        LongStrings.codePrefix,
                                        style: const TextStyle(
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
                                '${LongStrings.familyMembersHeader(members.length)} · ${LongStrings.t("Chạm để quản trị", "Tap to manage")}',
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
                            (member) => FamilyMemberTile(
                              member: member,
                              onTap: () => _showMemberActionDialog(
                                member,
                                isOwner,
                                family.id,
                              ),
                            ),
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
                                label: Text(
                                  LongStrings.addNewMember,
                                  style: const TextStyle(
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
                                    ? LongStrings.t('Vui lòng chờ...', 'Please wait...')
                                    : isOwner
                                        ? LongStrings.deleteFamily
                                        : LongStrings.leaveFamily,
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

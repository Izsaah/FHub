import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/family_model.dart';
import '../../models/family_member_model.dart';
import '../../models/hierarchy_role.dart';
import '../../models/member_status.dart';
import '../../services/family_state_manager.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/family_member_tile.dart';
import '../../widgets/family_switcher_bar.dart';
import 'create_family_screen.dart';
import 'join_family_screen.dart';
import '../../../Danh/danh_payment_entry.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _stateManager = FamilyStateManager();

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
    if (_stateManager.currentFamily != null) {
      DanhPaymentEntry.onFamilyCreatedOrJoined(_stateManager.currentFamily!.id);
    }
    if (mounted) setState(() {});
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
              Text('Giới Hạn Thành Viên'),
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
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showMemberActionDialog(FamilyMemberModel targetMember, bool isCurrentUserOwner) {
    final currentUserId = _stateManager.service.currentUserId;
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
                  'Vai vế: ${targetMember.hierarchyRole.displayName} · Trạng thái: ${targetMember.status.displayName}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF6E7A75)),
                ),
                if (targetMember.lastActiveAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Hoạt động gần nhất: ${targetMember.lastActiveAt!.day}/${targetMember.lastActiveAt!.month}/${targetMember.lastActiveAt!.year} '
                    '(${DateTime.now().difference(targetMember.lastActiveAt!).inDays} ngày trước)',
                    style: TextStyle(
                      fontSize: 12,
                      color: DateTime.now().difference(targetMember.lastActiveAt!).inDays >= 30
                          ? Colors.deepOrange
                          : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const Divider(height: 24),

                if (isCurrentUserOwner && !isSelf) ...[
                  const Text(
                    'Quản lý trạng thái (Chủ phòng):',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Hoạt động'),
                        selected: targetMember.status == MemberStatus.active,
                        onSelected: (val) async {
                          Navigator.pop(ctx);
                          await _changeMemberStatus(targetMember.user.id, MemberStatus.active);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Tạm ngưng'),
                        selected: targetMember.status == MemberStatus.deactivated,
                        onSelected: (val) async {
                          Navigator.pop(ctx);
                          await _changeMemberStatus(targetMember.user.id, MemberStatus.deactivated);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Tưởng niệm'),
                        selected: targetMember.status == MemberStatus.memorialized,
                        onSelected: (val) async {
                          Navigator.pop(ctx);
                          await _changeMemberStatus(targetMember.user.id, MemberStatus.memorialized);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (targetMember.hierarchyRole == HierarchyRole.parent &&
                      targetMember.status == MemberStatus.active)
                    ListTile(
                      leading: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF005F50)),
                      title: const Text('Chuyển nhượng quyền Chủ phòng (Owner)'),
                      subtitle: const Text('Chỉ có thể chuyển cho thành viên vai vế Bố Mẹ'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _transferOwnership(targetMember.user.id);
                      },
                    ),
                ] else if (isSelf) ...[
                  const Text(
                    'Đây là tài khoản của bạn trong tổ ấm này.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ] else ...[
                  const Text(
                    'Chỉ Chủ phòng (Owner) mới có quyền đổi trạng thái hoặc chuyển nhượng quyền.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _changeMemberStatus(String targetUserId, MemberStatus newStatus) async {
    try {
      await _stateManager.service.updateMemberStatus(targetUserId, newStatus);
      await _stateManager.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã cập nhật trạng thái thành: ${newStatus.displayName}'),
          backgroundColor: const Color(0xFF005F50),
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

  Future<void> _transferOwnership(String newOwnerUserId) async {
    try {
      await _stateManager.service.transferOwnership(newOwnerUserId);
      await _stateManager.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chuyển nhượng quyền Owner thành công!'),
          backgroundColor: Color(0xFF005F50),
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

  Future<void> _handleTakeoverClaim(String familyId) async {
    try {
      await _stateManager.service.claimOwnership(familyId: familyId);
      await _stateManager.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Bạn đã tiếp quản quyền Owner thành công!'),
          backgroundColor: Color(0xFF005F50),
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

  @override
  Widget build(BuildContext context) {
    if (_stateManager.isLoading && _stateManager.currentFamily == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final FamilyModel? family = _stateManager.currentFamily;
    final List<FamilyMemberModel> members = _stateManager.currentMembers;

    if (family == null) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Tổ Ấm Yêu Thương'),
        body: Padding(
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
              const Text(
                'Chào mừng đến Family Hub',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF151D1B),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Bạn chưa tham gia tổ ấm nào. Hãy tạo mới hoặc nhập mã mời để bắt đầu.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Color(0xFF3E4946)),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF005F50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateFamilyScreen(),
                    ),
                  );
                  _stateManager.reload();
                },
                child: const Text(
                  'Tạo Tổ Ấm Mới',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  foregroundColor: const Color(0xFF005F50),
                  side: const BorderSide(color: Color(0xFF005F50)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const JoinFamilyScreen(),
                    ),
                  );
                  _stateManager.reload();
                },
                child: const Text(
                  'Tham Gia Bằng Mã',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final currentUserId = _stateManager.service.currentUserId;
    final currentMember = members.firstWhere(
      (m) => m.user.id == currentUserId,
      orElse: () => FamilyMemberModel(
        familyId: family.id,
        user: members.isNotEmpty ? members.first.user : _stateManager.service.currentUserId as dynamic,
        role: Role.member,
      ),
    );
    final isOwner = currentMember.isOwner;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Tổ Ấm Yêu Thương'),
      body: RefreshIndicator(
        onRefresh: () => _stateManager.reload(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Family Switcher Header
              FamilySwitcherBar(
                currentFamily: family,
                families: _stateManager.myFamilies,
                onFamilyChanged: (famId) {
                  _stateManager.switchFamily(famId);
                },
                onTakeoverClaimed: () => _handleTakeoverClaim(family.id),
              ),
              const SizedBox(height: 12),

              // Widget hiển thị gói Premium & hạn mức thành viên (dành cho mọi thành viên)
              DanhPaymentEntry.buildFamilyPremiumStatus(members.length),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
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
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.cottage,
                              color: Color(0xFF0D7A68),
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
                          onTap: () => _handleInviteMember(family.joinCode, members.length),
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
                          'Thành viên (${members.length}) · Chạm để quản trị',
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
                        onTap: () => _showMemberActionDialog(member, isOwner),
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
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            foregroundColor: const Color(0xFF005F50),
                            backgroundColor: const Color(0xFFE7F0EC)
                                .withValues(alpha: 0.3),
                          ),
                          onPressed: () => _handleInviteMember(family.joinCode, members.length),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// lib/Vinh/screens/wishlist_and_ledger_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/family_member.dart';
import '../models/wishlist_models.dart';
import '../services/star_economy_service.dart';

/// Màn hình Cửa hàng Đổi Sao (Wishlist Phúc lợi thực tế), Lì xì Sao từ Người thân (RELATIVE),
/// và Sổ cái Lịch sử Giao dịch Sao (`star_ledger`).
class WishlistAndLedgerScreen extends StatefulWidget {
  final String familyId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final List<FamilyMember> familyMembers;
  final StarEconomyService? starEconomyService;
  final int initialTabIndex;

  const WishlistAndLedgerScreen({
    super.key,
    required this.familyId,
    required this.currentUserId,
    required this.currentUserName,
    this.currentUserRole = 'PARENT',
    this.familyMembers = const [],
    this.starEconomyService,
    this.initialTabIndex = 0,
  });

  @override
  State<WishlistAndLedgerScreen> createState() =>
      _WishlistAndLedgerScreenState();
}

class _WishlistAndLedgerScreenState extends State<WishlistAndLedgerScreen>
    with SingleTickerProviderStateMixin {
  late final StarEconomyService _starService;
  late final TabController _tabController;
  String _ledgerFilterType = 'ALL';

  FamilyMember? get _currentMember {
    for (final m in widget.familyMembers) {
      if (m.id == widget.currentUserId) return m;
    }
    return null;
  }

  String get _effectiveRole {
    final m = _currentMember;
    if (m != null && m.role.trim().isNotEmpty) return m.role.trim();
    return widget.currentUserRole;
  }

  bool get _isGuardian {
    final m = _currentMember;
    if (m != null) return m.isGuardian && !m.isRelative;
    final upper = _effectiveRole.toUpperCase();
    return (upper.contains('PARENT') ||
            upper.contains('GRANDPARENT') ||
            upper.contains('OWNER')) &&
        !upper.contains('RELATIVE') &&
        !upper.contains('CHILD');
  }

  bool get _isRelative {
    final m = _currentMember;
    if (m != null) return m.isRelative;
    final upper = _effectiveRole.toUpperCase();
    return upper.contains('RELATIVE') ||
        upper.contains('UNCLE') ||
        upper.contains('AUNT');
  }

  int get _myStarBalance {
    final balanceInService =
        _starService.getBalance(widget.familyId, widget.currentUserId);
    if (balanceInService > 0) return balanceInService;
    final m = _currentMember;
    if (m != null && m.rewardStarsTotal > 0) {
      _starService.seedMemberBalance(
        widget.familyId,
        widget.currentUserId,
        m.rewardStarsTotal,
      );
      return m.rewardStarsTotal;
    }
    return balanceInService;
  }

  @override
  void initState() {
    super.initState();
    _starService = widget.starEconomyService ?? StarEconomyService.instance;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    for (final m in widget.familyMembers) {
      if (m.rewardStarsTotal > 0 &&
          _starService.getBalance(widget.familyId, m.id) == 0) {
        _starService.seedMemberBalance(
          widget.familyId,
          m.id,
          m.rewardStarsTotal,
        );
      }
    }
    _starService.getWishlistCatalog(widget.familyId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF005F50);
    final catalog = _starService.getWishlistCatalog(widget.familyId);
    final claims = _starService.getWishlistClaims(widget.familyId);
    final pendingClaims =
        claims.where((c) => c.status == WishlistClaimStatus.pending).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDF5F2),
        elevation: 1,
        title: Text(
          AppLanguage.text(
            'Cửa Hàng Đổi Sao & Sổ Cái ⭐',
            'Star Shop & Ledger ⭐',
          ),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: primaryColor,
          ),
        ),
        actions: [
          if (_isRelative || _isGuardian)
            IconButton(
              tooltip: AppLanguage.text(
                'Lì xì / Tặng sao khích lệ cho cháu',
                'Sponsor / Gift Stars to Child',
              ),
              icon: const Icon(
                Icons.card_giftcard_rounded,
                color: Color(0xFFE65100),
              ),
              onPressed: _showSponsorStarsDialog,
            ),
          if (_isGuardian)
            IconButton(
              tooltip: AppLanguage.text(
                'Thêm phúc lợi thực tế mới',
                'Add New Real-World Reward',
              ),
              icon: const Icon(
                Icons.add_business_rounded,
                color: primaryColor,
              ),
              onPressed: _showCreateRewardDialog,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryColor,
          unselectedLabelColor: Colors.black54,
          indicatorColor: primaryColor,
          tabs: [
            Tab(
              icon: const Icon(Icons.storefront_rounded, size: 18),
              text: AppLanguage.text(
                'Đổi Quà Phúc Lợi (${catalog.length})',
                'Reward Shop (${catalog.length})',
              ),
            ),
            Tab(
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              text: AppLanguage.text(
                'Lịch Sử Sao (Sổ Cái)',
                'Star Ledger History',
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWishlistShopTab(catalog, claims, pendingClaims),
          _buildLedgerHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildWishlistShopTab(
    List<WishlistRewardItem> catalog,
    List<WishlistClaimRecord> allClaims,
    List<WishlistClaimRecord> pendingClaims,
  ) {
    final potStars = _starService.getFamilyStarPool(widget.familyId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Thẻ tổng quan Số dư Sao cá nhân & Quỹ Hũ Sao Gia Đình
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFB300), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLanguage.text(
                              'SỐ DƯ SAO CỦA BẠN (${widget.currentUserName})',
                              'YOUR STAR BALANCE (${widget.currentUserName})',
                            ),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8A5300),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_myStarBalance ⭐',
                            key: const Key('user_star_balance_text'),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFE65100),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFB74D)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Hũ Sao Gia Đình',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.black54,
                            ),
                          ),
                          Text(
                            '$potStars ⭐',
                            key: const Key('family_pot_stars_text'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD84315),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_isGuardian)
                      ElevatedButton.icon(
                        key: const Key('btn_add_wishlist_reward'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF005F50),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Thêm phúc lợi thực tế'),
                        onPressed: _showCreateRewardDialog,
                      ),
                    if (_isRelative || _isGuardian)
                      OutlinedButton.icon(
                        key: const Key('btn_sponsor_stars'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFE65100),
                          side: const BorderSide(color: Color(0xFFE65100)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                        label: Text(
                          _isRelative
                              ? '🎁 Cô/Chú/Bác lì xì Sao cho cháu'
                              : '🎁 Tặng / Lì xì Sao khích lệ',
                        ),
                        onPressed: _showSponsorStarsDialog,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Khu vực Duyệt yêu cầu đổi quà dành cho Phụ huynh / Ông bà
          if (pendingClaims.isNotEmpty) ...[
            Text(
              AppLanguage.text(
                '🔔 Yêu Cầu Đổi Sao Đang Chờ Phụ Huynh Duyệt (${pendingClaims.length})',
                '🔔 Pending Star Redemption Requests (${pendingClaims.length})',
              ),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD84315),
              ),
            ),
            const SizedBox(height: 10),
            ...pendingClaims.map(_buildPendingClaimCard),
            const SizedBox(height: 20),
          ],

          // 3. Danh sách Phúc lợi thực tế để con cái đổi sao
          Text(
            AppLanguage.text(
              '🎁 Danh Sách Phúc Lợi Thực Tế Từ Phụ Huynh',
              '🎁 Real-World Family Rewards Catalog',
            ),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF005F50),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLanguage.text(
              'Chăm chỉ làm việc nhà tích sao để đổi lấy những phần thưởng hấp dẫn từ Bố Mẹ!',
              'Complete chores to earn stars and redeem real-world rewards from parents!',
            ),
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          ...catalog.map(_buildRewardCatalogCard),
        ],
      ),
    );
  }

  Widget _buildPendingClaimCard(WishlistClaimRecord claim) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(claim.iconEmoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${claim.childName} muốn đổi: ${claim.itemName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Đã trừ tạm giữ: ${claim.starCost} ⭐ • Trạng thái: Chờ duyệt',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isGuardian) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  key: Key('btn_reject_claim_${claim.id}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC62828),
                    side: const BorderSide(color: Color(0xFFC62828)),
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Từ chối & Hoàn sao'),
                  onPressed: () => _handleRejectClaim(claim),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  key: Key('btn_approve_claim_${claim.id}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Đồng ý trao quà'),
                  onPressed: () => _handleApproveClaim(claim),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRewardCatalogCard(WishlistRewardItem item) {
    final canAfford = _myStarBalance >= item.starCost;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE8E3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(item.iconEmoji, style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${item.starCost} ⭐',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isGuardian) ...[
            IconButton(
              key: Key('btn_edit_reward_${item.id}'),
              icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF005F50)),
              tooltip: 'Sửa phúc lợi',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _showEditRewardDialog(item),
            ),
            IconButton(
              key: Key('btn_delete_reward_${item.id}'),
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFBA1A1A)),
              tooltip: 'Xóa phúc lợi',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _confirmDeleteReward(item),
            ),
            const SizedBox(width: 4),
          ],
          ElevatedButton(
            key: Key('btn_redeem_${item.id}'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  canAfford ? const Color(0xFFE65100) : Colors.grey.shade300,
              foregroundColor: canAfford ? Colors.white : Colors.black45,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () => _handleRedeemReward(item),
            child: Text(
              AppLanguage.text('Đổi quà', 'Redeem'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerHistoryTab() {
    final allEntries = _starService.getStarLedgerHistory(widget.familyId);
    final filteredEntries = _ledgerFilterType == 'ALL'
        ? allEntries
        : allEntries
            .where((e) => e.type.toUpperCase() == _ledgerFilterType)
            .toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildFilterChip('ALL', 'Tất cả'),
              const SizedBox(width: 8),
              _buildFilterChip('TASK_REWARD', 'Việc nhà (+⭐)'),
              const SizedBox(width: 8),
              _buildFilterChip('JACKPOT_WIN', 'Nổ Hũ Sao (🎉)'),
              const SizedBox(width: 8),
              _buildFilterChip('RELATIVE_SPONSOR', 'Lì xì Sao (🎁)'),
              const SizedBox(width: 8),
              _buildFilterChip('WISHLIST_CLAIM', 'Đổi quà (-⭐)'),
              const SizedBox(width: 8),
              _buildFilterChip('CLAIM_REFUND', 'Hoàn sao (🔄)'),
            ],
          ),
        ),
        Expanded(
          child: filteredEntries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.history_edu_rounded,
                        size: 52,
                        color: Colors.black26,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        AppLanguage.text(
                          'Chưa có giao dịch sao nào trong Sổ cái.',
                          'No star transactions recorded yet.',
                        ),
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: filteredEntries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = filteredEntries[index];
                    final isPos = entry.isPositive;
                    final color = isPos
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828);
                    final sign = isPos ? '+' : '';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(
                          isPos
                              ? Icons.stars_rounded
                              : Icons.shopping_bag_rounded,
                          color: color,
                        ),
                      ),
                      title: Text(
                        entry.displayTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        'Thành viên: ${entry.userName ?? entry.userId}'
                        '${entry.actorName != null ? ' • Duyệt/Gửi bởi: ${entry.actorName}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        '$sign${entry.amount} ⭐',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: color,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String code, String label) {
    final selected = _ledgerFilterType == code;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _ledgerFilterType = code),
    );
  }

  Future<void> _handleRedeemReward(WishlistRewardItem item) async {
    try {
      HapticFeedback.mediumImpact();
      await _starService.submitWishlistRedemption(
        familyId: widget.familyId,
        childId: widget.currentUserId,
        childName: widget.currentUserName,
        item: item,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎉 Đã đổi "${item.title}" (-${item.starCost} ⭐)! Đã gửi thông báo cho Phụ huynh duyệt.',
          ),
          backgroundColor: const Color(0xFF005F50),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('StateError: ', '')),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  Future<void> _handleApproveClaim(WishlistClaimRecord claim) async {
    try {
      await _starService.approveWishlistRedemption(
        claimId: claim.id,
        guardianId: widget.currentUserId,
        guardianName: widget.currentUserName,
        guardianRole: _effectiveRole,
        isGuardian: _isGuardian,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Đã duyệt trao phần thưởng "${claim.itemName}" cho ${claim.childName}!',
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  Future<void> _handleRejectClaim(WishlistClaimRecord claim) async {
    try {
      await _starService.rejectWishlistRedemption(
        claimId: claim.id,
        guardianId: widget.currentUserId,
        guardianName: widget.currentUserName,
        guardianRole: _effectiveRole,
        isGuardian: _isGuardian,
        reason: 'Phụ huynh từ chối & hoàn sao',
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🔄 Đã từ chối và hoàn lại ${claim.starCost} ⭐ cho ${claim.childName}!',
          ),
          backgroundColor: const Color(0xFFE65100),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  void _showEditRewardDialog(WishlistRewardItem item) {
    final titleCtrl = TextEditingController(text: item.title);
    final descCtrl = TextEditingController(text: item.description);
    final costCtrl = TextEditingController(text: item.starCost.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chỉnh Sửa Phúc Lợi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_edit_reward_title'),
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên phần thưởng',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_edit_reward_cost'),
                controller: costCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số sao cần đổi (⭐)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_edit_reward_desc'),
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mô tả chi tiết',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('btn_save_edit_reward'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF005F50),
            ),
            onPressed: () async {
              final newTitle = titleCtrl.text.trim();
              final newCost = int.tryParse(costCtrl.text.trim()) ?? item.starCost;
              final newDesc = descCtrl.text.trim();
              if (newTitle.isEmpty || newCost <= 0) return;

              try {
                await _starService.updateWishlistRewardItem(
                  familyId: widget.familyId,
                  itemId: item.id,
                  editorId: widget.currentUserId,
                  editorName: widget.currentUserName,
                  editorRole: _effectiveRole,
                  isGuardian: _isGuardian,
                  title: newTitle,
                  description: newDesc,
                  starCost: newCost,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Đã cập nhật phúc lợi "$newTitle"!'),
                    backgroundColor: const Color(0xFF005F50),
                  ),
                );
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFFC62828)),
                );
              }
            },
            child: const Text('Lưu Thay Đổi'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteReward(WishlistRewardItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa Phúc Lợi Thực Tế?'),
        content: Text(
          'Bạn có chắc chắn muốn xóa "${item.title}" (${item.starCost} ⭐) khỏi danh mục đổi quà của gia đình không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('btn_confirm_delete_reward'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
            ),
            onPressed: () async {
              try {
                await _starService.removeWishlistRewardItem(
                  familyId: widget.familyId,
                  itemId: item.id,
                  removerId: widget.currentUserId,
                  removerName: widget.currentUserName,
                  removerRole: _effectiveRole,
                  isGuardian: _isGuardian,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ Đã xóa phúc lợi "${item.title}"!'),
                    backgroundColor: const Color(0xFFE65100),
                  ),
                );
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFFC62828)),
                );
              }
            },
            child: const Text('Xóa Phúc Lợi'),
          ),
        ],
      ),
    );
  }

  void _showCreateRewardDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final costCtrl = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Phúc Lợi Thực Tế Mới'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_reward_title'),
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên phần thưởng (VD: Xem phim 30 phút)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_reward_cost'),
                controller: costCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số sao cần đổi (⭐)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mô tả chi tiết (không bắt buộc)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_create_reward'),
            onPressed: () async {
              final cost = int.tryParse(costCtrl.text.trim()) ?? 0;
              try {
                await _starService.createWishlistRewardItem(
                  familyId: widget.familyId,
                  creatorId: widget.currentUserId,
                  creatorName: widget.currentUserName,
                  creatorRole: _effectiveRole,
                  isGuardian: _isGuardian,
                  title: titleCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  starCost: cost,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            child: const Text('Lưu phúc lợi'),
          ),
        ],
      ),
    );
  }

  void _showSponsorStarsDialog() {
    final children = widget.familyMembers.where((m) => m.isChild).toList();
    String targetChildId =
        children.isNotEmpty ? children.first.id : 'child_default';
    String targetChildName =
        children.isNotEmpty ? children.first.name : 'Cháu ngoan';
    final starsCtrl = TextEditingController(text: '10');
    final noteCtrl = TextEditingController(text: 'Lì xì sao khích lệ cháu chăm ngoan');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('🎁 Lì Xì / Tặng Sao Khích Lệ Cháu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (children.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: targetChildId,
                    decoration: const InputDecoration(labelText: 'Chọn cháu nhận sao'),
                    items: children
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          targetChildId = val;
                          targetChildName = children
                              .firstWhere((c) => c.id == val)
                              .name;
                        });
                      }
                    },
                  ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('input_sponsor_stars'),
                  controller: starsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số sao lì xì (> 0 ⭐)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lời nhắn khích lệ',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              key: const Key('btn_confirm_sponsor_stars'),
              onPressed: () async {
                final stars = int.tryParse(starsCtrl.text.trim()) ?? 0;
                try {
                  await _starService.giftStarsToChild(
                    familyId: widget.familyId,
                    senderId: widget.currentUserId,
                    senderName: widget.currentUserName,
                    senderRole: _effectiveRole,
                    childId: targetChildId,
                    childName: targetChildName,
                    stars: stars,
                    note: noteCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '🎁 Đã lì xì +$stars ⭐ cho $targetChildName thành công!',
                        ),
                        backgroundColor: const Color(0xFF2E7D32),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: const Color(0xFFC62828),
                      ),
                    );
                  }
                }
              },
              child: const Text('Tặng Sao Ngay'),
            ),
          ],
        ),
      ),
    );
  }
}

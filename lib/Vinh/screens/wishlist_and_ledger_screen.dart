// lib/Vinh/screens/wishlist_and_ledger_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/family_member.dart';
import '../models/wishlist_models.dart';
import '../services/star_economy_service.dart';
import '../../Long/services/family_data_service.dart';

/// Màn hình Cửa hàng Đổi Sao (Wishlist Phúc lợi thực tế), Lì xì Sao từ Người thân (RELATIVE),
/// và Sổ cái Lịch sử Giao dịch Sao (`star_ledger`).
class WishlistAndLedgerScreen extends StatefulWidget {
  final String familyId;
  final String? familyName;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final List<FamilyMember> familyMembers;
  final StarEconomyService? starEconomyService;
  final int initialTabIndex;

  const WishlistAndLedgerScreen({
    super.key,
    required this.familyId,
    this.familyName,
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
  String _resolvedFamilyName = '';

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
    _resolvedFamilyName = widget.familyName ?? '';
    if (_resolvedFamilyName.isEmpty) {
      FamilyDataService().getCurrentFamily().then((f) {
        if (mounted && f != null && f.name.isNotEmpty) {
          setState(() => _resolvedFamilyName = f.name);
        }
      });
    }
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
    _starService.fetchWishlistCatalog(widget.familyId).then((_) {
      if (mounted) setState(() {});
    });
    _starService.fetchMemberBalance(widget.familyId, widget.currentUserId).then((b) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF005F50);

    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, isEn, child) {
        return StreamBuilder<List<WishlistRewardItem>>(
      stream: _starService.watchWishlistCatalog(widget.familyId),
      initialData: _starService.getWishlistCatalog(widget.familyId),
      builder: (context, catalogSnap) {
        final catalog = catalogSnap.data ?? [];
        return StreamBuilder<List<WishlistClaimRecord>>(
          stream: _starService.watchWishlistClaims(widget.familyId),
          initialData: _starService.getWishlistClaims(widget.familyId),
          builder: (context, claimsSnap) {
            final claims = claimsSnap.data ?? [];
            final pendingClaims = claims
                .where((c) => c.status == WishlistClaimStatus.pending)
                .toList();
            final pendingItemIds = pendingClaims.map((c) => c.itemId).toSet();
            final availableCatalog =
                catalog.where((item) => !pendingItemIds.contains(item.id)).toList();

            return StreamBuilder<int>(
              stream: _starService.watchMemberBalance(
                widget.familyId,
                widget.currentUserId,
              ),
              initialData: _myStarBalance,
              builder: (context, balanceSnap) {
                final liveBalance = balanceSnap.data ?? _myStarBalance;

                return Scaffold(
                  backgroundColor: const Color(0xFFF3FBF8),
                  appBar: AppBar(
                    backgroundColor: const Color(0xFFEDF5F2),
                    elevation: 1,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppLanguage.text(
                            'Cửa Hàng Đổi Sao & Sổ Cái ⭐',
                            'Star Shop & Ledger ⭐',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: primaryColor,
                          ),
                        ),
                        if (_resolvedFamilyName.isNotEmpty)
                          Text(
                            _resolvedFamilyName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: primaryColor.withValues(alpha: 0.8),
                            ),
                          ),
                      ],
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
                          key: const Key('btn_appbar_add_reward'),
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
                            'Đổi Quà Phúc Lợi (${availableCatalog.length})',
                            'Reward Shop (${availableCatalog.length})',
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
                      _buildWishlistShopTab(
                        availableCatalog,
                        claims,
                        pendingClaims,
                        liveBalance,
                      ),
                      _buildLedgerHistoryTab(),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
      },
    );
  }

  Widget _buildWishlistShopTab(
    List<WishlistRewardItem> catalog,
    List<WishlistClaimRecord> allClaims,
    List<WishlistClaimRecord> pendingClaims,
    int liveBalance,
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
                            '$liveBalance ⭐',
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
                          Text(
                            AppLanguage.text('Hũ Sao Gia Đình', 'Family Star Pot'),
                            style: const TextStyle(
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
                        label: Text(AppLanguage.text('Thêm phúc lợi thực tế', 'Add Real Reward')),
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
                              ? AppLanguage.text('Cô/Chú/Bác lì xì Sao cho cháu', 'Gift Stars to Child')
                              : AppLanguage.text('Tặng / Lì xì Sao khích lệ', 'Gift / Sponsor Stars'),
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
          if (catalog.isEmpty)
            _buildEmptyCatalogCard()
          else
            ...catalog.map((item) => _buildRewardCatalogCard(item, liveBalance)),
        ],
      ),
    );
  }

  Widget _buildEmptyCatalogCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      margin: const EdgeInsets.only(top: 8, bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0ECE6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('🎁', style: TextStyle(fontSize: 36)),
          ),
          const SizedBox(height: 16),
          Text(
            AppLanguage.text(
              'Gia đình chưa có phần thưởng nào!',
              'No rewards added for this family yet!',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF005F50),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.text(
              'Mỗi gia đình có một Cửa hàng Đổi Sao riêng biệt trên Firebase. Bố/Mẹ hãy tạo các phần thưởng thiết thực (như xem TV 30 phút, mua truyện, đi chơi...) để các con chăm chỉ làm việc nhà tích sao đổi thưởng nhé!',
              'Each family has its own rewards market on Firebase. Parents can create real-world rewards (screen time, books, outings) to motivate children!',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
          if (_isGuardian) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              key: const Key('btn_add_first_reward'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005F50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: Text(
                AppLanguage.text(
                  '+ Thêm phúc lợi cho gia đình',
                  '+ Add family reward',
                ),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: _showCreateRewardDialog,
            ),
          ] else ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Text(
                AppLanguage.text(
                  '💡 Nhắc Bố/Mẹ thêm phần thưởng con yêu thích vào cửa hàng nhé!',
                  '💡 Ask Mom/Dad to add rewards you would love to redeem!',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE65100),
                ),
              ),
            ),
          ],
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
                      AppLanguage.text(
                        '${claim.childName} muốn đổi: ${claim.itemName}',
                        '${claim.childName} requests: ${claim.itemName}',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      AppLanguage.text(
                        'Đã trừ tạm giữ: ${claim.starCost} ⭐ • Trạng thái: Chờ duyệt',
                        'Held: ${claim.starCost} ⭐ • Status: Pending approval',
                      ),
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
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: Key('btn_reject_claim_${claim.id}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC62828),
                    side: const BorderSide(color: Color(0xFFC62828)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: Text(AppLanguage.text('Từ chối & Hoàn sao', 'Reject & Refund')),
                  onPressed: () => _handleRejectClaim(claim),
                ),
                ElevatedButton.icon(
                  key: Key('btn_approve_claim_${claim.id}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(AppLanguage.text('Đồng ý trao quà', 'Approve & Grant')),
                  onPressed: () => _handleApproveClaim(claim),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRewardCatalogCard(WishlistRewardItem item, [int? liveBalance]) {
    final effectiveBalance = liveBalance ?? _myStarBalance;
    final canAfford = effectiveBalance >= item.starCost;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: canAfford ? const Color(0xFFFFCC80) : const Color(0xFFE0ECE6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: canAfford ? const Color(0x12FF9800) : const Color(0x06000000),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF9C4), Color(0xFFFFE082)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14F57F17),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
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
                        fontSize: 15,
                        color: Color(0xFF1B2E28),
                      ),
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.description,
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF556962), height: 1.3),
                      ),
                    ],
                  ],
                ),
              ),
              if (_isGuardian) ...[
                IconButton(
                  key: Key('btn_edit_reward_${item.id}'),
                  icon: const Icon(Icons.edit_outlined, size: 19, color: Color(0xFF005F50)),
                  tooltip: AppLanguage.text('Sửa phúc lợi', 'Edit reward'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _showEditRewardDialog(item),
                ),
                IconButton(
                  key: Key('btn_delete_reward_${item.id}'),
                  icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFBA1A1A)),
                  tooltip: AppLanguage.text('Xóa phúc lợi', 'Delete reward'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _confirmDeleteReward(item),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF0F4F2)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFCC80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars_rounded, size: 16, color: Color(0xFFE65100)),
                        const SizedBox(width: 4),
                        Text(
                          '${item.starCost} ⭐',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: canAfford ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      canAfford
                          ? AppLanguage.text('Đủ sao đổi', 'Available')
                          : AppLanguage.text('Thiếu ${item.starCost - effectiveBalance} ⭐', 'Need ${item.starCost - effectiveBalance} ⭐'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: canAfford ? const Color(0xFF2E7D32) : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.currentUserId.isNotEmpty && widget.currentUserId == item.createdBy)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: Text(
                    AppLanguage.text('Bạn đã tạo', 'Created by you'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                )
              else
                ElevatedButton.icon(
                  key: Key('btn_redeem_${item.id}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAfford ? const Color(0xFFE65100) : Colors.grey.shade300,
                    foregroundColor: canAfford ? Colors.white : Colors.black45,
                    elevation: canAfford ? 2 : 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.card_giftcard_rounded, size: 16),
                  label: Text(
                    AppLanguage.text('Đổi quà', 'Redeem'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: () => _handleRedeemReward(item),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerHistoryTab() {
    return StreamBuilder<List<StarLedgerEntryModel>>(
      stream: _starService.watchStarLedger(widget.familyId),
      initialData: _starService.getStarLedgerHistory(widget.familyId),
      builder: (context, snapshot) {
        final allEntries = snapshot.data ?? [];
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
              _buildFilterChip('ALL', AppLanguage.text('Tất cả', 'All'), Icons.all_inclusive_rounded),
              const SizedBox(width: 8),
              _buildFilterChip('TASK_REWARD', AppLanguage.text('Việc nhà', 'Chores'), Icons.task_alt_rounded),
              const SizedBox(width: 8),
              _buildFilterChip('JACKPOT_WIN', AppLanguage.text('Heo Đất', 'Piggy Bank'), Icons.savings_outlined),
              const SizedBox(width: 8),
              _buildFilterChip('RELATIVE_SPONSOR', AppLanguage.text('Lì xì Sao', 'Gifts / Sponsor'), Icons.card_giftcard_rounded),
              const SizedBox(width: 8),
              _buildFilterChip('WISHLIST_CLAIM', AppLanguage.text('Đổi quà', 'Redemption'), Icons.shopping_bag_outlined),
              const SizedBox(width: 8),
              _buildFilterChip('CLAIM_REFUND', AppLanguage.text('Hoàn sao', 'Refund'), Icons.replay_rounded),
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

                    final memberName = (entry.userName != null &&
                            entry.userName!.trim().isNotEmpty)
                        ? entry.userName!
                        : (entry.userId == widget.currentUserId
                            ? AppLanguage.text('Bạn', 'You')
                            : AppLanguage.text('Thành viên gia đình', 'Family member'));
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
                        AppLanguage.text('Thành viên: $memberName', 'Member: $memberName') +
                        (entry.actorName != null ? AppLanguage.text(' • Duyệt/Gửi bởi: ${entry.actorName}', ' • Reviewed/Sent by: ${entry.actorName}') : ''),
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
      },
    );
  }

  Widget _buildFilterChip(String code, String label, IconData icon) {
    final selected = _ledgerFilterType == code;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : const Color(0xFF005F50),
      ),
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFF005F50),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? Colors.white : const Color(0xFF1B382B),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? const Color(0xFF005F50) : const Color(0xFFCFE0D8),
        ),
      ),
      onSelected: (_) => setState(() => _ledgerFilterType = code),
    );
  }

  Future<void> _handleRedeemReward(WishlistRewardItem item) async {
    final isAlreadyPending = _starService
        .getWishlistClaims(widget.familyId)
        .any((c) => c.itemId == item.id && c.status == WishlistClaimStatus.pending);
    if (isAlreadyPending) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              '⚠️ Phần thưởng này đang có yêu cầu đổi chờ phụ huynh duyệt!',
              '⚠️ This reward already has a pending redemption request awaiting parent approval!',
            ),
          ),
          backgroundColor: const Color(0xFFD84315),
        ),
      );
      return;
    }
    if (widget.currentUserId.isNotEmpty && widget.currentUserId == item.createdBy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              '⚠️ Bạn là người tạo phần thưởng này, không thể tự đổi vật phẩm của chính mình.',
              '⚠️ You created this reward and cannot redeem your own item.',
            ),
          ),
          backgroundColor: const Color(0xFFD84315),
        ),
      );
      return;
    }
    final balance = _myStarBalance;
    if (balance < item.starCost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              '⚠️ Số dư sao của bạn ($balance ⭐) không đủ để đổi "${item.title}" (Cần ${item.starCost} ⭐). Hãy làm thêm việc nhà để tích sao nhé!',
              '⚠️ Your star balance ($balance ⭐) is insufficient to redeem "${item.title}" (Need ${item.starCost} ⭐). Do more chores to earn stars!',
            ),
          ),
          backgroundColor: const Color(0xFFD84315),
        ),
      );
      return;
    }
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
            AppLanguage.text(
              '✨ Đã đổi "${item.title}" (-${item.starCost} ⭐)! Đã gửi thông báo cho Phụ huynh duyệt.',
              '✨ Redeemed "${item.title}" (-${item.starCost} ⭐)! Sent to Parents for approval.',
            ),
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
            AppLanguage.text(
              '✅ Đã duyệt trao phần thưởng "${claim.itemName}" cho ${claim.childName}!',
              '✅ Approved reward "${claim.itemName}" for ${claim.childName}!',
            ),
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
        reason: AppLanguage.text('Phụ huynh từ chối & hoàn sao', 'Parents rejected & refunded stars'),
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              '🔄 Đã từ chối và hoàn lại ${claim.starCost} ⭐ cho ${claim.childName}!',
              '🔄 Rejected and refunded ${claim.starCost} ⭐ to ${claim.childName}!',
            ),
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
        title: Text(AppLanguage.text('Chỉnh Sửa Phúc Lợi', 'Edit Real-World Reward')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_edit_reward_title'),
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: AppLanguage.text('Tên phần thưởng', 'Reward title'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_edit_reward_cost'),
                controller: costCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppLanguage.text('Số sao cần đổi (⭐)', 'Star cost (⭐)'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_edit_reward_desc'),
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: AppLanguage.text('Mô tả chi tiết', 'Detailed description'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLanguage.text('Hủy', 'Cancel')),
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
                    content: Text(AppLanguage.text('✅ Đã cập nhật phúc lợi "$newTitle"!', '✅ Updated reward "$newTitle"!')),
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
            child: Text(AppLanguage.text('Lưu Thay Đổi', 'Save Changes')),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteReward(WishlistRewardItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLanguage.text('Xóa Phúc Lợi Thực Tế?', 'Delete Real-World Reward?')),
        content: Text(
          AppLanguage.text(
            'Bạn có chắc chắn muốn xóa "${item.title}" (${item.starCost} ⭐) khỏi danh mục đổi quà của gia đình không?',
            'Are you sure you want to delete "${item.title}" (${item.starCost} ⭐) from the family rewards catalog?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLanguage.text('Hủy', 'Cancel')),
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
                    content: Text(AppLanguage.text('🗑️ Đã xóa phúc lợi "${item.title}"!', '🗑️ Deleted reward "${item.title}"!')),
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
            child: Text(AppLanguage.text('Xóa Phúc Lợi', 'Delete Reward')),
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
        title: Text(AppLanguage.text('Thêm Phúc Lợi Thực Tế Mới', 'Add New Real-World Reward')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_reward_title'),
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: AppLanguage.text('Tên phần thưởng (VD: Xem phim 30 phút)', 'Reward title (e.g. 30m TV time)'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_reward_cost'),
                controller: costCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppLanguage.text('Số sao cần đổi (⭐)', 'Star cost (⭐)'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: AppLanguage.text('Mô tả chi tiết (không bắt buộc)', 'Detailed description (optional)'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLanguage.text('Hủy', 'Cancel')),
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
            child: Text(AppLanguage.text('Lưu phúc lợi', 'Save Reward')),
          ),
        ],
      ),
    );
  }

  void _showSponsorStarsDialog() {
    final eligibleReceivers = widget.familyMembers.where((m) => m.id != widget.currentUserId).toList();
    if (eligibleReceivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguage.text('Gia đình cần có ít nhất 2 thành viên để sử dụng tính năng tặng sao khích lệ!', 'Family must have at least 2 members to sponsor stars!')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String targetMemberId = eligibleReceivers.first.id;
    String targetMemberName = eligibleReceivers.first.name;
    final starsCtrl = TextEditingController(text: '10');
    final noteCtrl = TextEditingController(text: AppLanguage.text('Lì xì sao khích lệ chăm ngoan', 'Encouragement gift stars'));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.card_giftcard_rounded, color: Color(0xFF005F50), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLanguage.text('Lì Xì / Tặng Sao Khích Lệ', 'Gift / Sponsor Stars'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: targetMemberId,
                  decoration: InputDecoration(
                    labelText: AppLanguage.text('Chọn thành viên nhận sao', 'Select member to receive stars'),
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                  items: eligibleReceivers
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.name} (${c.role.isNotEmpty ? c.role : AppLanguage.text("Thành viên", "Member")})'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        targetMemberId = val;
                        targetMemberName = eligibleReceivers
                            .firstWhere((c) => c.id == val)
                            .name;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input_sponsor_stars'),
                  controller: starsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: AppLanguage.text('Số sao lì xì (1 - 20 ⭐)', 'Gift stars amount (1 - 20 ⭐)'),
                    helperText: AppLanguage.text(
                      'Tối đa 20 ⭐ và không quá số dư hiện có ($_myStarBalance ⭐)',
                      'Limit: max 20 ⭐ and not exceeding current balance ($_myStarBalance ⭐)',
                    ),
                    prefixIcon: const Icon(Icons.stars_rounded, color: Colors.amber),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: AppLanguage.text('Lời nhắn khích lệ', 'Encouragement message'),
                    prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLanguage.text('Hủy', 'Cancel')),
            ),
            ElevatedButton(
              key: const Key('btn_confirm_sponsor_stars'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005F50),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final stars = int.tryParse(starsCtrl.text.trim()) ?? 0;
                if (stars <= 0 || stars > 20) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLanguage.text('Số sao tặng mỗi lần phải từ 1 đến 20 ⭐!', 'Gifted stars must be between 1 and 20 ⭐!')),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (stars > _myStarBalance) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLanguage.text(
                        'Số sao tặng không được vượt quá số sao bạn hiện có ($_myStarBalance ⭐)!',
                        'Cannot gift more than your current star balance ($_myStarBalance ⭐)!',
                      )),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                try {
                  await _starService.giftStarsToChild(
                    familyId: widget.familyId,
                    senderId: widget.currentUserId,
                    senderName: widget.currentUserName,
                    senderRole: _effectiveRole,
                    childId: targetMemberId,
                    childName: targetMemberName,
                    stars: stars,
                    note: noteCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLanguage.text(
                            '🎁 Đã lì xì +$stars ⭐ cho $targetMemberName thành công!',
                            '🎁 Successfully gifted +$stars ⭐ to $targetMemberName!',
                          ),
                        ),
                        backgroundColor: const Color(0xFF2E7D32),
                      ),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '')),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(AppLanguage.text('Tặng Sao Ngay', 'Gift Stars Now')),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import '../../Long/models/family_member_model.dart';
import '../../Thinh/theme/app_language.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_jackpot_model.dart';
import '../models/user_bank_info.dart';
import '../models/notification_model.dart';
import '../models/wallet_transaction_model.dart';
import '../services/notification_service.dart';
import '../../Long/services/family_data_service.dart';
import '../services/family_jackpot_service.dart';
import '../services/payment_config.dart';
import '../services/bank_directory.dart';
import '../services/payment_service.dart';
import '../services/sepay_service.dart';
import '../theme/danh_colors.dart';
import '../theme/danh_svgs.dart';
import 'premium_plan_screen.dart';
import '../danh_payment_entry.dart';

/// Màn hình Hũ Niềm Vui Gia Đình (Nổ Hũ Shopee Shake)
/// Tính năng độc quyền cho gói Tổ Ấm Premium
class FamilyJackpotScreen extends StatefulWidget {
  const FamilyJackpotScreen({super.key});

  @override
  State<FamilyJackpotScreen> createState() => _FamilyJackpotScreenState();
}

class _FamilyJackpotScreenState extends State<FamilyJackpotScreen>
    with SingleTickerProviderStateMixin {
  final FamilyJackpotService _jackpotService = FamilyJackpotService();
  late AnimationController _shakeAnimController;
  String _familyName = '';
  bool _hasShownYTroiDialog = false;
  int _lastRenderedShakeCount = 0;
  double? _lastMouseX;
  DateTime? _lastMouseShakeTime;
  bool _isCurrentUserParent = true;
  List<FamilyMemberModel> _currentFamilyMembers = [];

  @override
  void initState() {
    super.initState();
    final famId = PaymentService().currentFamilyId;
    _jackpotService.initForFamily(famId);
    _loadFamilyContext();
    _lastRenderedShakeCount = _jackpotService.myShakeCount;
    _shakeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      lowerBound: -0.12,
      upperBound: 0.12,
    );
  }

  Future<void> _loadFamilyContext() async {
    try {
      final fam = await FamilyDataService().getCurrentFamily();
      final effectiveFamId = (fam != null && fam.id.isNotEmpty)
          ? fam.id
          : (PaymentService().currentFamilyId.isNotEmpty
              ? PaymentService().currentFamilyId
              : 'f1');

      if (PaymentService().currentFamilyId != effectiveFamId) {
        PaymentService().setFamilyId(effectiveFamId);
      }
      _jackpotService.initForFamily(effectiveFamId);

      if (mounted && fam != null && fam.name.isNotEmpty) {
        setState(() => _familyName = fam.name);
      }

      final members = await FamilyDataService().getFamilyMembers(familyId: effectiveFamId);
      if (mounted) {
        setState(() {
          _currentFamilyMembers = members;
          final myUid = _jackpotService.currentUserId;
          String? currentEmail;
          try {
            currentEmail = FirebaseAuth.instance.currentUser?.email;
          } catch (_) {}
          for (final m in members) {
            if (m.user.id == myUid || (currentEmail != null && m.user.email == currentEmail)) {
              _isCurrentUserParent = m.isParent || m.isOwner || m.isGuardian;
              break;
            }
          }
        });
      }

      final isParent = await _jackpotService.isUserParent(familyId: effectiveFamId);
      if (mounted) {
        setState(() => _isCurrentUserParent = isParent);
      }

      _syncCheckInFromHome(effectiveFamId);
    } catch (e) {
      debugPrint('Error loading family context in jackpot: $e');
    }
  }

  String? _getMemberName(String uid) {
    for (final m in _currentFamilyMembers) {
      if (m.user.id == uid) return m.user.name;
    }
    return null;
  }

  String? _getMemberRoleLabel(String uid) {
    for (final m in _currentFamilyMembers) {
      if (m.user.id == uid) return m.roleLabel;
    }
    return null;
  }

  Future<void> _syncCheckInFromHome(String famId) async {
    try {
      final members = await FamilyDataService().getFamilyMembers(familyId: famId);
      await _jackpotService.syncCheckInsFromMembers(members);
    } catch (e) {
      debugPrint('_syncCheckInFromHome error: $e');
    }
  }

  @override
  void dispose() {
    _shakeAnimController.dispose();
    super.dispose();
  }

  void _triggerShakeAnimation() {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _shakeAnimController.forward().then((_) {
      if (mounted) _shakeAnimController.reverse();
    });
  }

  void _onManualShake() {
    _jackpotService.recordShake();
    _triggerShakeAnimation();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, isEn, _) {
        return ListenableBuilder(
          listenable: _jackpotService,
          builder: (context, _) {
        final jackpot = _jackpotService.jackpot;
        final currentShakeCount = _jackpotService.myShakeCount;

        // Tự động rung và lắc icon trên màn hình khi cảm biến điện thoại ghi nhận lượt lắc mới
        if (jackpot.isShaking && currentShakeCount > _lastRenderedShakeCount) {
          _lastRenderedShakeCount = currentShakeCount;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _triggerShakeAnimation();
          });
        } else if (!jackpot.isShaking) {
          _lastRenderedShakeCount = 0;
        }

        // Tự động bật Modal meme "Ý Trời" khi kết thúc: Chỉ popup với Quán quân thể lực bị trượt Giải Nhất
        if (jackpot.isFinished && !_hasShownYTroiDialog) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && jackpot.isTopShakerUnlucky) {
              _hasShownYTroiDialog = true;
              final myUid = _jackpotService.currentUserId;
              final isMeTopShaker = myUid == jackpot.topShakerId;
              final isMeWinner = myUid == jackpot.firstPrizeWinnerId;
              if (isMeTopShaker && !isMeWinner) {
                _showYTroiDialog(jackpot);
              }
            }
          });
        }

        return Scaffold(
          backgroundColor: DanhColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: DanhColors.brand50,
            elevation: 1,
            titleSpacing: 0,
            leading: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: DanhColors.brand800),
              onPressed: () => Navigator.pop(context),
            ),
            title: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLanguage.text('Hũ Niềm Vui Gia Đình', 'Family Happiness Pot'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: DanhColors.brand800,
                    ),
                  ),
                  if (_familyName.isNotEmpty)
                    Text(
                      _familyName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: DanhColors.brand700.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              // Nút Thông Báo In-app Hub với Unread Badge Count
              StreamBuilder<int>(
                stream: NotificationService.instance.watchUnreadCount(
                  PaymentService().currentFamilyId,
                  currentUserId: _jackpotService.currentUserId,
                ),
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        tooltip: AppLanguage.text('Thông báo gia đình', 'Family Notifications'),
                        icon: const Icon(Icons.notifications_outlined, color: DanhColors.brand800),
                        onPressed: _openNotificationsModal,
                      ),
                      if (unread > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFD32F2F),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              unread > 9 ? '9+' : '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              IconButton(
                tooltip: AppLanguage.text('Luật chơi & Giải thưởng', 'Pot Rules & Guidelines'),
                icon: const Icon(Icons.help_outline_rounded, color: DanhColors.brand800),
                onPressed: _showRulesModal,
              ),
              PopupMenuButton<String>(
                tooltip: 'Tùy chọn khác',
                icon: const Icon(Icons.more_vert_rounded, color: DanhColors.brand800),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (val) {
                  if (val == 'history') {
                    _openWalletHistoryModal();
                  } else if (val == 'withdraw') {
                    _openBankAndWithdrawModal();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'history',
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, size: 18, color: DanhColors.brand800),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Lịch sử ví & quỹ (15 ngày)',
                            style: TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'withdraw',
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded, size: 18, color: DanhColors.brand800),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ví thưởng & rút tiền',
                            style: TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            bottom: true,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 28,
              ),
            child: Column(
              children: [
                // Cảnh báo nếu hũ vừa bị tiêu hủy do mất gói Premium
                if (jackpot.lostDueToPremiumExpired)
                  _buildForfeitedPotWarning(),

                // Thẻ Hũ Vàng trung tâm kèm Ví cá nhân
                _buildPotHeaderCard(jackpot),
                const SizedBox(height: 20),

                // Nếu gia đình chưa có Premium -> Khóa và yêu cầu nâng cấp
                if (!_jackpotService.canUseJackpot)
                  _buildPremiumRequiredSection()
                // Nội dung thay đổi linh hoạt theo trạng thái: IDLE / SHAKING / SUSPENSE / FINISHED
                else if (jackpot.isIdle)
                  _buildIdleSection(jackpot)
                else if (jackpot.isShaking)
                  _buildShakingSection(jackpot)
                else if (jackpot.isSuspense)
                  _buildSuspenseSection(jackpot)
                else
                  _buildFinishedSection(jackpot),
              ],
            ),
          ),
          ),
        );
      },
    );
      },
    );
  }

  /// Thẻ Hũ Vàng trung tâm với biểu tượng SVG và tổng quỹ Sao Gia Đình
  Widget _buildPotHeaderCard(FamilyJackpotModel jackpot) {
    final formattedAmount = '${jackpot.totalPoolAmount} ⭐'.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3), Color(0xFFFFE082)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DanhColors.gold.withValues(alpha: 0.8), width: 1.5),
        boxShadow: DanhColors.premiumGlowShadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DanhSvgs.goldenPot(size: 56),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.text('TỔNG QUỸ HŨ SAO GIA ĐÌNH', 'FAMILY STAR JACKPOT POOL'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8A5300),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formattedAmount,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF663C00),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DanhColors.gold.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DanhSvgs.crown(size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    AppLanguage.text('Người nạp nhiều nhất: ${jackpot.topContributorName}', 'Top Contributor: ${jackpot.topContributorName}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: DanhColors.brand900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Trạng thái 1: Chuẩn bị & Nạp tiền vào hũ (Qua VietQR SePay)
  Widget _buildIdleSection(FamilyJackpotModel jackpot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              AppLanguage.text('1. Tích Lũy Sao Vào Hũ Niềm Vui ⭐', '1. Contribute Stars into Family Pot ⭐'),
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.bold,
                color: DanhColors.brand900,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300, width: 0.8),
              ),
              child: Text(
                '⭐ Nổ Hũ Sao',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFDE7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFFE082)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.stars_rounded, color: Color(0xFFF57F17), size: 20),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      AppLanguage.text('Quy chế tích lũy sao vào hũ', 'How pot stars accumulate'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFFE65100),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                AppLanguage.text(
                                  '• Cả nhà hoàn thành điểm danh mỗi ngày: +10 ⭐ vào hũ.\n'
                                  '• Đổi phúc lợi từ shop: Tích điểm 10% tổng số sao vào hũ.',
                                  '• Daily family check-in completed: +10 ⭐ to pot.\n'
                                  '• Wishlist reward redeemed: 10% cashback added to pot.',
                                ),
                                style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF5D4037)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDailyCheckInCard(jackpot),
                        const SizedBox(height: 24),

        Text(
          AppLanguage.text('2. Bảng Vinh Danh Thành Viên Đóng Góp', '2. Contributor Leaderboard'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: DanhColors.brand900,
          ),
        ),
        const SizedBox(height: 10),
        _buildContributionsList(jackpot),
        const SizedBox(height: 24),

        Text(
          AppLanguage.text('3. Danh Sách Tham Gia Nổ Hũ', '3. Pot Shake Participants'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: DanhColors.brand900,
          ),
        ),
        const SizedBox(height: 10),
        _buildParticipantsList(jackpot),
        const SizedBox(height: 24),

        // Nút chính: Phát động phiếu chờ 5 phút / Xác nhận tham gia / Bắt đầu ngay
        _buildMainActionButton(jackpot),
      ],
    );
  }

  /// Mục 3: Danh sách thành viên tham gia nổ hũ (Giới hạn tối đa 5 tên, cuộn mượt nếu > 5)
  Widget _buildParticipantsList(FamilyJackpotModel jackpot) {
    final isLobby = jackpot.isLobbyActive;
    final acceptedIds = jackpot.lobbyAcceptedMemberIds.toSet();
    final targetIds = jackpot.lobbyTargetMemberIds.toSet();

    final List<Map<String, dynamic>> items = [];

    if (isLobby) {
      final allLobbyUids = <String>{};
      allLobbyUids.addAll(targetIds);
      allLobbyUids.addAll(acceptedIds);
      for (final m in _currentFamilyMembers) {
        allLobbyUids.add(m.user.id);
      }
      for (final k in jackpot.memberNames.keys) {
        if (k != 'system_daily_mission') allLobbyUids.add(k);
      }
      for (final k in _jackpotService.cachedFamilyMembers.keys) {
        if (k != 'system_daily_mission') allLobbyUids.add(k);
      }
      if (allLobbyUids.isEmpty && _jackpotService.currentUserId.isNotEmpty) {
        allLobbyUids.add(_jackpotService.currentUserId);
      }

      for (final uid in allLobbyUids) {
        final name = jackpot.memberNames[uid] ?? _getMemberName(uid) ?? 'Thành viên';
        final isAccepted = acceptedIds.contains(uid);
        final isInitiator = uid == jackpot.lobbyInitiatorId;
        items.add({
          'uid': uid,
          'name': name,
          'isAccepted': isAccepted,
          'isInitiator': isInitiator,
        });
      }

      items.sort((a, b) {
        if (a['isInitiator'] == true) return -1;
        if (b['isInitiator'] == true) return 1;
        if (a['isAccepted'] == true && b['isAccepted'] != true) return -1;
        if (a['isAccepted'] != true && b['isAccepted'] == true) return 1;
        return 0;
      });
    } else {
      final allUids = jackpot.memberNames.keys
          .where((k) => k != 'system_daily_mission')
          .toSet();
      for (final m in _currentFamilyMembers) {
        allUids.add(m.user.id);
      }
      for (final k in _jackpotService.cachedFamilyMembers.keys) {
        if (k != 'system_daily_mission') allUids.add(k);
      }
      if (allUids.isEmpty && _jackpotService.currentUserId.isNotEmpty) {
        allUids.add(_jackpotService.currentUserId);
      }
      for (final uid in allUids) {
        final name = jackpot.memberNames[uid] ?? _getMemberName(uid) ?? 'Thành viên';
        items.add({
          'uid': uid,
          'name': name,
          'isAccepted': false,
          'isReady': true,
        });
      }
    }

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DanhColors.brand200),
        ),
        child: const Center(
          child: Text(
            'Chưa có thành viên nào trong danh sách gia đình.',
            style: TextStyle(fontSize: 12, color: DanhColors.textMuted),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLobby ? const Color(0xFFFFB74D) : DanhColors.brand200,
          width: isLobby ? 1.5 : 1.0,
        ),
        boxShadow: isLobby
            ? [
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : DanhColors.fhubCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Scrollbar(
          thumbVisibility: items.length > 5,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              thickness: 0.7,
              color: Colors.grey.shade100,
              indent: 52,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final name = item['name'] as String;
              final uid = item['uid'] as String;
              final isAccepted = item['isAccepted'] as bool? ?? false;
              final isInitiator = item['isInitiator'] as bool? ?? false;
              final isMe = uid == _jackpotService.currentUserId;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: isAccepted
                          ? const Color(0xFFE8F5E9)
                          : (isLobby ? const Color(0xFFFFF3E0) : DanhColors.brand50),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isAccepted
                              ? const Color(0xFF2E7D32)
                              : (isLobby ? const Color(0xFFE65100) : DanhColors.brand800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: DanhColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: DanhColors.brand800,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Tôi',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              if (isInitiator) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF8F00),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Phát động',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_getMemberRoleLabel(uid) != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              _getMemberRoleLabel(uid)!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: DanhColors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isLobby) ...[
                      if (isAccepted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF81C784)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF2E7D32)),
                              SizedBox(width: 4),
                              Text(
                                'Đã tham gia',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFB74D)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hourglass_empty_rounded, size: 13, color: Color(0xFFE65100)),
                              SizedBox(width: 4),
                              Text(
                                'Đang chờ...',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFE65100),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Sẵn sàng',
                          style: TextStyle(
                            fontSize: 11,
                            color: DanhColors.brand800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Nút chính: Chuyển đổi trạng thái linh hoạt theo thời gian thực (5 phút đếm ngược)
  Widget _buildMainActionButton(FamilyJackpotModel jackpot) {
    final hasPool = jackpot.totalPoolAmount > 0;
    final isLobby = jackpot.isLobbyActive;
    final myUid = _jackpotService.currentUserId;
    final hasUserAccepted = jackpot.lobbyAcceptedMemberIds.contains(myUid);
    final isParent = _isCurrentUserParent;

    if (!isLobby) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: !hasPool
                ? Colors.grey.shade400
                : (isParent ? const Color(0xFFE65100) : Colors.grey.shade400),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: (hasPool && isParent) ? 4 : 0,
          ),
          icon: Icon(
            !hasPool
                ? Icons.lock_clock_rounded
                : (isParent ? Icons.timer_outlined : Icons.lock_outline_rounded),
            size: 22,
          ),
          label: Text(
            !hasPool
                ? AppLanguage.text('Hũ Đang Trống (0 ⭐) - Tích Sao Để Lắc', 'Pot Empty (0 ⭐) - Add Stars to Shake')
                : (isParent
                    ? AppLanguage.text('🎲 PHÁT ĐỘNG NỔ HŨ (5 PHÚT CHỜ)', '🎲 START POT SHAKE (5-MIN LOBBY)')
                    : AppLanguage.text('⏳ CHỜ BỐ MẸ PHÁT ĐỘNG NỔ HŨ', '⏳ WAITING FOR PARENTS TO START')),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          onPressed: () {
            if (!hasPool) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLanguage.text(
                      'Quỹ Hũ hiện đang là 0 ⭐! Cả nhà cùng hoàn thành Điểm danh mỗi ngày (+10 ⭐) hoặc Đổi phúc lợi trong Shop (+10% sao tích lũy) để làm đầy Hũ trước khi Nổ Hũ nhé!',
                      'Family Pot currently has 0 ⭐! Complete daily check-in (+10 ⭐) or redeem shop items (+10% stars) to fill the pot before shaking!',
                    ),
                  ),
                  backgroundColor: const Color(0xFFE65100),
                  duration: const Duration(seconds: 4),
                ),
              );
              return;
            }
            if (!isParent) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Chỉ Bố hoặc Mẹ mới có quyền phát động phiên Nổ Hũ cho cả gia đình!',
                  ),
                  backgroundColor: DanhColors.warning,
                ),
              );
              return;
            }
            _showLobbyParticipantPickerModal();
          },
        ),
      );
    }

    final remSecs = jackpot.remainingLobbySeconds;
    final mm = (remSecs ~/ 60).toString().padLeft(2, '0');
    final ss = (remSecs % 60).toString().padLeft(2, '0');
    final countdownStr = '$mm:$ss';
    final acceptedCount = jackpot.lobbyAcceptedMemberIds.length;
    final targetCount = max(jackpot.lobbyTargetMemberIds.length, acceptedCount);

    if (!hasUserAccepted) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 22),
          label: Text(
            AppLanguage.text(
              '✅ XÁC NHẬN THAM GIA LẮC HŨ ($countdownStr)',
              '✅ JOIN POT SHAKE NOW ($countdownStr)',
            ),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          onPressed: () async {
            try {
              await _jackpotService.acceptJackpotLobby(
                userId: myUid,
                userName: _jackpotService.currentUserName,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bạn đã xác nhận tham gia Nổ Hũ thành công!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                );
              }
            }
          },
        ),
      );
    }

    if (isParent) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              icon: const Icon(Icons.rocket_launch_rounded, size: 22),
              label: Text(
                AppLanguage.text(
                  '🚀 BẮT ĐẦU LẮC NGAY ($acceptedCount/$targetCount) - ($countdownStr)',
                  '🚀 START SHAKE NOW ($acceptedCount/$targetCount) - ($countdownStr)',
                ),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                _hasShownYTroiDialog = false;
                await _jackpotService.startShakeBattleEarly(initiatorId: myUid);
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLanguage.text(
              'Bố Mẹ có thể bấm bắt đầu ngay với $acceptedCount thành viên đã có mặt hoặc chờ đủ cả nhà.',
              'Parents can start now with $acceptedCount present members or wait for everyone.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: DanhColors.textSecondary),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber.shade100,
          foregroundColor: const Color(0xFFE65100),
          disabledBackgroundColor: Colors.amber.shade100,
          disabledForegroundColor: const Color(0xFFE65100),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFFFB74D), width: 1.5),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.hourglass_top_rounded, size: 22),
        label: Text(
          AppLanguage.text(
            '⏳ ĐÃ THAM GIA - CHỜ CẢ NHÀ ($acceptedCount/$targetCount) - ($countdownStr)',
            '⏳ JOINED - WAITING FOR FAMILY ($acceptedCount/$targetCount) - ($countdownStr)',
          ),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bạn đã có mặt trong phòng chờ! Trận chiến lắc 30s sẽ bắt đầu khi cả nhà sẵn sàng.'),
            ),
          );
        },
      ),
    );
  }

  /// Modal chọn danh sách thành viên tham gia nổ hũ dành cho Bố Mẹ
  void _showLobbyParticipantPickerModal() async {
    final currentJackpot = _jackpotService.jackpot;
    final allMembers = <String, String>{};

    for (final m in _currentFamilyMembers) {
      if (m.user.id.isNotEmpty && m.user.name.isNotEmpty) {
        allMembers[m.user.id] = m.user.name;
      }
    }
    for (final entry in _jackpotService.cachedFamilyMembers.entries) {
      if (entry.key != 'system_daily_mission' && entry.value.isNotEmpty) {
        allMembers.putIfAbsent(entry.key, () => entry.value);
      }
    }
    for (final entry in currentJackpot.memberNames.entries) {
      if (entry.key != 'system_daily_mission' && entry.value.isNotEmpty) {
        allMembers.putIfAbsent(entry.key, () => entry.value);
      }
    }
    if (allMembers.length <= 1) {
      try {
        final mems = await FamilyDataService().getFamilyMembers(
          familyId: PaymentService().currentFamilyId.isNotEmpty
              ? PaymentService().currentFamilyId
              : null,
        );
        for (final m in mems) {
          if (m.user.id.isNotEmpty && m.user.name.isNotEmpty) {
            allMembers[m.user.id] = m.user.name;
          }
        }
      } catch (_) {}
    }
    if (_jackpotService.currentUserId.isNotEmpty) {
      allMembers.putIfAbsent(_jackpotService.currentUserId, () => _jackpotService.currentUserName);
    }

    final selectedIds = Set<String>.from(allMembers.keys);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.group_add_rounded, color: Color(0xFFE65100), size: 24),
                        const SizedBox(width: 8),
                        Text(
                          AppLanguage.text('Chọn Thành Viên Tham Gia Nổ Hũ', 'Select Participants for Pot Shake'),
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: DanhColors.brand900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppLanguage.text(
                        'Phiếu chờ có hiệu lực trong 5 phút. Cả nhà vào xác nhận để cùng lắc điện thoại!',
                        'Ticket is valid for 5 minutes. Family members will receive an invite to join!',
                      ),
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.3),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Đã chọn: ${selectedIds.length}/${allMembers.length} thành viên',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              if (selectedIds.length == allMembers.length) {
                                selectedIds.clear();
                                if (_jackpotService.currentUserId.isNotEmpty) {
                                  selectedIds.add(_jackpotService.currentUserId);
                                }
                              } else {
                                selectedIds.addAll(allMembers.keys);
                              }
                            });
                          },
                          child: Text(
                            selectedIds.length == allMembers.length ? 'Bỏ chọn tất cả' : 'Chọn tất cả',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView(
                        shrinkWrap: true,
                        children: allMembers.entries.map((entry) {
                          final uid = entry.key;
                          final name = entry.value;
                          final isSelected = selectedIds.contains(uid);
                          final isMe = uid == _jackpotService.currentUserId;

                          return CheckboxListTile(
                            dense: true,
                            value: isSelected,
                            activeColor: const Color(0xFFE65100),
                            title: Row(
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                if (isMe) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: DanhColors.brand800,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Bố / Mẹ',
                                      style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            onChanged: (val) {
                              setModalState(() {
                                if (val == true) {
                                  selectedIds.add(uid);
                                } else {
                                  if (selectedIds.length > 1) {
                                    selectedIds.remove(uid);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Cần ít nhất 1 thành viên tham gia!'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.send_rounded),
                        label: Text(
                          AppLanguage.text('PHÁT ĐỘNG PHIẾU CHỜ (5 PHÚT)', 'START 5-MIN LOBBY TICKET'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(ctx);
                          try {
                            await _jackpotService.initiateJackpotLobby(
                              initiatorId: _jackpotService.currentUserId,
                              initiatorName: _jackpotService.currentUserName,
                              targetMemberIds: selectedIds.toList(),
                            );
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Đã phát động phiếu chờ 5 phút! Thông báo đã gửi tới cả gia đình.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Lỗi: $e'),
                                backgroundColor: Colors.red,
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

  /// Trạng thái 2: Trận chiến Lắc Điện Thoại 30 giây (Shake Battle)
  /// Hỗ trợ cả 3 phương thức:
  /// 1. Cảm biến gia tốc thật khi cầm điện thoại lắc (Android/iOS)
  /// 2. Lắc chuột qua lại trên biểu tượng hoặc nhấn phím Space / Enter (Laptop/Web)
  /// 3. Bấm nút "Lắc Ngay (+1 Lượt)" trên màn hình
  Widget _buildShakingSection(FamilyJackpotModel jackpot) {
    final remaining = jackpot.remainingSeconds;
    final isUrgent = remaining <= 5 && remaining > 0;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          _onManualShake();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isUrgent ? const Color(0xFFD32F2F) : const Color(0xFFFF9800),
                width: isUrgent ? 2.5 : 2,
              ),
              boxShadow: isUrgent
                  ? const [
                      BoxShadow(
                        color: Color(0x44D32F2F),
                        blurRadius: 18,
                        spreadRadius: 2,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : DanhColors.fhubCardShadow,
            ),
            child: Column(
              children: [
                if (isUrgent) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFEF5350), width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33D32F2F),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '$remaining GIÂY CUỐI CÙNG - TĂNG TỐC LẮC!',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFD32F2F),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      color: isUrgent ? const Color(0xFFD32F2F) : const Color(0xFFE65100),
                      size: isUrgent ? 30 : 26,
                    ),
                    const SizedBox(width: 8),
                    TweenAnimationBuilder<double>(
                      key: ValueKey(remaining),
                      tween: Tween<double>(begin: 1.25, end: 1.0),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutBack,
                      builder: (ctx, scale, child) {
                        return Transform.scale(
                          scale: isUrgent ? scale : 1.0,
                          child: child,
                        );
                      },
                      child: Text(
                        '$remaining Giây',
                        style: TextStyle(
                          fontSize: isUrgent ? 36 : 32,
                          fontWeight: FontWeight.w900,
                          color: isUrgent ? const Color(0xFFD32F2F) : const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: remaining / 30.0,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isUrgent ? const Color(0xFFD32F2F) : const Color(0xFFE65100),
                  ),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 16),
                Text(
                  isUrgent
                      ? 'HẾT GIỜ TỚI NƠI RỒI! LẮC NHIỆT TÌNH LÊN CẢ NHÀ ƠI!'
                      : 'CẦM ĐIỆN THOẠI LẮC THẬT MẠNH!\n(Trên Laptop: Lắc chuột vào vòng tròn, nhấn phím Space hoặc bấm nút bên dưới)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: isUrgent ? const Color(0xFFD32F2F) : DanhColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),

                // Hiệu ứng lắc điện thoại (Hỗ trợ bấm hoặc lắc chuột qua lại trên Laptop)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onHover: (event) {
                    final x = event.localPosition.dx;
                    if (_lastMouseX != null && (x - _lastMouseX!).abs() > 32) {
                      final now = DateTime.now();
                      if (_lastMouseShakeTime == null ||
                          now.difference(_lastMouseShakeTime!).inMilliseconds > 180) {
                        _lastMouseShakeTime = now;
                        _lastMouseX = x;
                        _onManualShake();
                      }
                    } else {
                      _lastMouseX ??= x;
                    }
                  },
                  child: GestureDetector(
                    onTap: _onManualShake,
                    child: RotationTransition(
                      turns: _shakeAnimController,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: isUrgent ? const Color(0xFFFFEBEE) : const Color(0xFFFFF3E0),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isUrgent ? const Color(0xFFEF5350) : const Color(0xFFFFB74D),
                            width: isUrgent ? 3 : 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isUrgent ? const Color(0x55D32F2F) : const Color(0x22E65100),
                              blurRadius: isUrgent ? 18 : 12,
                              spreadRadius: isUrgent ? 3 : 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.vibration_rounded,
                            size: 52,
                            color: isUrgent ? const Color(0xFFD32F2F) : const Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Số lần bạn đã lắc: ${_jackpotService.myShakeCount}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: DanhColors.brand800,
                  ),
                ),
                const SizedBox(height: 16),

                // Nút Lắc Ngay (Hỗ trợ máy không có cảm biến hoặc bấm trên màn hình)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isUrgent ? const Color(0xFFD32F2F) : const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.touch_app_rounded),
                    label: Text(
                      isUrgent ? 'LẮC NGAY BÂY GIỜ! ($remaining GIÂY CUỐI)' : 'Lắc Ngay (+1 Lượt / Phím Space)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _onManualShake,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Trạng thái 2.5: Vừa hết 30s lắc -> LẬP TỨC LỘ DIỆN QUÁN QUÂN LẮC TAY!
  /// và đếm ngược 10 giây thần may mắn phân xử trao thưởng!
  Widget _buildSuspenseSection(FamilyJackpotModel jackpot) {
    final remainingSuspense = jackpot.remainingSuspenseSeconds;
    final topShakerName = jackpot.memberNames[jackpot.topShakerId] ?? 'Thành viên';
    final topShakerCount = jackpot.shakeCounts[jackpot.topShakerId] ?? 0;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3), Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFFB300), width: 2),
            boxShadow: DanhColors.premiumGlowShadow,
          ),
          child: Column(
            children: [
              // Huy hiệu quán quân lắc tay
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DanhSvgs.crown(size: 18),
                    const SizedBox(width: 6),
                    const Text(
                      '🏆 QUÁN QUÂN LẮC TAY ĐÃ LỘ DIỆN!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                topShakerName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: DanhColors.brand900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Đã lắc thần tốc $topShakerCount lần (nhiều nhất gia đình!) 🔥',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD84315),
                ),
              ),
              const Divider(height: 32),

              // Đếm ngược 10s hồi hộp
              const Text(
                '⏳ THẦN MAY MẮN ĐANG PHÂN XỬ GIẢI THƯỞNG...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: DanhColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$remainingSuspense Giây',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFC62828),
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: remainingSuspense / 10.0,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC62828)),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 14),
              const Text(
                'Liệu quán quân lắc tay có ôm trọn Giải Nhất 3/4 quỹ hũ\nhay sẽ phải đón nhận tấm poster "Ý TRỜI"? Cùng nín thở chờ xem! 🎁',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: DanhColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Trạng thái 3: Công bố kết quả trao thưởng & Popup Ý Trời
  Widget _buildFinishedSection(FamilyJackpotModel jackpot) {
    final prizes = jackpot.prizeResults;
    final topShakerId = jackpot.topShakerId;
    final firstWinnerId = jackpot.firstPrizeWinnerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DanhColors.brand200),
            boxShadow: DanhColors.fhubCardShadow,
          ),
          child: Column(
            children: [
              DanhSvgs.checkSuccess(size: 54),
              const SizedBox(height: 12),
              const Text(
                'NỔ HŨ THÀNH CÔNG! ✨',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: DanhColors.brand900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppLanguage.text(
                  'Sao thưởng đã được cộng trực tiếp vào Ví Sao của từng thành viên!\nDùng sao để đổi những phần quà & phúc lợi từ Bố Mẹ.',
                  'Reward stars have been credited directly to each member\'s Star Wallet!\nUse stars to redeem rewards & wishes from Parents.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: DanhColors.textSecondary, height: 1.4),
              ),
              const Divider(height: 28),

              ...prizes.entries.where((entry) => entry.value > 0).map((entry) {
                final uid = entry.key;
                final amount = entry.value;
                final name = jackpot.memberNames[uid] ?? 'Thành viên';
                final shakes = jackpot.shakeCounts[uid] ?? 0;
                final isWinner = uid == firstWinnerId;
                final isTopShaker = uid == topShakerId;
                final isMe = uid == _jackpotService.currentUserId;

                final formattedAmount = amount.toString().replaceAllMapped(
                  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                  (Match m) => '${m[1]}.',
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isWinner ? const Color(0xFFFFF8E1) : DanhColors.brand50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isWinner ? DanhColors.gold : DanhColors.brand200,
                      width: isWinner ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              if (isWinner)
                                DanhSvgs.crown(size: 24)
                              else
                                DanhSvgs.coin(size: 22),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: DanhColors.textPrimary,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: DanhColors.brand800,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Tôi',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$shakes lần lắc ${isTopShaker ? '🔥 (Lắc nhiều nhất)' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isTopShaker ? Colors.orange.shade800 : DanhColors.textMuted,
                                      fontWeight: isTopShaker ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            '+$formattedAmount ⭐',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: isWinner ? const Color(0xFFC67D00) : DanhColors.brand800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Trạng thái cộng sao vào ví thành viên
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF81C784)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.stars_rounded, size: 15, color: Color(0xFF2E7D32)),
                            const SizedBox(width: 5),
                            Text(
                              AppLanguage.text('Đã nhận thưởng vào Ví Sao', 'Credited to Star Wallet'),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Nút Xem lại Poster Ý Trời nếu Quán quân lắc tay trượt Giải Nhất
        if (jackpot.isTopShakerUnlucky) ...[
          Builder(
            builder: (ctx) {
              final myUid = _jackpotService.currentUserId;
              final isMeTop = myUid == jackpot.topShakerId;
              final topName = jackpot.memberNames[jackpot.topShakerId] ?? 'Quán quân';
              return Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB71C1C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.movie_filter_rounded),
                      label: Text(
                        isMeTop
                            ? '🎬 Xem Lại Poster Kỷ Niệm "Ý Trời"'
                            : '🎬 Xem Poster "Ý Trời" Của $topName',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _showYTroiDialog(jackpot),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              );
            },
          ),
        ],

        // Nút Nhận sao từ hũ (thay cho Rút tiền thưởng về ngân hàng)
        Builder(
          builder: (ctx) {
            final myPrize = jackpot.prizeResults[_jackpotService.currentUserId] ?? 0;
            final myBal = _jackpotService.myWalletBalance;
            final displayStars = myPrize > 0 ? myPrize : myBal;
            final starSuffix = displayStars > 0 ? ' (+$displayStars ⭐)' : '';

            return Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.stars_rounded, size: 22, color: Colors.amber),
                    label: Text(
                      AppLanguage.text(
                        'Nhận sao từ hũ$starSuffix',
                        'Claim stars from pot$starSuffix',
                      ),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      _hasShownYTroiDialog = false;
                      await _jackpotService.resetJackpot();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLanguage.text(
                                'Đã nhận thành công ${displayStars > 0 ? "$displayStars ⭐" : "sao thưởng"} vào Ví Sao của bạn! Đang mở Cửa Hàng Đổi Sao...',
                                'Successfully claimed ${displayStars > 0 ? "$displayStars ⭐" : "reward stars"} into your Star Wallet! Opening Star Shop...',
                              ),
                            ),
                            backgroundColor: const Color(0xFF2E7D32),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        // Điều hướng trực tiếp tới Cửa Hàng Đổi Sao & Sổ Cái Phúc Lợi Thực Tế
                        await DanhPaymentEntry.openWishlistAndLedger(context);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            );
          },
        ),

        // Nút Góp sao hũ mới (rút gọn từ "Góp Vui Hũ Mới & Chơi Tiếp")
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: DanhColors.brand800, width: 1.5),
              foregroundColor: DanhColors.brand800,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.stars_outlined, size: 20),
            onPressed: () {
              _hasShownYTroiDialog = false;
              _jackpotService.resetJackpot();
            },
            label: Text(
              AppLanguage.text('Góp sao hũ mới', 'Contribute stars to new pot'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }


  /// DIALOG NẠP TIỀN VÀO HŨ BẰNG VIETQR SEPAY + TỰ ĐỘNG BẮT GIAO DỊCH
  // ignore: unused_element
  void _openDepositQrDialog(int amount) {
    final depositOrderCode = 'FHUBPOT${Random().nextInt(899999) + 100000}';
    final qrUrl = PaymentConfig.buildVietQrUrl(orderCode: depositOrderCode, amount: amount);
    Timer? pollingTimer;
    bool isDeposited = false;
    bool isCheckingManual = false;
    BuildContext? zoomQrCtx;

    Future<void> completeDeposit(BuildContext dialogContext, {required bool simulated}) async {
      if (isDeposited) return;
      isDeposited = true;
      pollingTimer?.cancel();
      if (zoomQrCtx != null && zoomQrCtx!.mounted) {
        Navigator.of(zoomQrCtx!).pop();
        zoomQrCtx = null;
      }
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      await _jackpotService.contributeMoney(amount: amount);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              simulated
                  ? '✨ Mô phỏng nạp thành công $amount đ vào Hũ Niềm Vui!'
                  : '✨ Nạp thành công $amount đ vào Hũ Niềm Vui!',
            ),
            backgroundColor: DanhColors.brand800,
          ),
        );
      }
    }

    void openZoomedDepositQr(BuildContext parentDialogCtx) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (zCtx) {
          zoomQrCtx = zCtx;
          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Mã VietQR Nạp Quỹ Hũ',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: DanhColors.brand800),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(zCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 3.5,
                      child: Image.network(
                        qrUrl,
                        width: 280,
                        height: 280,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.qr_code_2_rounded, size: 180, color: DanhColors.brand800),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Số tiền: $amount đ  |  Nội dung: $depositOrderCode',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: DanhColors.brand800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Đang tự động lắng nghe SePay (tự đóng khi hoàn tất)...',
                      style: TextStyle(fontSize: 11.5, color: DanhColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ).whenComplete(() => zoomQrCtx = null);
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            pollingTimer ??= Timer.periodic(const Duration(milliseconds: 2000), (_) async {
              if (isDeposited) return;
              final result = await SepayService.instance.checkPayment(
                orderCode: depositOrderCode,
                expectedAmount: amount,
              );
              if (!isDeposited && result.isSuccess && ctx.mounted) {
                await completeDeposit(ctx, simulated: false);
              }
            });

            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              AppLanguage.text('Quét VietQR Nạp Quỹ Hũ', 'Scan VietQR to Deposit'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: DanhColors.brand900),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () => openZoomedDepositQr(ctx),
                        borderRadius: BorderRadius.circular(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(6),
                            child: Image.network(
                              qrUrl,
                              width: 220,
                              height: 220,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.qr_code_2_rounded, size: 150, color: DanhColors.brand800),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => openZoomedDepositQr(ctx),
                        child: const Text(
                          '🔍 Nhấp vào QR để phóng to',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: DanhColors.brand800),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: DanhColors.brand50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            _buildModalRow('Ngân hàng:', '${PaymentConfig.bankShortName} (${PaymentConfig.accountNo})'),
                            _buildModalRow('Số tiền nạp:', '$amount đ', isHighlight: true),
                            _buildModalRow('Nội dung CK:', depositOrderCode, canCopy: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: DanhColors.brand800),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              AppLanguage.text('Đang tự động kiểm tra SePay...', 'Checking SePay automatically...'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: DanhColors.textMuted),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: isCheckingManual
                                ? null
                                : () async {
                                    if (isDeposited) return;
                                    setDialogState(() => isCheckingManual = true);
                                    final res = await SepayService.instance.checkPayment(
                                      orderCode: depositOrderCode,
                                      expectedAmount: amount,
                                    );
                                    if (!isDeposited && res.isSuccess && ctx.mounted) {
                                      await completeDeposit(ctx, simulated: false);
                                    } else if (dialogCtx.mounted) {
                                      setDialogState(() => isCheckingManual = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Chưa thấy giao dịch $depositOrderCode trên SePay.'),
                                            backgroundColor: DanhColors.warning,
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  },
                            child: Text(
                              isCheckingManual ? AppLanguage.text('Đang kiểm...', 'Checking...') : AppLanguage.text('Kiểm tra ngay', 'Check now'),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE65100),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE65100)),
                            foregroundColor: const Color(0xFFE65100),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              AppLanguage.text('Mô Phỏng Nạp Thành Công (Thử Nghiệm)', 'Simulate Successful Deposit (Test)'),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          onPressed: () => completeDeposit(ctx, simulated: true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) => pollingTimer?.cancel());
  }

  Widget _buildModalRow(String title, String value, {bool isHighlight = false, bool canCopy = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: DanhColors.textSecondary)),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isHighlight ? const Color(0xFFE65100) : DanhColors.textPrimary,
                    ),
                  ),
                ),
                if (canCopy) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Đã sao chép "$value"'), duration: const Duration(seconds: 1)),
                      );
                    },
                    child: const Icon(Icons.copy_rounded, size: 14, color: DanhColors.brand800),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// MODAL VÍ THƯỞNG & CÀI ĐẶT STK NGÂN HÀNG ĐỂ RÚT TIỀN
  /// MODAL LỊCH SỬ BIẾN ĐỘNG VÍ GIA ĐÌNH (Family-scoped Ledger)
  void _openWalletHistoryModal() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: DanhColors.borderLight)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long_rounded, color: DanhColors.brand800, size: 22),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLanguage.text('Lịch Sử Biến Động Ví & Quỹ', 'Wallet & Pot Transaction History'),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: DanhColors.brand800),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  AppLanguage.text('Lưu trữ tự động trong 15 ngày gần nhất', 'Auto-stored for the last 15 days'),
                                  style: const TextStyle(fontSize: 11, color: DanhColors.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),

              // Danh sách giao dịch Realtime theo đúng familyId
              Expanded(
                child: StreamBuilder<List<WalletTransactionModel>>(
                  stream: _jackpotService.watchWalletTransactions(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: DanhColors.brand800));
                    }
                    final list = snapshot.data ?? [];
                    if (list.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined, size: 48, color: Colors.black26),
                            SizedBox(height: 12),
                            Text(
                              'Chưa có biến động số dư nào trong gia đình này.',
                              style: TextStyle(color: DanhColors.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: max(24.0, MediaQuery.of(ctx).viewPadding.bottom + 24.0),
                      ),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: DanhColors.borderLight),
                      itemBuilder: (context, index) {
                        final tx = list[index];
                        final isPositive = tx.isPositive;
                        final color = isPositive ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
                        final prefix = isPositive ? '+' : '-';
                        final timeStr = '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')} • ${tx.createdAt.day.toString().padLeft(2, '0')}/${tx.createdAt.month.toString().padLeft(2, '0')}';

                        IconData iconData;
                        Color iconBg;
                        if (tx.type == WalletTransactionType.contribute) {
                          iconData = Icons.arrow_downward_rounded;
                          iconBg = const Color(0xFFE8F5E9);
                        } else if (tx.type == WalletTransactionType.prize) {
                          iconData = Icons.emoji_events_rounded;
                          iconBg = const Color(0xFFFFF8E1);
                        } else {
                          iconData = Icons.arrow_upward_rounded;
                          iconBg = const Color(0xFFFFEBEE);
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: iconBg,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(iconData, color: color, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tx.title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: DanhColors.textPrimary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${tx.userName} • $timeStr',
                                      style: const TextStyle(fontSize: 12, color: DanhColors.textMuted),
                                    ),
                                    if (tx.description != null && tx.description!.isNotEmpty)
                                      Text(
                                        tx.description!,
                                        style: const TextStyle(fontSize: 11.5, color: DanhColors.textSecondary),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                '$prefix${tx.amount} ⭐',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openBankAndWithdrawModal() {
    final currentBank = _jackpotService.myBankInfo;
    String selectedBankCode = currentBank.bankCode.isNotEmpty ? currentBank.bankCode : 'MB';
    String selectedBankShortName = currentBank.bankShortName.isNotEmpty ? currentBank.bankShortName : 'MBBank';
    final accNumController = TextEditingController(text: currentBank.accountNumber);
    final holderController = TextEditingController(
      text: currentBank.accountHolder.isNotEmpty
          ? currentBank.accountHolder
          : _jackpotService.currentUserName.toUpperCase(),
    );
    final withdrawAmountController = TextEditingController(
      text: _jackpotService.myWalletBalance > 0 ? _jackpotService.myWalletBalance.toString() : '',
    );
    String? sheetError;
    String? sheetSuccess;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: _jackpotService,
          builder: (ctx, _) {
            return StatefulBuilder(
              builder: (bottomCtx, setSheetState) {
                final balance = _jackpotService.myWalletBalance;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(bottomCtx).viewInsets.bottom + MediaQuery.of(bottomCtx).padding.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            AppLanguage.text('Ví Thưởng & Rút Tiền Về Ngân Hàng', 'Reward Wallet & Bank Withdrawal'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: DanhColors.brand900),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Thẻ số dư ví
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFB74D)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Số Dư Ví Khả Dụng', style: TextStyle(fontSize: 12, color: Color(0xFF8A5300))),
                                Text('Tiền thưởng sau các lần nổ hũ', style: TextStyle(fontSize: 10, color: Color(0xFF8A5300))),
                              ],
                            ),
                          ),
                          Text(
                            '$balance đ',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFE65100)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (sheetError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: DanhColors.errorBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: DanhColors.error),
                        ),
                        child: Text(
                          sheetError!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: DanhColors.error),
                        ),
                      ),
                    ],

                    if (sheetSuccess != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: DanhColors.brand50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: DanhColors.brand500),
                        ),
                        child: Text(
                          sheetSuccess!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: DanhColors.brand800),
                        ),
                      ),
                    ],

                    const Text(
                      '1. Cài Đặt STK Ngân Hàng Cá Nhân',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: DanhColors.brand900),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: BankDirectory.supportedBanks.any((b) => b.code == selectedBankCode)
                          ? selectedBankCode
                          : 'MB',
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Ngân hàng nhận tiền',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: BankDirectory.supportedBanks.map((b) {
                        return DropdownMenuItem(
                          value: b.code,
                          child: Text(b.name, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() {
                            selectedBankCode = val;
                            final bItem = BankDirectory.findByCode(val);
                            if (bItem != null) {
                              selectedBankShortName = bItem.shortName;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: accNumController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Số tài khoản ngân hàng',
                        hintText: 'Nhập số tài khoản của bạn',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: holderController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Tên chủ tài khoản',
                        hintText: 'NGUYEN VAN A',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: DanhColors.brand800),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          if (accNumController.text.trim().isEmpty || holderController.text.trim().isEmpty) {
                            setSheetState(() {
                              sheetSuccess = null;
                              sheetError = 'Vui lòng nhập đầy đủ Số tài khoản và Tên chủ tài khoản!';
                            });
                            return;
                          }
                          final bankInfo = UserBankInfo(
                            bankCode: selectedBankCode,
                            bankShortName: selectedBankShortName,
                            accountNumber: accNumController.text.trim(),
                            accountHolder: holderController.text.trim().toUpperCase(),
                          );
                          await _jackpotService.saveMyBankInfo(bankInfo);
                          if (bottomCtx.mounted) {
                            setSheetState(() {
                              sheetError = null;
                              sheetSuccess = '✅ Đã lưu thông tin tài khoản ngân hàng (${bankInfo.bankShortName} - ${bankInfo.accountNumber})!';
                            });
                          }
                        },
                        child: Text(AppLanguage.text('Lưu Tài Khoản Ngân Hàng', 'Save Bank Account'), style: const TextStyle(color: DanhColors.brand800, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const Divider(height: 28),

                    const Text(
                      '2. Rút Tiền Về Tài Khoản',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: DanhColors.brand900),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: withdrawAmountController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Số tiền muốn rút (VNĐ)',
                              hintText: 'VD: 50000',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              withdrawAmountController.text = balance.toString();
                              sheetError = null;
                            });
                          },
                          child: Text(AppLanguage.text('Rút Hết', 'Withdraw All'), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.send_to_mobile_rounded),
                        label: const Text('Xác Nhận Rút Tiền Về STK', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final amount = int.tryParse(withdrawAmountController.text.trim()) ?? 0;
                          if (balance <= 0) {
                            setSheetState(() {
                              sheetSuccess = null;
                              sheetError = 'Số dư ví của bạn hiện đang là 0 đ. Hãy tham gia Nổ Hũ để nhận thưởng trước khi rút!';
                            });
                            return;
                          }
                          if (amount <= 0) {
                            setSheetState(() {
                              sheetSuccess = null;
                              sheetError = 'Vui lòng nhập số tiền muốn rút hợp lệ (> 0 đ)!';
                            });
                            return;
                          }
                          if (amount > balance) {
                            setSheetState(() {
                              sheetSuccess = null;
                              sheetError = 'Số tiền muốn rút ($amount đ) vượt quá số dư ví khả dụng ($balance đ)!';
                            });
                            return;
                          }
                          if (accNumController.text.trim().isEmpty) {
                            setSheetState(() {
                              sheetSuccess = null;
                              sheetError = 'Vui lòng nhập Số tài khoản ngân hàng cá nhân ở mục 1 để nhận tiền!';
                            });
                            return;
                          }

                          final holderName = holderController.text.trim().isNotEmpty
                              ? holderController.text.trim().toUpperCase()
                              : _jackpotService.currentUserName.toUpperCase();

                          final bankInfo = UserBankInfo(
                            bankCode: selectedBankCode,
                            bankShortName: selectedBankShortName,
                            accountNumber: accNumController.text.trim(),
                            accountHolder: holderName,
                          );

                          // Tự động lưu thông tin ngân hàng
                          await _jackpotService.saveMyBankInfo(bankInfo);

                          final success = await _jackpotService.withdrawToBank(amount);
                          if (success && mounted && ctx.mounted) {
                            Navigator.pop(ctx);
                            _showWithdrawSuccessDialog(amount, bankInfo);
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
      },
    ).whenComplete(() {
      accNumController.dispose();
      holderController.dispose();
      withdrawAmountController.dispose();
    });
  }

  void _showWithdrawSuccessDialog(int amount, UserBankInfo bankInfo) {
    final txId = 'FHUBWD${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final payoutQrUrl = bankInfo.buildReceiveQrUrl(amount: amount, description: txId);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DanhSvgs.checkSuccess(size: 56),
                const SizedBox(height: 12),
                const Text(
                  'Lệnh Rút Tiền Đã Xác Nhận!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: DanhColors.brand900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Hệ thống đã ghi nhận yêu cầu và xuất phiếu chi $amount đ về tài khoản của bạn:',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: DanhColors.textSecondary),
                ),
                const SizedBox(height: 14),

                // Phiếu chi tiết
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DanhColors.brand50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: DanhColors.brand200),
                  ),
                  child: Column(
                    children: [
                      _buildModalRow('Mã giao dịch:', txId, canCopy: true),
                      _buildModalRow('Ngân hàng nhận:', bankInfo.bankShortName),
                      _buildModalRow('Số tài khoản:', bankInfo.accountNumber, canCopy: true),
                      _buildModalRow('Chủ tài khoản:', bankInfo.accountHolder),
                      _buildModalRow('Số tiền rút:', '$amount đ', isHighlight: true),
                      _buildModalRow('Trạng thái:', 'Thành công (Đã trừ ví)'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // VietQR hoàn trả cá nhân
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(6),
                    child: Image.network(
                      payoutQrUrl,
                      width: 170,
                      height: 170,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFD54F)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Color(0xFFE65100), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mã QR Nhận Tiền: Người giữ quỹ gia đình (hoặc chính bạn) dùng App ngân hàng quét mã này để hoàn tiền thưởng về STK của bạn.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFFE65100), height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DanhColors.brand800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hoàn Tất & Đóng'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDailyCheckInCard(FamilyJackpotModel jackpot) {
    final uid = _jackpotService.currentUserId;
    final hasCheckedIn = _jackpotService.hasUserCheckedInToday(uid);
    final checkInCount = _jackpotService.getTodayCheckInCount();
    final isCompleted = _jackpotService.isDailyCheckInCompletedToday();
    final totalMembers = jackpot.memberNames.isNotEmpty
        ? jackpot.memberNames.length
        : 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCompleted ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted ? const Color(0xFF81C784) : const Color(0xFFFFB74D),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_rounded, color: Color(0xFFE65100), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLanguage.text(
                    'Nhiệm Vụ Hằng Ngày: Cả nhà điểm danh (+10 ⭐)',
                    'Daily Mission: Family Check-in (+10 ⭐)',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'ĐÃ NHẬN +10 ⭐',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isCompleted
                ? AppLanguage.text(
                    '✨ Toàn bộ thành viên gia đình đã hoàn thành điểm danh hôm nay! Hũ đã nhận +10 ⭐.',
                    '✨ All family members checked in today! +10 ⭐ added to the pot.',
                  )
                : AppLanguage.text(
                    'Đã điểm danh: $checkInCount/$totalMembers thành viên. Cả nhà cùng điểm danh để nhận +10 ⭐ vào hũ!',
                    'Checked in: $checkInCount/$totalMembers members. All check in to add +10 ⭐ to pot!',
                  ),
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          if (!isCompleted) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('btn_jackpot_daily_checkin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasCheckedIn ? Colors.grey.shade400 : const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(hasCheckedIn ? Icons.check_circle_rounded : Icons.touch_app_rounded, size: 18),
                label: Text(
                  hasCheckedIn
                      ? AppLanguage.text('Bạn đã điểm danh hôm nay (Chờ cả nhà)', 'You checked in today (Waiting for others)')
                      : AppLanguage.text('Điểm danh hôm nay (+10 ⭐ cả nhà)', 'Check in today (+10 ⭐ for family)'),
                ),
                onPressed: hasCheckedIn
                    ? null
                    : () async {
                        final awarded = await _jackpotService.checkInDaily(
                          userId: _jackpotService.currentUserId,
                          userName: _jackpotService.currentUserName,
                          totalFamilyMembers: totalMembers,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              awarded
                                  ? '✨ Cả nhà đã điểm danh đủ! Hũ Niềm Vui được cộng +10 ⭐!'
                                  : '✅ Bạn đã điểm danh hôm nay thành công!',
                            ),
                            backgroundColor: awarded ? const Color(0xFF2E7D32) : const Color(0xFF005F50),
                          ),
                        );
                      },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContributionsList(FamilyJackpotModel jackpot) {
    final list = jackpot.contributions.entries.toList();
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DanhColors.brand200),
        ),
        child: const Center(
          child: Text(
            'Chưa có ai góp sao. Hãy góp sao để làm Đại Gia Đình!',
            style: TextStyle(fontSize: 12, color: DanhColors.textMuted),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanhColors.brand200),
      ),
      child: Column(
        children: list.map((e) {
          final name = jackpot.memberNames[e.key] ?? 'Thành viên';
          final isTop = e.key == jackpot.topContributorId;
          return ListTile(
            dense: true,
            leading: isTop ? DanhSvgs.crown(size: 20) : DanhSvgs.coin(size: 18),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            trailing: Text(
              '${e.value} ⭐',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isTop ? const Color(0xFFD48800) : DanhColors.brand800,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// MODAL POSTER MEME Ý TRỜI:
  /// Xuất hiện khi người lắc nhiều nhất bị hụt giải nhất
  /// Thiết kế như một tấm Poster nghệ thuật kỷ niệm gia đình, có dấu [X] to rõ ở góc trên để tắt
  void _showYTroiDialog(FamilyJackpotModel jackpot) {
    final topShakerName = jackpot.memberNames[jackpot.topShakerId] ?? 'Bạn';
    final winnerName = jackpot.memberNames[jackpot.firstPrizeWinnerId] ?? 'người khác';
    final shakes = jackpot.shakeCounts[jackpot.topShakerId] ?? 0;
    final myUid = _jackpotService.currentUserId;
    final isMeTopShaker = myUid == jackpot.topShakerId;
    final isMeWinner = myUid == jackpot.firstPrizeWinnerId;

    String headerBannerTitle = 'VẠN SỰ DO TRỜI ĐỊNH! 😂';
    String posterBody = 'Cật lực lắc điện thoại $shakes lần (nhiều nhất cả nhà!)\nnhưng Giải Nhất 3/4 quỹ hũ đã thuộc về $winnerName! 😭💸\n\nThần may mắn nhắn gửi: "Mưu sự tại nhân, thành sự tại thiên" 🙏\nThôi thì nhận tiền khuyến khích và giữ tấm Poster này làm kỷ niệm nhé!';
    String closeButtonLabel = 'Thuận Theo Ý Trời 😂';

    if (isMeWinner) {
      headerBannerTitle = '👑 BẠN ĐÃ LẬT KÈO NGOẠN MỤC!';
      posterBody = 'Dù $topShakerName cật lực lắc $shakes lần (nhiều nhất cả nhà),\nnhưng Thần May Mắn hôm nay đã mỉm cười và trao Giải Nhất cho bạn! 🏆✨\n\nĐúng là "Vạn sự do trời định" 😂!';
      closeButtonLabel = 'Vui Vẻ Nhận Giải 👑';
    } else if (!isMeTopShaker) {
      posterBody = '$topShakerName cật lực lắc điện thoại $shakes lần (nhiều nhất cả nhà)\nnhưng Giải Nhất đã thuộc về $winnerName! 😭💸\n\nĐúng là mưu sự tại nhân, thành sự tại thiên 🙏!';
      closeButtonLabel = 'Xem Tiếp Kết Quả 😂';
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Khung Poster điện ảnh gia đình
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E24), // Tông đen điện ảnh
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFFD54F), width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 26,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Thanh banner đầu Poster
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFB71C1C), Color(0xFFE53935), Color(0xFFB71C1C)],
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(21)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            '🎬 POSTER KỶ NIỆM GIA ĐÌNH',
                            style: TextStyle(
                              color: Color(0xFFFFD54F),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            headerBannerTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Ảnh Poster Khổng Minh Ý Trời
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/images/y_troi.png',
                          width: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Container(
                            height: 200,
                            color: Colors.black26,
                            child: const Center(
                              child: Icon(
                                Icons.sentiment_very_dissatisfied_rounded,
                                size: 80,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Nội dung Poster
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(
                              '👑 Quán quân thể lực: $topShakerName ($shakes lần lắc)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFFD54F),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            posterBody,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Colors.white70,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Nút đóng poster
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE53935),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(closeButtonLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // NÚT DẤU [X] Ở GÓC TRÊN ĐỂ TẮT POSTER
            Positioned(
              top: -10,
              right: -10,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(ctx),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFB71C1C), width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// MODAL IN-APP NOTIFICATION HUB (Lưu trữ tự động 15 ngày)
  void _openNotificationsModal() {
    final familyId = PaymentService().currentFamilyId;
    final currentUserId = _jackpotService.currentUserId;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: DanhColors.borderLight)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active_rounded, color: DanhColors.brand800, size: 22),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLanguage.text('Thông Báo Gia Đình', 'Family Notifications'),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: DanhColors.brand800),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  AppLanguage.text('Lưu trữ tự động trong 15 ngày gần nhất', 'Auto-stored for the last 15 days'),
                                  style: const TextStyle(fontSize: 11, color: DanhColors.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await NotificationService.instance.markAllAsRead(
                              familyId,
                              currentUserId: currentUserId,
                            );
                          },
                          child: Text(AppLanguage.text('Đã đọc tất cả', 'Mark all as read'), style: const TextStyle(fontSize: 12, color: DanhColors.brand800)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Danh sách thông báo
              Expanded(
                child: StreamBuilder<List<NotificationModel>>(
                  stream: NotificationService.instance.watchNotifications(
                    familyId,
                    currentUserId: currentUserId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: DanhColors.brand800));
                    }
                    final notifs = snapshot.data ?? [];
                    if (notifs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none_rounded, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              AppLanguage.text('Chưa có thông báo nào mới', 'No new notifications'),
                              style: const TextStyle(fontSize: 14, color: DanhColors.textMuted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppLanguage.text('Các sự kiện nạp quỹ, lắc hũ và rút tiền sẽ hiển thị tại đây.', 'Pot deposits, shake events, and withdrawals will appear here.'),
                              style: TextStyle(fontSize: 11.5, color: DanhColors.textMuted),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: max(24.0, MediaQuery.of(ctx).viewPadding.bottom + 24.0),
                      ),
                      itemCount: notifs.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final n = notifs[index];
                        final dt = n.createdAt;
                        final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.day}/${dt.month}';

                        IconData iconData;
                        Color iconColor;
                        if (n.type == 'jackpot_deposit') {
                          iconData = Icons.add_circle_outline_rounded;
                          iconColor = const Color(0xFF2E7D32);
                        } else if (n.type == 'jackpot_shake') {
                          iconData = Icons.vibration_rounded;
                          iconColor = const Color(0xFFE65100);
                        } else if (n.type == 'jackpot_win') {
                          iconData = Icons.emoji_events_rounded;
                          iconColor = const Color(0xFFF57F17);
                        } else if (n.type == 'wallet_withdraw') {
                          iconData = Icons.account_balance_rounded;
                          iconColor = const Color(0xFF1565C0);
                        } else {
                          iconData = Icons.info_outline_rounded;
                          iconColor = DanhColors.brand800;
                        }

                        return InkWell(
                          onTap: () {
                            if (!n.isRead) {
                              NotificationService.instance.markAsRead(familyId, n.id);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: iconColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(iconData, color: iconColor, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        n.localizedTitle(AppLanguage.isEnglish.value),
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: n.isRead ? FontWeight.w600 : FontWeight.bold,
                                          color: DanhColors.brand900,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        n.localizedBody(AppLanguage.isEnglish.value),
                                        style: const TextStyle(fontSize: 12, color: DanhColors.textSecondary, height: 1.35),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        timeStr,
                                        style: const TextStyle(fontSize: 10.5, color: DanhColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!n.isRead)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4, left: 8),
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFD32F2F),
                                      shape: BoxShape.circle,
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
            ],
          ),
        );
      },
    );
  }

  void _showRulesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.82,
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: max(32.0, MediaQuery.of(context).viewPadding.bottom + 24.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      AppLanguage.text('Luật Chơi Hũ Niềm Vui Gia Đình 📜', 'Family Pot Rules & Guidelines 📜'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: DanhColors.brand900),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    '1. Quỹ Hũ Sao được tích lũy tự động từ: Nhiệm vụ điểm danh hằng ngày (+10 ⭐) và tích điểm 10% sao khi đổi quà phúc lợi.\n'
                    '2. Người đóng góp nhiều sao nhất cho gia đình trở thành "Trưởng Ban Lễ Hội" và có quyền phát lệnh Nổ Hũ.\n'
                    '3. Trận chiến Lắc 30s: Cả nhà cùng lắc điện thoại (hoặc bấm Lắc Ngay). Mỗi lần lắc = +1 vé may mắn!\n'
                    '4. Vừa hết 30s: Lộ diện ngay "Quán Quân Lắc Tay", sau đó 10s thần may mắn công bố kết quả trao thưởng.\n'
                    '5. Công thức chia thưởng tổng quỹ A: Giải Nhất nhận 3/4 của A, Giải Nhì nhận 3/5 phần còn lại, tiếp theo nhận 3/4 của 2 phần còn lại, chia trọn vẹn 100% quỹ cho cả nhà.\n'
                    '6. Đặc biệt: Khi hết hạn gói Premium, số sao đã tích lũy trong hũ vẫn được bảo toàn nguyên vẹn (chỉ lắc nổ hũ khi kích hoạt Premium)!\n'
                    '7. Ai lắc nhiều nhất nhà mà trượt Giải Nhất sẽ nhận thêm tấm Poster "Ý TRỜI"! 🤣',
                    style: TextStyle(fontSize: 13, height: 1.45, color: DanhColors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DanhColors.brand800,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(AppLanguage.text('Đã Hiểu', 'Understood'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cảnh báo Hũ đã bị hủy/mất do gói Premium bị hết hạn/hủy
  Widget _buildForfeitedPotWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanhColors.errorBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DanhColors.error.withValues(alpha: 0.6), width: 1.5),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: DanhColors.error, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HŨ SAO GIA ĐÌNH ĐƯỢC BẢO TOÀN!',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: DanhColors.brand900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Khi gói Premium hết hạn, số sao đã tích lũy trong Hũ vẫn được giữ nguyên vẹn. Bạn chỉ cần gia hạn gói Premium để tiếp tục cùng gia đình lắc nổ hũ!',
                  style: TextStyle(
                    fontSize: 12,
                    color: DanhColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Giao diện yêu cầu nâng cấp Gói Premium để mở khóa Hũ
  Widget _buildPremiumRequiredSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DanhColors.borderLight),
        boxShadow: DanhColors.fhubCardShadow,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DanhColors.gold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_rounded, size: 36, color: DanhColors.goldDark),
          ),
          const SizedBox(height: 14),
          const Text(
            'Yêu Cầu Gói Tổ Ấm Premium',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: DanhColors.brand900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hũ Niềm Vui Gia Đình là đặc quyền dành riêng cho gia đình sở hữu Gói Premium.\n\n⭐ Lưu ý: Khi hết hạn Premium, số sao đã tích trữ trong hũ vẫn được BẢO TOÀN NGUYÊN VẸN. Nhiệm vụ điểm danh vẫn đồng bộ nhưng chỉ tăng sao vào hũ khi kích hoạt lại gói Premium!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: DanhColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: DanhColors.brand800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: DanhSvgs.crown(size: 20),
              label: const Text(
                'Nâng Cấp Premium Ngay - 49.000 đ',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PremiumPlanScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


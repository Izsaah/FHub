import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_jackpot_model.dart';
import '../models/user_bank_info.dart';
import '../models/wallet_transaction_model.dart';
import '../services/family_jackpot_service.dart';
import '../services/payment_config.dart';
import '../services/payment_service.dart';
import '../services/sepay_service.dart';
import '../theme/danh_colors.dart';
import '../theme/danh_svgs.dart';
import 'premium_plan_screen.dart';

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
  bool _hasShownYTroiDialog = false;
  int _lastRenderedShakeCount = 0;
  double? _lastMouseX;
  DateTime? _lastMouseShakeTime;

  @override
  void initState() {
    super.initState();
    _jackpotService.initForFamily(PaymentService().currentFamilyId);
    _lastRenderedShakeCount = _jackpotService.myShakeCount;
    _shakeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      lowerBound: -0.12,
      upperBound: 0.12,
    );
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

        // Tự động bật Modal meme "Ý Trời" khi kết thúc mà người lắc nhiều nhất trượt giải nhất
        if (jackpot.isFinished && !_hasShownYTroiDialog) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && jackpot.isTopShakerUnlucky) {
              _hasShownYTroiDialog = true;
              _showYTroiDialog(jackpot);
            }
          });
        }

        return Scaffold(
          backgroundColor: DanhColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: DanhColors.brand50,
            elevation: 1,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: DanhColors.brand800),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Hũ Niềm Vui Gia Đình',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: DanhColors.brand800,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Lịch sử ví gia đình',
                icon: const Icon(Icons.receipt_long_rounded, color: DanhColors.brand800),
                onPressed: _openWalletHistoryModal,
              ),
              IconButton(
                tooltip: 'Ví Thưởng & Rút Tiền',
                icon: const Icon(Icons.account_balance_wallet_rounded, color: DanhColors.brand800),
                onPressed: _openBankAndWithdrawModal,
              ),
              IconButton(
                tooltip: 'Luật chơi & Giải thưởng',
                icon: const Icon(Icons.help_outline_rounded, color: DanhColors.brand800),
                onPressed: _showRulesModal,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
        );
      },
    );
  }

  /// Thẻ Hũ Vàng trung tâm với biểu tượng SVG và tổng quỹ A + Ví cá nhân
  Widget _buildPotHeaderCard(FamilyJackpotModel jackpot) {
    final formattedAmount = '${jackpot.totalPoolAmount} đ'.replaceAllMapped(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TỔNG QUỸ HŨ NIỀM VUI',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8A5300),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formattedAmount,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF663C00),
                    ),
                  ),
                ],
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
                Text(
                  'Người nạp nhiều nhất: ${jackpot.topContributorName}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: DanhColors.brand900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Thẻ hiển thị Ví cá nhân tích lũy & Nút Rút tiền về Ngân hàng
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DanhColors.gold.withValues(alpha: 0.6)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFE65100), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ví Thưởng Của Tôi',
                          style: TextStyle(fontSize: 11, color: DanhColors.textMuted),
                        ),
                        Text(
                          '${_jackpotService.myWalletBalance} đ',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 32,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF3E0),
                          foregroundColor: const Color(0xFFE65100),
                          side: const BorderSide(color: Color(0xFFFFB74D), width: 1.2),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.receipt_long_rounded, size: 14),
                        label: const Text(
                          'Lịch Sử',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        onPressed: _openWalletHistoryModal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.account_balance_wallet_rounded, size: 14),
                        label: const Text(
                          'Rút Tiền',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        onPressed: _openBankAndWithdrawModal,
                      ),
                    ),
                  ],
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
    final isTopContributor = (jackpot.topContributorId == null) ||
        (jackpot.topContributorId == _jackpotService.currentUserId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '1. Nạp Tiền Vào Quỹ Hũ (VietQR)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: DanhColors.brand900,
              ),
            ),
            Text(
              'MBBank 0000000001',
              style: TextStyle(fontSize: 11, color: Colors.blue.shade800, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildQuickDepositButton(20000, '+20.000 đ'),
            const SizedBox(width: 8),
            _buildQuickDepositButton(50000, '+50.000 đ'),
            const SizedBox(width: 8),
            _buildQuickDepositButton(100000, '+100.000 đ'),
          ],
        ),
        const SizedBox(height: 24),

        const Text(
          '2. Bảng Vinh Danh Thành Viên Đóng Góp',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: DanhColors.brand900,
          ),
        ),
        const SizedBox(height: 10),
        _buildContributionsList(jackpot),
        const SizedBox(height: 24),

        // Nút Bắt Đầu Nổ Hũ (30 Giây) - Chỉ người nạp nhiều nhất mới được phát lệnh
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: (isTopContributor && jackpot.totalPoolAmount > 0)
                  ? const Color(0xFFE65100)
                  : Colors.grey.shade400,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: (isTopContributor && jackpot.totalPoolAmount > 0) ? 4 : 0,
            ),
            icon: (isTopContributor && jackpot.totalPoolAmount > 0)
                ? const Icon(Icons.play_circle_fill_rounded, size: 22)
                : const Icon(Icons.lock_clock_rounded, size: 22),
            label: Text(
              jackpot.totalPoolAmount <= 0
                  ? 'Hãy Nạp Tiền Vào Hũ Trước Khi Lắc'
                  : (isTopContributor
                      ? 'BẮT ĐẦU NỔ HŨ (30 GIÂY LẮC)'
                      : 'Chờ ${jackpot.topContributorName} phát động Nổ Hũ'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              if (jackpot.totalPoolAmount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Quỹ Hũ hiện đang là 0 đ! Hãy nạp tiền vào hũ trước khi phát lệnh lắc.',
                    ),
                    backgroundColor: DanhColors.warning,
                  ),
                );
                return;
              }
              if (!isTopContributor) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Chỉ người đóng góp nhiều nhất (${jackpot.topContributorName}) mới có quyền phát lệnh Nổ Hũ!',
                    ),
                    backgroundColor: DanhColors.warning,
                  ),
                );
                return;
              }
              _hasShownYTroiDialog = false;
              _jackpotService.startShakeBattle();
            },
          ),
        ),
      ],
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
                      border: Border.all(color: const Color(0xFFEF5350), width: 1.2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.whatshot_rounded, color: Color(0xFFD32F2F), size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '🔥 $remaining GIÂY CUỐI - LẮC NHANH TAY!',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFD32F2F),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isUrgent ? Icons.whatshot_rounded : Icons.timer_outlined,
                      color: isUrgent ? const Color(0xFFD32F2F) : const Color(0xFFE65100),
                      size: isUrgent ? 32 : 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$remaining Giây',
                      style: TextStyle(
                        fontSize: isUrgent ? 36 : 32,
                        fontWeight: FontWeight.w900,
                        color: isUrgent ? const Color(0xFFD32F2F) : const Color(0xFFE65100),
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
                            isUrgent ? Icons.whatshot_rounded : Icons.vibration_rounded,
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
                    icon: Icon(isUrgent ? Icons.whatshot_rounded : Icons.touch_app_rounded),
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
                'NỔ HŨ THÀNH CÔNG! 🎉',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: DanhColors.brand900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tiền thưởng đã được cộng trực tiếp vào Ví App của từng thành viên!\nCó thể rút về tài khoản ngân hàng cá nhân bất cứ lúc nào.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: DanhColors.textSecondary, height: 1.4),
              ),
              const Divider(height: 28),

              ...prizes.entries.map((entry) {
                final uid = entry.key;
                final amount = entry.value;
                final name = jackpot.memberNames[uid] ?? 'Thành viên';
                final shakes = jackpot.shakeCounts[uid] ?? 0;
                final isWinner = uid == firstWinnerId;
                final isTopShaker = uid == topShakerId;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isWinner ? const Color(0xFFFFF8E1) : DanhColors.brand50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isWinner ? DanhColors.gold : DanhColors.brand200,
                      width: isWinner ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (isWinner)
                            DanhSvgs.crown(size: 22)
                          else
                            DanhSvgs.coin(size: 20),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: DanhColors.textPrimary,
                                ),
                              ),
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
                        '+$amount đ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isWinner ? const Color(0xFFC67D00) : DanhColors.brand800,
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
              label: const Text(
                '🎬 Xem Lại Poster Kỷ Niệm "Ý Trời"',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              onPressed: () => _showYTroiDialog(jackpot),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Nút Rút tiền về Ngân hàng
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.account_balance_rounded),
            label: Text(
              'Rút Tiền Thưởng Về Ngân Hàng (${_jackpotService.myWalletBalance} đ)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            onPressed: _openBankAndWithdrawModal,
          ),
        ),
        const SizedBox(height: 10),

        // Nút Tạo Hũ Mới
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: DanhColors.brand800),
              foregroundColor: DanhColors.brand800,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              _hasShownYTroiDialog = false;
              _jackpotService.resetJackpot();
            },
            child: const Text(
              'Góp Vui Hũ Mới & Chơi Tiếp',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickDepositButton(int amount, String label) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: const BorderSide(color: DanhColors.brand500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white,
        ),
        onPressed: () => _openDepositQrDialog(amount),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: DanhColors.brand800),
        ),
      ),
    );
  }

  /// DIALOG NẠP TIỀN VÀO HŨ BẰNG VIETQR SEPAY + TỰ ĐỘNG BẮT GIAO DỊCH
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
                  ? '🎉 Mô phỏng nạp thành công $amount đ vào Hũ Niềm Vui!'
                  : '🎉 Nạp thành công $amount đ vào Hũ Niềm Vui!',
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
                            'Quét VietQR Nạp Quỹ Hũ',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: DanhColors.brand900),
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
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: DanhColors.brand800),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Đang tự động kiểm tra SePay...',
                            style: TextStyle(fontSize: 11.5, color: DanhColors.textMuted),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                              isCheckingManual ? 'Đang kiểm...' : 'Kiểm tra ngay',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE65100),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE65100)),
                            foregroundColor: const Color(0xFFE65100),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                          label: const Text('Mô Phỏng Nạp Thành Công (Thử Nghiệm)'),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: DanhColors.textSecondary)),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isHighlight ? const Color(0xFFE65100) : DanhColors.textPrimary,
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
        ],
      ),
    );
  }

  /// MODAL VÍ THƯỞNG & CÀI ĐẶT STK NGÂN HÀNG ĐỂ RÚT TIỀN
  /// MODAL LỊCH SỬ BIẾN ĐỘNG VÍ GIA ĐÌNH (Family-scoped Ledger)
  void _openWalletHistoryModal() {
    showModalBottomSheet(
      context: context,
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
                    const Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, color: DanhColors.brand800, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Lịch Sử Biến Động Ví & Quỹ',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: DanhColors.brand800),
                        ),
                      ],
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                '$prefix${tx.amount} đ',
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
        return StatefulBuilder(
          builder: (bottomCtx, setSheetState) {
            final balance = _jackpotService.myWalletBalance;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(bottomCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Ví Thưởng & Rút Tiền Về Ngân Hàng',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: DanhColors.brand900),
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
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Số Dư Ví Khả Dụng', style: TextStyle(fontSize: 12, color: Color(0xFF8A5300))),
                              Text('Tiền thưởng sau các lần nổ hũ', style: TextStyle(fontSize: 10, color: Color(0xFF8A5300))),
                            ],
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
                      initialValue: selectedBankCode,
                      decoration: InputDecoration(
                        labelText: 'Ngân hàng nhận tiền',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'MB', child: Text('MBBank - Ngân hàng Quân Đội')),
                        DropdownMenuItem(value: 'VCB', child: Text('Vietcombank - Ngoại Thương')),
                        DropdownMenuItem(value: 'TCB', child: Text('Techcombank - Kỹ Thương')),
                        DropdownMenuItem(value: 'ACB', child: Text('ACB - Á Châu')),
                        DropdownMenuItem(value: 'ICB', child: Text('VietinBank - Công Thương')),
                        DropdownMenuItem(value: 'BIDV', child: Text('BIDV - Đầu tư & Phát triển')),
                        DropdownMenuItem(value: 'VPB', child: Text('VPBank - VN Thịnh Vượng')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() {
                            selectedBankCode = val;
                            if (val == 'MB') selectedBankShortName = 'MBBank';
                            if (val == 'VCB') selectedBankShortName = 'Vietcombank';
                            if (val == 'TCB') selectedBankShortName = 'Techcombank';
                            if (val == 'ACB') selectedBankShortName = 'ACB';
                            if (val == 'ICB') selectedBankShortName = 'VietinBank';
                            if (val == 'BIDV') selectedBankShortName = 'BIDV';
                            if (val == 'VPB') selectedBankShortName = 'VPBank';
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
                        child: const Text('Lưu Tài Khoản Ngân Hàng', style: TextStyle(color: DanhColors.brand800, fontWeight: FontWeight.bold)),
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
                              labelText: 'Số tiền muốn rút (VND)',
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
                          child: const Text('Rút Hết', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
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
            'Chưa có ai nạp quỹ. Hãy quét VietQR để nạp và làm Đại Gia Đình!',
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
              '${e.value} đ',
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
                      child: const Column(
                        children: [
                          Text(
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
                            'VẠN SỰ DO TRỜI ĐỊNH! 😂',
                            style: TextStyle(
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
                            'Cật lực lắc điện thoại $shakes lần (nhiều nhất cả nhà!)\nnhưng Giải Nhất 3/4 quỹ hũ đã thuộc về $winnerName! 😭💸\n\nThần may mắn nhắn gửi: "Mưu sự tại nhân, thành sự tại thiên" 🙏\nThôi thì nhận tiền khuyến khích và giữ tấm Poster này làm kỷ niệm nhé!',
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
                              child: const Text('Thuận Theo Ý Trời 😂', style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _showRulesModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Luật Chơi Hũ Niềm Vui Gia Đình 📜',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: DanhColors.brand900),
            ),
            const SizedBox(height: 14),
            const Text(
              '1. Thành viên cùng nạp tiền vào Quỹ Hũ bằng mã VietQR Napas (SePay) realtime.\n'
              '2. Người nạp nhiều nhất trở thành "Đại Gia Đình" và có quyền bấm Nổ Hũ.\n'
              '3. Trận chiến Lắc 30s: Cả nhà cùng lắc điện thoại (hoặc bấm Lắc Ngay). Mỗi lần lắc = +1 vé may mắn!\n'
              '4. Vừa hết 30s: Lộ diện ngay "Quán Quân Lắc Tay", sau đó 10s thần may mắn công bố kết quả trao thưởng.\n'
              '5. Công thức chia thưởng tổng quỹ A: Giải Nhất nhận 3/4 của A, Giải Nhì nhận 3/5 phần còn lại, tiếp theo nhận 3/4 của 2 phần còn lại, chia trọn vẹn 100% quỹ cho cả nhà.\n'
              '6. Đặc biệt: Nếu mất gói Premium khi hũ chưa lắc -> Toàn bộ tiền trong hũ bị tiêu hủy!\n'
              '7. Ai lắc nhiều nhất nhà mà trượt Giải Nhất sẽ nhận thêm tấm Poster "Ý TRỜI"! 🤣',
              style: TextStyle(fontSize: 13, height: 1.45, color: DanhColors.textPrimary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: DanhColors.brand800),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đã Hiểu', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
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
                  'HŨ ĐÃ BỊ TIÊU HỦY DO MẤT GÓI PREMIUM!',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: DanhColors.error,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Theo quy định: Hũ Niềm Vui Gia Đình chỉ duy trì khi gia đình sở hữu Gói Premium. Khi gói hết hạn hoặc bị hủy trước khi nổ hũ, toàn bộ số tiền quỹ trong hũ đã bị tiêu hủy!',
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
            'Hũ Niềm Vui Gia Đình là đặc quyền dành riêng cho gia đình sở hữu Gói Premium.\n\n⚠️ Lưu ý nghiêm ngặt: Trong quá trình tích lũy hũ, nếu gia đình hết hạn Premium trước khi bấm nổ hũ thì toàn bộ số tiền trong hũ sẽ bị mất!',
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


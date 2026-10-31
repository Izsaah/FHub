import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../Long/services/family_data_service.dart';
import '../services/family_jackpot_service.dart';
import '../services/payment_service.dart';
import '../theme/danh_colors.dart';
import '../theme/danh_svgs.dart';
import '../widgets/premium_badge_widget.dart';
import 'family_jackpot_screen.dart';
import 'premium_plan_screen.dart';

class ManageSubscriptionScreen extends StatefulWidget {
  final int? initialMemberCount;

  const ManageSubscriptionScreen({
    super.key,
    this.initialMemberCount,
  });

  @override
  State<ManageSubscriptionScreen> createState() => _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState extends State<ManageSubscriptionScreen> {
  final PaymentService _paymentService = PaymentService();
  int _memberCount = 1;
  String _familyName = 'Gia đình';

  @override
  void initState() {
    super.initState();
    _paymentService.addListener(_onServiceUpdate);
    _loadFamilyInfo();
    _loadMemberCount();
  }

  @override
  void dispose() {
    _paymentService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFamilyInfo() async {
    try {
      final fam = await FamilyDataService().getCurrentFamily();
      if (fam != null && fam.name.trim().isNotEmpty && mounted) {
        setState(() => _familyName = fam.name.trim());
      }
    } catch (_) {}
  }

  Future<void> _loadMemberCount() async {
    if (widget.initialMemberCount != null) {
      setState(() => _memberCount = widget.initialMemberCount!);
      return;
    }

    // Đọc số lượng thành viên thực tế từ Cloud Firestore
    final familyId = _paymentService.currentFamilyId;
    if (familyId.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('family_members')
            .where('familyId', isEqualTo: familyId)
            .get();
        if (mounted && snap.docs.isNotEmpty) {
          setState(() => _memberCount = snap.docs.length);
          return;
        }
      } catch (e) {
        debugPrint('ManageSubscriptionScreen: Error loading member count: $e');
      }
    }

    if (mounted) setState(() => _memberCount = 1);
  }

  void _resetToFreeForDemo() {
    _paymentService.resetToFreeForDemo();
    FamilyJackpotService.instance.onPremiumLost();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã đặt lại về Gói Cơ Bản (Free). Hũ Niềm Vui chưa lắc đã bị tiêu hủy!'),
        backgroundColor: DanhColors.warning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = _paymentService.currentSubscription;
    final isPremium = _paymentService.isPremium;
    final maxMembers = sub.maxMembers;
    final progress = (_memberCount / maxMembers).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: DanhColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: DanhColors.brand50,
        elevation: 1,
        shadowColor: Colors.black12.withValues(alpha: 0.05),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: DanhColors.brand800),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _familyName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: DanhColors.brand800,
                letterSpacing: -0.5,
              ),
            ),
            const Text(
              'Quản lý gói dịch vụ',
              style: TextStyle(
                fontSize: 12,
                color: DanhColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Đặt lại về Free (Demo mất gói -> mất hũ)',
            icon: const Icon(Icons.restart_alt_rounded, color: DanhColors.warning),
            onPressed: _resetToFreeForDemo,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thẻ gói hiện tại
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isPremium ? DanhColors.gold.withValues(alpha: 0.6) : DanhColors.borderLight,
                  width: isPremium ? 1.5 : 1.0,
                ),
                boxShadow: isPremium ? DanhColors.premiumGlowShadow : DanhColors.fhubCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      PremiumBadgeWidget(
                        isPremium: isPremium,
                        customText: isPremium ? 'PREMIUM ACTIVE' : 'FREE TIER',
                      ),
                      if (isPremium)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: DanhColors.successBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: DanhColors.brand200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DanhSvgs.checkSuccess(size: 14),
                              const SizedBox(width: 4),
                              const Text(
                                'Đang hoạt động',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: DanhColors.brand800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    sub.planName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: DanhColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isPremium
                        ? 'Hạn dùng: ${sub.formattedExpiry} • Áp dụng cho cả gia đình'
                        : 'Giới hạn tối đa 4 thành viên. Nâng cấp để mở rộng tới 10 người!',
                    style: const TextStyle(fontSize: 13, color: DanhColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Dung lượng thành viên
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: DanhColors.borderLight),
                boxShadow: DanhColors.fhubCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Dung lượng thành viên',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: DanhColors.textPrimary,
                        ),
                      ),
                      Text(
                        '$_memberCount / $maxMembers người',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: DanhColors.brand800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: DanhColors.borderLight,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isPremium ? DanhColors.brand700 : DanhColors.brand500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    maxMembers > _memberCount
                        ? 'Còn trống ${maxMembers - _memberCount} vị trí mời thêm vào gia đình.'
                        : 'Đã đạt giới hạn tối đa của gói hiện tại.',
                    style: const TextStyle(fontSize: 12.5, color: DanhColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Đặc quyền Hũ Niềm Vui Gia Đình (Shopee Shake)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FamilyJackpotScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isPremium
                        ? [const Color(0xFFFFF8E1), const Color(0xFFFFECB3)]
                        : [Colors.grey.shade100, Colors.grey.shade200],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isPremium ? const Color(0xFFFFB300) : Colors.grey.shade300,
                    width: 1.5,
                  ),
                  boxShadow: isPremium ? DanhColors.premiumGlowShadow : DanhColors.fhubCardShadow,
                ),
                child: Row(
                  children: [
                    DanhSvgs.goldenPot(size: 46),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Hũ Niềm Vui Gia Đình',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: isPremium ? const Color(0xFFE65100) : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPremium ? const Color(0xFFE65100) : Colors.grey.shade500,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isPremium ? 'MỞ KHÓA' : 'KHÓA',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isPremium
                                ? 'Nạp quỹ VietQR • Đại gia đình phát lệnh • Lắc 30s nổ hũ'
                                : 'Đặc quyền riêng cho gói Premium (Mất gói là mất hũ!)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isPremium ? const Color(0xFF663C00) : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFFE65100), size: 24),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Nút hành động
            if (!isPremium)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DanhColors.brand800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PremiumPlanScreen()),
                  );
                },
                icon: const Icon(Icons.workspace_premium_rounded, size: 20),
                label: const Text(
                  'Nâng Cấp Lên Family Hub Premium',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FamilyJackpotScreen()),
                  );
                },
                icon: DanhSvgs.goldenPot(size: 22),
                label: const Text(
                  'Vào Hũ Niềm Vui Gia Đình Ngay',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../Long/services/supabase_service.dart';
import '../services/payment_service.dart';
import '../theme/danh_colors.dart';
import '../widgets/premium_badge_widget.dart';
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
  final SupabaseService _supabaseService = SupabaseService();
  int _memberCount = 1;

  @override
  void initState() {
    super.initState();
    _paymentService.addListener(_onServiceUpdate);
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

  Future<void> _loadMemberCount() async {
    if (widget.initialMemberCount != null) {
      setState(() => _memberCount = widget.initialMemberCount!);
      return;
    }
    try {
      final members = await _supabaseService.getFamilyMembers();
      if (mounted) {
        setState(() => _memberCount = members.isNotEmpty ? members.length : 1);
      }
    } catch (_) {
      if (mounted) setState(() => _memberCount = 1);
    }
  }

  void _resetToFreeForDemo() {
    _paymentService.resetToFreeForDemo();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã đặt lại về Gói Cơ Bản (Free) để thử nghiệm nhiều lần!'),
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tổ Ấm Yêu Thương',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: DanhColors.brand800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
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
            tooltip: 'Đặt lại về Free (Demo)',
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
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, size: 12, color: DanhColors.brand700),
                              SizedBox(width: 4),
                              Text(
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
                icon: const Icon(Icons.flash_on, color: DanhColors.gold, size: 20),
                label: const Text(
                  'Nâng Cấp Lên Family Hub Premium',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: DanhColors.brand800,
                  side: const BorderSide(color: DanhColors.brand800, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tổ ấm của bạn đang sở hữu gói Premium cao cấp nhất (10 thành viên).'),
                      backgroundColor: DanhColors.brand800,
                    ),
                  );
                },
                icon: const Icon(Icons.workspace_premium, color: DanhColors.goldDark, size: 20),
                label: const Text(
                  'Gói Premium Đang Hoạt Động (10 người)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

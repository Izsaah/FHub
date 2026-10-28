import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../Long/services/family_data_service.dart';
import '../models/family.dart';
import '../models/family_member.dart';
import '../services/family_service.dart';
import 'create_family_screen.dart';
import 'join_family_screen.dart';

class FamilySetupScreen extends StatefulWidget {
  const FamilySetupScreen({super.key});

  @override
  State<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends State<FamilySetupScreen> {
  static const Color background = Color(0xFFF2FAF7);
  static const Color primary = Color(0xFF07866F);
  static const Color darkText = Color(0xFF18332E);
  static const Color mutedText = Color(0xFF71827D);
  static const Color border = Color(0xFFD8E7E2);

  final FamilyDataService _dataService = FamilyDataService();
  List<Family> _families = [];
  Map<String, FamilyMember> _memberships = {};
  String? _selectedFamilyId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFamilies();
  }

  Future<void> _loadFamilies() async {
    setState(() => _isLoading = true);
    try {
      final service = FamilyService();
      final fams = await service.getMyFamilies();
      final mems = await service.getMyMembershipsByFamily();
      final activeId = _dataService.selectedFamilyId ??
          (fams.isNotEmpty ? fams.first.id : null);
      if (mounted) {
        setState(() {
          _families = fams;
          _memberships = mems;
          _selectedFamilyId = activeId;
          _isLoading = false;
        });
      }
    } catch (_) {
      // Fallback sang FamilyDataService Firestore cache
      try {
        final fams = await _dataService.getMyFamilies();
        final converted = fams
            .map(
              (f) => Family(
                id: f.id,
                name: f.name,
                joinCode: f.joinCode,
                ownerId: f.ownerId,
              ),
            )
            .toList();
        if (mounted) {
          setState(() {
            _families = converted;
            _selectedFamilyId = _dataService.selectedFamilyId ??
                (converted.isNotEmpty ? converted.first.id : null);
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  String _roleLabel(FamilyMember? member, Family family) {
    final isOwner = member?.isOwner == true ||
        (family.ownerId.isNotEmpty &&
            family.ownerId == _dataService.currentUserId);
    final String rolePart;
    switch (member?.role) {
      case FamilyMember.roleGrandparent:
        rolePart = 'Ông / Bà';
        break;
      case FamilyMember.roleChild:
        rolePart = 'Con cái';
        break;
      case FamilyMember.roleParent:
        rolePart = 'Bố / Mẹ';
        break;
      default:
        rolePart = 'Thành viên';
    }
    return isOwner ? 'Owner • $rolePart' : rolePart;
  }

  Future<void> _selectActiveFamily(Family family) async {
    await _dataService.selectFamily(family.id);
    if (!mounted) return;
    setState(() => _selectedFamilyId = family.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã chọn gia đình hiển thị: "${family.name}"'),
        backgroundColor: primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyJoinCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép mã mời: $code'),
        backgroundColor: primary,
      ),
    );
  }

  Future<void> _openCreateFamily() async {
    final hadNoFamily = _families.isEmpty;
    final created = await Navigator.of(context).push<Family>(
      MaterialPageRoute(builder: (_) => const CreateFamilyScreen()),
    );
    if (!mounted) return;
    if (created != null) {
      _dataService.clearCache();
      await _dataService.selectFamily(created.id);
      if (hadNoFamily && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(created);
        return;
      }
      await _loadFamilies();
    }
  }

  Future<void> _openJoinFamily() async {
    final hadNoFamily = _families.isEmpty;
    final joined = await Navigator.of(context).push<Family>(
      MaterialPageRoute(builder: (_) => const JoinFamilyScreen()),
    );
    if (!mounted) return;
    if (joined != null) {
      _dataService.clearCache();
      await _dataService.selectFamily(joined.id);
      if (hadNoFamily && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(joined);
        return;
      }
      await _loadFamilies();
    }
  }

  Widget _buildExistingFamiliesSection() {
    if (_isLoading || _families.isEmpty) {
      return const SizedBox.shrink();
    }

    final isSingle = _families.length == 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F4EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.home_work_rounded,
                    color: primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isSingle
                        ? 'Gia đình hiện tại của bạn'
                        : 'Các gia đình đã tham gia (${_families.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: darkText,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F6EF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isSingle ? '1 nhà' : 'A → Z (${_families.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isSingle
                  ? 'Bạn đang tham gia 1 gia đình. Bạn có thể tạo thêm hoặc tham gia các gia đình khác (Nội, Ngoại...) bên dưới.'
                  : 'Chạm vào một gia đình để chọn làm gia đình hiển thị chính.',
              style: const TextStyle(
                fontSize: 12.5,
                color: mutedText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            ..._families.map((fam) {
              final isSelected = fam.id == _selectedFamilyId || isSingle;
              final member = _memberships[fam.id];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _selectActiveFamily(fam),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEAF7F3)
                          : const Color(0xFFF9FCFB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? primary : const Color(0xFFDCE9E5),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 19,
                          backgroundColor: isSelected
                              ? primary
                              : const Color(0xFFDCE9E5),
                          child: Text(
                            fam.name.isNotEmpty
                                ? fam.name[0].toUpperCase()
                                : 'G',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      fam.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: darkText,
                                      ),
                                    ),
                                  ),
                                  if (!isSingle && isSelected) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Đang chọn',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _roleLabel(member, fam),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: mutedText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (fam.joinCode.isNotEmpty)
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _copyJoinCode(fam.joinCode),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFD2E2DD),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    fam.joinCode,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.copy_rounded,
                                    size: 13,
                                    color: primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = _families.isNotEmpty;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopBar(
                        title: 'Thiết lập gia đình',
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 20),

                      // Hiển thị 1 hoặc nhiều gia đình hiện tại (nếu có)
                      _buildExistingFamiliesSection(),

                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.035),
                              blurRadius: 18,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F4EE),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                Icons.groups_rounded,
                                size: 38,
                                color: primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              hasExisting
                                  ? 'Thêm hoặc tham gia gia đình khác'
                                  : 'Kết nối với gia đình',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: darkText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tạo một gia đình mới hoặc tham gia\n'
                              'vào gia đình mà người thân đã tạo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.55,
                                color: mutedText,
                              ),
                            ),
                            const SizedBox(height: 22),
                            _SetupOptionCard(
                              icon: Icons.add_home_work_rounded,
                              iconBackground: const Color(0xFFE4F6EF),
                              iconColor: primary,
                              title: 'Tạo gia đình mới',
                              description:
                                  'Bạn sẽ là người quản trị và có thể mời các thành viên.',
                              onTap: _openCreateFamily,
                            ),
                            const SizedBox(height: 14),
                            _SetupOptionCard(
                              icon: Icons.group_add_rounded,
                              iconBackground: const Color(0xFFFFF0DF),
                              iconColor: const Color(0xFFE77D2B),
                              title: 'Tham gia gia đình',
                              description:
                                  'Nhập mã gia đình được chia sẻ bởi người thân.',
                              onTap: _openJoinFamily,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 15,
                            color: Color(0xFF7D918B),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Thông tin gia đình được bảo mật',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SetupOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _SetupOptionCard({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFAFCFB),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFDCE9E5)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor, size: 27),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF18332E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Color(0xFF788984),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF8EA09B),
                size: 25,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF18332E),
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFDCE9E5)),
          ),
          child: Icon(icon, color: const Color(0xFF27443E), size: 21),
        ),
      ),
    );
  }
}

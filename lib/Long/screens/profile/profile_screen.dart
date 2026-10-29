import 'package:flutter/material.dart';

import '../../services/family_data_service.dart';
import '../../models/user_model.dart';
import '../../models/family_model.dart';
import '../../widgets/custom_app_bar.dart';
import '../../../Khoa/screens/family_setup_screen.dart';
import '../../../Thinh/screens/auth_screen.dart';
import '../../../Thinh/services/auth_service.dart';
import '../../../Thinh/theme/app_language.dart';
import '../../utils/long_strings.dart';
import '../../../Danh/danh_payment_entry.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _familyDataService = FamilyDataService();
  late Future<Map<String, dynamic>> _profileDataFuture;

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
    _profileDataFuture = _fetchProfileData();
  }

  Future<Map<String, dynamic>> _fetchProfileData() async {
    final user = await _familyDataService.getCurrentUser();
    final families = await _familyDataService.getMyFamilies();
    final family = await _familyDataService.getCurrentFamily();
    if (family != null) {
      DanhPaymentEntry.onFamilyCreatedOrJoined(family.id);
    }
    return {
      'user': user,
      'families': families,
      'family': family,
    };
  }

  Future<void> _openFamilySetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FamilySetupScreen()),
    );
    if (mounted) {
      _familyDataService.clearCache();
      setState(_loadData);
    }
  }

  Future<void> _selectFamily(FamilyModel family) async {
    await _familyDataService.selectFamily(family.id);
    if (mounted) {
      setState(_loadData);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LongStrings.t(
              'Đã chuyển sang gia đình "${family.name}"',
              'Switched to family "${family.name}"',
            ),
          ),
          backgroundColor: const Color(0xFF005F50),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Hiển thị phần thông tin gia đình cho 0, 1 hoặc nhiều gia đình
  Widget _buildFamiliesProfileSection(
    List<FamilyModel> families,
    FamilyModel? currentFamily,
  ) {
    if (families.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            LongStrings.currentFamilyTitle,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF6E7A75),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF005F50),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _openFamilySetup,
            icon: const Icon(Icons.group_add_outlined, size: 16),
            label: Text(
              LongStrings.notJoinedJoinNow,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }

    if (families.length == 1) {
      final single = families.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LongStrings.currentFamilySingle,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6E7A75),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _openFamilySetup,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_circle_outline,
                        size: 14,
                        color: Color(0xFF005F50),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        LongStrings.addOrJoin,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF005F50),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF5F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFBDC9C4).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cottage_rounded,
                  size: 18,
                  color: Color(0xFF005F50),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    single.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF151D1B),
                    ),
                  ),
                ),
                if (single.joinCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${LongStrings.codePrefix}${single.joinCode}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF005F50),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    // Khi người dùng tham gia nhiều gia đình (N > 1)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                LongStrings.joinedFamiliesCount(families.length),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6E7A75),
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _openFamilySetup,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_home_work_outlined,
                      size: 14,
                      color: Color(0xFF005F50),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      LongStrings.manageOrAdd,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF005F50),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...families.map((fam) {
          final isSelected = fam.id == currentFamily?.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _selectFamily(fam),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFE4F6EF)
                      : const Color(0xFFF7FAF8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF005F50)
                        : const Color(0xFFDCE8E3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cottage_rounded,
                      size: 17,
                      color: isSelected
                          ? const Color(0xFF005F50)
                          : const Color(0xFF6E7A75),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fam.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? const Color(0xFF005F50)
                              : const Color(0xFF151D1B),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF005F50),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          LongStrings.activeTag,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (fam.joinCode.isNotEmpty)
                      Text(
                        fam.joinCode,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6E7A75),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLanguageSettingsCard() {
    final isEn = AppLanguage.isEnglish.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFBDC9C4).withValues(alpha: 0.6),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120D7A68),
            offset: Offset(0, 4),
            blurRadius: 10,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE4F6EF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.translate_rounded,
              color: Color(0xFF005F50),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LongStrings.t('Ngôn ngữ hiển thị', 'App Language'),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF151D1B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isEn ? 'English (Tiếng Anh)' : 'Tiếng Việt (Vietnamese)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6E7A75),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF5F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFBDC9C4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLanguageChip(
                  label: 'VN',
                  isSelected: !isEn,
                  onTap: () {
                    AppLanguage.isEnglish.value = false;
                    setState(() {});
                  },
                ),
                _buildLanguageChip(
                  label: 'EN',
                  isSelected: isEn,
                  onTap: () {
                    AppLanguage.isEnglish.value = true;
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF005F50) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : const Color(0xFF6E7A75),
          ),
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
          appBar: CustomAppBar(
            title: LongStrings.profileTitle,
            subtitle: LongStrings.profileSubtitle,
          ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data!;
          final UserModel user = data['user'];
          final List<FamilyModel> families =
              (data['families'] as List<FamilyModel>?) ?? [];
          final FamilyModel? family = data['family'];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
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
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue[100],
                              border: Border.all(
                                color: const Color(0xFF005F50)
                                    .withValues(alpha: 0.2),
                                width: 4,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: user.avatarUrl.isNotEmpty
                                ? ClipOval(
                                    child: Image.network(
                                      user.avatarUrl,
                                      width: 72,
                                      height: 72,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) => Text(
                                        user.name.isNotEmpty
                                            ? user.name
                                                .substring(0, 1)
                                                .toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontSize: 32,
                                          color: Colors.blue[900],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                : Text(
                                    user.name.isNotEmpty
                                        ? user.name
                                            .substring(0, 1)
                                            .toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 32,
                                      color: Colors.blue[900],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFDCBD),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.shield,
                                        size: 12,
                                        color: Color(0xFF2C1600),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        LongStrings.memberBadge,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF2C1600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  user.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF151D1B),
                                  ),
                                ),
                                Text(
                                  user.email,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF3E4946),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEDF5F2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(
                                            Icons.bloodtype,
                                            size: 14,
                                            color: Color(0xFF005F50),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'O+',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF005F50),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFBDC9C4), thickness: 0.5),
                      const SizedBox(height: 8),
                      _buildFamiliesProfileSection(families, family),
                    ],
                  ),
                ),

                // Banner nâng cấp / quản lý gói Premium
                DanhPaymentEntry.buildPremiumBanner(context),

                const SizedBox(height: 16),

                // Cài đặt ngôn ngữ hiển thị (Tiếng Việt & English)
                _buildLanguageSettingsCard(),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: const Color(0xFFBA1A1A),
                      side: const BorderSide(color: Color(0xFFBA1A1A)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.transparent,
                    ),
                    onPressed: () async {
                      final shouldLogout = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text(LongStrings.t('Đăng xuất?', 'Log out?')),
                          content: Text(
                            LongStrings.t(
                              'Bạn có chắc muốn đăng xuất khỏi thiết bị này không?',
                              'Are you sure you want to log out of this device?',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: Text(LongStrings.t('Hủy', 'Cancel')),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: Text(LongStrings.t('Đăng xuất', 'Log out')),
                            ),
                          ],
                        ),
                      );
                      if (shouldLogout != true || !context.mounted) return;

                      try {
                        _familyDataService.resetAll();
                        await AuthService().logout();
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => const AuthScreen(),
                            ),
                            (route) => false,
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error logging out: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: Text(
                      LongStrings.t(
                        'Đăng xuất khỏi thiết bị này',
                        'Log out from this device',
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/family_data_service.dart';
import '../../models/user_model.dart';
import '../../models/family_model.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/app_toast.dart';
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
  final ScrollController _familyScrollController = ScrollController();
  late Future<Map<String, dynamic>> _profileDataFuture;
  Map<String, dynamic>? _cachedProfileData;
  String? _currentFamilyName;

  @override
  void initState() {
    super.initState();
    _familyDataService.ensureRealtimeSync();
    _loadData();
    _familyDataService.selectedFamilyIdNotifier.addListener(
      _onSelectedFamilyChanged,
    );
    _familyDataService.membershipRevisionNotifier.addListener(
      _onSelectedFamilyChanged,
    );
  }

  @override
  void dispose() {
    _familyScrollController.dispose();
    _familyDataService.selectedFamilyIdNotifier.removeListener(
      _onSelectedFamilyChanged,
    );
    _familyDataService.membershipRevisionNotifier.removeListener(
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
    _profileDataFuture = _fetchProfileData().then((data) {
      _cachedProfileData = data;
      final family = data['family'] as FamilyModel?;
      if (mounted && _currentFamilyName != family?.name) {
        setState(() {
          _currentFamilyName = family?.name;
        });
      }
      return data;
    });
  }

  Future<Map<String, dynamic>> _fetchProfileData() async {
    final results = await Future.wait([
      _familyDataService.getCurrentUser(),
      _familyDataService.getMyFamilies(),
    ]);
    final user = results[0] as UserModel;
    final families = results[1] as List<FamilyModel>;
    final family = await _familyDataService.getCurrentFamily();
    if (family != null && families.isNotEmpty) {
      DanhPaymentEntry.onFamilyCreatedOrJoined(family.id);
    } else {
      DanhPaymentEntry.clearFamilyContext();
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
      AppToast.show(
        context,
        LongStrings.t(
          'Đã chuyển sang gia đình "${family.name}"',
          'Switched to family "${family.name}"',
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
        Builder(
          builder: (context) {
            Widget buildList({
              ScrollController? controller,
              required ScrollPhysics physics,
            }) {
              return ListView.separated(
                controller: controller,
                shrinkWrap: true,
                physics: physics,
                padding: EdgeInsets.zero,
                itemCount: families.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final fam = families[index];
                final isSelected = fam.id == currentFamily?.id;
                return InkWell(
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
                );
              },
            );
            }

            if (families.length > 3) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180.0),
                child: Scrollbar(
                  controller: _familyScrollController,
                  thumbVisibility: true,
                  child: buildList(
                    controller: _familyScrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                  ),
                ),
              );
            }

            return buildList(
              physics: const NeverScrollableScrollPhysics(),
            );
          },
        ),
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
                    if (AppLanguage.isEnglish.value) {
                      AppLanguage.isEnglish.value = false;
                      setState(() {});
                      AppToast.show(context, 'Đã chuyển sang Tiếng Việt');
                    }
                  },
                ),
                _buildLanguageChip(
                  label: 'EN',
                  isSelected: isEn,
                  onTap: () {
                    if (!AppLanguage.isEnglish.value) {
                      AppLanguage.isEnglish.value = true;
                      setState(() {});
                      AppToast.show(context, 'Switched to English');
                    }
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
            subtitle: _currentFamilyName,
          ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileDataFuture,
        builder: (context, snapshot) {
          final effectiveData = snapshot.data ?? _cachedProfileData;
          if (effectiveData == null &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (effectiveData == null) {
            return Center(
              child: Text(
                LongStrings.t(
                  'Đã có lỗi xảy ra: ${snapshot.error}',
                  'An error occurred: ${snapshot.error}',
                ),
              ),
            );
          }

          final data = effectiveData;
          final UserModel user = data['user'];
          final List<FamilyModel> families =
              (data['families'] as List<FamilyModel>?) ?? [];
          final FamilyModel? family = data['family'];

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
                          _buildUserAvatar(user),
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
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF151D1B),
                                  ),
                                ),
                                Text(
                                  user.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF3E4946),
                                  ),
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

                // Banner nâng cấp / quản lý gói Premium & Hũ Niềm Vui (chỉ dành cho người dùng đã tham gia gia đình)
                if (families.isNotEmpty && family != null) ...[
                  DanhPaymentEntry.buildPremiumBanner(context),
                  const SizedBox(height: 16),
                ] else
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
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF005F50),
                              ),
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
                        DanhPaymentEntry.clearFamilyContext();
                        if (context.mounted) {
                          // Điều hướng mượt mà ngay lập tức tránh để màn hình cũ lắng nghe Firestore rỗng gây giật lag
                          Navigator.of(context).pushAndRemoveUntil(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                  const AuthScreen(),
                              transitionsBuilder:
                                  (context, animation, secondaryAnimation, child) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                              transitionDuration: const Duration(milliseconds: 200),
                            ),
                            (route) => false,
                          );
                        }
                        await AuthService().logout();
                      } catch (e) {
                        debugPrint('Logout error: $e');
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

  Widget _buildUserAvatar(UserModel user) {
    return GestureDetector(
      onTap: () => _showAvatarDetailAndSelectionSheet(context, user),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE4F6EF),
              border: Border.all(
                color: const Color(0xFF005F50).withValues(alpha: 0.25),
                width: 3.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: _buildAvatarContent(user, size: 72, fontSize: 32),
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF005F50),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.edit_rounded,
                color: Colors.white,
                size: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarContent(UserModel user, {required double size, required double fontSize}) {
    if (user.avatarUrl.isNotEmpty && user.avatarUrl.startsWith('emoji:')) {
      final emoji = user.avatarUrl.replaceFirst('emoji:', '');
      return Text(
        emoji,
        style: TextStyle(fontSize: fontSize),
      );
    }

    if (user.avatarUrl.isNotEmpty &&
        (user.avatarUrl.startsWith('http://') || user.avatarUrl.startsWith('https://'))) {
      return ClipOval(
        child: Image.network(
          user.avatarUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Text(
            user.name.isNotEmpty ? user.name.substring(0, 1).toUpperCase() : '?',
            style: TextStyle(
              fontSize: fontSize,
              color: const Color(0xFF005F50),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    const emojiMap = {
      'dad': '👨',
      'mom': '👩',
      'grandpa': '👴',
      'grandma': '👵',
      'boy': '👦',
      'girl': '👧',
      'cat': '🐱',
      'dog': '🐶',
      'star': '⭐',
      'superhero': '🦸',
      'rocket': '🚀',
      'flower': '🌸',
    };
    if (emojiMap.containsKey(user.avatarType)) {
      return Text(
        emojiMap[user.avatarType]!,
        style: TextStyle(fontSize: fontSize),
      );
    }

    return Text(
      user.name.isNotEmpty ? user.name.substring(0, 1).toUpperCase() : '?',
      style: TextStyle(
        fontSize: fontSize,
        color: const Color(0xFF005F50),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  void _showAvatarDetailAndSelectionSheet(BuildContext context, UserModel user) {
    final presets = [
      {'type': 'dad', 'label': LongStrings.t('Bố', 'Dad'), 'emoji': '👨'},
      {'type': 'mom', 'label': LongStrings.t('Mẹ', 'Mom'), 'emoji': '👩'},
      {'type': 'boy', 'label': LongStrings.t('Con trai', 'Son'), 'emoji': '👦'},
      {'type': 'girl', 'label': LongStrings.t('Con gái', 'Daughter'), 'emoji': '👧'},
      {'type': 'grandpa', 'label': LongStrings.t('Ông', 'Grandpa'), 'emoji': '👴'},
      {'type': 'grandma', 'label': LongStrings.t('Bà', 'Grandma'), 'emoji': '👵'},
      {'type': 'cat', 'label': LongStrings.t('Mèo cưng', 'Cat'), 'emoji': '🐱'},
      {'type': 'dog', 'label': LongStrings.t('Cún cưng', 'Dog'), 'emoji': '🐶'},
      {'type': 'star', 'label': LongStrings.t('Ngôi sao', 'Star'), 'emoji': '⭐'},
      {'type': 'superhero', 'label': LongStrings.t('Siêu anh hùng', 'Hero'), 'emoji': '🦸'},
      {'type': 'rocket', 'label': LongStrings.t('Tên lửa', 'Rocket'), 'emoji': '🚀'},
      {'type': 'flower', 'label': LongStrings.t('Hoa nhỏ', 'Flower'), 'emoji': '🌸'},
    ];

    final googlePhoto = FirebaseAuth.instance.currentUser?.photoURL;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Thanh kéo nhẹ
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),

                // Tiêu đề & nút đóng
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      LongStrings.t('Ảnh đại diện & Tài khoản', 'Avatar & Account'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF151D1B),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Xem chi tiết Avatar lớn
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE4F6EF),
                      border: Border.all(
                        color: const Color(0xFF005F50),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF005F50).withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: _buildAvatarContent(user, size: 88, fontSize: 44),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.name.isNotEmpty ? user.name : 'Người dùng FHub',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF151D1B),
                  ),
                ),
                if (user.email.isNotEmpty)
                  Text(
                    user.email,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF6E7A75),
                    ),
                  ),
                const SizedBox(height: 16),

                const Divider(height: 1),
                const SizedBox(height: 14),

                // Mục chọn Avatar biểu tượng
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    LongStrings.t(
                      'Chọn hình đại diện biểu tượng:',
                      'Choose an avatar icon:',
                    ),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3E4946),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Grid presets
                SizedBox(
                  height: 140,
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: presets.length,
                    itemBuilder: (ctx, index) {
                      final item = presets[index];
                      final isSelected = user.avatarUrl == 'emoji:${item['emoji']}' ||
                          user.avatarType == item['type'];

                      return InkWell(
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _updateUserAvatar(
                            user: user,
                            avatarType: item['type']!,
                            avatarUrl: 'emoji:${item['emoji']}',
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFE0F2EC)
                                : const Color(0xFFF7FAF9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF005F50)
                                  : const Color(0xFFE2EAE7),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item['emoji']!,
                                style: const TextStyle(fontSize: 24),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['label']!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? const Color(0xFF005F50)
                                      : const Color(0xFF6E7A75),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),

                // Tùy chọn ảnh Google hoặc link ảnh web
                Row(
                  children: [
                    if (googlePhoto != null && googlePhoto.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            side: const BorderSide(color: Color(0xFFBDC9C4)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.account_circle_outlined, size: 16),
                          label: Text(
                            LongStrings.t('Ảnh Google', 'Google Photo'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _updateUserAvatar(
                              user: user,
                              avatarType: 'google',
                              avatarUrl: googlePhoto,
                            );
                          },
                        ),
                      ),
                    if (googlePhoto != null && googlePhoto.isNotEmpty)
                      const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          side: const BorderSide(color: Color(0xFFBDC9C4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.link_rounded, size: 16),
                        label: Text(
                          LongStrings.t('Link ảnh web', 'Image URL'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showCustomImageUrlDialog(context, user);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateUserAvatar({
    required UserModel user,
    required String avatarType,
    required String avatarUrl,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'avatar_type': avatarType,
        'avatarUrl': avatarUrl,
      });

      _familyDataService.clearCache();
      if (mounted) {
        setState(_loadData);
        AppToast.showSuccess(
          context,
          LongStrings.t(
            'Đã cập nhật ảnh đại diện thành công!',
            'Avatar updated successfully!',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.showInfo(
          context,
          LongStrings.t(
            'Không thể cập nhật ảnh: $e',
            'Could not update avatar: $e',
          ),
        );
      }
    }
  }

  void _showCustomImageUrlDialog(BuildContext context, UserModel user) {
    final controller = TextEditingController(
      text: user.avatarUrl.startsWith('http') ? user.avatarUrl : '',
    );

    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LongStrings.t('Nhập liên kết ảnh', 'Enter Image URL'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'https://example.com/avatar.png',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: Text(LongStrings.t('Hủy', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF005F50),
            ),
            onPressed: () {
              final url = controller.text.trim();
              Navigator.pop(dlgCtx);
              if (url.isNotEmpty) {
                _updateUserAvatar(
                  user: user,
                  avatarType: 'custom_url',
                  avatarUrl: url,
                );
              }
            },
            child: Text(LongStrings.t('Lưu', 'Save')),
          ),
        ],
      ),
    );
  }
}

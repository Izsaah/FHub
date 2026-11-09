import 'dart:async';
import 'package:flutter/material.dart';

import '../../Danh/danh_payment_entry.dart';
import '../../Long/services/family_data_service.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/family.dart';
import '../models/family_member.dart';
import '../services/family_service.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final FamilyService _familyService = FamilyService();

  bool _isJoining = false;
  String _selectedRole = FamilyMember.roleChild;
  Family? _previewFamily;
  bool _isLookingUp = false;
  String? _lookupError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
  }

  void _onCodeChanged() {
    final code = _codeController.text.trim().toUpperCase();
    _debounce?.cancel();
    if (code.length < 6) {
      if (_previewFamily != null || _lookupError != null || _isLookingUp) {
        setState(() {
          _previewFamily = null;
          _lookupError = null;
          _isLookingUp = false;
        });
      }
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _isLookingUp = true;
        _lookupError = null;
      });
      try {
        final fam = await _familyService.findFamilyByJoinCode(code);
        if (!mounted) return;
        setState(() {
          _isLookingUp = false;
          _previewFamily = fam;
          if (fam == null) {
            _lookupError = AppLanguage.text(
              'Không tìm thấy gia đình với mã này.',
              'No family found with this code.',
            );
          } else {
            if (_selectedRole == FamilyMember.roleMember) {
              _selectedRole = FamilyMember.roleChild;
            }
          }
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLookingUp = false;
          });
        }
      }
    });
  }

  static const Color background = Color(0xFFF2FAF7);
  static const Color primary = Color(0xFF07866F);
  static const Color darkText = Color(0xFF18332E);
  static const Color mutedText = Color(0xFF71827D);

  @override
  void dispose() {
    _debounce?.cancel();
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinFamily() async {
    if (!_formKey.currentState!.validate() || _isJoining) return;
    FocusScope.of(context).unfocus();
    setState(() => _isJoining = true);

    try {
      final family = await _familyService.joinFamily(
        joinCode: _codeController.text,
        role: _selectedRole,
      );
      DanhPaymentEntry.onFamilyCreatedOrJoined(family.id);
      FamilyDataService().clearCache();
      await FamilyDataService().selectFamily(family.id);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            AppLanguage.text('Tham gia thành công', 'Joined successfully'),
            style: const TextStyle(fontWeight: FontWeight.w800, color: darkText),
          ),
          content: Text(
            AppLanguage.text(
              'Bạn đã tham gia gia đình "${family.name}" với vai vế ${_roleLabel(_selectedRole)}.',
              'You joined family "${family.name}" as ${_roleLabel(_selectedRole)}.',
            ),
            style: const TextStyle(color: mutedText, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (mounted) Navigator.of(context).pop(family);
              },
              child: Text(
                AppLanguage.text('Đã hiểu', 'Got it'),
                style: const TextStyle(color: primary, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case FamilyMember.roleGrandparent:
        return AppLanguage.text('Ông / Bà', 'Grandparent');
      case FamilyMember.roleRelative:
        return AppLanguage.text('Cô / Dì / Chú / Bác', 'Relative');
      case FamilyMember.roleMember:
        return AppLanguage.text('Thành viên / Bạn bè', 'Member / Friend');
      case FamilyMember.roleChild:
        return AppLanguage.text('Con cái', 'Child');
      default:
        return AppLanguage.text('Bố / Mẹ', 'Parent');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        return Scaffold(
          backgroundColor: background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          title: AppLanguage.text('Tham gia gia đình', 'Join Family'),
                          subtitle: AppLanguage.text('Kết nối với gia đình của bạn', 'Connect with your family'),
                          onBack: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 23, 20, 22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(21),
                            border: Border.all(color: const Color(0xFFDCE9E5)),
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
                                width: 82,
                                height: 82,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE4F6EF),
                                  borderRadius: BorderRadius.circular(27),
                                ),
                                child: const Icon(
                                  Icons.group_add_rounded,
                                  size: 42,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(height: 17),
                              Text(
                                AppLanguage.text('Nhập mã gia đình', 'Enter family code'),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: darkText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppLanguage.text(
                                  'Nhập mã được chia sẻ bởi quản trị viên\ncủa gia đình bạn.',
                                  'Enter the code shared by your\nfamily owner.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: mutedText,
                                ),
                              ),
                              const SizedBox(height: 25),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _RequiredLabel(
                                  text: AppLanguage.text('Mã gia đình', 'Family Code'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _codeController,
                                textCapitalization: TextCapitalization.characters,
                                textInputAction: TextInputAction.done,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 3,
                                  color: darkText,
                                ),
                                decoration: InputDecoration(
                                  hintText: AppLanguage.text('VD: PALP-7279', 'e.g. PALP-7279'),
                                  hintStyle: const TextStyle(
                                    fontSize: 16,
                                    letterSpacing: 1.2,
                                    color: Color(0xFFA2B0AC),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FBFA),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 17,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFDCE9E5),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFDCE9E5),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: primary,
                                      width: 1.5,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFD56B6B),
                                    ),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFD56B6B),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  final code = value?.trim() ?? '';
                                  if (code.isEmpty) {
                                    return AppLanguage.text(
                                      'Vui lòng nhập mã gia đình',
                                      'Please enter a family code',
                                    );
                                  }
                                  if (code.length < 6) {
                                    return AppLanguage.text(
                                      'Mã gia đình chưa hợp lệ',
                                      'Invalid family code',
                                    );
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              // Preview Không Gian khi nhập mã
                              if (_isLookingUp) ...[
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      AppLanguage.text('Đang nhận diện không gian...', 'Identifying space...'),
                                      style: const TextStyle(fontSize: 12, color: mutedText, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ] else if (_lookupError != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFDE8E8),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFD32F2F)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _lookupError!,
                                          style: const TextStyle(fontSize: 12, color: Color(0xFFD32F2F), fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (_previewFamily != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F4EE),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: primary,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.family_restroom_rounded,
                                        color: primary,
                                        size: 26,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _previewFamily!.name,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: darkText,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              AppLanguage.text(
                                                '🏡 Tổ ấm gia đình (Có phân cấp Bố Mẹ, Con cái, Ông Bà)',
                                                '🏡 Family Hub (Parent, Child, Grandparent hierarchy)',
                                              ),
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _RequiredLabel(
                                  text: AppLanguage.text('Vai vế của bạn', 'Your Role'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: [
                                  FamilyMember.roleGrandparent,
                                  FamilyMember.roleParent,
                                  FamilyMember.roleRelative,
                                  FamilyMember.roleMember,
                                  FamilyMember.roleChild,
                                ].contains(_selectedRole)
                                    ? _selectedRole
                                    : FamilyMember.roleChild,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                    Icons.family_restroom_rounded,
                                    size: 20,
                                    color: Color(0xFF6E8B83),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FBFA),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 15,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFDCE9E5),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFDCE9E5),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: primary,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: FamilyMember.roleChild,
                                    child: Text(AppLanguage.text('Con cái (Mặc định)', 'Child (Default)')),
                                  ),
                                  DropdownMenuItem(
                                    value: FamilyMember.roleParent,
                                    child: Text(AppLanguage.text('Bố / Mẹ', 'Parent')),
                                  ),
                                  DropdownMenuItem(
                                    value: FamilyMember.roleGrandparent,
                                    child: Text(AppLanguage.text('Ông / Bà', 'Grandparent')),
                                  ),
                                  DropdownMenuItem(
                                    value: FamilyMember.roleRelative,
                                    child: Text(AppLanguage.text('Cô / Dì / Chú / Bác', 'Relative')),
                                  ),
                                  DropdownMenuItem(
                                    value: FamilyMember.roleMember,
                                    child: Text(AppLanguage.text('Thành viên / Bạn bè', 'Member / Friend')),
                                  ),
                                ],
                                onChanged: _isJoining
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          setState(() => _selectedRole = value);
                                        }
                                      },
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7FBF9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2EFEA)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.shield_outlined, size: 15, color: primary),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        AppLanguage.text(
                                          'Quản trị an toàn: Chủ nhà (Bố/Mẹ) có toàn quyền xác thực và điều chỉnh vai vế của bạn sau khi tham gia.',
                                          'Family governance: Family Owner (Parents) can verify and adjust your role anytime after joining.',
                                        ),
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF5A726B), height: 1.35),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 13),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4FAF8),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      size: 19,
                                      color: primary,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        AppLanguage.text(
                                          'Mã gia đình thường gồm chữ và số, ví dụ PALP-7279.',
                                          'Family code consists of letters and numbers, e.g. PALP-7279.',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          height: 1.45,
                                          color: Color(0xFF6D817B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              SizedBox(
                                width: double.infinity,
                                height: 53,
                                child: ElevatedButton.icon(
                                  onPressed: _isJoining ? null : _joinFamily,
                                  icon: _isJoining
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.group_add_rounded),
                                  label: Text(
                                    _isJoining
                                        ? AppLanguage.text('Đang xử lý...', 'Processing...')
                                        : AppLanguage.text('Tham gia gia đình', 'Join Family'),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    disabledBackgroundColor: const Color(
                                      0xFF76B8A9,
                                    ),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 17),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF2DEAE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.help_outline_rounded,
                                    size: 19,
                                    color: Color(0xFFD8911B),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      AppLanguage.text('Không có mã gia đình?', "Don't have a code?"),
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF6E4E10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                AppLanguage.text(
                                  'Hãy nhờ người thân đang làm Chủ nhà chia sẻ mã mời trong mục Thông tin gia đình.',
                                  'Ask the family owner to share the invite code from their Family details screen.',
                                ),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: Color(0xFF7D6330),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RequiredLabel extends StatelessWidget {
  final String text;

  const _RequiredLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF27443E),
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          '*',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFFBA1A1A),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFDCE9E5)),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF27443E),
                size: 21,
              ),
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF18332E),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7E79),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

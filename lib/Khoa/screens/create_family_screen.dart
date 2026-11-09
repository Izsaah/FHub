import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../Danh/danh_payment_entry.dart';
import '../../Long/services/family_data_service.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/family_member.dart';
import '../services/family_service.dart';

class CreateFamilyScreen extends StatefulWidget {
  final bool initialIsPeerGroup;

  const CreateFamilyScreen({super.key, this.initialIsPeerGroup = false});

  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _familyNameController = TextEditingController();
  final FamilyService _familyService = FamilyService();
  late bool _isPeerGroup;
  String _selectedRole = FamilyMember.roleParent;
  bool _isCreating = false;

  static const Color background = Color(0xFFF2FAF7);
  static const Color primary = Color(0xFF07866F);
  static const Color darkText = Color(0xFF18332E);
  static const Color mutedText = Color(0xFF71827D);

  @override
  void initState() {
    super.initState();
    _isPeerGroup = widget.initialIsPeerGroup;
    if (_isPeerGroup) {
      _selectedRole = FamilyMember.roleMember;
    }
  }

  @override
  void dispose() {
    _familyNameController.dispose();
    super.dispose();
  }

  Future<void> _createFamily() async {
    if (!_formKey.currentState!.validate() || _isCreating) return;
    FocusScope.of(context).unfocus();
    setState(() => _isCreating = true);

    try {
      final family = await _familyService.createFamily(
        name: _familyNameController.text.trim(),
        role: _isPeerGroup ? FamilyMember.roleMember : _selectedRole,
        isPeerGroup: _isPeerGroup,
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
            _isPeerGroup
                ? AppLanguage.text('Tạo nhóm bạn thành công', 'Group created successfully')
                : AppLanguage.text('Tạo gia đình thành công', 'Family created successfully'),
            style: const TextStyle(fontWeight: FontWeight.w800, color: darkText),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isPeerGroup
                    ? AppLanguage.text(
                        'Không gian nhóm bạn "${family.name}" đã được tạo. Tất cả thành viên tham gia đều là Bạn bè bình đẳng, không ai là Bố/Mẹ hay Con cái, tránh mọi tranh chấp vai trò.',
                        'Peer space "${family.name}" was created. All members join as equal friends without parent/child hierarchy, preventing any role disputes.',
                      )
                    : AppLanguage.text(
                        'Gia đình "${family.name}" đã được tạo. Bạn là Chủ nhà của gia đình này.',
                        'Family "${family.name}" was created. You are the Owner of this family.',
                      ),
                style: const TextStyle(color: mutedText, height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(
                AppLanguage.text('Mã mời thành viên', 'Member invitation code'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: darkText),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2FAF7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  family.joinCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: family.joinCode));
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLanguage.text('Đã sao chép mã gia đình.', 'Family code copied.'),
                      ),
                    ),
                  );
                  Navigator.of(context).pop(family);
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(
                AppLanguage.text('Sao chép mã & tiếp tục', 'Copy code & continue'),
                style: const TextStyle(color: primary, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (mounted) Navigator.of(context).pop(family);
              },
              child: Text(
                AppLanguage.text('Đóng', 'Close'),
                style: const TextStyle(color: primary, fontWeight: FontWeight.w700),
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
      if (mounted) setState(() => _isCreating = false);
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
                          title: _isPeerGroup
                              ? AppLanguage.text('Tạo nhóm bạn bè', 'Create Peer Group')
                              : AppLanguage.text('Tạo gia đình', 'Create Family'),
                          subtitle: _isPeerGroup
                              ? AppLanguage.text(
                                  'Không gian sống chung bình đẳng, không role vai vế',
                                  'Shared living space, equal peers, no role hierarchy',
                                )
                              : AppLanguage.text(
                                  'Thiết lập không gian chung cho gia đình bạn',
                                  'Set up a shared space for your family',
                                ),
                          onBack: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: _cardDecoration(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel(
                                text: AppLanguage.text('Mô hình không gian', 'Space Model'),
                                requiredField: false,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: _isCreating ? null : () => setState(() => _isPeerGroup = false),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: !_isPeerGroup ? const Color(0xFFE0F4EE) : Colors.white,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: !_isPeerGroup ? primary : const Color(0xFFDCE9E5),
                                            width: !_isPeerGroup ? 1.8 : 1.0,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                              Icons.family_restroom_rounded,
                                              color: !_isPeerGroup ? primary : mutedText,
                                              size: 26,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              AppLanguage.text('Tổ ấm gia đình', 'Family Hub'),
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: !_isPeerGroup ? FontWeight.bold : FontWeight.w500,
                                                color: !_isPeerGroup ? darkText : mutedText,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              AppLanguage.text('Có vai vế phụ huynh', 'With role hierarchy'),
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: !_isPeerGroup ? primary : mutedText,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: InkWell(
                                      onTap: _isCreating ? null : () => setState(() => _isPeerGroup = true),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: _isPeerGroup ? const Color(0xFFE8F5E9) : Colors.white,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: _isPeerGroup ? const Color(0xFF2E7D32) : const Color(0xFFDCE9E5),
                                            width: _isPeerGroup ? 1.8 : 1.0,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                              Icons.groups_rounded,
                                              color: _isPeerGroup ? const Color(0xFF2E7D32) : mutedText,
                                              size: 26,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              AppLanguage.text('Bạn bè / Sống chung', 'Roommates / Friends'),
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: _isPeerGroup ? FontWeight.bold : FontWeight.w500,
                                                color: _isPeerGroup ? darkText : mutedText,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              AppLanguage.text('Không role, bình đẳng', 'No role, equal peers'),
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: _isPeerGroup ? FontWeight.w600 : FontWeight.normal,
                                                color: _isPeerGroup ? const Color(0xFF2E7D32) : mutedText,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _SectionTitle(
                                icon: _isPeerGroup ? Icons.groups_rounded : Icons.home_work_rounded,
                                title: _isPeerGroup
                                    ? AppLanguage.text('Thông tin nhóm bạn', 'Group Information')
                                    : AppLanguage.text('Thông tin gia đình', 'Family Information'),
                              ),
                              const SizedBox(height: 18),
                              _FieldLabel(
                                text: _isPeerGroup
                                    ? AppLanguage.text('Tên nhóm bạn / Tên phòng trọ', 'Group / Room Name')
                                    : AppLanguage.text('Tên gia đình', 'Family Name'),
                                requiredField: true,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _familyNameController,
                                textInputAction: TextInputAction.done,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: darkText,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: _inputDecoration(
                                  hintText: _isPeerGroup
                                      ? AppLanguage.text('Ví dụ: Phòng 402, Nhà KTX Bách Khoa', 'e.g. Room 402, Green Dorm')
                                      : AppLanguage.text('Ví dụ: Gia đình Lê Hoàng', 'e.g. The Smith Family'),
                                  prefixIcon: _isPeerGroup ? Icons.group_work_rounded : Icons.home_rounded,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return _isPeerGroup
                                        ? AppLanguage.text('Vui lòng nhập tên nhóm / phòng trọ', 'Please enter a group name')
                                        : AppLanguage.text('Vui lòng nhập tên gia đình', 'Please enter a family name');
                                  }
                                  if (value.trim().length < 3) {
                                    return _isPeerGroup
                                        ? AppLanguage.text('Tên nhóm cần ít nhất 3 ký tự', 'Group name must be at least 3 characters')
                                        : AppLanguage.text('Tên gia đình cần ít nhất 3 ký tự', 'Family name must be at least 3 characters');
                                  }
                                  return null;
                                },
                              ),
                              if (!_isPeerGroup) ...[
                                const SizedBox(height: 16),
                                _FieldLabel(
                                  text: AppLanguage.text('Vai vế của bạn', 'Your Role'),
                                  requiredField: true,
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedRole,
                                  decoration: _inputDecoration(
                                    hintText: AppLanguage.text('Chọn vai vế', 'Select role'),
                                    prefixIcon: Icons.family_restroom_rounded,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: FamilyMember.roleGrandparent,
                                      child: Text(AppLanguage.text('Ông / Bà', 'Grandparent')),
                                    ),
                                    DropdownMenuItem(
                                      value: FamilyMember.roleParent,
                                      child: Text(AppLanguage.text('Bố / Mẹ', 'Parent')),
                                    ),
                                    DropdownMenuItem(
                                      value: FamilyMember.roleRelative,
                                      child: Text(AppLanguage.text('Cô / Dì / Chú / Bác', 'Relative')),
                                    ),
                                    DropdownMenuItem(
                                      value: FamilyMember.roleChild,
                                      child: Text(AppLanguage.text('Con cái', 'Child')),
                                    ),
                                  ],
                                  onChanged: _isCreating
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(() => _selectedRole = value);
                                          }
                                        },
                                ),
                              ] else ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F8E9),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFFC5E1A5)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.shield_outlined, color: Color(0xFF2E7D32), size: 24),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              AppLanguage.text(
                                                'Chế độ Không Role (Bạn bè sống chung)',
                                                'No-Role Mode (Roommates Living Together)',
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Color(0xFF1B5E20),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              AppLanguage.text(
                                                'Tất cả thành viên đều là Bạn bè bình đẳng. Không có vai vế Bố/Mẹ hay Con cái, loại bỏ hoàn toàn tranh chấp vai trò trong nhà!',
                                                'All members join as equal friends. No parent/child hierarchy, eliminating any role disputes!',
                                              ),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF2E7D32),
                                                height: 1.45,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF2DEAE)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 21,
                                color: Color(0xFFD8911B),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  AppLanguage.text(
                                    'Sau khi tạo, bạn sẽ nhận được mã gia đình để chia sẻ cho người thân. Một tài khoản có thể tham gia nhiều gia đình cùng lúc.',
                                    'After creating, you will get a family code to share with relatives. One account can join multiple families at the same time.',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: Color(0xFF7D6330),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _isCreating ? null : _createFamily,
                            icon: _isCreating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.add_home_rounded),
                            label: Text(
                              _isCreating
                                  ? AppLanguage.text('Đang tạo...', 'Creating...')
                                  : _isPeerGroup
                                      ? AppLanguage.text('Tạo nhóm bạn bè', 'Create Peer Group')
                                      : AppLanguage.text('Tạo gia đình', 'Create Family'),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
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
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: darkText,
                              side: const BorderSide(color: Color(0xFFD2E2DD)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: Text(
                              AppLanguage.text('Quay lại', 'Go Back'),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
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

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9AA9A5)),
      prefixIcon: Icon(prefixIcon, size: 20, color: const Color(0xFF6E8B83)),
      filled: true,
      fillColor: const Color(0xFFF7FAF9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD5E3DF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD5E3DF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.5),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFD8E7E2)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.035),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFFE4F6EF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF07866F)),
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF18332E),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool requiredField;

  const _FieldLabel({required this.text, this.requiredField = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF27443E),
          ),
        ),
        if (requiredField) ...[
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

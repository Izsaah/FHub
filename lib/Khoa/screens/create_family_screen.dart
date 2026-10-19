import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/family_member.dart';
import '../services/family_service.dart';

class CreateFamilyScreen extends StatefulWidget {
  const CreateFamilyScreen({super.key});

  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _familyNameController = TextEditingController();
  final FamilyService _familyService = FamilyService();
  String _selectedRole = FamilyMember.roleParent;
  bool _isCreating = false;

  static const Color background = Color(0xFFF2FAF7);
  static const Color primary = Color(0xFF07866F);
  static const Color darkText = Color(0xFF18332E);
  static const Color mutedText = Color(0xFF71827D);

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
        role: _selectedRole,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            'Tạo gia đình thành công',
            style: TextStyle(fontWeight: FontWeight.w800, color: darkText),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gia đình "${family.name}" đã được tạo. Bạn là Owner của gia đình này.',
                style: const TextStyle(color: mutedText, height: 1.5),
              ),
              const SizedBox(height: 16),
              const Text('Mã mời thành viên', style: TextStyle(fontWeight: FontWeight.w700, color: darkText)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF2FAF7), borderRadius: BorderRadius.circular(12)),
                child: SelectableText(
                  family.joinCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w800, color: primary),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép mã gia đình.')));
                  Navigator.of(context).pop(family);
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Sao chép mã & tiếp tục', style: TextStyle(color: primary, fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (mounted) Navigator.of(context).pop(family);
              },
              child: const Text('Đóng', style: TextStyle(color: primary, fontWeight: FontWeight.w700)),
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
                      title: 'Tạo gia đình',
                      subtitle: 'Thiết lập không gian chung cho gia đình bạn',
                      onBack: () => Navigator.of(context).pop(),
                    ),

                    const SizedBox(height: 22),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: _cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle(
                            icon: Icons.home_work_rounded,
                            title: 'Thông tin gia đình',
                          ),

                          const SizedBox(height: 18),

                          const _FieldLabel(
                            text: 'Tên gia đình',
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
                              hintText: 'Ví dụ: Gia đình Lê Hoàng',
                              prefixIcon: Icons.home_rounded,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Vui lòng nhập tên gia đình';
                              }

                              if (value.trim().length < 3) {
                                return 'Tên gia đình cần ít nhất 3 ký tự';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          const _FieldLabel(text: 'Vai vế của bạn', requiredField: true),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedRole,
                            decoration: _inputDecoration(
                              hintText: 'Chọn vai vế',
                              prefixIcon: Icons.family_restroom_rounded,
                            ),
                            items: const [
                              DropdownMenuItem(value: FamilyMember.roleGrandparent, child: Text('Ông / Bà')),
                              DropdownMenuItem(value: FamilyMember.roleParent, child: Text('Bố / Mẹ')),
                              DropdownMenuItem(value: FamilyMember.roleChild, child: Text('Con cái')),
                            ],
                            onChanged: _isCreating ? null : (value) {
                              if (value != null) setState(() => _selectedRole = value);
                            },
                          ),
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
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 21,
                            color: Color(0xFFD8911B),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Sau khi tạo, bạn sẽ nhận được mã gia đình '
                              'để chia sẻ cho người thân.',
                              style: TextStyle(
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
                        icon: _isCreating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add_home_rounded),
                        label: Text(_isCreating ? 'Đang tạo...' : 'Tạo gia đình'),
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
                        child: const Text(
                          'Quay lại',
                          style: TextStyle(fontWeight: FontWeight.w700),
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
      fillColor: const Color(0xFFF8FBFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE9E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE9E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD56B6B)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD56B6B), width: 1.5),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
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
      children: [
        _BackButton(onTap: onBack),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF18332E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF788984)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

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
          child: const Icon(
            Icons.arrow_back_rounded,
            color: Color(0xFF27443E),
            size: 21,
          ),
        ),
      ),
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
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: const Color(0xFFE2F4EF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF07866F), size: 21),
        ),
        const SizedBox(width: 10),
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
            color: Color(0xFF36504A),
          ),
        ),
        if (requiredField) ...[
          const SizedBox(width: 3),
          const Text(
            '*',
            style: TextStyle(
              color: Color(0xFFD45C5C),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

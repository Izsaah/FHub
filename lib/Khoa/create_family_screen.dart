import 'package:flutter/material.dart';

class CreateFamilyScreen extends StatefulWidget {
  const CreateFamilyScreen({super.key});

  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _familyNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isPrivate = true;

  static const Color background = Color(0xFFF2FAF7);
  static const Color primary = Color(0xFF07866F);
  static const Color darkText = Color(0xFF18332E);
  static const Color mutedText = Color(0xFF71827D);

  @override
  void dispose() {
    _familyNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _createFamily() {
    if (!_formKey.currentState!.validate()) return;

    final familyName = _familyNameController.text.trim();

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Tạo gia đình thành công',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: darkText,
            ),
          ),
          content: Text(
            'Gia đình "$familyName" đã được tạo. '
            'Bạn có thể tiếp tục mời các thành viên.',
            style: const TextStyle(
              color: mutedText,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text(
                'Tiếp tục',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
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
                          _SectionTitle(
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
                            textInputAction: TextInputAction.next,
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
                          const SizedBox(height: 17),

                          const _FieldLabel(text: 'Mô tả'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 3,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(
                              fontSize: 14,
                              color: darkText,
                            ),
                            decoration: _inputDecoration(
                              hintText:
                                  'Ví dụ: Không gian kết nối và chăm sóc gia đình',
                              prefixIcon: Icons.notes_rounded,
                            ),
                          ),
                          const SizedBox(height: 19),

                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6FAF8),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: const Color(0xFFDDEAE6),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F4EE),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Quyền riêng tư',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: darkText,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Chỉ thành viên có mã mời mới có thể tham gia.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.35,
                                          color: mutedText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                  value: _isPrivate,
                                  activeColor: primary,
                                  onChanged: (value) {
                                    setState(() => _isPrivate = value);
                                  },
                                ),
                              ],
                            ),
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
                        border: Border.all(
                          color: const Color(0xFFF2DEAE),
                        ),
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
                        onPressed: _createFamily,
                        icon: const Icon(Icons.add_home_rounded),
                        label: const Text('Tạo gia đình'),
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
                          side: const BorderSide(
                            color: Color(0xFFD2E2DD),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: const Text(
                          'Quay lại',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
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
      hintStyle: const TextStyle(
        fontSize: 13,
        color: Color(0xFF9AA9A5),
      ),
      prefixIcon: Icon(
        prefixIcon,
        size: 20,
        color: const Color(0xFF6E8B83),
      ),
      filled: true,
      fillColor: const Color(0xFFF8FBFA),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 15,
      ),
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
        borderSide: const BorderSide(
          color: primary,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD56B6B)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFFD56B6B),
          width: 1.5,
        ),
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
          color: Colors.black.withOpacity(0.035),
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
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF788984),
                ),
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

  const _SectionTitle({
    required this.icon,
    required this.title,
  });

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
          child: const Icon(
            Icons.home_work_rounded,
            color: Color(0xFF07866F),
            size: 21,
          ),
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

  const _FieldLabel({
    required this.text,
    this.requiredField = false,
  });

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

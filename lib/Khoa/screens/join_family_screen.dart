import 'package:flutter/material.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  bool _isJoining = false;

  static const Color background = Color(0xFFF2FAF7);
  static const Color primary = Color(0xFF07866F);
  static const Color darkText = Color(0xFF18332E);
  static const Color mutedText = Color(0xFF71827D);

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinFamily() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isJoining = true);

    await Future<void>.delayed(const Duration(milliseconds: 550));

    if (!mounted) return;

    setState(() => _isJoining = false);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Tham gia thành công',
            style: TextStyle(fontWeight: FontWeight.w800, color: darkText),
          ),
          content: const Text(
            'Bạn đã gửi yêu cầu tham gia gia đình. '
            'Trong phiên bản kết nối thật, yêu cầu sẽ được gửi đến quản trị viên.',
            style: TextStyle(color: mutedText, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text(
                'Đã hiểu',
                style: TextStyle(color: primary, fontWeight: FontWeight.w800),
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
                      title: 'Tham gia gia đình',
                      subtitle: 'Kết nối với gia đình của bạn',
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
                            color: Colors.black.withOpacity(0.035),
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

                          const Text(
                            'Nhập mã gia đình',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: darkText,
                            ),
                          ),

                          const SizedBox(height: 8),

                          const Text(
                            'Nhập mã được chia sẻ bởi quản trị viên\n'
                            'của gia đình bạn.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: mutedText,
                            ),
                          ),

                          const SizedBox(height: 25),

                          const Align(
                            alignment: Alignment.centerLeft,
                            child: _RequiredLabel(text: 'Mã gia đình'),
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
                              hintText: 'VD: TOAM-8869',
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
                                return 'Vui lòng nhập mã gia đình';
                              }

                              if (code.length < 6) {
                                return 'Mã gia đình chưa hợp lệ';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 13),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4FAF8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 19,
                                  color: primary,
                                ),
                                SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    'Mã gia đình thường gồm chữ và số, '
                                    'ví dụ TOAM-8869.',
                                    style: TextStyle(
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
                                    ? 'Đang xử lý...'
                                    : 'Tham gia gia đình',
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
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.help_outline_rounded,
                                size: 19,
                                color: Color(0xFFD8911B),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Không có mã gia đình?',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF6F592D),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 7),
                          Text(
                            'Hãy nhờ một thành viên trong gia đình mở phần '
                            'thông tin gia đình và chia sẻ mã cho bạn.',
                            style: TextStyle(
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
  }
}

class _RequiredLabel extends StatelessWidget {
  final String text;

  const _RequiredLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: '$text ',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF36504A),
        ),
        children: const [
          TextSpan(
            text: '*',
            style: TextStyle(color: Color(0xFFD45C5C)),
          ),
        ],
      ),
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

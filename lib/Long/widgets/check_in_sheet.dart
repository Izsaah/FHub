import 'package:flutter/material.dart';
import '../services/family_state_manager.dart';

class CheckInSheet extends StatefulWidget {
  final VoidCallback onCheckInSuccess;

  const CheckInSheet({super.key, required this.onCheckInSuccess});

  static Future<void> show(BuildContext context, {required VoidCallback onSuccess}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => CheckInSheet(onCheckInSuccess: onSuccess),
    );
  }

  @override
  State<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<CheckInSheet> {
  final TextEditingController _captionController = TextEditingController();
  String? _selectedImageUrl;
  bool _isLoading = false;

  final List<Map<String, String>> _samplePhotos = [
    {
      'label': 'Bữa sáng',
      'url': 'https://images.unsplash.com/photo-1525351484163-7529414344d8?w=500',
    },
    {
      'label': 'Tập thể dục',
      'url': 'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=500',
    },
    {
      'label': 'Uống trà',
      'url': 'https://images.unsplash.com/photo-1544787219-7f47ccb76574?w=500',
    },
    {
      'label': 'Đi dạo',
      'url': 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=500',
    },
  ];

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _handleQuickCheckIn() async {
    setState(() => _isLoading = true);
    try {
      final service = FamilyStateManager().service;
      await service.checkIn(service.currentUserId);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCheckInSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Check-in nhanh thành công! Gia đình đã yên tâm.'),
          backgroundColor: Color(0xFF005F50),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePhotoCheckIn() async {
    if (_selectedImageUrl == null && _captionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn 1 bức ảnh hoặc nhập lời nhắn.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final service = FamilyStateManager().service;
      await service.checkIn(
        service.currentUserId,
        imageUrl: _selectedImageUrl,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : 'Đã check-in an toàn hôm nay!',
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCheckInSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Check-in kèm ảnh thành công! Đã đăng vào Kỷ niệm gia đình.'),
          backgroundColor: Color(0xFF005F50),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_user_rounded,
                        color: Color(0xFF005F50), size: 26),
                    SizedBox(width: 8),
                    Text(
                      "Check-in: I'M OK",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF151D1B),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Chọn cách check-in hôm nay để báo tin an vui đến gia đình:',
              style: TextStyle(fontSize: 13, color: Color(0xFF5A6F68)),
            ),
            const SizedBox(height: 18),

            // Option 1: Quick 1-tap check-in
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF5F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFBDC9C4).withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚡ Check-in Nhanh (1 Chạm)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF005F50),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cập nhật trạng thái an toàn ngay tức thì lên mục Family Today.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF5A6F68)),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005F50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.touch_app),
                      label: const Text(
                        'Check-in 1 chạm ngay',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isLoading ? null : _handleQuickCheckIn,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'HOẶC KÈM ẢNH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),

            // Option 2: Attach photo & caption
            const Text(
              '📸 Đính kèm ảnh hoạt động hôm nay:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF151D1B),
              ),
            ),
            const SizedBox(height: 8),

            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _samplePhotos.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final photo = _samplePhotos[index];
                  final isSelected = _selectedImageUrl == photo['url'];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedImageUrl = isSelected ? null : photo['url'];
                      });
                    },
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF005F50)
                              : Colors.grey[300]!,
                          width: isSelected ? 3 : 1,
                        ),
                        image: DecorationImage(
                          image: NetworkImage(photo['url']!),
                          fit: BoxFit.cover,
                        ),
                      ),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(10),
                          ),
                        ),
                        child: Text(
                          photo['label']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),
            TextField(
              controller: _captionController,
              decoration: InputDecoration(
                hintText: 'Nhập lời nhắn gửi đến con cháu...',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFFF7FAF9),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFBDC9C4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: const Color(0xFFBDC9C4).withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF49D37),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.photo_camera),
                label: const Text(
                  'Đăng Check-in Kèm Ảnh lên Feed',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _isLoading ? null : _handlePhotoCheckIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

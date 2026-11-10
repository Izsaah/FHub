import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../Thinh/theme/app_language.dart';
import '../services/family_state_manager.dart';
import '../utils/check_in_image_compressor.dart';
import 'app_toast.dart';
import 'check_in_camera_screen.dart';

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
  Uint8List? _capturedImageBytes;
  bool _isLoading = false;
  bool _isTakingPhoto = false;

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
      AppToast.showSuccess(
        context,
        AppLanguage.text(
          '✓ Check-in thành công! Đã cập nhật trạng thái an toàn cho tất cả gia đình của bạn.',
          '✓ Checked in successfully! Updated safety status across all your families.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.showInfo(
        context,
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePhotoCheckIn() async {
    if (_selectedImageUrl == null &&
        _capturedImageBytes == null &&
        _captionController.text.trim().isEmpty) {
      AppToast.showInfo(
        context,
        AppLanguage.text(
          'Vui lòng chọn 1 bức ảnh hoặc nhập lời nhắn.',
          'Please select a photo or enter a caption.',
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final service = FamilyStateManager().service;
      final imageUrl = _capturedImageBytes == null
          ? _selectedImageUrl
          : 'data:image/jpeg;base64,${base64Encode(
              await compute(compressCheckInImage, _capturedImageBytes!),
            )}';
      await service.checkIn(
        service.currentUserId,
        imageUrl: imageUrl,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : 'Đã check-in an toàn hôm nay!',
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCheckInSuccess();
      AppToast.showSuccess(
        context,
        AppLanguage.text(
          '✓ Check-in kèm ảnh thành công! Đã đồng bộ lên tất cả gia đình của bạn.',
          '✓ Photo check-in succeeded! Synced across all your families.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.showInfo(
        context,
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _capturePhoto() async {
    setState(() => _isTakingPhoto = true);
    try {
      final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => const CheckInCameraScreen(),
        ),
      );
      if (bytes != null && mounted) {
        setState(() {
          _capturedImageBytes = bytes;
          _selectedImageUrl = null;
        });
      }
    } catch (e) {
      debugPrint('CheckInSheet camera screen error: $e');
      if (!mounted) return;
      AppToast.showInfo(
        context,
        AppLanguage.text(
          'Không thể mở máy ảnh: $e',
          'Could not open camera: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => _isTakingPhoto = false);
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
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_rounded,
                          color: Color(0xFF005F50), size: 26),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "Check-in: I'M OK",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF151D1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              AppLanguage.text(
                'Chỉ cần 1 lần Check-in để báo tin an vui đồng loạt cho tất cả gia đình bạn đang tham gia:',
                'Check in once to update your safety status across all families you belong to:',
              ),
              style: const TextStyle(fontSize: 13, color: Color(0xFF5A6F68)),
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
                  Text(
                    AppLanguage.text(
                      '⚡ Check-in Nhanh (1 Chạm • Toàn Bộ Gia Đình)',
                      '⚡ Quick Check-in (1 Tap • All Families)',
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF005F50),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLanguage.text(
                      'Cập nhật trạng thái an toàn ngay tức thì cho tất cả tổ ấm của bạn.',
                      'Instantly update your safety status across all your families.',
                    ),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF5A6F68)),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005F50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.touch_app),
                      label: Flexible(
                        child: Text(
                          AppLanguage.text(
                            'Check-in 1 chạm ngay',
                            '1-Tap Check-in Now',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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
                        _capturedImageBytes = null;
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

            if (_capturedImageBytes != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _capturedImageBytes!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLanguage.text('Ảnh đã chụp', 'Photo captured'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF005F50),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: AppLanguage.text('Chụp lại', 'Retake photo'),
                    onPressed: _isLoading || _isTakingPhoto
                        ? null
                        : () => setState(() => _capturedImageBytes = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ],

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isTakingPhoto
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.photo_camera),
                label: Flexible(
                  child: Text(
                    AppLanguage.text(
                      'Chụp ảnh bằng Camera',
                      'Take a photo with camera',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                onPressed: _isLoading || _isTakingPhoto ? null : _capturePhoto,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005F50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.send),
                label: Flexible(
                  child: Text(
                    AppLanguage.text(
                      'Đăng Check-in Kèm Ảnh lên Feed',
                      'Post Check-in with Photo to Feed',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                onPressed: _isLoading || _isTakingPhoto
                    ? null
                    : _handlePhotoCheckIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

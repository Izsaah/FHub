import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/reminder_model.dart';

class CameraProofDialog extends StatefulWidget {
  final ReminderModel reminder;
  final String currentUserName;

  const CameraProofDialog({
    super.key,
    required this.reminder,
    required this.currentUserName,
  });

  static Future<String?> show(
    BuildContext context, {
    required ReminderModel reminder,
    required String currentUserName,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CameraProofDialog(
        reminder: reminder,
        currentUserName: currentUserName,
      ),
    );
  }

  @override
  State<CameraProofDialog> createState() => _CameraProofDialogState();
}

class _CameraProofDialogState extends State<CameraProofDialog> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _noteController = TextEditingController();

  String? _capturedImagePath;
  String? _noteError;
  bool _isTakingPhoto = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String _formatCurrentTimestamp() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final y = now.year;
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min:$s';
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isTakingPhoto = true);
    try {
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}

      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        final base64String = base64Encode(bytes);
        final dataUri = 'data:image/jpeg;base64,$base64String';
        setState(() {
          _capturedImagePath = dataUri;
        });
      }
    } catch (e) {
      debugPrint('CameraProofDialog pickImage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở máy ảnh: $e'),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTakingPhoto = false);
      }
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedImagePath = null;
    });
  }

  void _submitProof() {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      setState(() {
        _noteError = 'Vui lòng nhập ghi chú nghiệm thu công việc!';
      });
      return;
    }

    if (_capturedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Vui lòng chụp ảnh bằng Camera của máy trước khi xác nhận!'),
          backgroundColor: Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    Navigator.of(context).pop(_capturedImagePath);
  }

  Widget _buildImageWidget(String path) {
    if (path.startsWith('data:image/')) {
      try {
        final commaIdx = path.indexOf(',');
        final b64 = commaIdx != -1 ? path.substring(commaIdx + 1) : path;
        final bytes = base64Decode(b64);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _buildImagePlaceholder(),
        );
      } catch (_) {
        return _buildImagePlaceholder();
      }
    }
    if (path.startsWith('http') || path.startsWith('blob:')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _buildImagePlaceholder(),
      );
    }
    if (kIsWeb) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _buildImagePlaceholder(),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (ctx, err, stack) => _buildImagePlaceholder(),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: const Color(0xFF2C3835),
      alignment: Alignment.center,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_camera_rounded, color: Color(0xFF67DFCB), size: 48),
          SizedBox(height: 8),
          Text(
            'Ảnh bằng chứng đã được lưu',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    const tealAccent = Color(0xFF67DFCB);
    final timestamp = _formatCurrentTimestamp();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2321),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header Bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF2C3835))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.camera_alt_rounded,
                        color: tealAccent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Chụp ảnh nghiệm thu bằng máy',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.reminder.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF9AA7A2),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                  ],
                ),
              ),

              // Camera Viewfinder / Preview Area
              Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    height: 250,
                    color: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_capturedImagePath != null)
                          _buildImageWidget(_capturedImagePath!)
                        else
                          // Camera viewfinder placeholder
                          InkWell(
                            onTap: _isTakingPhoto
                                ? null
                                : () => _pickImage(ImageSource.camera),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: const BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment.center,
                                  radius: 1.0,
                                  colors: [
                                    Color(0xFF23302C),
                                    Color(0xFF101715)
                                  ],
                                ),
                              ),
                              child: Center(
                                child: _isTakingPhoto
                                    ? const CircularProgressIndicator(
                                        color: tealAccent)
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 72,
                                            height: 72,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: Colors.white24,
                                                  width: 2),
                                              color: const Color(0x3367DFCB),
                                            ),
                                            child: const Icon(
                                              Icons.photo_camera_rounded,
                                              size: 36,
                                              color: tealAccent,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Chạm vào đây để mở Camera máy',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Chụp ảnh thực tế công việc đã hoàn thành',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Color(0xFF9AA7A2),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),

                        // Timestamp watermark
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: tealAccent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.verified,
                                          color: tealAccent, size: 14),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          widget.currentUserName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  timestamp,
                                  style: const TextStyle(
                                    color: Color(0xFF9AA7A2),
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Ghi chú nghiệm thu (Bắt buộc người dùng tự ghi)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          'Ghi chú nghiệm thu ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            '* (Bắt buộc)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFFFF8A80),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText:
                            'Nhập mô tả việc bạn đã hoàn thành (VD: Đã rửa sạch chén dĩa và lau khô bàn bếp...)',
                        hintStyle: const TextStyle(
                            color: Color(0xFF70807A), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF26322F),
                        errorText: _noteError,
                        errorStyle: const TextStyle(
                            color: Color(0xFFFF8A80), fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF374642)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: tealAccent),
                        ),
                      ),
                      onChanged: (val) {
                        if (_noteError != null && val.trim().isNotEmpty) {
                          setState(() => _noteError = null);
                        }
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Camera buttons & actions
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  children: [
                    if (_capturedImagePath == null)
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF005F50),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.camera_alt_rounded),
                              label: const Text(
                                'Mở Camera Chụp',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              onPressed: _isTakingPhoto
                                  ? null
                                  : () => _pickImage(ImageSource.camera),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF26322F),
                              foregroundColor: tealAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            tooltip: 'Chọn ảnh từ thư viện',
                            icon: const Icon(Icons.photo_library_outlined),
                            onPressed: _isTakingPhoto
                                ? null
                                : () => _pickImage(ImageSource.gallery),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side:
                                    const BorderSide(color: Color(0xFF3E4D49)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text(
                                'Chụp lại',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: _retakePhoto,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              icon: const Icon(Icons.check_circle_rounded,
                                  size: 18),
                              label: const Text(
                                'Xác nhận hoàn thành',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              onPressed: _submitProof,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

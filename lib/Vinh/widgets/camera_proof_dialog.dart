import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String? _capturedImageUrl;
  bool _isFlashOn = false;
  int _selectedPresetIndex = 0;

  final List<Map<String, String>> _sampleProofs = [
    {
      'title': 'Rửa bát sạch sẽ',
      'url':
          'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=600&q=80',
    },
    {
      'title': 'Bàn học ngăn nắp',
      'url':
          'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?auto=format&fit=crop&w=600&q=80',
    },
    {
      'title': 'Quần áo gấp gọn',
      'url':
          'https://images.unsplash.com/photo-1540518614846-7ede433c4ef4?auto=format&fit=crop&w=600&q=80',
    },
    {
      'title': 'Phòng khách sạch đẹp',
      'url':
          'https://images.unsplash.com/photo-1583847268964-b28dc8f51f92?auto=format&fit=crop&w=600&q=80',
    },
  ];

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

  void _capturePhoto() {
    HapticFeedback.heavyImpact();
    setState(() {
      _capturedImageUrl = _sampleProofs[_selectedPresetIndex]['url'];
    });
  }

  void _retakePhoto() {
    setState(() {
      _capturedImageUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
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
                      color: Color(0xFF67DFCB), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chụp ảnh nghiệm thu',
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
                  if (widget.reminder.hasRewardStars)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF382A00),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFB900)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFFFB900), size: 14),
                          const SizedBox(width: 3),
                          Text(
                            '+${widget.reminder.rewardStars} sao',
                            style: const TextStyle(
                              color: Color(0xFFFFB900),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
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
                  height: 280,
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image Display
                      if (_capturedImageUrl != null)
                        Image.network(
                          _capturedImageUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF67DFCB)),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: const Color(0xFF2C3835),
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    color: Color(0xFF67DFCB), size: 48),
                                SizedBox(height: 8),
                                Text(
                                  'Đã chụp ảnh bằng chứng!',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        // Live Viewfinder Simulation
                        Container(
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.center,
                              radius: 1.0,
                              colors: [Color(0xFF23302C), Color(0xFF101715)],
                            ),
                          ),
                          child: Stack(
                            children: [
                              // Grid lines simulation
                              Center(
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white24,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.photo_camera_outlined,
                                    size: 54,
                                    color: Colors.white38,
                                  ),
                                ),
                              ),
                              // Live flash toggle button
                              Positioned(
                                top: 12,
                                right: 12,
                                child: IconButton(
                                  icon: Icon(
                                    _isFlashOn
                                        ? Icons.flash_on
                                        : Icons.flash_off,
                                    color: _isFlashOn
                                        ? const Color(0xFFFFB900)
                                        : Colors.white70,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() => _isFlashOn = !_isFlashOn);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Verification Watermark Overlay (Bottom of Camera View)
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
                                color: const Color(0xFF67DFCB)
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.verified,
                                      color: Color(0xFF67DFCB), size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.currentUserName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
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

            // Scenario Preset Selector (when not captured yet)
            if (_capturedImageUrl == null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chọn nội dung chụp nghiệm thu:',
                      style: TextStyle(
                        color: Color(0xFF9AA7A2),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: List.generate(_sampleProofs.length, (idx) {
                        final isSel = _selectedPresetIndex == idx;
                        return ChoiceChip(
                          label: Text(_sampleProofs[idx]['title']!),
                          selected: isSel,
                          selectedColor: const Color(0xFF005F50),
                          backgroundColor: const Color(0xFF26322F),
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : const Color(0xFF9AA7A2),
                            fontSize: 12,
                            fontWeight:
                                isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isSel
                                  ? const Color(0xFF67DFCB)
                                  : Colors.transparent,
                            ),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedPresetIndex = idx);
                            }
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Shutter / Action Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: _capturedImageUrl == null
                  ? Center(
                      child: GestureDetector(
                        onTap: _capturePhoto,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            color: Colors.transparent,
                          ),
                          child: Center(
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF67DFCB),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  color: Color(0xFF00372E)),
                            ),
                          ),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Color(0xFF3E4D49)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Chụp lại'),
                            onPressed: _retakePhoto,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.check_circle, size: 20),
                            label: Text(
                              widget.reminder.hasRewardStars
                                  ? 'Xác nhận (+${widget.reminder.rewardStars} ⭐)'
                                  : 'Xác nhận nộp ảnh',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop(_capturedImageUrl);
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

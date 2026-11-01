import 'package:flutter/material.dart';

/// Thẻ tùy chọn nghiệm thu việc nhà:
/// - Bật/Tắt yêu cầu bắt buộc chụp ảnh bằng chứng hoàn thành bằng Camera
class ChoreRewardCard extends StatelessWidget {
  final bool requiresProofImage;
  final ValueChanged<bool> onProofRequiredChanged;

  const ChoreRewardCard({
    super.key,
    required this.requiresProofImage,
    required this.onProofRequiredChanged,
  });

  static const Color primaryColor = Color(0xFF005F50);
  static const Color textPrimary = Color(0xFF151D1B);
  static const Color textMuted = Color(0xFF6E7A75);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFD0E6DE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.camera_alt_rounded,
                  color: primaryColor,
                  size: 22,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nghiệm thu hoàn thành việc nhà',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Bắt buộc chụp ảnh nghiệm thu',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: const Text(
                'Người nhận việc cần chụp ảnh hoàn thành bằng Camera để xác thực',
                style: TextStyle(
                  fontSize: 12,
                  color: textMuted,
                ),
              ),
              value: requiresProofImage,
              activeTrackColor: primaryColor,
              onChanged: onProofRequiredChanged,
            ),
          ],
        ),
      ),
    );
  }
}

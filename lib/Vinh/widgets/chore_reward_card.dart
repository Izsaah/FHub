import 'package:flutter/material.dart';

/// Card tùy chọn tính năng Gamification và Nghiệm thu việc nhà:
/// - Switch bắt buộc chụp ảnh bằng chứng nghiệm thu (Camera Proof of Work)
/// - Selector điểm thưởng sao (0, 1, 2, 3, 5 sao)
class ChoreRewardCard extends StatelessWidget {
  final bool requiresProofImage;
  final int rewardStars;
  final ValueChanged<bool> onProofRequiredChanged;
  final ValueChanged<int> onRewardStarsChanged;

  const ChoreRewardCard({
    super.key,
    required this.requiresProofImage,
    required this.rewardStars,
    required this.onProofRequiredChanged,
    required this.onRewardStarsChanged,
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
                Icons.stars_rounded,
                color: Color(0xFFFFA000),
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                'Dạy con & Nghiệm thu việc nhà',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Bắt buộc chụp ảnh nghiệm thu 📸',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: const Text(
              'Người nhận phải chụp ảnh bằng chứng để hoàn thành công việc',
              style: TextStyle(
                fontSize: 12,
                color: textMuted,
              ),
            ),
            value: requiresProofImage,
            activeTrackColor: primaryColor,
            onChanged: onProofRequiredChanged,
          ),
          const Divider(height: 16),
          const Text(
            'Tặng sao thưởng (Reward Stars):',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [0, 1, 2, 3, 5].map((stars) {
                final isSel = rewardStars == stars;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (stars > 0) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFFFA000),
                          ),
                          const SizedBox(width: 2),
                        ],
                        Text(
                          stars == 0 ? 'Không thưởng' : '+$stars sao',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                isSel ? FontWeight.bold : FontWeight.normal,
                            color: isSel ? primaryColor : textPrimary,
                          ),
                        ),
                      ],
                    ),
                    selected: isSel,
                    selectedColor: const Color(0xFFD4ECE5),
                    backgroundColor: const Color(0xFFF3FBF8),
                    side: BorderSide(
                      color: isSel ? primaryColor : const Color(0xFFBDC9C4),
                    ),
                    onSelected: (_) => onRewardStarsChanged(stars),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    ),
  );
  }
}

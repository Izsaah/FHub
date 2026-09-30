import 'package:flutter/material.dart';
import '../theme/danh_colors.dart';

class PremiumBadgeWidget extends StatelessWidget {
  final bool isPremium;
  final bool compact;
  final String? customText;

  const PremiumBadgeWidget({
    super.key,
    required this.isPremium,
    this.compact = false,
    this.customText,
  });

  @override
  Widget build(BuildContext context) {
    if (isPremium) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [DanhColors.gold, DanhColors.goldDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(compact ? 8 : 12),
          boxShadow: [
            BoxShadow(
              color: DanhColors.gold.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium,
              color: Colors.white,
              size: compact ? 12 : 15,
            ),
            SizedBox(width: compact ? 3 : 5),
            Text(
              customText ?? 'PREMIUM',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: compact ? 10 : 12,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: DanhColors.brand50,
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(color: DanhColors.brand200),
      ),
      child: Text(
        customText ?? 'FREE',
        style: TextStyle(
          color: DanhColors.brand700,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 10 : 11,
        ),
      ),
    );
  }
}

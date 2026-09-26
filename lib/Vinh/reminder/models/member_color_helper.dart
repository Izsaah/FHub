import 'package:flutter/material.dart';

class MemberColorHelper {
  /// Returns main brand color for family members based on name/role:
  /// - Dad / Bố: Blue (#2A7DE1)
  /// - Mom / Mẹ: Emerald Teal (#0D7A68)
  /// - Minh / Con: Honey Orange (#F49D37)
  /// - Grandparents / Others: Purple (#8E44AD)
  static Color getPrimaryColor(String nameOrRole) {
    final lower = nameOrRole.toLowerCase();
    if (lower.contains('dad') || lower.contains('bố') || lower.contains('ba')) {
      return const Color(0xFF2A7DE1);
    }
    if (lower.contains('mom') || lower.contains('mẹ') || lower.contains('má')) {
      return const Color(0xFF0D7A68);
    }
    if (lower.contains('minh') ||
        lower.contains('con') ||
        lower.contains('bé') ||
        lower.contains('child') ||
        lower.contains('son') ||
        lower.contains('daughter')) {
      return const Color(0xFFF49D37);
    }
    if (lower.contains('ông') || lower.contains('bà') || lower.contains('grand')) {
      return const Color(0xFF8E44AD);
    }
    return const Color(0xFF0D7A68);
  }

  /// Returns soft background container color for member avatar/badge
  static Color getBackgroundColor(String nameOrRole) {
    final lower = nameOrRole.toLowerCase();
    if (lower.contains('dad') || lower.contains('bố') || lower.contains('ba')) {
      return const Color(0xFFEBF3FC);
    }
    if (lower.contains('mom') || lower.contains('mẹ') || lower.contains('má')) {
      return const Color(0xFFE7F5F2);
    }
    if (lower.contains('minh') ||
        lower.contains('con') ||
        lower.contains('bé') ||
        lower.contains('child') ||
        lower.contains('son') ||
        lower.contains('daughter')) {
      return const Color(0xFFFFF3E5);
    }
    if (lower.contains('ông') || lower.contains('bà') || lower.contains('grand')) {
      return const Color(0xFFF5EBF9);
    }
    return const Color(0xFFE7F0EC);
  }
}

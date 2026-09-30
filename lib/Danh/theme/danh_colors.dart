import 'package:flutter/material.dart';

/// Bảng màu chuẩn giao diện FHub (đồng bộ phong cách 100% với Long và Thinh)
/// Tông xanh ngọc bích đậm (#005F50, #0D7A68) kết hợp vàng kim hoàng gia (#F49D37, #D97706)
class DanhColors {
  DanhColors._();

  // Primary Theme Colors (Chuẩn FHub)
  static const Color brand900 = Color(0xFF00382E);
  static const Color brand800 = Color(0xFF005F50); // Primary chính của FHub
  static const Color brand700 = Color(0xFF0D7A68); // Secondary teal
  static const Color brand500 = Color(0xFF14B8A6);
  static const Color brand200 = Color(0xFF99F6E4);
  static const Color brand50 = Color(0xFFEDF5F2);  // Nền AppBar chuẩn của FHub

  // Premium / Gold Accents (Huy hiệu VIP & Điểm nhấn)
  static const Color gold = Color(0xFFF49D37);     // Amber warm của FHub
  static const Color goldDark = Color(0xFFD97706);
  static const Color goldLight = Color(0xFFFEF3C7);
  static const Color goldBadge = Color(0xFFFFFBEB);

  // Neutral Colors (Đồng bộ với Scaffold & Cards của FHub)
  static const Color scaffoldBg = Color(0xFFF3FBF8); // Nền Scaffold chuẩn của FHub
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF151D1B);
  static const Color textSecondary = Color(0xFF3E4946);
  static const Color textMuted = Color(0xFF6E7A75);
  static const Color borderLight = Color(0xFFE2EAE7);
  static const Color divider = Color(0xFFBDC9C4);

  // Status Colors
  static const Color success = Color(0xFF0D7A68);
  static const Color successBg = Color(0xFFE8F6F3);
  static const Color warning = Color(0xFFF49D37);
  static const Color warningBg = Color(0xFFFFF7ED);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorBg = Color(0xFFFFEDEC);

  // Dual Shadow đặc trưng của FHub
  static const List<BoxShadow> fhubCardShadow = [
    BoxShadow(
      color: Color(0x120D7A68),
      offset: Offset(0, 8),
      blurRadius: 20,
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x0DF49D37),
      offset: Offset(0, 4),
      blurRadius: 10,
      spreadRadius: -2,
    ),
  ];

  static List<BoxShadow> premiumGlowShadow = [
    BoxShadow(
      color: gold.withValues(alpha: 0.18),
      offset: const Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -2,
    ),
    BoxShadow(
      color: brand800.withValues(alpha: 0.08),
      offset: const Offset(0, 4),
      blurRadius: 12,
      spreadRadius: -2,
    ),
  ];
}

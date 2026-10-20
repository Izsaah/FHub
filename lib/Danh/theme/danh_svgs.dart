import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Bộ ký hiệu và đồ họa Vector SVG cao cấp dành riêng cho Module Danh
/// Tinh tế, sắc nét, không bị nhòe vỡ trên mọi độ phân giải màn hình
class DanhSvgs {
  DanhSvgs._();

  // 1. Vương miện hoàng gia Premium VIP (Gold Crown)
  static const String crownRaw = '''
<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M6 38L8 16L18 28L24 10L30 28L40 16L42 38H6Z" fill="url(#crown_grad)" stroke="#D4A017" stroke-width="2" stroke-linejoin="round"/>
  <circle cx="8" cy="14" r="3" fill="#FFE57F" stroke="#D4A017" stroke-width="1.5"/>
  <circle cx="24" cy="8" r="3.5" fill="#FFE57F" stroke="#D4A017" stroke-width="1.5"/>
  <circle cx="40" cy="14" r="3" fill="#FFE57F" stroke="#D4A017" stroke-width="1.5"/>
  <rect x="6" y="38" width="36" height="5" rx="2.5" fill="#B38600" stroke="#8A6800" stroke-width="1"/>
  <defs>
    <linearGradient id="crown_grad" x1="24" y1="10" x2="24" y2="38" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FFEB3B"/>
      <stop offset="0.5" stop-color="#FFC107"/>
      <stop offset="1" stop-color="#FFA000"/>
    </linearGradient>
  </defs>
</svg>
''';

  // 2. Huy hiệu VIP đa giác lấp lánh (VIP Diamond Star)
  static const String vipBadgeRaw = '''
<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <polygon points="24,2 30,16 46,18 34,30 38,46 24,38 10,46 14,30 2,18 18,16" fill="url(#star_grad)" stroke="#C69214" stroke-width="1.5" stroke-linejoin="round"/>
  <circle cx="24" cy="24" r="8" fill="#FFFFFF" fill-opacity="0.3"/>
  <defs>
    <linearGradient id="star_grad" x1="24" y1="2" x2="24" y2="46" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FFF59D"/>
      <stop offset="0.6" stop-color="#FFD54F"/>
      <stop offset="1" stop-color="#FFB300"/>
    </linearGradient>
  </defs>
</svg>
''';

  // 3. Tích xanh xác thực thành công (Green Checkmark Badge)
  static const String checkSuccessRaw = '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="32" cy="32" r="30" fill="url(#check_grad)"/>
  <path d="M20 33L28 41L45 23" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
  <defs>
    <linearGradient id="check_grad" x1="10" y1="10" x2="54" y2="54" gradientUnits="userSpaceOnUse">
      <stop stop-color="#2ECC71"/>
      <stop offset="1" stop-color="#1B9A59"/>
    </linearGradient>
  </defs>
</svg>
''';

  // 4. Hũ Niềm Vui Gia Đình (Golden Jackpot Pot)
  static const String goldenPotRaw = '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="18" rx="22" ry="7" fill="#E65100"/>
  <path d="M10 18C10 18 6 36 12 48C18 58 46 58 52 48C58 36 54 18 54 18" fill="url(#pot_grad)" stroke="#B26A00" stroke-width="2"/>
  <ellipse cx="32" cy="17" rx="19" ry="5" fill="#FFE082"/>
  <circle cx="27" cy="14" r="5" fill="#FFD54F" stroke="#FFA000" stroke-width="1"/>
  <circle cx="37" cy="13" r="6" fill="#FFE082" stroke="#FFA000" stroke-width="1"/>
  <circle cx="32" cy="11" r="5.5" fill="#FFCA28" stroke="#FF8F00" stroke-width="1"/>
  <circle cx="32" cy="36" r="10" fill="#FFE082" fill-opacity="0.3" stroke="#FFD54F" stroke-width="2"/>
  <path d="M32 30V42M26 36H38" stroke="#FFE082" stroke-width="2.5" stroke-linecap="round"/>
  <defs>
    <linearGradient id="pot_grad" x1="32" y1="18" x2="32" y2="58" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FF9800"/>
      <stop offset="0.6" stop-color="#F57C00"/>
      <stop offset="1" stop-color="#E65100"/>
    </linearGradient>
  </defs>
</svg>
''';

  // 5. Đồng xu may mắn (Lucky Gold Coin)
  static const String coinRaw = '''
<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="16" cy="16" r="14" fill="url(#coin_grad)" stroke="#C69214" stroke-width="2"/>
  <circle cx="16" cy="16" r="10" stroke="#FFE082" stroke-width="1.5" stroke-dasharray="2 2"/>
  <text x="16" y="21" font-size="14" font-weight="bold" text-anchor="middle" fill="#FFFFFF" font-family="sans-serif">đ</text>
  <defs>
    <linearGradient id="coin_grad" x1="6" y1="6" x2="26" y2="26" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FFD54F"/>
      <stop offset="1" stop-color="#FF8F00"/>
    </linearGradient>
  </defs>
</svg>
''';

  // 6. Tia sét kích hoạt / bùng nổ (Energy Shake Lightning)
  static const String lightningRaw = '''
<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M18 2L5 17H15L13 30L27 14H16L18 2Z" fill="url(#light_grad)" stroke="#FF8F00" stroke-width="1.5" stroke-linejoin="round"/>
  <defs>
    <linearGradient id="light_grad" x1="16" y1="2" x2="16" y2="30" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FFF176"/>
      <stop offset="1" stop-color="#FFB300"/>
    </linearGradient>
  </defs>
</svg>
''';

  // Helper widget render
  static Widget crown({double size = 28}) => SvgPicture.string(
        crownRaw,
        width: size,
        height: size,
      );

  static Widget vipBadge({double size = 26}) => SvgPicture.string(
        vipBadgeRaw,
        width: size,
        height: size,
      );

  static Widget checkSuccess({double size = 64}) => SvgPicture.string(
        checkSuccessRaw,
        width: size,
        height: size,
      );

  static Widget goldenPot({double size = 48}) => SvgPicture.string(
        goldenPotRaw,
        width: size,
        height: size,
      );

  static Widget coin({double size = 24}) => SvgPicture.string(
        coinRaw,
        width: size,
        height: size,
      );

  static Widget lightning({double size = 24}) => SvgPicture.string(
        lightningRaw,
        width: size,
        height: size,
      );
}

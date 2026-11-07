import 'package:flutter/material.dart';

import '../models/family_member_model.dart';
import '../models/hierarchy_role.dart';
import '../utils/long_strings.dart';

class FamilyMemberTile extends StatelessWidget {
  final FamilyMemberModel member;
  final VoidCallback? onTap;

  const FamilyMemberTile({
    super.key,
    required this.member,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (member.isMemorialized) {
      return _buildMemorialTile(context);
    }

    if (member.isDeactivated) {
      return _buildDeactivatedTile(context);
    }

    return _buildActiveTile(context);
  }

  // --- MEMORIALIZED TILE (TƯỞNG NIỆM) ---
  Widget _buildMemorialTile(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F7F3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
              offset: const Offset(0, 4),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE8E2D2),
                    border:
                        Border.all(color: const Color(0xFFD4AF37), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    member.user.name.isNotEmpty
                        ? member.user.name.substring(0, 1).toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Color(0xFF5D4037),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFF5D4037),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite,
                      size: 10,
                      color: Color(0xFFD4AF37),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Color(0xFF4A3E3D),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildHierarchyBadge(member.hierarchyRole),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.spa, size: 13, color: Color(0xFFB08D57)),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Tưởng niệm · Kỷ niệm mãi lưu giữ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF8D7B68),
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEADBC8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Tưởng niệm',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF634832),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- DEACTIVATED TILE (TẠM DỪNG KẾT NỐI) ---
  Widget _buildDeactivatedTile(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFBDC9C4).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD6DBDA),
                border: Border.all(color: const Color(0xFF9EA8A5), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                member.user.name.isNotEmpty
                    ? member.user.name.substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Color(0xFF6E7A75),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Color(0xFF86928E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildHierarchyBadge(member.hierarchyRole, isMuted: true),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Row(
                    children: [
                      Icon(Icons.pause_circle_outline,
                          size: 14, color: Color(0xFF86928E)),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Tài khoản đang tạm khóa kết nối',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF86928E),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E5E3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Tạm ngưng kết nối',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF5A6662),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ACTIVE TILE ---
  Widget _buildActiveTile(BuildContext context) {
    final isCheckedIn = member.isCheckedInToday;
    final timeString = member.lastCheckInAt != null
        ? '${member.lastCheckInAt!.hour.toString().padLeft(2, '0')}:${member.lastCheckInAt!.minute.toString().padLeft(2, '0')}'
        : '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFEDF5F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFBDC9C4).withValues(alpha: 0.4),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120D7A68),
              offset: Offset(0, 10),
              blurRadius: 24,
              spreadRadius: -4,
            ),
            BoxShadow(
              color: Color(0x0DF49D37),
              offset: Offset(0, 4),
              blurRadius: 10,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCheckedIn
                    ? const Color(0xFFD7EFE6)
                    : const Color(0xFFE0E5E3),
                border: Border.all(
                  color: isCheckedIn
                      ? const Color(0xFF005F50)
                      : const Color(0xFFBDC9C4),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                member.user.name.isNotEmpty
                    ? member.user.name.substring(0, 1).toUpperCase()
                    : '?',
                style: TextStyle(
                  color: isCheckedIn
                      ? const Color(0xFF005F50)
                      : Colors.blue[900],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Color(0xFF151D1B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildHierarchyBadge(member.hierarchyRole),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isCheckedIn
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 14,
                        color: isCheckedIn
                            ? const Color(0xFF005F50)
                            : const Color(0xFF6E7A75),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          isCheckedIn
                              ? 'Checked in · $timeString'
                              : 'Not checked in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCheckedIn
                                ? const Color(0xFF005F50)
                                : const Color(0xFF6E7A75),
                            fontSize: 12,
                            fontWeight: isCheckedIn
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (member.isOwner)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFDCBD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('👑 ', style: TextStyle(fontSize: 10)),
                    Text(
                      LongStrings.t('Chủ nhà', 'Owner'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6C3E00),
                        fontWeight: FontWeight.bold,
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

  Widget _buildHierarchyBadge(HierarchyRole role, {bool isMuted = false}) {
    Color bg;
    Color fg;
    String label = role.displayName;

    switch (role) {
      case HierarchyRole.grandparent:
        bg = const Color(0xFFFFF3CD);
        fg = const Color(0xFF856404);
        break;
      case HierarchyRole.parent:
        bg = const Color(0xFFD1ECF1);
        fg = const Color(0xFF0C5460);
        break;
      case HierarchyRole.child:
        bg = const Color(0xFFE8DAEF);
        fg = const Color(0xFF5B2C6F);
        break;
      case HierarchyRole.relative:
        bg = const Color(0xFFE2F0D9);
        fg = const Color(0xFF385723);
        break;
    }

    if (isMuted) {
      bg = const Color(0xFFE2E6E5);
      fg = const Color(0xFF6E7A75);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

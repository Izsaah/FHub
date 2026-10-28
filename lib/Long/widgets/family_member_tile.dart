import 'package:flutter/material.dart';

import '../models/family_member_model.dart';
import '../utils/long_strings.dart';

class FamilyMemberTile extends StatelessWidget {
  final FamilyMemberModel member;

  const FamilyMemberTile({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    final isCheckedIn = member.isCheckedInToday;
    final timeString = isCheckedIn && member.lastCheckInAt != null
        ? '${member.lastCheckInAt!.hour.toString().padLeft(2, '0')}:${member.lastCheckInAt!.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
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
                color: Colors.blue[900],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.user.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Color(0xFF151D1B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                            ? LongStrings.t('Đã điểm danh · $timeString', 'Checked in · $timeString')
                            : LongStrings.t('Chưa điểm danh', 'Not checked in'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCheckedIn
                              ? const Color(0xFF005F50)
                              : const Color(0xFF6E7A75),
                          fontSize: 12,
                          fontWeight:
                              isCheckedIn ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F4EE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  member.roleLabel,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF005F50),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (member.role == Role.owner) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFDCBD),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    LongStrings.t('Chủ nhà', 'Owner'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6C3E00),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

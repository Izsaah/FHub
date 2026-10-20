import 'package:flutter/material.dart';
import '../models/family_member.dart';
import '../services/member_color_helper.dart';

/// BottomSheet chọn người nhận lời nhắc:
/// - Chọn thành viên cụ thể trong gia đình
/// - Hoặc chọn "👨‍👩‍👧 Cả nhà (Việc chung / Open Task)"
class MemberPickerBottomSheet extends StatelessWidget {
  final List<FamilyMember> familyMembers;
  final FamilyMember? selectedMember;

  const MemberPickerBottomSheet({
    super.key,
    required this.familyMembers,
    this.selectedMember,
  });

  static const Color primaryColor = Color(0xFF005F50);
  static const Color textPrimary = Color(0xFF151D1B);
  static const Color textMuted = Color(0xFF6E7A75);

  static Future<FamilyMember?> show(
    BuildContext context, {
    required List<FamilyMember> familyMembers,
    FamilyMember? selectedMember,
  }) {
    return showModalBottomSheet<FamilyMember>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => MemberPickerBottomSheet(
        familyMembers: familyMembers,
        selectedMember: selectedMember,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Chọn người nhận việc (For)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2EAE7)),

            // 1. Tùy chọn đặc biệt: Cả nhà (Việc chung / Open Task)
            ListTile(
              leading: const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFFE0F7FA),
                child: Icon(
                  Icons.groups_rounded,
                  color: Color(0xFF00796B),
                  size: 20,
                ),
              ),
              title: const Text(
                '👨‍👩‍👧 Cả nhà (Việc chung / Open Task)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF005F50),
                ),
              ),
              subtitle: const Text(
                'Chưa gán ai, các thành viên có thể xung phong nhận việc',
                style: TextStyle(fontSize: 12, color: textMuted),
              ),
              trailing: selectedMember?.id == 'OPEN'
                  ? const Icon(Icons.check_circle, color: primaryColor)
                  : null,
              tileColor: selectedMember?.id == 'OPEN'
                  ? const Color(0xFFE7F5F2)
                  : Colors.transparent,
              onTap: () {
                Navigator.of(context).pop(
                  const FamilyMember(
                    id: 'OPEN',
                    name: 'Cả nhà',
                    role: 'Open Task',
                    familyId: '',
                  ),
                );
              },
            ),
            const Divider(height: 1, color: Color(0xFFE2EAE7)),

            // 2. Danh sách từng thành viên gia đình
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: familyMembers.length,
                itemBuilder: (ctx, index) {
                  final member = familyMembers[index];
                  final isSelected = member.id == selectedMember?.id;
                  final primary = MemberColorHelper.getPrimaryColor(member.name);
                  final bg = MemberColorHelper.getBackgroundColor(member.name);

                  return ListTile(
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: bg,
                      child: Text(
                        member.name.isNotEmpty
                            ? member.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                    ),
                    title: Text(
                      member.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      member.roleDisplayName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: textMuted,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: primaryColor)
                        : null,
                    tileColor:
                        isSelected ? const Color(0xFFE7F5F2) : Colors.transparent,
                    onTap: () => Navigator.of(context).pop(member),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

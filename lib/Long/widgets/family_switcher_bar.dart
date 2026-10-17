import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/family_model.dart';
import '../services/family_state_manager.dart';
import '../screens/family/create_family_screen.dart';
import '../screens/family/join_family_screen.dart';

class FamilySwitcherBar extends StatelessWidget {
  final FamilyModel? currentFamily;
  final List<FamilyModel> families;
  final ValueChanged<String> onFamilyChanged;
  final VoidCallback? onTakeoverClaimed;

  const FamilySwitcherBar({
    super.key,
    required this.currentFamily,
    required this.families,
    required this.onFamilyChanged,
    this.onTakeoverClaimed,
  });

  void _copyJoinCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép mã gia đình: $code'),
        backgroundColor: const Color(0xFF005F50),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showFamilyPickerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Danh sách Gia đình',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF151D1B),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ...families.map((fam) {
                  final isSelected = fam.id == currentFamily?.id;
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF005F50).withValues(alpha: 0.15)
                            : const Color(0xFFF1F3F4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.family_restroom,
                        color: isSelected
                            ? const Color(0xFF005F50)
                            : const Color(0xFF6E7A75),
                      ),
                    ),
                    title: Text(
                      fam.name,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFF005F50)
                            : const Color(0xFF2B3633),
                      ),
                    ),
                    subtitle: Text('Mã: ${fam.joinCode}'),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                            color: Color(0xFF005F50))
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (!isSelected) {
                        onFamilyChanged(fam.id);
                      }
                    },
                  );
                }),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline,
                      color: Color(0xFF005F50)),
                  title: const Text(
                    'Tạo gia đình mới',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF005F50),
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateFamilyScreen(),
                      ),
                    );
                    FamilyStateManager().reload();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group_add_outlined,
                      color: Color(0xFF0D7A68)),
                  title: const Text(
                    'Tham gia gia đình bằng mã',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D7A68),
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const JoinFamilyScreen(),
                      ),
                    );
                    FamilyStateManager().reload();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentFamily == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3CD),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Chưa chọn gia đình nào.'),
      );
    }

    final isEligible = FamilyStateManager().service.isTakeoverEligible(
          familyId: currentFamily!.id,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF5F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFBDC9C4).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showFamilyPickerSheet(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF005F50).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.family_restroom,
                          size: 20,
                          color: Color(0xFF005F50),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Gia đình đang chọn',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6E7A75),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    currentFamily!.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF005F50),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF005F50),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () => _copyJoinCode(context, currentFamily!.joinCode),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF005F50).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentFamily!.joinCode,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: Color(0xFF005F50),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: Color(0xFF005F50),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isEligible) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFB74D)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE65100), size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Chủ phòng vắng mặt/tạm ngưng > 30 ngày. Bạn (Bố Mẹ) có thể tiếp quản!',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A3B00),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: onTakeoverClaimed,
                  child: const Text('Tiếp quản'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

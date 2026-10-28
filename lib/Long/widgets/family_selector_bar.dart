import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/family_model.dart';
import '../utils/long_strings.dart';

/// Thanh chọn gia đình dạng select (khớp giao diện ReminderListScreen),
/// hỗ trợ hộp thoại chọn gia đình giới hạn tối đa 5 dòng hiển thị,
/// nếu nhiều hơn 5 gia đình thì tự động cuộn xuống.
class FamilySelectorBar extends StatelessWidget {
  final List<FamilyModel> families;
  final FamilyModel? currentFamily;
  final ValueChanged<FamilyModel> onFamilySelected;
  final VoidCallback onAddFamily;
  final VoidCallback? onQuickNavigateToFamily;

  const FamilySelectorBar({
    super.key,
    required this.families,
    required this.currentFamily,
    required this.onFamilySelected,
    required this.onAddFamily,
    this.onQuickNavigateToFamily,
  });

  void _showFamilySelectionBox(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thanh kéo (handle bar)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Header
              Row(
                children: [
                  const Icon(
                    Icons.home_work_rounded,
                    color: Color(0xFF005F50),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      LongStrings.selectFamilyTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF151D1B),
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4F6EF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'A → Z (${families.length})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF005F50),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                LongStrings.selectFamilyDesc,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF6E7A75),
                ),
              ),
              const SizedBox(height: 14),

              // Danh sách gia đình: Giới hạn tối đa 5 mục hiển thị, nếu > 5 thì cuộn (scroll)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(families.length, 5) * 58.0,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: families.length > 5
                      ? const AlwaysScrollableScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: families.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final fam = families[index];
                    final isSelected = fam.id == currentFamily?.id;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onFamilySelected(fam);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFE4F6EF)
                              : const Color(0xFFF7FBF9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF005F50)
                                : const Color(0xFFDCE8E3),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF005F50)
                                    : const Color(0xFFE4F6EF),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.cottage_rounded,
                                size: 16,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF005F50),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                fam.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? const Color(0xFF005F50)
                                      : const Color(0xFF151D1B),
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF005F50),
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              // Nút Tạo / Tham gia thêm gia đình
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: Color(0xFF005F50)),
                  foregroundColor: const Color(0xFF005F50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_home_work_outlined, size: 18),
                label: Text(
                  LongStrings.addOrJoinFamily,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onAddFamily();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (families.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayName = currentFamily?.name ?? families.first.name;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showFamilySelectionBox(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBDC9C4)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.home_work_rounded,
                size: 16,
                color: Color(0xFF005F50),
              ),
              const SizedBox(width: 6),
              Text(
                LongStrings.selectFamily,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6E7A75),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF005F50),
                  ),
                ),
              ),
              if (families.length > 1)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F6EF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    LongStrings.houses(families.length),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF005F50),
                    ),
                  ),
                ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF005F50),
                size: 18,
              ),
              if (onQuickNavigateToFamily != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: LongStrings.familyShortcutTooltip,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: onQuickNavigateToFamily,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.open_in_new_rounded,
                        size: 15,
                        color: Color(0xFF005F50),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

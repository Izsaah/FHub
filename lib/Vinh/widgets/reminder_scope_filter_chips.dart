import 'package:flutter/material.dart';

/// Thanh lựa chọn phạm vi xem: [👨‍👩‍👧 Cả nhà] hoặc [👤 Việc của tôi]
class ReminderScopeFilterChips extends StatelessWidget {
  final bool filterOnlyMine;
  final ValueChanged<bool> onScopeChanged;

  const ReminderScopeFilterChips({
    super.key,
    required this.filterOnlyMine,
    required this.onScopeChanged,
  });

  static const Color primaryColor = Color(0xFF005F50);
  static const Color selectedBgColor = Color(0xFFD4ECE5);
  static const Color unselectedTextColor = Color(0xFF49454F);
  static const Color borderColor = Color(0xFFC4C7C5);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDF5F2),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: ChoiceChip(
              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: Icon(
                Icons.groups_rounded,
                size: 16,
                color: !filterOnlyMine ? primaryColor : unselectedTextColor,
              ),
              label: const Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '👨‍👩‍👧 Cả nhà',
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
              selected: !filterOnlyMine,
              selectedColor: selectedBgColor,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: !filterOnlyMine ? primaryColor : unselectedTextColor,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: !filterOnlyMine ? primaryColor : borderColor,
                ),
              ),
              onSelected: (selected) {
                if (selected) {
                  onScopeChanged(false);
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ChoiceChip(
              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: Icon(
                Icons.person_rounded,
                size: 16,
                color: filterOnlyMine ? primaryColor : unselectedTextColor,
              ),
              label: const Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '👤 Việc của tôi',
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
              selected: filterOnlyMine,
              selectedColor: selectedBgColor,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: filterOnlyMine ? primaryColor : unselectedTextColor,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: filterOnlyMine ? primaryColor : borderColor,
                ),
              ),
              onSelected: (selected) {
                if (selected) {
                  onScopeChanged(true);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

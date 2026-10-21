import 'package:flutter/material.dart';
import '../models/reminder_model.dart';
import '../services/member_color_helper.dart';

/// Thẻ công việc thu nhỏ (Task Mini Card) hiển thị trực tiếp
/// bên trong khung Chat AI khi AI tự động tạo lời nhắc hoặc việc chung.
class TaskMiniCard extends StatelessWidget {
  final ReminderModel reminder;
  final VoidCallback? onTap;
  final VoidCallback? onClaim;

  const TaskMiniCard({
    super.key,
    required this.reminder,
    this.onTap,
    this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    final isOpen = reminder.isOpenTask;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E3DE), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Icon + Trạng thái
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isOpen ? const Color(0xFFE0F2EC) : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isOpen ? Icons.groups_rounded : Icons.alarm_rounded,
                  size: 16,
                  color: isOpen ? primaryColor : const Color(0xFFE65100),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isOpen ? 'CÔNG VIỆC CHUNG GIA ĐÌNH' : 'LỜI NHẮC MỚI ĐƯỢC TẠO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isOpen ? primaryColor : const Color(0xFFE65100),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isOpen ? const Color(0xFFE0F2EC) : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isOpen ? 'ĐANG MỞ' : 'CHỜ LÀM',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isOpen ? primaryColor : const Color(0xFFE65100),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tiêu đề công việc
          Text(
            reminder.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF151D1B),
            ),
          ),
          const SizedBox(height: 6),

          // Thông tin người nhận & Thời gian
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isOpen
                      ? '👨‍👩‍👧 Cả nhà (Việc chung)'
                      : 'Giao cho: ${reminder.assignedToName}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isOpen
                        ? const Color(0xFF00796B)
                        : MemberColorHelper.getPrimaryColor(reminder.assignedToName),
                  ),
                ),
              ),
              Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '${reminder.time}  ${reminder.date}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Nút thao tác
          Row(
            children: [
              if (isOpen && onClaim != null) ...[
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.touch_app_rounded, size: 16),
                      label: const Text(
                        'Nhận việc ngay',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: onClaim,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF151D1B),
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onTap,
                    child: const Text(
                      'Xem chi tiết',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

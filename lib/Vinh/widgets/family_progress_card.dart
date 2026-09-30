import 'package:flutter/material.dart';
import '../models/reminder_model.dart';

class FamilyProgressCard extends StatelessWidget {
  final List<ReminderModel> reminders;
  final String dateTitle;

  const FamilyProgressCard({
    super.key,
    required this.reminders,
    this.dateTitle = 'Hôm nay',
  });

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return const SizedBox.shrink();
    }

    final total = reminders.length;
    final completed = reminders.where((r) => r.isCompleted).length;
    final percent = total > 0 ? (completed / total) : 0.0;
    final isAllDone = total > 0 && completed == total;

    const primaryColor = Color(0xFF0D7A68);
    const accentOrange = Color(0xFFF49D37);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isAllDone ? const Color(0xFFE7F5F2) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAllDone
              ? const Color(0xFF0D7A68)
              : const Color(0xFFE2EAE7),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080D7A68),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isAllDone
                        ? Icons.celebration_outlined
                        : Icons.task_alt_outlined,
                    color: isAllDone ? primaryColor : accentOrange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isAllDone
                        ? 'Cả nhà đã hoàn thành hết việc! 🎉'
                        : 'Tiến độ gia đình ($dateTitle)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF151D1B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isAllDone
                      ? const Color(0xFF0D7A68)
                      : const Color(0xFFFFF3E5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$completed/$total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isAllDone ? Colors.white : accentOrange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 8,
              backgroundColor: const Color(0xFFE2EAE7),
              valueColor: AlwaysStoppedAnimation<Color>(
                isAllDone ? primaryColor : accentOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

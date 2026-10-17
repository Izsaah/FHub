import 'package:flutter/material.dart';

import '../services/family_state_manager.dart';

class CheckInReminderCard extends StatelessWidget {
  final String? familyId;

  const CheckInReminderCard({super.key, this.familyId});

  @override
  Widget build(BuildContext context) {
    final reminders = FamilyStateManager().service.getSimulatedReminders(
          familyId: familyId,
        );

    if (reminders.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF005F50).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF005F50).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.alarm_on_rounded,
                  size: 18,
                  color: Color(0xFF005F50),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Giám sát Ngoại lệ & Nhắc nhở (Mô phỏng)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF005F50),
                      ),
                    ),
                    Text(
                      'Mốc 0h (08:00 Nhẹ) ➔ +6h (14:00 Rung) ➔ +12h (20:00 Báo Bố Mẹ)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF5A6F68),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...reminders.take(3).map((r) {
            final isCancelled = r.isCancelled;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isCancelled ? const Color(0xFFE8F5E9) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCancelled
                      ? const Color(0xFF81C784)
                      : const Color(0xFFE0E0E0),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCancelled
                        ? Icons.check_circle_rounded
                        : (r.isVibration ? Icons.vibration : Icons.notifications_active),
                    size: 18,
                    color: isCancelled
                        ? const Color(0xFF2E7D32)
                        : (r.isVibration ? Colors.deepOrange : const Color(0xFF005F50)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              r.slot.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isCancelled
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFF151D1B),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isCancelled
                                    ? const Color(0xFFC8E6C9)
                                    : const Color(0xFFFFE0B2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isCancelled ? 'Đã hủy (Đã check-in)' : 'Đang chờ mốc',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isCancelled
                                      ? const Color(0xFF1B5E20)
                                      : const Color(0xFFE65100),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.message,
                          style: TextStyle(
                            fontSize: 11,
                            color: isCancelled
                                ? const Color(0xFF558B2F)
                                : const Color(0xFF424242),
                            decoration: isCancelled
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

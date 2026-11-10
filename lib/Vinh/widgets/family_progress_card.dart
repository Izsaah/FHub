import 'package:flutter/material.dart';
import '../../Thinh/theme/app_language.dart';
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
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        final activeReminders = reminders.where((r) => !r.isDeleted).toList();
        if (activeReminders.isEmpty) {
          return const SizedBox.shrink();
        }

        final total = activeReminders.length;
        final completed = activeReminders.where((r) => r.isCompleted).length;
        final percent = total > 0 ? (completed / total) : 0.0;
        final isAllDone = total > 0 && completed == total;

        const primaryColor = Color(0xFF0D7A68);
        const accentOrange = Color(0xFFF49D37);

        final displayDateTitle = dateTitle == 'Tất cả'
            ? AppLanguage.text('Tất cả', 'All')
            : (dateTitle == 'Hôm nay'
                ? AppLanguage.text('Hôm nay', 'Today')
                : dateTitle);

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          isAllDone
                              ? Icons.verified_rounded
                              : Icons.task_alt_outlined,
                          color: isAllDone ? primaryColor : accentOrange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            isAllDone
                                ? AppLanguage.text(
                                    'Cả nhà đã hoàn thành xuất sắc mục tiêu hôm nay',
                                    'All family tasks completed!',
                                  )
                                : AppLanguage.text(
                                    'Tiến độ gia đình ($displayDateTitle)',
                                    'Family progress ($displayDateTitle)',
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF151D1B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
      },
    );
  }
}

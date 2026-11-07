import 'package:flutter/material.dart';
import '../../../Thinh/theme/app_language.dart';
import '../../models/reminder_model.dart';
import '../../widgets/reminder_card.dart';
import '../../widgets/reminder_empty_states.dart';
import '../../widgets/reminder_section_header.dart';

/// View danh sách hiển thị các lời nhắc được phân nhóm theo 4 mức ưu tiên:
/// 1. Quá hạn (OVERDUE)
/// 2. Đang mở / Việc chung (OPEN)
/// 3. Chờ xử lý (PENDING)
/// 4. Đã hoàn thành (COMPLETED)
class ReminderListView extends StatelessWidget {
  final List<ReminderModel> allReminders;
  final List<ReminderModel> displayedReminders;
  final String currentUserId;
  final String selectedDateStr;
  final bool isShowingAll;
  final bool isParentOrOwner;
  final Map<String, String> familyNamesById;
  final bool showFamilyBadge;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final bool Function(ReminderModel)? canDeletePredicate;
  final VoidCallback onCreatePressed;
  final VoidCallback onShowAllPressed;
  final ValueChanged<ReminderModel> onTapReminder;
  final ValueChanged<ReminderModel> onCompleteReminder;
  final ValueChanged<ReminderModel> onDeleteReminder;
  final ValueChanged<ReminderModel> onClaimReminder;
  final ValueChanged<ReminderModel>? onClaimAndCompleteReminder;

  const ReminderListView({
    super.key,
    required this.allReminders,
    required this.displayedReminders,
    required this.currentUserId,
    required this.selectedDateStr,
    required this.isShowingAll,
    this.isParentOrOwner = false,
    this.familyNamesById = const {},
    this.showFamilyBadge = false,
    this.shrinkWrap = false,
    this.physics,
    this.canDeletePredicate,
    required this.onCreatePressed,
    required this.onShowAllPressed,
    required this.onTapReminder,
    required this.onCompleteReminder,
    required this.onDeleteReminder,
    required this.onClaimReminder,
    this.onClaimAndCompleteReminder,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        final activeAllReminders =
            allReminders.where((r) => !r.isDeleted).toList();
        if (activeAllReminders.isEmpty) {
          return ReminderEmptyState(onCreatePressed: onCreatePressed);
        }

        final activeReminders =
            displayedReminders.where((r) => !r.isDeleted).toList();

        if (activeReminders.isEmpty) {
          return ReminderDayEmptyState(
            dateStr: selectedDateStr,
            onShowAllPressed: onShowAllPressed,
          );
        }

        final overdueList = activeReminders
            .where((r) => r.isOverdue && !r.isCompleted && !r.isSubmitted)
            .toList();

        final openList = activeReminders
            .where((r) => r.isOpen && !r.isOverdue && !r.isCompleted)
            .toList();

        final pendingList = activeReminders
            .where((r) =>
                r.isPending && !r.isOverdue && !r.isOpen && !r.isCompleted)
            .toList();

        final submittedList = activeReminders
            .where((r) => r.isSubmitted && !r.isCompleted)
            .toList();

        final completedList =
            activeReminders.where((r) => r.isCompleted).toList();

        bool canDelete(ReminderModel r) {
          if (canDeletePredicate != null) {
            return canDeletePredicate!(r);
          }
          return r.creatorId == currentUserId || isParentOrOwner;
        }

        String? resolveFamilyName(ReminderModel r) {
          if (r.familyName != null && r.familyName!.trim().isNotEmpty) {
            return r.familyName;
          }
          return familyNamesById[r.familyId];
        }

        return ListView(
          shrinkWrap: shrinkWrap,
          physics: physics,
          padding: EdgeInsets.fromLTRB(16, 4, 16, shrinkWrap ? 24 : 110),
          children: [
            // 1. Nhóm Quá Hạn (Ưu tiên cao nhất)
            if (overdueList.isNotEmpty) ...[
              ReminderSectionHeader(
                title: AppLanguage.text('QUÁ HẠN', 'OVERDUE'),
                count: overdueList.length,
                color: const Color(0xFFBA1A1A),
                icon: Icons.warning_amber_rounded,
              ),
              ...overdueList.map(
                (reminder) => ReminderCard(
                  reminder: reminder,
                  currentUserId: currentUserId,
                  familyName:
                      showFamilyBadge ? resolveFamilyName(reminder) : null,
                  showFamilyBadge: showFamilyBadge,
                  onTap: () => onTapReminder(reminder),
                  onComplete: reminder.assignedTo == currentUserId
                      ? () => onCompleteReminder(reminder)
                      : null,
                  onDelete: canDelete(reminder)
                      ? () => onDeleteReminder(reminder)
                      : null,
                  onClaim: reminder.isOpenTask
                      ? () => onClaimReminder(reminder)
                      : null,
                  onClaimAndComplete:
                      reminder.isOpenTask && onClaimAndCompleteReminder != null
                          ? () => onClaimAndCompleteReminder!(reminder)
                          : null,
                ),
              ),
            ],

            // 1b. Nhóm Chờ Duyệt Nghiệm Thu (Ảnh con nộp chờ Bố Mẹ / Ông Bà duyệt & thưởng sao)
            if (submittedList.isNotEmpty) ...[
              ReminderSectionHeader(
                title: AppLanguage.text('CHỜ DUYỆT NGHIỆM THU', 'PENDING APPROVAL'),
                count: submittedList.length,
                color: const Color(0xFF6750A4),
                icon: Icons.rate_review_rounded,
              ),
              ...submittedList.map(
                (reminder) => ReminderCard(
                  reminder: reminder,
                  currentUserId: currentUserId,
                  familyName:
                      showFamilyBadge ? resolveFamilyName(reminder) : null,
                  showFamilyBadge: showFamilyBadge,
                  onTap: () => onTapReminder(reminder),
                  onDelete: canDelete(reminder)
                      ? () => onDeleteReminder(reminder)
                      : null,
                ),
              ),
            ],

            // 2. Nhóm Việc chung chưa gán ai
            if (openList.isNotEmpty) ...[
              ReminderSectionHeader(
                title: AppLanguage.text(
                    'VIỆC CHUNG CHƯA GÁN', 'UNASSIGNED SHARED'),
                count: openList.length,
                color: const Color(0xFF006A6A),
                icon: Icons.lock_open_rounded,
              ),
              ...openList.map(
                (reminder) => ReminderCard(
                  reminder: reminder,
                  currentUserId: currentUserId,
                  familyName:
                      showFamilyBadge ? resolveFamilyName(reminder) : null,
                  showFamilyBadge: showFamilyBadge,
                  onTap: () => onTapReminder(reminder),
                  onComplete: reminder.assignedTo == currentUserId
                      ? () => onCompleteReminder(reminder)
                      : null,
                  onDelete: canDelete(reminder)
                      ? () => onDeleteReminder(reminder)
                      : null,
                  onClaim: () => onClaimReminder(reminder),
                  onClaimAndComplete: onClaimAndCompleteReminder != null
                      ? () => onClaimAndCompleteReminder!(reminder)
                      : null,
                ),
              ),
            ],

            // 3. Nhóm Việc chờ thực hiện
            if (pendingList.isNotEmpty) ...[
              ReminderSectionHeader(
                title: AppLanguage.text('CHỜ THỰC HIỆN', 'PENDING'),
                count: pendingList.length,
                color: const Color(0xFF49454F),
                icon: Icons.hourglass_top_rounded,
              ),
              ...pendingList.map(
                (reminder) => ReminderCard(
                  reminder: reminder,
                  currentUserId: currentUserId,
                  familyName:
                      showFamilyBadge ? resolveFamilyName(reminder) : null,
                  showFamilyBadge: showFamilyBadge,
                  onTap: () => onTapReminder(reminder),
                  onComplete: reminder.assignedTo == currentUserId
                      ? () => onCompleteReminder(reminder)
                      : null,
                  onDelete: canDelete(reminder)
                      ? () => onDeleteReminder(reminder)
                      : null,
                  onClaim: reminder.isOpenTask
                      ? () => onClaimReminder(reminder)
                      : null,
                  onClaimAndComplete:
                      reminder.isOpenTask && onClaimAndCompleteReminder != null
                          ? () => onClaimAndCompleteReminder!(reminder)
                          : null,
                ),
              ),
            ],

            // 4. Nhóm Việc đã hoàn thành
            if (completedList.isNotEmpty) ...[
              ReminderSectionHeader(
                title: AppLanguage.text('ĐÃ HOÀN THÀNH', 'COMPLETED'),
                count: completedList.length,
                color: const Color(0xFF005F50),
                icon: Icons.check_circle_outline_rounded,
              ),
              ...completedList.map(
                (reminder) => ReminderCard(
                  reminder: reminder,
                  currentUserId: currentUserId,
                  familyName:
                      showFamilyBadge ? resolveFamilyName(reminder) : null,
                  showFamilyBadge: showFamilyBadge,
                  onTap: () => onTapReminder(reminder),
                  onDelete: canDelete(reminder)
                      ? () => onDeleteReminder(reminder)
                      : null,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

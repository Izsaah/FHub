import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/ai_speech_service.dart';
import '../services/member_color_helper.dart';
import '../services/reminder_repository.dart';
import '../services/star_economy_service.dart';
import '../screens/create_reminder_screen.dart';
import 'camera_proof_dialog.dart';
import 'member_picker_bottom_sheet.dart';
import 'parent_triage_actions_widget.dart';
import 'voice_reminder_player.dart';

/// Hộp thoại hiển thị chi tiết lời nhắc (Việt hóa 100%, tương thích mọi kích thước màn hình)
class ReminderDetailBottomSheet extends StatelessWidget {
  final ReminderModel reminder;
  final String currentUserId;
  final String currentUserName;
  final String? familyName;
  final ReminderRepository repository;
  final List<FamilyMember> familyMembers;
  final VoidCallback? onReminderUpdated;
  final StarEconomyService? starEconomyService;

  const ReminderDetailBottomSheet({
    super.key,
    required this.reminder,
    required this.currentUserId,
    this.currentUserName = 'Tôi',
    this.familyName,
    required this.repository,
    this.familyMembers = const [],
    this.onReminderUpdated,
    this.starEconomyService,
  });

  StarEconomyService get _starEconomyService =>
      starEconomyService ?? StarEconomyService.instance;

  static Future<void> show(
    BuildContext context, {
    required ReminderModel reminder,
    required String currentUserId,
    String currentUserName = 'Tôi',
    String? familyName,
    required ReminderRepository repository,
    List<FamilyMember> familyMembers = const [],
    VoidCallback? onReminderUpdated,
    StarEconomyService? starEconomyService,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReminderDetailBottomSheet(
        reminder: reminder,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        familyName: familyName,
        repository: repository,
        familyMembers: familyMembers,
        onReminderUpdated: onReminderUpdated,
        starEconomyService: starEconomyService,
      ),
    );
  }

  bool get isAssignedToMe => reminder.assignedTo == currentUserId;

  bool get canComplete =>
      !reminder.isCompleted &&
      !reminder.isDeleted &&
      !reminder.isClosedMissed &&
      isAssignedToMe &&
      reminder.canBeCompleted;

  bool get isLockedCompletion =>
      !reminder.isCompleted &&
      !reminder.isDeleted &&
      !reminder.isClosedMissed &&
      isAssignedToMe &&
      reminder.isFutureDate;

  bool get canDelete {
    if (reminder.creatorId == currentUserId) return true;
    final currentMember = familyMembers.firstWhere(
      (m) => m.id == currentUserId,
      orElse: () =>
          const FamilyMember(id: '', name: '', role: '', familyId: ''),
    );
    return currentMember.isParent || currentMember.isGrandparent;
  }

  bool get canEdit {
    if (reminder.creatorId == currentUserId) return true;
    final currentMember = familyMembers.firstWhere(
      (m) => m.id == currentUserId,
      orElse: () =>
          const FamilyMember(id: '', name: '', role: '', familyId: ''),
    );
    final roleUpper = currentMember.role.toUpperCase();
    return roleUpper.contains('PARENT') ||
        roleUpper.contains('OWNER') ||
        roleUpper.contains('GRANDPARENT');
  }

  bool get isGuardian {
    final currentMember = familyMembers.firstWhere(
      (m) => m.id == currentUserId,
      orElse: () =>
          const FamilyMember(id: '', name: '', role: '', familyId: ''),
    );
    if (currentMember.id.isNotEmpty) {
      return currentMember.isGuardian && !currentMember.isRelative;
    }
    final roleUpper = currentMember.role.toUpperCase();
    return (currentMember.isParent ||
            currentMember.isGrandparent ||
            roleUpper.contains('PARENT') ||
            roleUpper.contains('OWNER') ||
            roleUpper.contains('GRANDPARENT')) &&
        !currentMember.isRelative;
  }

  Future<void> _showRejectionDialog(BuildContext context) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.replay_rounded, color: Color(0xFFBA1A1A)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLanguage.text('Yêu cầu làm lại việc', 'Require Task Redo'),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLanguage.text(
                'Nhập lý do chưa đạt để con biết cần hoàn thiện gì nhé:',
                'Enter reason why submission was not accepted:',
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: AppLanguage.text(
                  'Ví dụ: Bát đĩa còn bẩn, chưa lau bàn...',
                  'e.g. Dishes still dirty...',
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: const Color(0xFFF9F9F9),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(AppLanguage.text('Hủy', 'Cancel')),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFBA1A1A)),
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(dCtx, true);
            },
            child: Text(AppLanguage.text('Gửi yêu cầu', 'Submit')),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await repository.rejectTaskSubmission(
          taskId: reminder.id,
          reason: controller.text.trim(),
        );
        if (context.mounted) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                AppLanguage.text(
                  'Đã gửi yêu cầu làm lại cho ${reminder.assignedToName}',
                  'Redo request sent to ${reminder.assignedToName}',
                ),
              ),
              backgroundColor: const Color(0xFFBA1A1A),
            ),
          );
          onReminderUpdated?.call();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e.toString()),
                backgroundColor: const Color(0xFFBA1A1A)),
          );
        }
      }
    }
  }

  Future<void> _handleChildSubmitProof(BuildContext context) async {
    if (reminder.isClosedMissed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Công việc này đã đóng bỏ lỡ, không thể nộp ảnh nghiệm thu!',
              'This task is closed and cannot submit proof!',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }
    final proofUrl = await CameraProofDialog.show(
      context,
      reminder: reminder,
      currentUserName: currentUserName,
    );
    if (proofUrl == null) return;

    try {
      HapticFeedback.mediumImpact();
      await repository.submitTaskWithProof(
        taskId: reminder.id,
        proofImageUrl: proofUrl,
      );
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                '📸 Đã nộp ảnh nghiệm thu! Đang chờ Bố Mẹ/Ông Bà duyệt sao.',
                '📸 Proof submitted! Waiting for Guardian approval and stars.',
              ),
            ),
            backgroundColor: const Color(0xFF0D7A68),
          ),
        );
        onReminderUpdated?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: const Color(0xFFBA1A1A)),
        );
      }
    }
  }

  Future<void> _handleApproveSubmission(BuildContext context) async {
    // 1. Pre-flight check: Non-guardian approval
    final bool isTaskCreator = reminder.creatorId == currentUserId;
    if (!isGuardian && !isTaskCreator) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Chỉ Người giám hộ (Bố Mẹ/Ông Bà) mới có quyền duyệt việc và thưởng sao!',
              'Only Guardians (Parents/Grandparents) can approve tasks and award stars!',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    // 2. Pre-flight check: Self-awarding (cannot approve task assigned to oneself)
    if (reminder.assignedTo == currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Bạn không thể tự duyệt việc của chính mình!',
              'You cannot self-approve your own task!',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    // 3. Pre-flight check: Self-creation & self-approval farming
    if (reminder.creatorId == currentUserId && reminder.assignedTo == currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Người tạo việc không thể tự giao việc rồi tự duyệt để nhận sao!',
              'Task creators cannot self-assign and self-approve to receive stars!',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    try {
      HapticFeedback.heavyImpact();

      // Seed task into in-memory star service if not already present (for test resilience)
      final starService = _starEconomyService;
      if (starService.reminders[reminder.id] == null) {
        starService.seedTask(reminder.id, {
          'familyId': reminder.familyId,
          'assignedTo': reminder.assignedTo,
          'creatorId': reminder.creatorId,
          'status': 'SUBMITTED',
          'taskStatus': 'SUBMITTED',
          'rewardStars': reminder.rewardStars,
        });
      }

      // 1. Execute atomic approval with idempotent double-award protection
      await starService.approveTaskWithDoubleAwardProtection(
        taskId: reminder.id,
        reviewerId: currentUserId,
        reviewerName: currentUserName,
        familyId: reminder.familyId,
        childId: reminder.assignedTo,
        stars: reminder.rewardStars,
        creatorId: reminder.creatorId,
        isGuardian: isGuardian,
        familyMembers: familyMembers,
      );

      // 2. Synchronize reminder repository state
      await repository.approveTaskSubmission(
        taskId: reminder.id,
        reviewerId: currentUserId,
        reviewerName: currentUserName,
      );

      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              reminder.rewardStars > 0
                  ? AppLanguage.text(
                      '🎉 Đã duyệt đạt và thưởng ${reminder.rewardStars}⭐ cho ${reminder.assignedToName}!',
                      '🎉 Approved and awarded ${reminder.rewardStars}⭐ to ${reminder.assignedToName}!',
                    )
                  : AppLanguage.text(
                      '🎉 Đã duyệt đạt công việc!', '🎉 Task approved!'),
            ),
            backgroundColor: const Color(0xFF0D7A68),
          ),
        );
        onReminderUpdated?.call();
      }
    } on DoubleApprovalException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
        onReminderUpdated?.call();
      }
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  Future<void> _handleAcceptFavor(BuildContext context) async {
    try {
      HapticFeedback.mediumImpact();
      await repository.acceptFavorTask(reminder.id);
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                  '💙 Bạn đã đồng ý giúp lời nhờ này!', '💙 Favor accepted!'),
            ),
            backgroundColor: const Color(0xFF0277BD),
          ),
        );
        onReminderUpdated?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: const Color(0xFFBA1A1A)),
        );
      }
    }
  }

  Future<void> _handleDeclineFavor(BuildContext context) async {
    try {
      HapticFeedback.lightImpact();
      await repository.declineFavorTask(reminder.id);
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                  'Đã từ chối lời nhờ lịch sự.', 'Politely declined favor.'),
            ),
            backgroundColor: const Color(0xFF6E7A75),
          ),
        );
        onReminderUpdated?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: const Color(0xFFBA1A1A)),
        );
      }
    }
  }

  Future<void> _handleDelegateFavor(BuildContext context) async {
    final childMembers = familyMembers.where((m) => m.isChild).toList();
    if (childMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Không có thành viên con cái trong gia đình để chuyển tiếp.',
              'No children members found in family to delegate.',
            ),
          ),
        ),
      );
      return;
    }

    final selectedChild = await MemberPickerBottomSheet.show(
      context,
      familyMembers: childMembers,
    );
    if (selectedChild == null || !context.mounted) return;

    try {
      await repository.delegateFavorTask(
        taskId: reminder.id,
        delegatedToUserId: selectedChild.id,
        delegatedToUserName: selectedChild.name,
        currentUserId: currentUserId,
        currentUserRole: 'Parent',
        targetUserRole: 'Child',
      );
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                'Đã chuyển tiếp lời nhờ tới ${selectedChild.name}!',
                'Favor delegated to ${selectedChild.name}!',
              ),
            ),
            backgroundColor: const Color(0xFF005F50),
          ),
        );
        onReminderUpdated?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: const Color(0xFFBA1A1A)),
        );
      }
    }
  }

  Future<void> _handleComplete(BuildContext context) async {
    if (reminder.isClosedMissed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Công việc này đã đóng bỏ lỡ, không thể hoàn thành!',
              'This task is closed and cannot be completed!',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }
    if (reminder.isFutureDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Công việc này chỉ có thể hoàn thành vào đúng ngày hẹn (${reminder.date})!',
              'This task can only be completed on its scheduled date (${reminder.date})!',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    try {
      String? proofUrl;
      if (reminder.requiresProofImage) {
        proofUrl = await CameraProofDialog.show(
          context,
          reminder: reminder,
          currentUserName: currentUserName,
        );
        if (proofUrl == null) {
          return;
        }
      }

      HapticFeedback.mediumImpact();
      await repository.completeReminder(
        reminderId: reminder.id,
        currentUserId: currentUserId,
        proofImageUrl: proofUrl,
      );

      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                '🎉 Đã hoàn thành công việc!',
                '🎉 Task completed successfully!',
              ),
            ),
            backgroundColor: const Color(0xFF0D7A68),
            duration: const Duration(seconds: 3),
          ),
        );
        onReminderUpdated?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  Future<void> _handleClaim(BuildContext context) async {
    try {
      HapticFeedback.mediumImpact();

      // Kiểm tra xung đột lịch của chính mình trước khi nhận việc
      final conflict = await repository.checkScheduleConflict(
        userId: currentUserId,
        date: reminder.date,
        time: reminder.time,
        excludeReminderId: reminder.id,
      );
      if (conflict != null && context.mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (cCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLanguage.text('Cảnh Báo Trùng Giờ', 'Schedule Conflict'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              AppLanguage.text(
                'Bạn đã có công việc "${conflict.title}"${conflict.familyName != null ? ' tại ${conflict.familyName}' : ''} vào lúc ${reminder.time} ngày ${reminder.date}.\n\nBạn có chắc chắn muốn nhận thêm công việc này?',
                'You already have task "${conflict.title}" at ${reminder.time} on ${reminder.date}.\n\nDo you still want to claim this task?',
              ),
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(cCtx, false),
                child: Text(AppLanguage.text('Hủy', 'Cancel')),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D7A68),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(cCtx, true),
                child: Text(AppLanguage.text('Vẫn nhận việc', 'Proceed')),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }

      await repository.claimOpenTask(
        reminderId: reminder.id,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
      );
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                '🎉 Bạn đã xung phong nhận việc "${reminder.title}" thành công!',
                '🎉 Successfully claimed "${reminder.title}"!',
              ),
            ),
            backgroundColor: const Color(0xFF0D7A68),
          ),
        );
        onReminderUpdated?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  Future<void> _handleClaimAndComplete(BuildContext context) async {
    if (reminder.isFutureDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Công việc này lên lịch cho ngày ${reminder.date}. Bạn có thể nhận việc trước, nhưng chỉ được đánh dấu hoàn thành vào đúng ngày!',
              'This task is scheduled for ${reminder.date}. You can claim it now, but can only complete it on that day!',
            ),
          ),
          backgroundColor: const Color(0xFF455A64),
        ),
      );
      return;
    }

    try {
      String? proofUrl;
      if (reminder.requiresProofImage) {
        proofUrl = await CameraProofDialog.show(
          context,
          reminder: reminder,
          currentUserName: currentUserName,
        );
        if (proofUrl == null) {
          return;
        }
      }

      HapticFeedback.heavyImpact();
      await repository.claimOpenTask(
        reminderId: reminder.id,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
      );

      await repository.completeReminder(
        reminderId: reminder.id,
        currentUserId: currentUserId,
        proofImageUrl: proofUrl,
      );

      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                '🎉 Đã nhận & hoàn thành việc "${reminder.title}"!',
                '🎉 Claimed and completed "${reminder.title}"!',
              ),
            ),
            backgroundColor: const Color(0xFF0D7A68),
          ),
        );
        onReminderUpdated?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          AppLanguage.text('Xóa lời nhắc?', 'Delete reminder?'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          AppLanguage.text(
            'Bạn có chắc chắn muốn xóa lời nhắc "${reminder.title}"? (Hành động này có thể hoàn tác trong 10 giây).',
            'Are you sure you want to delete "${reminder.title}"? (This action can be undone within 10 seconds).',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(AppLanguage.text('Hủy', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(AppLanguage.text('Xóa', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
      try {
        await repository.deleteReminder(
          reminderId: reminder.id,
          currentUserId: currentUserId,
          familyMembers: familyMembers,
        );

        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            content: Text(
              AppLanguage.text(
                'Đã xóa "${reminder.title}".',
                'Deleted "${reminder.title}".',
              ),
            ),
            action: SnackBarAction(
              label: AppLanguage.text('HOÀN TÁC', 'UNDO'),
              textColor: const Color(0xFFaaffe9),
              onPressed: () async {
                try {
                  await repository.restoreReminder(
                    reminderId: reminder.id,
                    currentUserId: currentUserId,
                    familyMembers: familyMembers,
                  );
                  onReminderUpdated?.call();
                } catch (_) {}
              },
            ),
          ),
        );
        onReminderUpdated?.call();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  Future<void> _handleEdit(BuildContext context) async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateReminderScreen(
          familyId: reminder.familyId,
          familyName: familyName,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          familyMembers: familyMembers,
          repository: repository,
          existingReminder: reminder,
        ),
      ),
    );
    onReminderUpdated?.call();
  }

  Widget _buildProofImage(
    String imageUrl, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (imageUrl.startsWith('data:image/')) {
      try {
        final commaIdx = imageUrl.indexOf(',');
        final b64 =
            commaIdx != -1 ? imageUrl.substring(commaIdx + 1) : imageUrl;
        final bytes = base64Decode(b64);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => Container(
            height: height ?? 120,
            width: width,
            color: const Color(0xFFE0F2EC),
            alignment: Alignment.center,
            child: Text(
              AppLanguage.text(
                'Không thể tải ảnh nghiệm thu',
                'Unable to load proof photo',
              ),
            ),
          ),
        );
      } catch (_) {}
    }
    if (imageUrl.startsWith('http://') ||
        imageUrl.startsWith('https://') ||
        imageUrl.startsWith('blob:')) {
      return Image.network(
        imageUrl,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Container(
          height: height ?? 120,
          width: width,
          color: const Color(0xFFE0F2EC),
          alignment: Alignment.center,
          child: Text(
            AppLanguage.text(
              'Ảnh nghiệm thu đã lưu',
              'Proof photo saved',
            ),
          ),
        ),
      );
    }
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        height: height,
        width: width,
        fit: fit,
      );
    }
    if (!kIsWeb) {
      return Image.file(
        File(imageUrl),
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Container(
          height: height ?? 120,
          width: width,
          color: const Color(0xFFE0F2EC),
          alignment: Alignment.center,
          child: Text(
            AppLanguage.text(
              'Ảnh nghiệm thu đã lưu',
              'Proof photo saved',
            ),
          ),
        ),
      );
    }
    return Container(
      height: height ?? 120,
      width: width,
      color: const Color(0xFFE0F2EC),
      alignment: Alignment.center,
      child: Text(
        AppLanguage.text(
          'Ảnh nghiệm thu đã lưu',
          'Proof photo saved',
        ),
      ),
    );
  }

  void _showProofPreview(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: _buildProofImage(imageUrl, fit: BoxFit.contain),
                ),
                Container(
                  color: const Color(0xFF1B2321),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          AppLanguage.text(
                            '📸 Bằng chứng nghiệm thu',
                            '📸 Verification Proof Photo',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        const primaryColor = Color(0xFF0D7A68);
        final isCompleted = reminder.isCompleted;
        final isOpenTask = reminder.isOpenTask;
        final screenSize = MediaQuery.of(context).size;
        final horizontalPad = screenSize.width < 360 ? 16.0 : 24.0;

        return Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: screenSize.height * 0.90,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding:
                  EdgeInsets.fromLTRB(horizontalPad, 16, horizontalPad, 28),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Thanh kéo mở
                      Center(
                        child: Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Chế độ chăm sóc Ông Bà banner
                      if (reminder.isCare) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFFFFB74D), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.health_and_safety_rounded,
                                  color: Color(0xFFE65100), size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLanguage.text(
                                          'CHẾ ĐỘ CHĂM SÓC ÔNG BÀ',
                                          'ELDERLY CARE MODE'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFE65100),
                                      ),
                                    ),
                                    Text(
                                      AppLanguage.text(
                                        'Trợ năng chữ to, âm thanh đọc to & miễn trừ giờ yên tĩnh.',
                                        'Large typography, loud TTS & quiet hours exemption.',
                                      ),
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF8D3B00)),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFFE65100)),
                                icon: const Icon(Icons.volume_up_rounded,
                                    color: Colors.white, size: 22),
                                tooltip: AppLanguage.text(
                                    'Đọc to lời nhắc', 'Speak aloud'),
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  AiSpeechPlatform.instance.speak(
                                    "Kính mời Ông Bà: ${reminder.title}",
                                    isEnglish: false,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Banner thông báo yêu cầu làm lại
                      if (reminder.rejectionReason != null &&
                          reminder.rejectionReason!.isNotEmpty &&
                          !isCompleted) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: const Color(0xFFFFCDD2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: Color(0xFFBA1A1A), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLanguage.text(
                                        'Yêu cầu làm lại từ người lớn:',
                                        'Redo requested by Guardian:',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFBA1A1A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      reminder.rejectionReason!,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF7F0000)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Tiêu đề & nút Sửa / Xóa
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reminder.title,
                                  style: TextStyle(
                                    fontSize: reminder.isCare ? 24 : 22,
                                    fontWeight: reminder.isCare
                                        ? FontWeight.w800
                                        : FontWeight.bold,
                                    color: isCompleted
                                        ? Colors.grey.shade600
                                        : (reminder.isCare
                                            ? const Color(0xFF2E1500)
                                            : const Color(0xFF151D1B)),
                                    decoration: isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (reminder.creatorName != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    AppLanguage.text(
                                      'Giao bởi: ${reminder.creatorName}',
                                      'Assigned by: ${reminder.creatorName}',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6E7A75),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (canEdit && !isCompleted)
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: Color(0xFF0D7A68)),
                              tooltip: AppLanguage.text(
                                'Chỉnh sửa lời nhắc',
                                'Edit reminder',
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _handleEdit(context),
                            ),
                          if (canDelete)
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Color(0xFFBA1A1A)),
                              tooltip: AppLanguage.text(
                                'Xóa lời nhắc',
                                'Delete reminder',
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _handleDelete(context),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Chi tiết: Gia đình, Người nhận, Giờ, Ngày, Lặp lại, Nghiệm thu, Trạng thái
                      _buildDetailRow(
                        icon: Icons.home_work_outlined,
                        label: AppLanguage.text('Gia đình', 'Family'),
                        valueWidget: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE4F6EF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.home_rounded,
                                size: 15,
                                color: Color(0xFF005F50),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  (familyName != null &&
                                          familyName!.trim().isNotEmpty)
                                      ? familyName!.trim()
                                      : ((reminder.familyName != null &&
                                              reminder.familyName!
                                                  .trim()
                                                  .isNotEmpty)
                                          ? reminder.familyName!.trim()
                                          : (reminder.familyId.isNotEmpty
                                              ? reminder.familyId
                                              : AppLanguage.text(
                                                  'Gia đình của tôi',
                                                  'My Family',
                                                ))),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF005F50),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        icon: Icons.person_outline,
                        label: AppLanguage.text('Giao cho', 'Assignee'),
                        valueWidget: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isOpenTask
                                ? const Color(0xFFE0F7FA)
                                : MemberColorHelper.getBackgroundColor(
                                    reminder.assignedToName),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isOpenTask)
                                const Icon(Icons.groups_rounded,
                                    size: 14, color: Color(0xFF00796B))
                              else
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor:
                                      MemberColorHelper.getPrimaryColor(
                                          reminder.assignedToName),
                                  child: Text(
                                    reminder.assignedToName.isNotEmpty
                                        ? reminder.assignedToName[0]
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  isOpenTask
                                      ? AppLanguage.text(
                                          '👨‍👩‍👧 Cả nhà (Việc chung)',
                                          '👨‍👩‍👧 All Family (Shared)',
                                        )
                                      : reminder.assignedToName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isOpenTask
                                        ? const Color(0xFF00796B)
                                        : MemberColorHelper.getPrimaryColor(
                                            reminder.assignedToName),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        icon: Icons.access_time,
                        label: AppLanguage.text('Giờ', 'Time'),
                        value: reminder.time,
                      ),
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        icon: Icons.calendar_today_outlined,
                        label: AppLanguage.text('Ngày', 'Date'),
                        value: reminder.displayDate,
                      ),
                      if (reminder.isRecurring) ...[
                        const SizedBox(height: 10),
                        _buildDetailRow(
                          icon: Icons.repeat_rounded,
                          label: AppLanguage.text('Lặp lại', 'Repeat'),
                          value: reminder.repeatRule == 'DAILY'
                              ? AppLanguage.text('Hàng ngày', 'Daily')
                              : AppLanguage.text('Hàng tuần', 'Weekly'),
                        ),
                      ],
                      if (reminder.requiresProofImage) ...[
                        const SizedBox(height: 10),
                        _buildDetailRow(
                          icon: Icons.camera_alt_outlined,
                          label: AppLanguage.text('Nghiệm thu', 'Proof photo'),
                          valueWidget: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: reminder.hasProofImage
                                  ? const Color(0xFFE8F5E9)
                                  : const Color(0xFFEDE7F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              reminder.hasProofImage
                                  ? AppLanguage.text(
                                      '✅ Đã có ảnh nghiệm thu',
                                      '✅ Proof photo attached',
                                    )
                                  : AppLanguage.text(
                                      '📸 Bắt buộc chụp ảnh hoàn thành',
                                      '📸 Completion photo required',
                                    ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: reminder.hasProofImage
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFF5E35B1),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        icon: Icons.info_outline,
                        label: AppLanguage.text('Trạng thái', 'Status'),
                        valueWidget: _buildStatusBadge(reminder),
                      ),

                      // Xem ảnh nghiệm thu
                      if (reminder.hasProofImage) ...[
                        const SizedBox(height: 16),
                        Text(
                          AppLanguage.text(
                            'Ảnh bằng chứng nghiệm thu hoàn thành:',
                            'Completion verification proof photo:',
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF151D1B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _showProofPreview(
                              context, reminder.proofImageUrl!),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                _buildProofImage(
                                  reminder.proofImageUrl!,
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                                Container(
                                  margin: const EdgeInsets.all(10),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.zoom_in,
                                          color: Colors.white, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        AppLanguage.text('Phóng to', 'Zoom in'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // Lời nhắc giọng nói
                      if (reminder.hasVoiceNote) ...[
                        const SizedBox(height: 16),
                        Text(
                          AppLanguage.text(
                            'Lời nhắc giọng nói:',
                            'Voice Reminder:',
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF151D1B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        VoiceReminderPlayer(
                          reminder: reminder,
                          isCompact: false,
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Nút hành động: Xung phong nhận việc / Hoàn thành
                      if (reminder.isClosedMissed)
                        Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.lock_rounded, color: Color(0xFF64748B), size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  AppLanguage.text('Đã đóng (Bỏ lỡ hạn)', 'Closed (Missed deadline)'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (isOpenTask && !isCompleted) ...[
                        if (reminder.isFutureDate) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECEFF1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0xFFCFD8DC)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_clock_rounded,
                                    color: Color(0xFF455A64), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    AppLanguage.text(
                                      'Công việc này lên lịch cho ngày ${reminder.date}. Bạn có thể nhận việc trước, nhưng chỉ được đánh dấu hoàn thành vào đúng ngày!',
                                      'This task is scheduled for ${reminder.date}. You can claim it now, but can only complete it on that day!',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF455A64),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF005F50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.front_hand_rounded,
                                  size: 20),
                              label: Text(
                                AppLanguage.text(
                                  'Nhận việc trước',
                                  'Claim task in advance',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () => _handleClaim(context),
                            ),
                          ),
                        ] else ...[
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF005F50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: Icon(
                                reminder.requiresProofImage
                                    ? Icons.camera_alt_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 22,
                              ),
                              label: Text(
                                reminder.requiresProofImage
                                    ? AppLanguage.text(
                                        'Làm ngay & Chụp ảnh',
                                        'Do now & Take photo',
                                      )
                                    : AppLanguage.text(
                                        'Làm ngay & Hoàn thành',
                                        'Do now & Complete',
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () =>
                                  _handleClaimAndComplete(context),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF005F50),
                                side:
                                    const BorderSide(color: Color(0xFF005F50)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.front_hand_rounded,
                                  size: 20),
                              label: Text(
                                AppLanguage.text(
                                  'Nhận việc để làm sau',
                                  'Claim task for later',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () => _handleClaim(context),
                            ),
                          ),
                        ],
                      ] else if (reminder.taskType == TaskType.care) ...[
                        if (isCompleted)
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F0EC),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle, color: primaryColor),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    AppLanguage.text('Đã hoàn thành', 'Completed'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Row(
                            children: [
                              IconButton.filledTonal(
                                icon: const Icon(Icons.volume_up_rounded),
                                tooltip: 'Nghe đọc to',
                                onPressed: () {
                                  AiSpeechPlatform.instance.speak(
                                    "Kính mời Ông Bà: ${reminder.title}",
                                    isEnglish: false,
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFE65100),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    icon: const Icon(Icons.check_circle_outline, size: 22),
                                    label: const Text(
                                      'Đã uống thuốc / Đã xong việc',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () => _handleComplete(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ] else if (reminder.taskType == TaskType.favor) ...[
                        if (isCompleted)
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F0EC),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle, color: primaryColor),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    AppLanguage.text('Đã giúp xong việc', 'Completed favor'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (reminder.taskStatus == TaskStatus.declined)
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              AppLanguage.text('Đã từ chối lời nhờ vả', 'Favor declined'),
                              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
                            ),
                          )
                        else if (canComplete && reminder.taskStatus == TaskStatus.accepted)
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF00796B),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.check_circle_outline, size: 22),
                              label: Text(
                                AppLanguage.text('Đã giúp xong việc', 'Completed favor'),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              onPressed: () => _handleComplete(context),
                            ),
                          )
                        else if (canComplete && reminder.taskStatus == TaskStatus.pending) ...[
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                      side: BorderSide(color: Colors.red.shade300),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () => _handleDeclineFavor(context),
                                    child: Text(AppLanguage.text('Từ chối bận', 'Decline')),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF00796B),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () => _handleAcceptFavor(context),
                                    child: Text(AppLanguage.text('Đồng ý giúp', 'Accept')),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isGuardian && reminder.delegationCount == 0) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                icon: const Icon(Icons.forward_rounded, size: 20),
                                label: Text(AppLanguage.text('Chuyển tiếp cho con', 'Delegate to child')),
                                onPressed: () => _handleDelegateFavor(context),
                              ),
                            ),
                          ],
                        ] else if (isGuardian && reminder.delegationCount == 0) ...[
                          SizedBox(
                            height: 48,
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.forward_rounded, size: 20),
                              label: Text(AppLanguage.text('Chuyển tiếp cho con', 'Delegate to child')),
                              onPressed: () => _handleDelegateFavor(context),
                            ),
                          ),
                        ] else ...[
                          Text(
                            AppLanguage.text(
                              'Chỉ ${reminder.assignedToName} mới có thể thực hiện',
                              'Only ${reminder.assignedToName} can perform this action',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ] else ...[
                        // ASSIGN task
                        if (isCompleted)
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F0EC),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle, color: primaryColor),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    AppLanguage.text('Đã hoàn thành', 'Completed'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (reminder.isClosedMissed)
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.lock_rounded, color: Color(0xFF64748B)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    AppLanguage.text('Đã đóng (Bỏ lỡ hạn)', 'Closed (Missed deadline)'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (reminder.taskStatus == TaskStatus.submitted) ...[
                          if ((isGuardian || reminder.creatorId == currentUserId) && reminder.assignedTo != currentUserId)
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orange.shade800,
                                        side: BorderSide(color: Colors.orange.shade400),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      icon: const Icon(Icons.replay_rounded, size: 20),
                                      label: Text(
                                        AppLanguage.text('Yêu cầu làm lại', 'Reject & redo'),
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      onPressed: () => _showRejectionDialog(context),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      icon: const Icon(Icons.star_rounded, size: 20),
                                      label: Text(
                                        AppLanguage.text('Duyệt đạt & Thưởng sao', 'Approve & reward'),
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      onPressed: () => _handleApproveSubmission(context),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else if (reminder.assignedTo == currentUserId)
                            Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.amber.shade300),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                AppLanguage.text('Bạn không thể tự duyệt việc của chính mình', 'You cannot self-approve your own task'),
                                style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                              ),
                            )
                          else
                            Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                AppLanguage.text('Đang chờ phụ huynh duyệt ảnh...', 'Waiting for parent review...'),
                                style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ] else if (canComplete && (reminder.requiresProofImage || reminder.taskStatus == TaskStatus.rejected)) ...[
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.camera_alt_rounded, size: 22),
                              label: Text(
                                AppLanguage.text(
                                  'Chụp ảnh nộp việc',
                                  'Take photo & submit',
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () => _handleChildSubmitProof(context),
                            ),
                          ),
                        ] else if (canComplete)
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: Icon(
                                reminder.requiresProofImage
                                    ? Icons.camera_alt_rounded
                                    : Icons.check,
                                size: 22,
                              ),
                              label: Text(
                                reminder.requiresProofImage
                                    ? AppLanguage.text(
                                        'Chụp ảnh nghiệm thu & Hoàn thành',
                                        'Take photo proof & Complete',
                                      )
                                    : AppLanguage.text(
                                        'Đánh dấu đã hoàn thành',
                                        'Mark completed',
                                      ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () => _handleComplete(context),
                            ),
                          )
                        else if (isLockedCompletion)
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFBDC9C4),
                                foregroundColor: const Color(0xFF455A64),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon:
                                  const Icon(Icons.lock_clock_rounded, size: 22),
                              label: Text(
                                AppLanguage.text(
                                  'Chưa đến ngày thực hiện (${reminder.date})',
                                  'Locked until scheduled date (${reminder.date})',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.lock_clock_rounded,
                                            color: Colors.white, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            AppLanguage.text(
                                              'Công việc này được lên lịch cho ngày ${reminder.date}. Bạn chỉ có thể đánh dấu hoàn thành khi đến đúng ngày này!',
                                              'This task is scheduled for ${reminder.date}. It can only be completed on that day!',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: const Color(0xFF455A64),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              },
                            ),
                          )
                        else if (reminder.isOverdue && !reminder.isClosedMissed && !reminder.isOpenTask && (isGuardian || reminder.creatorId == currentUserId)) ...[
                          const SizedBox(height: 8),
                          ParentTriageActionsWidget(
                            reminder: reminder,
                            onActionCompleted: () {
                              Navigator.of(context).pop();
                              onReminderUpdated?.call();
                            },
                          ),
                        ] else
                          Text(
                            AppLanguage.text(
                              'Chỉ ${reminder.assignedToName} mới có thể đánh dấu hoàn thành',
                              'Only ${reminder.assignedToName} can mark as completed',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    String? value,
    Widget? valueWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF6E7A75)),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6E7A75),
          ),
        ),
        if (value != null)
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF151D1B),
              ),
            ),
          ),
        if (valueWidget != null)
          Flexible(
            child: valueWidget,
          ),
      ],
    );
  }

  Widget _buildStatusBadge(ReminderModel reminder) {
    Color bg = const Color(0xFFFFF1E0);
    Color fg = const Color(0xFF8A5100);
    String label = AppLanguage.text('CHỜ THỰC HIỆN', 'PENDING');

    if (reminder.isClosedMissed) {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF64748B);
      label = AppLanguage.text('ĐÃ ĐÓNG (BỎ LỠ)', 'CLOSED (MISSED)');
    } else if (reminder.isCompleted) {
      bg = const Color(0xFFE7F0EC);
      fg = const Color(0xFF0D7A68);
      label = AppLanguage.text('ĐÃ HOÀN THÀNH', 'COMPLETED');
    } else if (reminder.isOverdue) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFBA1A1A);
      label = AppLanguage.text('QUÁ HẠN', 'OVERDUE');
    } else if (reminder.isOpen) {
      bg = const Color(0xFFE0F2EC);
      fg = const Color(0xFF006A6A);
      label = AppLanguage.text(
        'VIỆC CHUNG (ĐANG MỞ)',
        'SHARED TASK (OPEN)',
      );
    } else if (reminder.isPending) {
      bg = const Color(0xFFFFF1E0);
      fg = const Color(0xFF8A5100);
      label = AppLanguage.text('CHỜ THỰC HIỆN', 'PENDING');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/member_color_helper.dart';
import '../services/reminder_repository.dart';
import '../screens/create_reminder_screen.dart';
import 'camera_proof_dialog.dart';
import 'voice_reminder_player.dart';

/// Hộp thoại hiển thị chi tiết lời nhắc (Việt hóa 100%)
class ReminderDetailBottomSheet extends StatelessWidget {
  final ReminderModel reminder;
  final String currentUserId;
  final String currentUserName;
  final ReminderRepository repository;
  final List<FamilyMember> familyMembers;
  final VoidCallback? onReminderUpdated;

  const ReminderDetailBottomSheet({
    super.key,
    required this.reminder,
    required this.currentUserId,
    this.currentUserName = 'Tôi',
    required this.repository,
    this.familyMembers = const [],
    this.onReminderUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required ReminderModel reminder,
    required String currentUserId,
    String currentUserName = 'Tôi',
    required ReminderRepository repository,
    List<FamilyMember> familyMembers = const [],
    VoidCallback? onReminderUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReminderDetailBottomSheet(
        reminder: reminder,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        repository: repository,
        familyMembers: familyMembers,
        onReminderUpdated: onReminderUpdated,
      ),
    );
  }

  bool get canComplete =>
      !reminder.isCompleted &&
      !reminder.isDeleted &&
      reminder.assignedTo == currentUserId;

  bool get canDelete {
    if (reminder.creatorId == currentUserId) return true;
    final currentMember = familyMembers.firstWhere(
      (m) => m.id == currentUserId,
      orElse: () => const FamilyMember(id: '', name: '', role: '', familyId: ''),
    );
    return currentMember.isParent || currentMember.isGrandparent;
  }

  bool get canEdit => reminder.creatorId == currentUserId;

  Future<void> _handleComplete(BuildContext context) async {
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
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Đã hoàn thành công việc!'),
            backgroundColor: Color(0xFF0D7A68),
            duration: Duration(seconds: 3),
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
      await repository.claimOpenTask(
        reminderId: reminder.id,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 Bạn đã xung phong nhận việc "${reminder.title}" thành công!',
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
      await repository.claimAndCompleteOpenTask(
        reminderId: reminder.id,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        proofImageUrl: proofUrl,
      );

      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 Bạn đã hoàn thành việc chung "${reminder.title}" xuất sắc!',
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
        title: const Text(
          'Xóa lời nhắc',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Bạn có chắc chắn muốn xóa lời nhắc này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await repository.deleteReminder(
          reminderId: reminder.id,
          currentUserId: currentUserId,
          familyMembers: familyMembers,
        );
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã xóa lời nhắc thành công.'),
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
  }

  Future<void> _handleEdit(BuildContext context) async {
    Navigator.of(context).pop();
    final updated = await Navigator.of(context).push<ReminderModel>(
      MaterialPageRoute(
        builder: (ctx) => CreateReminderScreen(
          familyId: reminder.familyId,
          currentUserId: currentUserId,
          currentUserName: reminder.creatorName ?? 'Tôi',
          familyMembers: familyMembers,
          repository: repository,
          existingReminder: reminder,
        ),
      ),
    );

    if (updated != null) {
      onReminderUpdated?.call();
    }
  }

  void _showProofPreview(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200,
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: const Text('Không thể tải ảnh bằng chứng',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
              Container(
                color: const Color(0xFF1B2321),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('📸 Bằng chứng nghiệm thu',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    final isCompleted = reminder.isCompleted;
    final isOpenTask = reminder.isOpenTask;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isCompleted
                                ? Colors.grey.shade600
                                : const Color(0xFF151D1B),
                            decoration:
                                isCompleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (reminder.creatorName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Giao bởi: ${reminder.creatorName}',
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
                      tooltip: 'Chỉnh sửa lời nhắc',
                      onPressed: () => _handleEdit(context),
                    ),
                  if (canDelete)
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Color(0xFFBA1A1A)),
                      tooltip: 'Xóa lời nhắc',
                      onPressed: () => _handleDelete(context),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Chi tiết: Người nhận, Giờ, Ngày, Lặp lại, Nghiệm thu, Trạng thái
              _buildDetailRow(
                icon: Icons.person_outline,
                label: 'Giao cho',
                valueWidget: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                          backgroundColor: MemberColorHelper.getPrimaryColor(
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
                      Text(
                        isOpenTask
                            ? '👨‍👩‍👧 Cả nhà (Việc chung)'
                            : reminder.assignedToName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isOpenTask
                              ? const Color(0xFF00796B)
                              : MemberColorHelper.getPrimaryColor(
                                  reminder.assignedToName),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildDetailRow(
                icon: Icons.access_time,
                label: 'Giờ',
                value: reminder.time,
              ),
              const SizedBox(height: 10),
              _buildDetailRow(
                icon: Icons.calendar_today_outlined,
                label: 'Ngày',
                value: reminder.displayDate,
              ),
              if (reminder.isRecurring) ...[
                const SizedBox(height: 10),
                _buildDetailRow(
                  icon: Icons.repeat_rounded,
                  label: 'Lặp lại',
                  value: reminder.repeatRule == 'DAILY'
                      ? 'Hàng ngày'
                      : 'Hàng tuần',
                ),
              ],
              if (reminder.requiresProofImage) ...[
                const SizedBox(height: 10),
                _buildDetailRow(
                  icon: Icons.camera_alt_outlined,
                  label: 'Nghiệm thu',
                  valueWidget: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: reminder.hasProofImage
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFEDE7F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      reminder.hasProofImage
                          ? '✅ Đã có ảnh nghiệm thu'
                          : '📸 Bắt buộc chụp ảnh hoàn thành',
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
                label: 'Trạng thái',
                valueWidget: _buildStatusBadge(reminder),
              ),

              // Xem ảnh nghiệm thu
              if (reminder.hasProofImage) ...[
                const SizedBox(height: 16),
                const Text(
                  'Ảnh bằng chứng nghiệm thu hoàn thành:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF151D1B),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () =>
                      _showProofPreview(context, reminder.proofImageUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Image.network(
                          reminder.proofImageUrl!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 120,
                            color: const Color(0xFFE0F2EC),
                            alignment: Alignment.center,
                            child: const Text('Ảnh nghiệm thu đã lưu'),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.all(10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text('Phóng to',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
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
                const Text(
                  'Lời nhắc giọng nói:',
                  style: TextStyle(
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
              if (isOpenTask && !isCompleted) ...[
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
                          ? 'Làm ngay & Chụp ảnh'
                          : 'Làm ngay & Hoàn thành',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _handleClaimAndComplete(context),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF005F50),
                      side: const BorderSide(color: Color(0xFF005F50)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.front_hand_rounded, size: 20),
                    label: const Text(
                      'Nhận việc để làm sau',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => _handleClaim(context),
                  ),
                ),
              ]
              else if (canComplete)
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
                          ? 'Chụp ảnh nghiệm thu & Hoàn thành'
                          : 'Đánh dấu đã hoàn thành',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => _handleComplete(context),
                  ),
                )
              else if (isCompleted)
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F0EC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: primaryColor),
                      SizedBox(width: 8),
                      Text(
                        'Đã hoàn thành',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'Chỉ ${reminder.assignedToName} mới có thể đánh dấu hoàn thành',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    String? value,
    Widget? valueWidget,
  }) {
    return Row(
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
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF151D1B),
            ),
          ),
        ?valueWidget,
      ],
    );
  }

  Widget _buildStatusBadge(ReminderModel reminder) {
    Color bg = const Color(0xFFFFF1E0);
    Color fg = const Color(0xFF8A5100);
    String label = 'CHỜ THỰC HIỆN';

    if (reminder.isCompleted) {
      bg = const Color(0xFFE7F0EC);
      fg = const Color(0xFF0D7A68);
      label = 'ĐÃ HOÀN THÀNH';
    } else if (reminder.isOverdue) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFBA1A1A);
      label = 'QUÁ HẠN';
    } else if (reminder.isOpen) {
      bg = const Color(0xFFE0F2EC);
      fg = const Color(0xFF006A6A);
      label = 'VIỆC CHUNG (ĐANG MỞ)';
    } else if (reminder.isPending) {
      bg = const Color(0xFFFFF1E0);
      fg = const Color(0xFF8A5100);
      label = 'CHỜ THỰC HIỆN';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

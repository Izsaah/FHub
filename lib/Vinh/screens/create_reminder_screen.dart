import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../services/ai_speech_service.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/member_color_helper.dart';
import '../services/reminder_repository.dart';
import '../services/reminder_validator.dart';
import '../widgets/chore_reward_card.dart';
import '../widgets/member_picker_bottom_sheet.dart';
import '../widgets/voice_recorder_widget.dart';

class CreateReminderScreen extends StatefulWidget {
  final String familyId;
  final String? familyName;
  final List<FamilyOption>? families;
  final Map<String, List<FamilyMember>>? membersByFamilyId;
  final String currentUserId;
  final String currentUserName;
  final List<FamilyMember> familyMembers;
  final ReminderRepository repository;
  final ReminderModel? existingReminder;

  const CreateReminderScreen({
    super.key,
    required this.familyId,
    this.familyName,
    this.families,
    this.membersByFamilyId,
    required this.currentUserId,
    this.currentUserName = 'Me',
    required this.familyMembers,
    required this.repository,
    this.existingReminder,
  });

  bool get isEditing => existingReminder != null;

  @override
  State<CreateReminderScreen> createState() => _CreateReminderScreenState();
}

class _CreateReminderScreenState extends State<CreateReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  late String _activeFamilyId;
  late String? _activeFamilyName;
  late List<FamilyOption> _families;
  late List<FamilyMember> _activeMembers;

  FamilyMember? _selectedMember;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _selectedRepeatRule = 'NONE';
  bool _requiresProofImage = false;
  String _selectedTaskType = TaskType.assign.dbValue;
  int _rewardStars = 2;

  String? _voiceNotePath;
  int? _voiceDurationSeconds;
  String? _voiceNoteDescription;

  String? _dateTimeError;
  bool _isLoading = false;

  FamilyMember? get _currentMember {
    try {
      return _activeMembers.firstWhere(
        (m) => m.id == widget.currentUserId,
      );
    } catch (_) {
      return null;
    }
  }

  bool get _canAssignChores => _currentMember?.canAssignChores ?? true;

  void _onVoiceRecorded(String path, int durationSeconds, String description) {
    setState(() {
      _voiceNotePath = path;
      _voiceDurationSeconds = durationSeconds;
      _voiceNoteDescription = description;
      if (_titleController.text.trim().isEmpty) {
        if (description.isNotEmpty) {
          _titleController.text = description.length > 25
              ? '${description.substring(0, 25)}...'
              : description;
        } else {
          _titleController.text = AppLanguage.text(
            'Lời nhắc giọng nói 🎙️',
            'Voice reminder 🎙️',
          );
        }
      }
    });
  }

  void _onVoiceRemoved() {
    setState(() {
      _voiceNotePath = null;
      _voiceDurationSeconds = null;
      _voiceNoteDescription = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _families = widget.families != null && widget.families!.isNotEmpty
        ? FamilyOption.sortAlphabetically(widget.families!)
        : [
            FamilyOption(
              id: widget.familyId,
              name: widget.familyName ?? 'Gia đình của tôi',
            ),
          ];
    _activeFamilyId = widget.familyId;
    _activeFamilyName = widget.familyName ??
        _families
            .where((f) => f.id == widget.familyId)
            .map((f) => f.name)
            .firstOrNull;
    _activeMembers = widget.membersByFamilyId?[_activeFamilyId] ??
        List<FamilyMember>.from(widget.familyMembers);

    final existing = widget.existingReminder;

    if (existing != null) {
      _activeFamilyId = existing.familyId;
      _activeFamilyName = existing.familyName ?? _activeFamilyName;
      _activeMembers = widget.membersByFamilyId?[_activeFamilyId] ??
          List<FamilyMember>.from(widget.familyMembers);
      _titleController.text = existing.title;
      _voiceNotePath = existing.voiceNotePath;
      _voiceDurationSeconds = existing.voiceDurationSeconds;
      _voiceNoteDescription = existing.voiceNoteDescription;
      _selectedRepeatRule = existing.repeatRule ?? 'NONE';
      _requiresProofImage = existing.requiresProofImage;
      _selectedTaskType = existing.taskType.dbValue;
      _rewardStars = existing.rewardStars;

      // Parse existing date and time
      final parsedDt = existing.dueDateTime;
      if (parsedDt != null) {
        _selectedDate = DateTime(parsedDt.year, parsedDt.month, parsedDt.day);
        _selectedTime = TimeOfDay(hour: parsedDt.hour, minute: parsedDt.minute);
      } else {
        final now = DateTime.now();
        _selectedDate = DateTime(now.year, now.month, now.day);
        _selectedTime =
            TimeOfDay(hour: (now.hour + 1) % 24, minute: now.minute);
      }

      // Find matching assigned member (hoặc Open Task)
      if (existing.isOpenTask) {
        _selectedMember = const FamilyMember(
          id: 'OPEN',
          name: 'Cả nhà (Việc chung)',
          role: 'Open Task',
          familyId: '',
        );
      } else if (existing.assignedTo.isNotEmpty) {
        try {
          _selectedMember = _activeMembers.firstWhere(
            (m) => m.id == existing.assignedTo,
          );
        } catch (_) {
          _selectedMember = FamilyMember(
            id: existing.assignedTo,
            name: existing.assignedToName,
            role: 'Thành viên',
            familyId: _activeFamilyId,
          );
        }
      }
    } else {
      // Create mode
      final now = DateTime.now();
      _selectedDate = DateTime(now.year, now.month, now.day);
      _selectedTime =
          TimeOfDay(hour: (now.hour + 1) % 24, minute: now.minute);

      // Default assigned to: Người khác (nếu là Parent), hoặc chính mình (nếu là Child/Thành viên)
      if (_canAssignChores) {
        _selectedTaskType = TaskType.assign.dbValue;
        _rewardStars = 2;
        final otherMember = _activeMembers.firstWhere(
          (m) => m.id != widget.currentUserId,
          orElse: () => _activeMembers.isNotEmpty
              ? _activeMembers.first
              : FamilyMember(
                  id: widget.currentUserId,
                  name: widget.currentUserName,
                  role: 'Bố/Mẹ',
                  familyId: _activeFamilyId,
                ),
        );
        _selectedMember = otherMember;
      } else {
        _selectedTaskType = TaskType.favor.dbValue;
        _rewardStars = 0;
        _selectedMember = _activeMembers.firstWhere(
          (m) => m.id == widget.currentUserId,
          orElse: () => FamilyMember(
            id: widget.currentUserId,
            name: widget.currentUserName,
            role: 'Thành viên',
            familyId: _activeFamilyId,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _validateDateTime() {
    if (_selectedDate == null || _selectedTime == null) {
      setState(() {
        _dateTimeError = AppLanguage.text(
          'Vui lòng chọn ngày và giờ',
          'Please select date and time',
        );
      });
      return false;
    }

    final err = widget.isEditing
        ? null
        : ReminderValidator.validateFutureDateTime(
            _selectedDate,
            _selectedTime,
          );

    setState(() {
      _dateTimeError = err;
    });

    return err == null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF005F50),
              onPrimary: Colors.white,
              onSurface: Color(0xFF151D1B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _validateDateTime();
    }
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF005F50),
              onPrimary: Colors.white,
              onSurface: Color(0xFF151D1B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
      _validateDateTime();
    }
  }

  Future<void> _showMemberPickerBottomSheet() async {
    if (_selectedTaskType == TaskType.assign.dbValue && !_canAssignChores) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Chỉ Bố/Mẹ mới có quyền phân công việc bắt buộc cho thành viên khác.',
              'Only parents can assign mandatory tasks to other members.',
            ),
          ),
          backgroundColor: const Color(0xFFE77D2B),
        ),
      );
      return;
    }
    final picked = await MemberPickerBottomSheet.show(
      context,
      familyMembers: _activeMembers,
      selectedMember: _selectedMember,
    );
    if (picked != null) {
      setState(() {
        _selectedMember = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (_activeFamilyId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Bạn chưa tham gia gia đình nào để tạo lời nhắc.',
              'You must join a family before creating reminders.',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    if (Firebase.apps.isNotEmpty) {
      try {
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser != null) {
          final memDoc = await FirebaseFirestore.instance
              .collection('family_members')
              .doc('${_activeFamilyId}_${fbUser.uid}')
              .get()
              .timeout(const Duration(seconds: 3));
          final status =
              (memDoc.data()?['status'] ?? 'ACTIVE').toString().toUpperCase();
          if (!memDoc.exists || status != 'ACTIVE') {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLanguage.text(
                    'Bạn không còn là thành viên của gia đình này.',
                    'You are no longer an active member of this family.',
                  ),
                ),
                backgroundColor: const Color(0xFFBA1A1A),
              ),
            );
            Navigator.of(context).pop();
            return;
          }
        }
      } catch (_) {}
      if (!mounted) return;
    }

    final isFormValid = _formKey.currentState?.validate() ?? false;
    final isDtValid = _validateDateTime();

    if (!isFormValid || !isDtValid) {
      return;
    }

    if (_selectedMember == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Vui lòng chọn người nhận việc hoặc Việc chung cho cả nhà.',
              'Please select an assignee or Shared task for all family.',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    final taskTypeEnum = TaskType.fromValue(_selectedTaskType);
    final creatorRole = _currentMember?.role ?? 'Member';
    final creatorLevel = getMemberHierarchyLevel(creatorRole);
    final targetRole = _selectedMember?.role ?? 'Member';
    final targetLevel = _selectedMember?.id == 'OPEN' ? 0 : getMemberHierarchyLevel(targetRole);

    final isCreatorChild = _currentMember?.isChild == true ||
        creatorLevel <= 1 ||
        creatorRole.toUpperCase().contains('CHILD') ||
        widget.currentUserId.toLowerCase().contains('child');
    final isSelfAssign = _selectedMember?.id == widget.currentUserId;

    // Anti-exploit: Prevent CHILD self-assignment with stars
    if (isCreatorChild && isSelfAssign && _rewardStars > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.text(
              'Trẻ em không được tự tạo việc cho mình để nhận sao.',
              'Children cannot self-assign tasks to receive stars.',
            ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    if (taskTypeEnum == TaskType.assign &&
        (creatorLevel < targetLevel || !_canAssignChores || isCreatorChild)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !_canAssignChores || isCreatorChild
                ? AppLanguage.text(
                    'Chỉ Người giám hộ (Bố Mẹ, Ông Bà) mới có quyền giao việc bắt buộc có thưởng/phạt. Hãy chọn chế độ "Nhờ vả (FAVOR)".',
                    'Only Guardians (Parents, Grandparents) can assign mandatory chores. Please select "Favor".',
                  )
                : AppLanguage.text(
                    'Trẻ em không được giao việc bắt buộc có thưởng/phạt cho người lớn. Hãy chọn chế độ "Nhờ vả (FAVOR)".',
                    'Children cannot assign mandatory chores to elders. Please select "Favor".',
                  ),
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dateStr = _formatDate(_selectedDate!);
      final timeStr = _formatTime(_selectedTime!);
      final isNowOpenTask = _selectedMember!.id == 'OPEN';
      final effectiveProofRequired =
          taskTypeEnum == TaskType.assign && _canAssignChores && _requiresProofImage;
      final effectiveRewardStars =
          taskTypeEnum == TaskType.assign ? _rewardStars : 0;

      if (widget.isEditing) {
        String updatedStatus;
        if (isNowOpenTask) {
          updatedStatus = ReminderStatus.open;
        } else if (widget.existingReminder!.isOpen) {
          updatedStatus = ReminderStatus.pending;
        } else {
          updatedStatus = widget.existingReminder!.status;
        }

        final updated = widget.existingReminder!.copyWith(
          familyId: _activeFamilyId,
          familyName: _activeFamilyName,
          title: _titleController.text.trim(),
          assignedTo: isNowOpenTask ? '' : _selectedMember!.id,
          assignedToName: isNowOpenTask ? 'Cả nhà' : _selectedMember!.name,
          date: dateStr,
          time: timeStr,
          repeatRule: _selectedRepeatRule,
          voiceNotePath: _voiceNotePath,
          voiceDurationSeconds: _voiceDurationSeconds,
          voiceNoteDescription: _voiceNoteDescription,
          clearVoiceNote: _voiceNotePath == null,
          requiresProofImage: effectiveProofRequired,
          rewardStars: effectiveRewardStars,
          taskType: taskTypeEnum,
          creatorHierarchyRole:
              widget.existingReminder!.creatorHierarchyRole ?? creatorRole,
          targetHierarchyRole: isNowOpenTask ? null : targetRole,
          status: updatedStatus,
        );

        final saved = await widget.repository.updateReminder(
          reminder: updated,
          currentUserId: widget.currentUserId,
          familyMembers: _activeMembers,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLanguage.text(
                  'Cập nhật lời nhắc thành công!',
                  'Reminder updated successfully!',
                ),
              ),
              backgroundColor: const Color(0xFF005F50),
            ),
          );
          Navigator.of(context).pop(saved);
        }
      } else {
        // Kiểm tra trùng việc hoặc trùng lịch trình trước khi tạo mới
        if (!isNowOpenTask && _selectedMember != null) {
          final dup = await widget.repository.findDuplicateReminder(
            familyId: _activeFamilyId,
            title: _titleController.text.trim(),
            date: dateStr,
            time: timeStr,
          );
          if (dup != null && mounted) {
            final ok = await _showConflictDialog(
              context: context,
              icon: Icons.info_outline_rounded,
              iconColor: const Color(0xFF005F50),
              title: AppLanguage.text('Trùng Lặp Công Việc', 'Duplicate Task'),
              message: AppLanguage.text(
                'Gia đình đã có công việc "${dup.title}" vào lúc $timeStr ngày $dateStr.\n\nBạn có muốn tiếp tục tạo thêm không?',
                'Family already has task "${dup.title}" at $timeStr on $dateStr.\n\nContinue creating anyway?',
              ),
              confirmLabel: AppLanguage.text('Tiếp tục tạo', 'Continue'),
            );
            if (ok != true) {
              setState(() => _isLoading = false);
              return;
            }
          }

          final conflict = await widget.repository.checkScheduleConflict(
            userId: _selectedMember!.id,
            date: dateStr,
            time: timeStr,
          );
          if (conflict != null && mounted) {
            final ok = await _showConflictDialog(
              context: context,
              icon: Icons.warning_amber_rounded,
              iconColor: const Color(0xFFE65100),
              title: AppLanguage.text('Cảnh Báo Trùng Giờ', 'Schedule Conflict'),
              message: AppLanguage.text(
                '${_selectedMember!.name} đã có công việc "${conflict.title}"${conflict.familyName != null ? ' tại ${conflict.familyName}' : ''} vào lúc $timeStr ngày $dateStr.\n\nBạn vẫn muốn giao thêm công việc này?',
                '${_selectedMember!.name} already has task "${conflict.title}" at $timeStr on $dateStr.\n\nStill assign this task?',
              ),
              confirmLabel: AppLanguage.text('Vẫn giao việc', 'Assign anyway'),
            );
            if (ok != true) {
              setState(() => _isLoading = false);
              return;
            }
          }
        }

        final newReminder = ReminderModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          familyId: _activeFamilyId,
          familyName: _activeFamilyName,
          creatorId: widget.currentUserId,
          creatorName: widget.currentUserName,
          title: _titleController.text.trim(),
          assignedTo: isNowOpenTask ? '' : _selectedMember!.id,
          assignedToName: isNowOpenTask ? 'Cả nhà' : _selectedMember!.name,
          date: dateStr,
          time: timeStr,
          repeatRule: _selectedRepeatRule,
          status: isNowOpenTask ? ReminderStatus.open : ReminderStatus.pending,
          taskType: taskTypeEnum,
          taskStatus: TaskStatus.pending,
          requiresProofImage: effectiveProofRequired,
          rewardStars: effectiveRewardStars,
          voiceNotePath: _voiceNotePath,
          voiceDurationSeconds: _voiceDurationSeconds,
          voiceNoteDescription: _voiceNoteDescription,
          creatorHierarchyRole: creatorRole,
          targetHierarchyRole: isNowOpenTask ? null : targetRole,
          createdAt: DateTime.now(),
        );

        final created = await widget.repository.createReminder(
          reminder: newReminder,
          currentUserId: widget.currentUserId,
          familyMembers: _activeMembers,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isNowOpenTask
                    ? AppLanguage.text(
                        '🎉 Tạo việc mở cho cả nhà thành công!',
                        '🎉 Shared task created successfully!',
                      )
                    : AppLanguage.text(
                        'Tạo lời nhắc thành công!',
                        'Reminder created successfully!',
                      ),
              ),
              backgroundColor: const Color(0xFF005F50),
            ),
          );
          Navigator.of(context).pop(created);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool?> _showConflictDialog({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(AppLanguage.text('Hủy', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005F50),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        const primaryColor = Color(0xFF005F50);
        const textPrimary = Color(0xFF151D1B);
        const textMuted = Color(0xFF6E7A75);
        final screenWidth = MediaQuery.of(context).size.width;
        final horizontalPad = screenWidth < 360 ? 14.0 : 20.0;

        return Scaffold(
          backgroundColor: const Color(0xFFF3FBF8),
          appBar: AppBar(
            title: Text(
              widget.isEditing
                  ? AppLanguage.text('Chỉnh sửa lời nhắc', 'Edit Reminder')
                  : AppLanguage.text('Tạo lời nhắc mới', 'Create New Reminder'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            backgroundColor: const Color(0xFFEDF5F2),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: primaryColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: const Color(0xFFDCE8E3), height: 1),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                      horizontal: horizontalPad, vertical: 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 0. CHỌN GIA ĐÌNH
                        if (_families.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFFBDC9C4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.home_work_rounded,
                                  color: primaryColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  AppLanguage.text('Gia đình:', 'Family:'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textMuted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: (!widget.isEditing &&
                                          _families.length > 1)
                                      ? DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: _families.any((f) =>
                                                    f.id == _activeFamilyId)
                                                ? _activeFamilyId
                                                : _families.first.id,
                                            isDense: true,
                                            isExpanded: true,
                                            icon: const Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: primaryColor,
                                            ),
                                            items: _families.map((fam) {
                                              return DropdownMenuItem<String>(
                                                value: fam.id,
                                                child: Text(
                                                  fam.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow
                                                      .ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: primaryColor,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (newFamId) {
                                              if (newFamId == null ||
                                                  newFamId ==
                                                      _activeFamilyId) {
                                                return;
                                              }
                                              final selectedFam = _families
                                                  .firstWhere(
                                                      (f) => f.id == newFamId);
                                              final newMembers = widget
                                                      .membersByFamilyId?[
                                                  newFamId] ??
                                                  widget.familyMembers;
                                              setState(() {
                                                _activeFamilyId = newFamId;
                                                _activeFamilyName =
                                                    selectedFam.name;
                                                _activeMembers =
                                                    List<FamilyMember>.from(
                                                        newMembers);
                                                if (_selectedMember != null &&
                                                    _selectedMember!.id !=
                                                        'OPEN') {
                                                  _selectedMember =
                                                      _activeMembers
                                                              .isNotEmpty
                                                          ? _activeMembers
                                                              .firstWhere(
                                                              (m) =>
                                                                  m.id !=
                                                                  widget
                                                                      .currentUserId,
                                                              orElse: () =>
                                                                  _activeMembers
                                                                      .first,
                                                            )
                                                          : null;
                                                }
                                              });
                                            },
                                          ),
                                        )
                                      : Text(
                                          _activeFamilyName ??
                                              AppLanguage.text(
                                                'Gia đình của tôi',
                                                'My Family',
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: primaryColor,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 0.5. CHỌN LOẠI CÔNG VIỆC (TASK TYPE)
                        Text(
                          AppLanguage.text('Loại công việc', 'Task Type'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final bool isNarrow = constraints.maxWidth < 360;
                            return SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<String>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment<String>(
                                    value: TaskType.assign.dbValue,
                                    icon: isNarrow
                                        ? null
                                        : const Icon(Icons.assignment_outlined, size: 16),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLanguage.text('Giao việc', 'Assign'),
                                        maxLines: 1,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  ButtonSegment<String>(
                                    value: TaskType.favor.dbValue,
                                    icon: isNarrow
                                        ? null
                                        : const Icon(Icons.volunteer_activism_outlined, size: 16),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLanguage.text('Nhờ vả', 'Favor'),
                                        maxLines: 1,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  ButtonSegment<String>(
                                    value: TaskType.care.dbValue,
                                    icon: isNarrow
                                        ? null
                                        : const Icon(Icons.favorite_outline, size: 16),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLanguage.text('Chăm sóc', 'Care'),
                                        maxLines: 1,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                                selected: {_selectedTaskType},
                                onSelectionChanged: (newSelection) {
                                  setState(() {
                                    _selectedTaskType = newSelection.first;
                                    if (_selectedTaskType == TaskType.favor.dbValue ||
                                        _selectedTaskType == TaskType.care.dbValue) {
                                      _rewardStars = 0;
                                      _requiresProofImage = false;
                                    } else if (_rewardStars == 0) {
                                      _rewardStars = 2;
                                    }
                                  });
                                },
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                                  ),
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      if (_selectedTaskType == TaskType.care.dbValue) {
                                        return const Color(0xFFFFE0B2);
                                      } else if (_selectedTaskType == TaskType.favor.dbValue) {
                                        return const Color(0xFFB2DFDB);
                                      }
                                      return const Color(0xFFD4ECE5);
                                    }
                                    return Colors.white;
                                  }),
                                  foregroundColor:
                                      WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      if (_selectedTaskType == TaskType.care.dbValue) {
                                        return const Color(0xFFE65100);
                                      } else if (_selectedTaskType == TaskType.favor.dbValue) {
                                        return const Color(0xFF00796B);
                                      }
                                      return primaryColor;
                                    }
                                    return textPrimary;
                                  }),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // 1. TIÊU ĐỀ
                        Text(
                          AppLanguage.text(
                            'Nội dung việc cần làm *',
                            'Task title *',
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _titleController,
                          maxLength: 100,
                          decoration: InputDecoration(
                            hintText: AppLanguage.text(
                              'Nhập việc cần làm hoặc bấm ghi âm giọng nói...',
                              'Enter task title or record voice note...',
                            ),
                            hintStyle: const TextStyle(color: textMuted),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.all(16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFFBDC9C4)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFFBDC9C4)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: primaryColor, width: 2),
                            ),
                          ),
                          validator: (val) =>
                              ReminderValidator.validateTitle(
                                  val?.trim() ?? ''),
                        ),
                        const SizedBox(height: 12),

                        // 1.5. GHI ÂM LỜI NHẮC GIỌNG NÓI
                        VoiceRecorderWidget(
                          initialAudioPath: _voiceNotePath,
                          initialDuration: _voiceDurationSeconds,
                          initialDescription: _voiceNoteDescription,
                          onVoiceRecorded: _onVoiceRecorded,
                          onVoiceRemoved: _onVoiceRemoved,
                        ),
                        const SizedBox(height: 20),

                        // 2. NGƯỜI NHẬN VIỆC (FOR)
                        Text(
                          AppLanguage.text('Người nhận việc', 'Assignee'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _showMemberPickerBottomSheet,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFFBDC9C4)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _selectedMember != null
                                      ? Row(
                                          children: [
                                            if (_selectedMember!.id ==
                                                'OPEN')
                                              const CircleAvatar(
                                                radius: 14,
                                                backgroundColor:
                                                    Color(0xFFE0F7FA),
                                                child: Icon(
                                                    Icons.groups_rounded,
                                                    color: Color(0xFF00796B),
                                                    size: 16),
                                              )
                                            else
                                              CircleAvatar(
                                                radius: 14,
                                                backgroundColor:
                                                    MemberColorHelper
                                                        .getBackgroundColor(
                                                            _selectedMember!
                                                                .name),
                                                child: Text(
                                                  _selectedMember!
                                                          .name.isNotEmpty
                                                      ? _selectedMember!
                                                          .name[0]
                                                          .toUpperCase()
                                                      : '?',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color: MemberColorHelper
                                                        .getPrimaryColor(
                                                            _selectedMember!
                                                                .name),
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                _selectedMember!.id ==
                                                        'OPEN'
                                                    ? AppLanguage.text(
                                                        '👨‍👩‍👧 Cả nhà (Việc chung chưa gán)',
                                                        '👨‍👩‍👧 All Family (Shared task)',
                                                      )
                                                    : '${_selectedMember!.name} (${_selectedMember!.roleDisplayName})',
                                                maxLines: 1,
                                                overflow: TextOverflow
                                                    .ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: textPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          AppLanguage.text(
                                            'Chọn thành viên',
                                            'Select member',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: textMuted,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_drop_down,
                                    color: primaryColor),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 3. NGÀY HẸN
                        Text(
                          AppLanguage.text('Ngày thực hiện', 'Date'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFFBDC9C4)),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedDate != null
                                        ? _formatDate(_selectedDate!)
                                        : AppLanguage.text(
                                            'Chọn ngày', 'Select date'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: _selectedDate != null
                                          ? textPrimary
                                          : textMuted,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.calendar_month,
                                    color: primaryColor),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 4. GIỜ HẸN
                        Text(
                          AppLanguage.text('Giờ thực hiện', 'Time'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _pickTime,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFFBDC9C4)),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedTime != null
                                        ? _formatTime(_selectedTime!)
                                        : AppLanguage.text(
                                            'Chọn giờ', 'Select time'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: _selectedTime != null
                                          ? textPrimary
                                          : textMuted,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.access_time,
                                    color: primaryColor),
                              ],
                            ),
                          ),
                        ),

                        // 4.5. TẦN SUẤT LẶP LẠI (REPEAT)
                        const SizedBox(height: 20),
                        Text(
                          AppLanguage.text(
                            'Tần suất lặp lại',
                            'Repeat frequency',
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final bool isNarrow = constraints.maxWidth < 360;
                            return SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<String>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment<String>(
                                    value: 'NONE',
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLanguage.text('Một lần', 'Once'),
                                        maxLines: 1,
                                      ),
                                    ),
                                    icon: isNarrow
                                        ? null
                                        : const Icon(Icons.event_outlined, size: 18),
                                  ),
                                  ButtonSegment<String>(
                                    value: 'DAILY',
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLanguage.text('Hàng ngày', 'Daily'),
                                        maxLines: 1,
                                      ),
                                    ),
                                    icon: isNarrow
                                        ? null
                                        : const Icon(Icons.repeat, size: 18),
                                  ),
                                  ButtonSegment<String>(
                                    value: 'WEEKLY',
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLanguage.text('Hàng tuần', 'Weekly'),
                                        maxLines: 1,
                                      ),
                                    ),
                                    icon: isNarrow
                                        ? null
                                        : const Icon(Icons.calendar_view_week, size: 18),
                                  ),
                                ],
                                selected: {_selectedRepeatRule},
                                onSelectionChanged: (newSelection) {
                                  setState(() {
                                    _selectedRepeatRule = newSelection.first;
                                  });
                                },
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                                  ),
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return const Color(0xFFD4ECE5);
                                    }
                                    return Colors.white;
                                  }),
                                  foregroundColor:
                                      WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return primaryColor;
                                    }
                                    return textPrimary;
                                  }),
                                ),
                              ),
                            );
                          },
                        ),

                        // 4.6. TÙY CHỌN RIÊNG THEO LOẠI CÔNG VIỆC
                        if (_selectedTaskType == TaskType.assign.dbValue) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFBDC9C4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, color: Colors.amber, size: 24),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        AppLanguage.text('Thưởng sao hoàn thành', 'Star Reward'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: [1, 2, 3, 5].map((star) {
                                    final isSelected = _rewardStars == star;
                                    return ChoiceChip(
                                      label: Text(
                                        '$star ⭐',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? Colors.amber.shade900 : textPrimary,
                                        ),
                                      ),
                                      selected: isSelected,
                                      selectedColor: Colors.amber.shade100,
                                      backgroundColor: Colors.grey.shade50,
                                      side: BorderSide(
                                        color: isSelected ? Colors.amber.shade700 : const Color(0xFFBDC9C4),
                                      ),
                                      onSelected: (selected) {
                                        if (selected) setState(() => _rewardStars = star);
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                          if (_canAssignChores) ...[
                            const SizedBox(height: 16),
                            ChoreRewardCard(
                              requiresProofImage: _requiresProofImage,
                              onProofRequiredChanged: (val) =>
                                  setState(() => _requiresProofImage = val),
                            ),
                          ],
                        ] else if (_selectedTaskType == TaskType.care.dbValue) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFFFB74D), width: 1.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.favorite_rounded, color: Color(0xFFE65100), size: 24),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        AppLanguage.text('Chế độ Chăm sóc Người cao tuổi', 'Elderly Care Mode'),
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppLanguage.text(
                                    'Lời nhắc sẽ hiển thị với chữ lớn, tương phản cao và hỗ trợ đọc to bằng giọng nói tiếng Việt tự động cho Ông Bà.',
                                    'Reminder will display with large high-contrast text and automated Vietnamese speech for Elders.',
                                  ),
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF5D4037)),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFE0B2),
                                    foregroundColor: const Color(0xFFE65100),
                                  ),
                                  icon: const Icon(Icons.volume_up_rounded, size: 20),
                                  label: Text(AppLanguage.text('🔊 Thử giọng đọc TTS', '🔊 Test TTS Voice')),
                                  onPressed: () {
                                    final title = _titleController.text.trim();
                                    final sample = title.isNotEmpty ? title : 'Uống thuốc huyết áp sau ăn';
                                    AiSpeechPlatform.instance.speak("Kính mời Ông Bà: $sample", isEnglish: false);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ] else if (_selectedTaskType == TaskType.favor.dbValue) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F2F1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF80CBC4), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.volunteer_activism_rounded, color: Color(0xFF00796B), size: 24),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    AppLanguage.text(
                                      'Chế độ Nhờ vả tự nguyện: Không tính điểm phạt hay thưởng sao, có thể chuyển tiếp công việc tối đa 1 lần.',
                                      'Voluntary Favor Mode: No star rewards or penalties, can be delegated at most 1 time.',
                                    ),
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF004D40)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        if (_dateTimeError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _dateTimeError!,
                            style: const TextStyle(
                              color: Color(0xFFBA1A1A),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 36),

                        // 5. NÚT SUBMIT
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _isLoading ? null : _submit,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      widget.isEditing
                                          ? AppLanguage.text(
                                              'Cập nhật lời nhắc',
                                              'Update reminder',
                                            )
                                          : (_selectedMember?.id == 'OPEN'
                                              ? AppLanguage.text(
                                                  'Đăng việc cho cả nhà',
                                                  'Post shared task',
                                                )
                                              : AppLanguage.text(
                                                  'Lưu lời nhắc',
                                                  'Save reminder',
                                                )),
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
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
  final String currentUserId;
  final String currentUserName;
  final List<FamilyMember> familyMembers;
  final ReminderRepository repository;
  final ReminderModel? existingReminder;

  const CreateReminderScreen({
    super.key,
    required this.familyId,
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

  FamilyMember? _selectedMember;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _selectedRepeatRule = 'NONE';
  bool _requiresProofImage = false;

  String? _voiceNotePath;
  int? _voiceDurationSeconds;
  String? _voiceNoteDescription;

  String? _dateTimeError;
  bool _isLoading = false;

  FamilyMember? get _currentMember {
    try {
      return widget.familyMembers.firstWhere(
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
          _titleController.text = 'Lời nhắc giọng nói 🎙️';
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
    final existing = widget.existingReminder;

    if (existing != null) {
      _titleController.text = existing.title;
      _voiceNotePath = existing.voiceNotePath;
      _voiceDurationSeconds = existing.voiceDurationSeconds;
      _voiceNoteDescription = existing.voiceNoteDescription;
      _selectedRepeatRule = existing.repeatRule ?? 'NONE';
      _requiresProofImage = existing.requiresProofImage;

      // Parse existing date and time
      final parsedDt = existing.dueDateTime;
      if (parsedDt != null) {
        _selectedDate = DateTime(parsedDt.year, parsedDt.month, parsedDt.day);
        _selectedTime = TimeOfDay(hour: parsedDt.hour, minute: parsedDt.minute);
      } else {
        final now = DateTime.now();
        _selectedDate = DateTime(now.year, now.month, now.day);
        _selectedTime = TimeOfDay(hour: (now.hour + 1) % 24, minute: now.minute);
      }

      // Find matching assigned member (hoặc Open Task)
      if (existing.isOpenTask) {
        _selectedMember = const FamilyMember(
          id: 'OPEN',
          name: 'Cả nhà (Việc chung)',
          role: 'Open Task',
          familyId: '',
        );
      } else {
        _selectedMember = widget.familyMembers.firstWhere(
          (m) => m.id == existing.assignedTo,
          orElse: () => FamilyMember(
            id: existing.assignedTo,
            name: existing.assignedToName,
            role: 'Member',
            familyId: widget.familyId,
          ),
        );
      }
    } else {
      // Default initial date/time: Hôm nay + 1 tiếng
      final now = DateTime.now();
      _selectedDate = DateTime(now.year, now.month, now.day);
      _selectedTime = TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);

      // Default member: Thành viên đầu tiên khác user hiện tại
      if (widget.familyMembers.isNotEmpty) {
        _selectedMember = widget.familyMembers.firstWhere(
          (m) => m.id != widget.currentUserId,
          orElse: () => widget.familyMembers.first,
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
        _dateTimeError = 'Vui lòng chọn ngày và giờ';
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
    final picked = await MemberPickerBottomSheet.show(
      context,
      familyMembers: widget.familyMembers,
      selectedMember: _selectedMember,
    );
    if (picked != null) {
      setState(() {
        _selectedMember = picked;
      });
    }
  }

  Future<void> _submit() async {
    final isFormValid = _formKey.currentState?.validate() ?? false;
    final isDtValid = _validateDateTime();

    if (!isFormValid || !isDtValid) {
      return;
    }

    if (_selectedMember == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn người nhận việc hoặc Việc chung cho cả nhà.'),
          backgroundColor: Color(0xFFBA1A1A),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dateStr = _formatDate(_selectedDate!);
      final timeStr = _formatTime(_selectedTime!);
      final isNowOpenTask = _selectedMember!.id == 'OPEN';
      final effectiveProofRequired = _canAssignChores && _requiresProofImage;

      if (widget.isEditing) {
        // Cập nhật trạng thái phù hợp khi đổi giữa Cả nhà (OPEN) và Cá nhân (PENDING)
        String updatedStatus;
        if (isNowOpenTask) {
          updatedStatus = ReminderStatus.open;
        } else if (widget.existingReminder!.isOpen) {
          updatedStatus = ReminderStatus.pending;
        } else {
          updatedStatus = widget.existingReminder!.status;
        }

        final updated = widget.existingReminder!.copyWith(
          title: _titleController.text.trim(),
          assignedTo: isNowOpenTask ? '' : _selectedMember!.id,
          assignedToName: isNowOpenTask ? 'Cả nhà' : _selectedMember!.name,
          date: dateStr,
          time: timeStr,
          repeatRule: _selectedRepeatRule,
          voiceNotePath: _voiceNotePath,
          voiceDurationSeconds: _voiceDurationSeconds,
          voiceNoteDescription: _voiceNoteDescription,
          requiresProofImage: effectiveProofRequired,
          rewardStars: 0,
          status: updatedStatus,
        );

        await widget.repository.updateReminder(
          reminder: updated,
          currentUserId: widget.currentUserId,
          familyMembers: widget.familyMembers,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cập nhật lời nhắc thành công!'),
              backgroundColor: Color(0xFF005F50),
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        final newReminder = ReminderModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          familyId: widget.familyId,
          creatorId: widget.currentUserId,
          creatorName: widget.currentUserName,
          title: _titleController.text.trim(),
          assignedTo: isNowOpenTask ? '' : _selectedMember!.id,
          assignedToName: isNowOpenTask ? 'Cả nhà' : _selectedMember!.name,
          date: dateStr,
          time: timeStr,
          repeatRule: _selectedRepeatRule,
          status: isNowOpenTask ? ReminderStatus.open : ReminderStatus.pending,
          requiresProofImage: effectiveProofRequired,
          rewardStars: 0,
          voiceNotePath: _voiceNotePath,
          voiceDurationSeconds: _voiceDurationSeconds,
          voiceNoteDescription: _voiceNoteDescription,
          createdAt: DateTime.now(),
        );

        await widget.repository.createReminder(
          reminder: newReminder,
          currentUserId: widget.currentUserId,
          familyMembers: widget.familyMembers,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isNowOpenTask
                    ? '🎉 Tạo việc mở cho cả nhà thành công!'
                    : 'Tạo lời nhắc thành công!',
              ),
              backgroundColor: const Color(0xFF005F50),
            ),
          );
          Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF005F50);
    const textPrimary = Color(0xFF151D1B);
    const textMuted = Color(0xFF6E7A75);

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBF8),
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Chỉnh sửa lời nhắc' : 'Tạo lời nhắc mới',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. TIÊU ĐỀ
              const Text(
                'Nội dung việc cần làm *',
                style: TextStyle(
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
                  hintText: 'Nhập việc cần làm hoặc bấm ghi âm giọng nói...',
                  hintStyle: const TextStyle(color: textMuted),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFBDC9C4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFBDC9C4)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: primaryColor, width: 2),
                  ),
                ),
                validator: (val) =>
                    ReminderValidator.validateTitle(val?.trim() ?? ''),
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
              const Text(
                'Người nhận việc',
                style: TextStyle(
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBDC9C4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _selectedMember != null
                          ? Row(
                              children: [
                                if (_selectedMember!.id == 'OPEN')
                                  const CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Color(0xFFE0F7FA),
                                    child: Icon(Icons.groups_rounded,
                                        color: Color(0xFF00796B), size: 16),
                                  )
                                else
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor:
                                        MemberColorHelper.getBackgroundColor(
                                            _selectedMember!.name),
                                    child: Text(
                                      _selectedMember!.name.isNotEmpty
                                          ? _selectedMember!.name[0]
                                              .toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            MemberColorHelper.getPrimaryColor(
                                                _selectedMember!.name),
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Text(
                                  _selectedMember!.id == 'OPEN'
                                      ? '👨‍👩‍👧 Cả nhà (Việc chung chưa gán)'
                                      : '${_selectedMember!.name} (${_selectedMember!.roleDisplayName})',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Chọn thành viên',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: textMuted,
                              ),
                            ),
                      const Icon(Icons.arrow_drop_down, color: primaryColor),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. NGÀY HẸN
              const Text(
                'Ngày thực hiện',
                style: TextStyle(
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBDC9C4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedDate != null
                            ? _formatDate(_selectedDate!)
                            : 'Chọn ngày',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color:
                              _selectedDate != null ? textPrimary : textMuted,
                        ),
                      ),
                      const Icon(Icons.calendar_month, color: primaryColor),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 4. GIỜ HẸN
              const Text(
                'Giờ thực hiện',
                style: TextStyle(
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBDC9C4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedTime != null
                            ? _formatTime(_selectedTime!)
                            : 'Chọn giờ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color:
                              _selectedTime != null ? textPrimary : textMuted,
                        ),
                      ),
                      const Icon(Icons.access_time, color: primaryColor),
                    ],
                  ),
                ),
              ),

              // 4.5. TẦN SUẤT LẶP LẠI (REPEAT)
              const SizedBox(height: 20),
              const Text(
                'Tần suất lặp lại',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'NONE',
                      label: Text('Một lần'),
                      icon: Icon(Icons.event_outlined),
                    ),
                    ButtonSegment<String>(
                      value: 'DAILY',
                      label: Text('Hàng ngày'),
                      icon: Icon(Icons.repeat),
                    ),
                    ButtonSegment<String>(
                      value: 'WEEKLY',
                      label: Text('Hàng tuần'),
                      icon: Icon(Icons.calendar_view_week),
                    ),
                  ],
                  selected: {_selectedRepeatRule},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _selectedRepeatRule = newSelection.first;
                    });
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Color(0xFFD4ECE5);
                      }
                      return Colors.white;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return primaryColor;
                      }
                      return textPrimary;
                    }),
                  ),
                ),
              ),

              // 4.6. NGHIỆM THU VIỆC NHÀ (CAMERA PROOF)
              if (_canAssignChores) ...[
                const SizedBox(height: 20),
                ChoreRewardCard(
                  requiresProofImage: _requiresProofImage,
                  onProofRequiredChanged: (val) =>
                      setState(() => _requiresProofImage = val),
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
                      : Text(
                          widget.isEditing
                              ? 'Cập nhật lời nhắc'
                              : (_selectedMember?.id == 'OPEN'
                                  ? 'Đăng việc cho cả nhà'
                                  : 'Lưu lời nhắc'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

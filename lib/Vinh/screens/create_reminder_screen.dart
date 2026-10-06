import 'package:flutter/material.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../services/member_color_helper.dart';
import '../services/reminder_repository.dart';
import '../services/reminder_validator.dart';
import '../widgets/voice_recorder_widget.dart';

class CreateReminderScreen extends StatefulWidget {
  final String familyId;
  final String currentUserId;
  final String currentUserName;
  final List<FamilyMember> familyMembers;
  final ReminderRepository repository;

  const CreateReminderScreen({
    super.key,
    required this.familyId,
    required this.currentUserId,
    this.currentUserName = 'Me',
    required this.familyMembers,
    required this.repository,
  });

  @override
  State<CreateReminderScreen> createState() => _CreateReminderScreenState();
}

class _CreateReminderScreenState extends State<CreateReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  FamilyMember? _selectedMember;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  String? _voiceNotePath;
  int? _voiceDurationSeconds;
  String? _voiceNoteDescription;

  String? _dateTimeError;
  bool _isLoading = false;

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
    // Default to tomorrow or later today if early
    final now = DateTime.now();
    // Default date is today
    _selectedDate = DateTime(now.year, now.month, now.day);
    // Default time is 1 hour in the future
    final nextHour = now.hour < 23 ? now.hour + 1 : 23;
    final nextMinute = now.minute;
    _selectedTime = TimeOfDay(hour: nextHour, minute: nextMinute);

    // If family members exist, default to the first one that is not current user, or first
    if (widget.familyMembers.isNotEmpty) {
      _selectedMember = widget.familyMembers.firstWhere(
        (m) => m.id != widget.currentUserId,
        orElse: () => widget.familyMembers.first,
      );
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0D7A68),
              onPrimary: Colors.white,
              surface: Colors.white,
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
        _validateDateTime();
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0D7A68),
              onPrimary: Colors.white,
              surface: Colors.white,
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
        _validateDateTime();
      });
    }
  }

  bool _validateDateTime() {
    final error = ReminderValidator.validateFutureDateTime(
      _selectedDate,
      _selectedTime,
    );
    setState(() {
      _dateTimeError = error;
    });
    return error == null;
  }

  Future<void> _pickMember() async {
    const primaryColor = Color(0xFF0D7A68);
    const textPrimary = Color(0xFF151D1B);

    final selected = await showModalBottomSheet<FamilyMember>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Member (For)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2EAE7)),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.familyMembers.length,
                    itemBuilder: (ctx, index) {
                      final member = widget.familyMembers[index];
                      final isSelected = member.id == _selectedMember?.id;
                      final primary =
                          MemberColorHelper.getPrimaryColor(member.name);
                      final bg =
                          MemberColorHelper.getBackgroundColor(member.name);

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: bg,
                          child: Text(
                            member.name.isNotEmpty
                                ? member.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: primary,
                            ),
                          ),
                        ),
                        title: Text(
                          member.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected ? primaryColor : textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          member.role,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6E7A75),
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: primaryColor)
                            : null,
                        tileColor: isSelected
                            ? const Color(0xFFE7F5F2)
                            : Colors.transparent,
                        onTap: () => Navigator.of(ctx).pop(member),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedMember = selected;
      });
    }
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    final dateTimeValid = _validateDateTime();

    if (!formValid || !dateTimeValid) {
      return;
    }

    if (_selectedMember == null || _selectedDate == null || _selectedTime == null) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dateStr = _formatDate(_selectedDate!);
      final timeStr = _formatTime(_selectedTime!);

      final reminder = ReminderModel(
        id: '',
        familyId: widget.familyId,
        creatorId: widget.currentUserId,
        creatorName: widget.currentUserName,
        assignedTo: _selectedMember!.id,
        assignedToName: _selectedMember!.name,
        title: _titleController.text.trim(),
        date: dateStr,
        time: timeStr,
        status: ReminderStatus.pending,
        voiceNotePath: _voiceNotePath,
        voiceDurationSeconds: _voiceDurationSeconds,
        voiceNoteDescription: _voiceNoteDescription,
      );

      final created = await widget.repository.createReminder(
        reminder: reminder,
        currentUserId: widget.currentUserId,
        familyMembers: widget.familyMembers,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reminder "${created.title}" created!'),
            backgroundColor: const Color(0xFF0D7A68),
          ),
        );
        Navigator.of(context).pop(created);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    const textPrimary = Color(0xFF151D1B);
    const textMuted = Color(0xFF6E7A75);

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBF8),
      appBar: AppBar(
        title: const Text(
          'Create Reminder',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2EAE7), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. TITLE
              const Text(
                'Title',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  hintText: 'Buy milk',
                  hintStyle: const TextStyle(color: textMuted),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    borderSide:
                        const BorderSide(color: primaryColor, width: 2),
                  ),
                ),
                validator: ReminderValidator.validateTitle,
              ),
              const SizedBox(height: 16),

              // 1.1 GHI ÂM GIỌNG NÓI (VOICE REMINDER VIA MICROPHONE & SPEAKER)
              VoiceRecorderWidget(
                onVoiceRecorded: _onVoiceRecorded,
                onVoiceRemoved: _onVoiceRemoved,
              ),
              const SizedBox(height: 20),

              // 2. FOR (Assigned Member)
              const Text(
                'For',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickMember,
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
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: MemberColorHelper.getBackgroundColor(
                                      _selectedMember!.name),
                                  child: Text(
                                    _selectedMember!.name.isNotEmpty
                                        ? _selectedMember!.name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: MemberColorHelper.getPrimaryColor(
                                          _selectedMember!.name),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${_selectedMember!.name} (${_selectedMember!.role})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: textPrimary,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Select Member',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: textMuted,
                              ),
                            ),
                      const Icon(Icons.person_outline, color: primaryColor),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. DATE
              const Text(
                'Date',
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
                            : 'Select Date',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _selectedDate != null ? textPrimary : textMuted,
                        ),
                      ),
                      const Icon(Icons.calendar_month, color: primaryColor),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 4. TIME
              const Text(
                'Time',
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
                            : 'Select Time',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _selectedTime != null ? textPrimary : textMuted,
                        ),
                      ),
                      const Icon(Icons.access_time, color: primaryColor),
                    ],
                  ),
                ),
              ),

              // 5. Future Date + Time Error Message
              if (_dateTimeError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFDAD6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFBA1A1A), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _dateTimeError!,
                          style: const TextStyle(
                            color: Color(0xFFBA1A1A),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // 6. CREATE BUTTON
              SizedBox(
                height: 54,
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
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Create',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

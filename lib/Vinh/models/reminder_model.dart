class ReminderStatus {
  static const String pending = 'PENDING';
  static const String completed = 'COMPLETED';
  static const String deleted = 'DELETED';
}

class ReminderModel {
  final String id;
  final String familyId;
  final String creatorId;
  final String? creatorName;
  final String assignedTo;
  final String assignedToName;
  final String title;
  final String date; // dd/MM/yyyy
  final String time; // HH:mm
  final String status; // PENDING, COMPLETED, DELETED
  final String? voiceNotePath;
  final int? voiceDurationSeconds;
  final String? voiceNoteDescription;
  final DateTime? completedAt;
  final DateTime? createdAt;

  const ReminderModel({
    required this.id,
    required this.familyId,
    required this.creatorId,
    this.creatorName,
    required this.assignedTo,
    required this.assignedToName,
    required this.title,
    required this.date,
    required this.time,
    this.status = ReminderStatus.pending,
    this.voiceNotePath,
    this.voiceDurationSeconds,
    this.voiceNoteDescription,
    this.completedAt,
    this.createdAt,
  });

  bool get hasVoiceNote => voiceNotePath != null && voiceNotePath!.isNotEmpty;

  bool get isPending => status == ReminderStatus.pending;
  bool get isCompleted => status == ReminderStatus.completed;
  bool get isDeleted => status == ReminderStatus.deleted;

  /// Returns parsed DateTime from [date] ("dd/MM/yyyy") and [time] ("HH:mm")
  DateTime? get dueDateTime {
    try {
      final dateParts = date.split('/');
      final timeParts = time.split(':');
      if (dateParts.length == 3 && timeParts.length == 2) {
        final day = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final year = int.parse(dateParts[2]);
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        return DateTime(year, month, day, hour, minute);
      }
    } catch (_) {
      // Fallback
    }
    return null;
  }

  /// Formatted date e.g. "24 Sep" or "24/09/2026"
  String get displayDate {
    final dt = dueDateTime;
    if (dt == null) return date;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  ReminderModel copyWith({
    String? id,
    String? familyId,
    String? creatorId,
    String? creatorName,
    String? assignedTo,
    String? assignedToName,
    String? title,
    String? date,
    String? time,
    String? status,
    String? voiceNotePath,
    int? voiceDurationSeconds,
    String? voiceNoteDescription,
    DateTime? completedAt,
    DateTime? createdAt,
  }) {
    return ReminderModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      title: title ?? this.title,
      date: date ?? this.date,
      time: time ?? this.time,
      status: status ?? this.status,
      voiceNotePath: voiceNotePath ?? this.voiceNotePath,
      voiceDurationSeconds: voiceDurationSeconds ?? this.voiceDurationSeconds,
      voiceNoteDescription: voiceNoteDescription ?? this.voiceNoteDescription,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      id: (json['id'] ?? '').toString(),
      familyId: (json['family_id'] ?? json['familyId'] ?? '').toString(),
      creatorId: (json['creator_id'] ?? json['creatorId'] ?? '').toString(),
      creatorName: json['creator_name'] as String? ?? json['creatorName'] as String?,
      assignedTo: (json['assigned_to'] ?? json['assignedTo'] ?? '').toString(),
      assignedToName: (json['assigned_to_name'] ?? json['assignedToName'] ?? '').toString(),
      title: json['title'] as String? ?? '',
      date: json['date'] as String? ?? '',
      time: json['time'] as String? ?? '',
      status: json['status'] as String? ?? ReminderStatus.pending,
      voiceNotePath: json['voice_note_path'] as String? ?? json['voiceNotePath'] as String?,
      voiceDurationSeconds: json['voice_duration_seconds'] is int
          ? json['voice_duration_seconds'] as int
          : (json['voiceDurationSeconds'] is int
              ? json['voiceDurationSeconds'] as int
              : (json['voice_duration_seconds'] != null
                  ? int.tryParse(json['voice_duration_seconds'].toString())
                  : null)),
      voiceNoteDescription: json['voice_note_description'] as String? ??
          json['voiceNoteDescription'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString())
          : (json['completedAt'] != null
              ? DateTime.tryParse(json['completedAt'].toString())
              : null),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : (json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'].toString())
              : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'familyId': familyId,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'title': title,
      'date': date,
      'time': time,
      'status': status,
      if (voiceNotePath != null) 'voiceNotePath': voiceNotePath,
      if (voiceDurationSeconds != null) 'voiceDurationSeconds': voiceDurationSeconds,
      if (voiceNoteDescription != null) 'voiceNoteDescription': voiceNoteDescription,
      'completedAt': completedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  /// Maps directly to Supabase table `reminders`
  Map<String, dynamic> toSupabaseMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'family_id': familyId,
      'creator_id': creatorId,
      'assigned_to': assignedTo,
      'title': title,
      'date': date,
      'time': time,
      'status': status,
      if (voiceNotePath != null) 'voice_note_path': voiceNotePath,
      if (voiceDurationSeconds != null)
        'voice_duration_seconds': voiceDurationSeconds,
      if (voiceNoteDescription != null)
        'voice_note_description': voiceNoteDescription,
      if (completedAt != null) 'completed_at': completedAt?.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          familyId == other.familyId &&
          status == other.status &&
          title == other.title &&
          voiceNotePath == other.voiceNotePath;

  @override
  int get hashCode =>
      id.hashCode ^
      familyId.hashCode ^
      status.hashCode ^
      title.hashCode ^
      voiceNotePath.hashCode;
}

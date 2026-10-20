class ReminderStatus {
  static const String open = 'OPEN';
  static const String pending = 'PENDING';
  static const String overdue = 'OVERDUE';
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
  final String date; // dd/MM/yyyy or yyyy-MM-dd
  final String time; // HH:mm
  final String status; // OPEN, PENDING, OVERDUE, COMPLETED, DELETED
  final String? repeatRule; // NONE, DAILY, WEEKLY
  final bool requiresProofImage; // Bắt buộc chụp ảnh nghiệm thu
  final String? proofImageUrl; // URL hoặc đường dẫn ảnh chụp nghiệm thu
  final int rewardStars; // Điểm thưởng sao dạy con (1, 2, 3, 5 sao)
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
    this.repeatRule = 'NONE',
    this.requiresProofImage = false,
    this.proofImageUrl,
    this.rewardStars = 0,
    this.voiceNotePath,
    this.voiceDurationSeconds,
    this.voiceNoteDescription,
    this.completedAt,
    this.createdAt,
  });

  bool get hasVoiceNote => voiceNotePath != null && voiceNotePath!.isNotEmpty;
  bool get hasProofImage => proofImageUrl != null && proofImageUrl!.isNotEmpty;
  bool get hasRewardStars => rewardStars > 0;

  bool get isOpen => status == ReminderStatus.open;
  bool get isPending => status == ReminderStatus.pending;
  bool get isCompleted => status == ReminderStatus.completed;
  bool get isDeleted => status == ReminderStatus.deleted;
  bool get isRecurring => repeatRule != null && repeatRule != 'NONE';

  String get statusDisplayName {
    if (isDeleted) return 'Đã xóa';
    if (isCompleted) return 'Đã xong';
    if (isOverdue) return 'Quá hạn';
    if (isOpen) return 'Đang mở';
    return 'Chờ xử lý';
  }

  String get voiceDurationFormatted {
    final sec = voiceDurationSeconds ?? 0;
    final m = (sec ~/ 60).toString();
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Kiểm tra nếu đây là việc chung của gia đình (Open Task chưa gán cụ thể)
  bool get isOpenTask =>
      status == ReminderStatus.open ||
      assignedTo.isEmpty ||
      assignedTo == 'OPEN' ||
      assignedTo == 'ALL';

  bool get isOverdue {
    if (isCompleted || isDeleted) return false;
    if (status == ReminderStatus.overdue) return true;
    final dt = dueDateTime;
    if (dt != null && dt.isBefore(DateTime.now())) return true;
    return false;
  }

  /// Returns parsed DateTime from [date] ("dd/MM/yyyy" or "yyyy-MM-dd") and [time] ("HH:mm" or "HH:mm:ss")
  DateTime? get dueDateTime {
    try {
      int day = 1, month = 1, year = 2026;
      if (date.contains('/')) {
        final dateParts = date.split('/');
        if (dateParts.length == 3) {
          day = int.parse(dateParts[0]);
          month = int.parse(dateParts[1]);
          year = int.parse(dateParts[2]);
        }
      } else if (date.contains('-')) {
        final dateParts = date.split('-');
        if (dateParts.length == 3) {
          year = int.parse(dateParts[0]);
          month = int.parse(dateParts[1]);
          day = int.parse(dateParts[2]);
        }
      }

      int hour = 0, minute = 0;
      final timeParts = time.split(':');
      if (timeParts.isNotEmpty) {
        hour = int.parse(timeParts[0]);
        if (timeParts.length > 1) {
          minute = int.parse(timeParts[1]);
        }
      }
      return DateTime(year, month, day, hour, minute);
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
    String? repeatRule,
    bool? requiresProofImage,
    String? proofImageUrl,
    int? rewardStars,
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
      repeatRule: repeatRule ?? this.repeatRule,
      requiresProofImage: requiresProofImage ?? this.requiresProofImage,
      proofImageUrl: proofImageUrl ?? this.proofImageUrl,
      rewardStars: rewardStars ?? this.rewardStars,
      voiceNotePath: voiceNotePath ?? this.voiceNotePath,
      voiceDurationSeconds: voiceDurationSeconds ?? this.voiceDurationSeconds,
      voiceNoteDescription: voiceNoteDescription ?? this.voiceNoteDescription,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    String rawDate = (json['date'] ?? '').toString();
    // Normalize yyyy-MM-dd to dd/MM/yyyy if coming from Postgres
    if (rawDate.contains('-')) {
      final parts = rawDate.split('-');
      if (parts.length == 3) {
        rawDate = '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
      }
    }

    String rawTime = (json['time'] ?? '').toString();
    if (rawTime.length >= 5) {
      rawTime = rawTime.substring(0, 5);
    }

    return ReminderModel(
      id: (json['id'] ?? '').toString(),
      familyId: (json['family_id'] ?? json['familyId'] ?? '').toString(),
      creatorId: (json['creator_id'] ?? json['creatorId'] ?? '').toString(),
      creatorName: json['creator_name'] as String? ?? json['creatorName'] as String?,
      assignedTo: (json['assigned_to'] ?? json['assignedTo'] ?? '').toString(),
      assignedToName: (json['assigned_to_name'] ?? json['assignedToName'] ?? '').toString(),
      title: json['title'] as String? ?? '',
      date: rawDate,
      time: rawTime,
      status: json['status'] as String? ?? ReminderStatus.pending,
      repeatRule: (json['repeat_rule'] ?? json['repeatRule'] ?? 'NONE').toString(),
      requiresProofImage: json['requires_proof_image'] == true ||
          json['requiresProofImage'] == true,
      proofImageUrl: json['proof_image_url'] as String? ??
          json['proofImageUrl'] as String?,
      rewardStars: json['reward_stars'] is int
          ? json['reward_stars'] as int
          : (json['rewardStars'] is int
              ? json['rewardStars'] as int
              : (int.tryParse((json['reward_stars'] ?? json['rewardStars'] ?? 0).toString()) ?? 0)),
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
      'family_id': familyId,
      'creatorId': creatorId,
      'creator_id': creatorId,
      'creatorName': creatorName,
      'creator_name': creatorName,
      'assignedTo': assignedTo,
      'assigned_to': assignedTo,
      'assignedToName': assignedToName,
      'assigned_to_name': assignedToName,
      'title': title,
      'date': date,
      'time': time,
      'status': status,
      'repeatRule': repeatRule ?? 'NONE',
      'repeat_rule': repeatRule ?? 'NONE',
      'requiresProofImage': requiresProofImage,
      'requires_proof_image': requiresProofImage,
      if (proofImageUrl != null) ...{
        'proofImageUrl': proofImageUrl,
        'proof_image_url': proofImageUrl,
      },
      'rewardStars': rewardStars,
      'reward_stars': rewardStars,
      if (voiceNotePath != null) ...{
        'voiceNotePath': voiceNotePath,
        'voice_note_path': voiceNotePath,
      },
      if (voiceDurationSeconds != null) ...{
        'voiceDurationSeconds': voiceDurationSeconds,
        'voice_duration_seconds': voiceDurationSeconds,
      },
      if (voiceNoteDescription != null) ...{
        'voiceNoteDescription': voiceNoteDescription,
        'voice_note_description': voiceNoteDescription,
      },
      'completedAt': completedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// Maps directly to Supabase table `reminders`
  Map<String, dynamic> toSupabaseMap() {
    return {
      if (id.isNotEmpty && id.contains('-')) 'id': id,
      'family_id': familyId,
      'creator_id': creatorId,
      if (creatorName != null) 'creator_name': creatorName,
      'assigned_to': assignedTo,
      if (assignedToName.isNotEmpty) 'assigned_to_name': assignedToName,
      'title': title,
      'date': date,
      'time': time,
      'status': status,
      'repeat_rule': repeatRule ?? 'NONE',
      'requires_proof_image': requiresProofImage,
      if (proofImageUrl != null) 'proof_image_url': proofImageUrl,
      'reward_stars': rewardStars,
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
          proofImageUrl == other.proofImageUrl &&
          requiresProofImage == other.requiresProofImage &&
          rewardStars == other.rewardStars &&
          voiceNotePath == other.voiceNotePath;

  @override
  int get hashCode =>
      id.hashCode ^
      familyId.hashCode ^
      status.hashCode ^
      title.hashCode ^
      proofImageUrl.hashCode ^
      requiresProofImage.hashCode ^
      rewardStars.hashCode ^
      voiceNotePath.hashCode;
}

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
    this.completedAt,
    this.createdAt,
  });

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
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      id: json['id'] as String,
      familyId: json['familyId'] as String,
      creatorId: json['creatorId'] as String,
      creatorName: json['creatorName'] as String?,
      assignedTo: json['assignedTo'] as String,
      assignedToName: json['assignedToName'] as String? ?? '',
      title: json['title'] as String,
      date: json['date'] as String,
      time: json['time'] as String,
      status: json['status'] as String? ?? ReminderStatus.pending,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
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
      'completedAt': completedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}

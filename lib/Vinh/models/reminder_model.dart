import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskType {
  assign,
  favor,
  care;

  bool get isAssign => this == TaskType.assign;
  bool get isFavor => this == TaskType.favor;
  bool get isCare => this == TaskType.care;

  String get displayName {
    switch (this) {
      case TaskType.assign:
        return 'Giao việc';
      case TaskType.favor:
        return 'Nhờ vả';
      case TaskType.care:
        return 'Chăm sóc Ông Bà';
    }
  }

  String get dbValue {
    switch (this) {
      case TaskType.assign:
        return 'ASSIGN';
      case TaskType.favor:
        return 'FAVOR';
      case TaskType.care:
        return 'CARE';
    }
  }

  static TaskType fromValue(dynamic value) {
    if (value is TaskType) return value;
    if (value == null) return TaskType.assign;
    final str = value.toString().toUpperCase().trim();
    if (str.contains('FAVOR')) return TaskType.favor;
    if (str.contains('CARE')) return TaskType.care;
    return TaskType.assign;
  }
}

enum TaskStatus {
  pending,
  inProgress,
  submitted,
  accepted,
  declined,
  completed,
  rejected;

  bool get isCompleted => this == TaskStatus.completed;
  bool get isPending => this == TaskStatus.pending;
  bool get isSubmitted => this == TaskStatus.submitted;
  bool get isRejected => this == TaskStatus.rejected;
  bool get isDeclined => this == TaskStatus.declined;

  String get displayName {
    switch (this) {
      case TaskStatus.pending:
        return 'Chờ thực hiện';
      case TaskStatus.inProgress:
        return 'Đang thực hiện';
      case TaskStatus.submitted:
        return 'Chờ duyệt';
      case TaskStatus.accepted:
        return 'Đã nhận lời';
      case TaskStatus.declined:
        return 'Đã từ chối';
      case TaskStatus.completed:
        return 'Đã hoàn thành';
      case TaskStatus.rejected:
        return 'Yêu cầu làm lại';
    }
  }

  String get dbValue {
    switch (this) {
      case TaskStatus.pending:
        return 'PENDING';
      case TaskStatus.inProgress:
        return 'IN_PROGRESS';
      case TaskStatus.submitted:
        return 'SUBMITTED';
      case TaskStatus.accepted:
        return 'ACCEPTED';
      case TaskStatus.declined:
        return 'DECLINED';
      case TaskStatus.completed:
        return 'COMPLETED';
      case TaskStatus.rejected:
        return 'REJECTED';
    }
  }

  static TaskStatus fromValue(dynamic value) {
    if (value is TaskStatus) return value;
    if (value == null) return TaskStatus.pending;
    final str = value.toString().toUpperCase().trim();
    if (str.contains('SUBMITTED')) return TaskStatus.submitted;
    if (str.contains('ACCEPTED')) return TaskStatus.accepted;
    if (str.contains('DECLINED')) return TaskStatus.declined;
    if (str.contains('COMPLETED') || str.contains('APPROVED')) {
      return TaskStatus.completed;
    }
    if (str.contains('REJECTED')) return TaskStatus.rejected;
    if (str.contains('IN_PROGRESS')) return TaskStatus.inProgress;
    return TaskStatus.pending;
  }
}

enum ReminderCategory {
  general,
  chore,
  favor,
  care,
  medication;

  String get dbValue => name.toUpperCase();
  static ReminderCategory fromValue(dynamic val) {
    if (val is ReminderCategory) return val;
    if (val == null) return ReminderCategory.general;
    final s = val.toString().toLowerCase();
    for (final c in ReminderCategory.values) {
      if (s.contains(c.name)) return c;
    }
    return ReminderCategory.general;
  }
}

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
  final String? familyName;
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
  final TaskType taskType;
  final TaskStatus taskStatus;
  final String? rejectionReason;
  final int delegationCount;
  final String? delegatedFromUserId;
  final String? originalTaskId;
  final String? creatorHierarchyRole;
  final String? targetHierarchyRole;
  final bool isClosedMissed;
  final DateTime? closedMissedAt;

  const ReminderModel({
    required this.id,
    required this.familyId,
    this.familyName,
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
    this.taskType = TaskType.assign,
    this.taskStatus = TaskStatus.pending,
    this.rejectionReason,
    this.delegationCount = 0,
    this.delegatedFromUserId,
    this.originalTaskId,
    this.creatorHierarchyRole,
    this.targetHierarchyRole,
    this.isClosedMissed = false,
    this.closedMissedAt,
  });

  bool get hasVoiceNote => voiceNotePath != null && voiceNotePath!.isNotEmpty;
  bool get hasProofImage => proofImageUrl != null && proofImageUrl!.isNotEmpty;
  bool get hasRewardStars => rewardStars > 0;

  bool get isOpen => status == ReminderStatus.open;
  bool get isPending =>
      (status == ReminderStatus.pending || status == 'PENDING') &&
      taskStatus.isPending;
  bool get isCompleted =>
      status == ReminderStatus.completed ||
      status == 'COMPLETED' ||
      status == 'APPROVED' ||
      taskStatus.isCompleted;
  bool get isDeleted => status == ReminderStatus.deleted;
  bool get isRecurring => repeatRule != null && repeatRule != 'NONE';
  bool get isSubmitted => status == 'SUBMITTED' || taskStatus.isSubmitted;
  bool get isRejected => status == 'REJECTED' || taskStatus.isRejected;
  bool get isDeclined => status == 'DECLINED' || taskStatus.isDeclined;
  bool get isAccepted =>
      status == 'ACCEPTED' || taskStatus == TaskStatus.accepted;

  bool get isAssign => taskType.isAssign;
  bool get isFavor => taskType.isFavor;
  bool get isCare => taskType.isCare;
  bool get canBeDelegated => isFavor && delegationCount < 1;
  bool get isExemptFromQuietHours =>
      isCare ||
      title.toLowerCase().contains('thuốc') ||
      title.toLowerCase().contains('medicine');

  String get statusDisplayName {
    if (isDeleted) return 'Đã xóa';
    if (isClosedMissed) return 'Đã đóng';
    if (isCompleted) return 'Đã xong';
    if (isRejected) return 'Yêu cầu làm lại';
    if (isSubmitted) return 'Chờ duyệt';
    if (taskStatus == TaskStatus.accepted) return 'Đã nhận lời';
    if (taskStatus == TaskStatus.declined) return 'Đã từ chối';
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
    if (isCompleted || isDeleted || isSubmitted || isClosedMissed) return false;
    if (status == ReminderStatus.overdue) return true;
    final dt = dueDateTime;
    if (dt != null && !dt.isAfter(DateTime.now())) return true;
    return false;
  }

  /// Kiểm tra xem nhắc việc có ngày thực hiện trong tương lai (sau ngày hôm nay) hay không.
  /// So sánh theo ngày (calendar date):
  /// - Nếu ngày hẹn > hôm nay (từ ngày mai trở đi): true (chưa đến ngày thực hiện, bị khóa hoàn thành).
  /// - Nếu ngày hẹn <= hôm nay (hôm nay hoặc đã quá hạn): false (đã mở, không khóa lại).
  bool isFutureDateAt([DateTime? referenceTime]) {
    final dt = dueDateTime;
    if (dt == null) return false;
    final now = referenceTime ?? DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final taskDay = DateTime(dt.year, dt.month, dt.day);
    return taskDay.isAfter(todayStart);
  }

  /// Trạng thái ngày hẹn có ở tương lai hay không (tính theo thời điểm hiện tại).
  bool get isFutureDate => isFutureDateAt();

  /// Trạng thái công việc có được phép hoàn thành hay không:
  /// Không thể hoàn thành nếu ngày làm việc nằm ở tương lai (chưa đến ngày).
  /// Khi đã đến ngày thực hiện (hôm nay hoặc quá hạn), việc được mở và không bị khóa lại.
  bool get canBeCompleted => !isFutureDate && !isClosedMissed;

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
    String? familyName,
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
    bool clearProofImage = false,
    int? rewardStars,
    String? voiceNotePath,
    int? voiceDurationSeconds,
    String? voiceNoteDescription,
    bool clearVoiceNote = false,
    DateTime? completedAt,
    DateTime? createdAt,
    TaskType? taskType,
    TaskStatus? taskStatus,
    String? rejectionReason,
    bool clearRejectionReason = false,
    int? delegationCount,
    String? delegatedFromUserId,
    String? originalTaskId,
    String? creatorHierarchyRole,
    String? targetHierarchyRole,
    bool? isClosedMissed,
    DateTime? closedMissedAt,
  }) {
    final newStatus = status ?? this.status;
    final newTaskStatus = taskStatus ??
        (status != null ? TaskStatus.fromValue(status) : this.taskStatus);

    return ReminderModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      familyName: familyName ?? this.familyName,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      title: title ?? this.title,
      date: date ?? this.date,
      time: time ?? this.time,
      status: newStatus,
      repeatRule: repeatRule ?? this.repeatRule,
      requiresProofImage: requiresProofImage ?? this.requiresProofImage,
      proofImageUrl:
          clearProofImage ? null : (proofImageUrl ?? this.proofImageUrl),
      rewardStars: rewardStars ?? this.rewardStars,
      voiceNotePath:
          clearVoiceNote ? null : (voiceNotePath ?? this.voiceNotePath),
      voiceDurationSeconds: clearVoiceNote
          ? null
          : (voiceDurationSeconds ?? this.voiceDurationSeconds),
      voiceNoteDescription: clearVoiceNote
          ? null
          : (voiceNoteDescription ?? this.voiceNoteDescription),
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      taskType: taskType ?? this.taskType,
      taskStatus: newTaskStatus,
      rejectionReason: clearRejectionReason
          ? null
          : (rejectionReason ?? this.rejectionReason),
      delegationCount: delegationCount ?? this.delegationCount,
      delegatedFromUserId: delegatedFromUserId ?? this.delegatedFromUserId,
      originalTaskId: originalTaskId ?? this.originalTaskId,
      creatorHierarchyRole:
          creatorHierarchyRole ?? this.creatorHierarchyRole,
      targetHierarchyRole: targetHierarchyRole ?? this.targetHierarchyRole,
      isClosedMissed: isClosedMissed ?? this.isClosedMissed,
      closedMissedAt: closedMissedAt ?? this.closedMissedAt,
    );
  }

  Map<String, dynamic> toMap() => toJson();
  Map<String, dynamic> toFirestore() => toFirestoreMap();

  factory ReminderModel.fromMap(dynamic idOrMap,
      [Map<String, dynamic>? maybeData]) {
    if (idOrMap is String && maybeData != null) {
      final map = Map<String, dynamic>.from(maybeData);
      map['id'] = idOrMap;
      return ReminderModel.fromJson(map);
    } else if (idOrMap is Map<String, dynamic>) {
      return ReminderModel.fromJson(idOrMap);
    } else {
      throw ArgumentError(
          'Invalid arguments to ReminderModel.fromMap: $idOrMap');
    }
  }

  factory ReminderModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final map = Map<String, dynamic>.from(data);
    map['id'] = doc.id;
    return ReminderModel.fromJson(map);
  }

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    String rawDate = (json['date'] ?? '').toString();
    // Normalize yyyy-MM-dd to dd/MM/yyyy if coming from Postgres
    if (rawDate.contains('-')) {
      final parts = rawDate.split('-');
      if (parts.length == 3) {
        rawDate =
            '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
      }
    }

    String rawTime = (json['time'] ?? '').toString();
    if (rawTime.length >= 5) {
      rawTime = rawTime.substring(0, 5);
    }

    final rawTaskType = json['taskType'] ?? json['task_type'];
    final parsedTaskType = TaskType.fromValue(rawTaskType);

    final rawTaskStatus = json['taskStatus'] ?? json['task_status'];
    final parsedTaskStatus = rawTaskStatus != null
        ? TaskStatus.fromValue(rawTaskStatus)
        : TaskStatus.fromValue(json['status']);

    final delegationCountVal = json['delegationCount'] is int
        ? json['delegationCount'] as int
        : (json['delegation_count'] is int
            ? json['delegation_count'] as int
            : (int.tryParse(
                    (json['delegationCount'] ?? json['delegation_count'] ?? 0)
                        .toString()) ??
                0));

    return ReminderModel(
      id: (json['id'] ?? '').toString(),
      familyId: (json['family_id'] ?? json['familyId'] ?? '').toString(),
      familyName:
          json['family_name'] as String? ?? json['familyName'] as String?,
      creatorId: (json['creator_id'] ?? json['creatorId'] ?? '').toString(),
      creatorName:
          json['creator_name'] as String? ?? json['creatorName'] as String?,
      assignedTo: (json['assigned_to'] ?? json['assignedTo'] ?? '').toString(),
      assignedToName: (json['assigned_to_name'] ??
              json['assignedToName'] ??
              '')
          .toString(),
      title: json['title'] as String? ?? '',
      date: rawDate,
      time: rawTime,
      status: json['status'] as String? ?? parsedTaskStatus.dbValue,
      repeatRule:
          (json['repeat_rule'] ?? json['repeatRule'] ?? 'NONE').toString(),
      requiresProofImage: json['requires_proof_image'] == true ||
          json['requiresProofImage'] == true ||
          (json['requires_proof_image'] ?? json['requiresProofImage'])
                  ?.toString()
                  .toLowerCase() ==
              'true' ||
          (json['requires_proof_image'] ?? json['requiresProofImage']) == 1 ||
          (json['requires_proof_image'] ?? json['requiresProofImage']) == '1',
      proofImageUrl: json['proof_image_url'] as String? ??
          json['proofImageUrl'] as String?,
      rewardStars: json['reward_stars'] is int
          ? json['reward_stars'] as int
          : (json['rewardStars'] is int
              ? json['rewardStars'] as int
              : (int.tryParse((json['reward_stars'] ??
                          json['rewardStars'] ??
                          0)
                      .toString()) ??
                  0)),
      voiceNotePath: json['voice_note_path'] as String? ??
          json['voiceNotePath'] as String?,
      voiceDurationSeconds: json['voice_duration_seconds'] is int
          ? json['voice_duration_seconds'] as int
          : (json['voiceDurationSeconds'] is int
              ? json['voiceDurationSeconds'] as int
              : (num.tryParse((json['voice_duration_seconds'] ??
                          json['voiceDurationSeconds'] ??
                          '')
                      .toString())
                  ?.toInt())),
      voiceNoteDescription: json['voice_note_description'] as String? ??
          json['voiceNoteDescription'] as String?,
      completedAt:
          _parseDateTime(json['completed_at'] ?? json['completedAt']),
      createdAt: _parseDateTime(json['created_at'] ?? json['createdAt']),
      taskType: parsedTaskType,
      taskStatus: parsedTaskStatus,
      rejectionReason: (json['rejectionReason'] ?? json['rejection_reason'])
          as String?,
      delegationCount: delegationCountVal,
      delegatedFromUserId: (json['delegatedFromUserId'] ??
          json['delegated_from_user_id'] ??
          json['delegatedFromId']) as String?,
      originalTaskId:
          (json['originalTaskId'] ?? json['original_task_id']) as String?,
      creatorHierarchyRole: (json['creatorHierarchyRole'] ??
          json['creator_hierarchy_role']) as String?,
      targetHierarchyRole: (json['targetHierarchyRole'] ??
          json['target_hierarchy_role']) as String?,
      isClosedMissed: json['isClosedMissed'] == true ||
          json['is_closed_missed'] == true ||
          json['closedMissedAt'] != null ||
          json['closed_missed_at'] != null ||
          json['status'] == 'CLOSED' ||
          json['status'] == 'MISSED',
      closedMissedAt: _parseDateTime(
          json['closedMissedAt'] ?? json['closed_missed_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse(value.toString());
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'familyId': familyId,
      'family_id': familyId,
      if (familyName != null) ...{
        'familyName': familyName,
        'family_name': familyName,
      },
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
      'taskType': taskType.dbValue,
      'task_type': taskType.dbValue,
      'taskStatus': taskStatus.dbValue,
      'task_status': taskStatus.dbValue,
      if (rejectionReason != null) ...{
        'rejectionReason': rejectionReason,
        'rejection_reason': rejectionReason,
      },
      'delegationCount': delegationCount,
      'delegation_count': delegationCount,
      if (delegatedFromUserId != null) ...{
        'delegatedFromUserId': delegatedFromUserId,
        'delegated_from_user_id': delegatedFromUserId,
      },
      if (originalTaskId != null) ...{
        'originalTaskId': originalTaskId,
        'original_task_id': originalTaskId,
      },
      if (creatorHierarchyRole != null) ...{
        'creatorHierarchyRole': creatorHierarchyRole,
        'creator_hierarchy_role': creatorHierarchyRole,
      },
      if (targetHierarchyRole != null) ...{
        'targetHierarchyRole': targetHierarchyRole,
        'target_hierarchy_role': targetHierarchyRole,
      },
      'isClosedMissed': isClosedMissed,
      'is_closed_missed': isClosedMissed,
      if (closedMissedAt != null) ...{
        'closedMissedAt': closedMissedAt!.toIso8601String(),
        'closed_missed_at': closedMissedAt!.toIso8601String(),
      },
    };
  }

  /// Maps directly to Cloud Firestore document format
  Map<String, dynamic> toFirestoreMap() {
    return {
      'familyId': familyId,
      'family_id': familyId,
      if (familyName != null) ...{
        'familyName': familyName,
        'family_name': familyName,
      },
      'creatorId': creatorId,
      'creator_id': creatorId,
      if (creatorName != null) ...{
        'creatorName': creatorName,
        'creator_name': creatorName,
      },
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
      'rewardStars': rewardStars,
      'reward_stars': rewardStars,
      if (proofImageUrl != null) ...{
        'proofImageUrl': proofImageUrl,
        'proof_image_url': proofImageUrl,
      },
      'voiceNotePath': voiceNotePath,
      'voice_note_path': voiceNotePath,
      'voiceDurationSeconds': voiceDurationSeconds,
      'voice_duration_seconds': voiceDurationSeconds,
      'voiceNoteDescription': voiceNoteDescription,
      'voice_note_description': voiceNoteDescription,
      if (completedAt != null) ...{
        'completedAt': Timestamp.fromDate(completedAt!),
        'completed_at': Timestamp.fromDate(completedAt!),
      },
      if (createdAt != null) ...{
        'createdAt': Timestamp.fromDate(createdAt!),
        'created_at': Timestamp.fromDate(createdAt!),
      },
      'taskType': taskType.dbValue,
      'task_type': taskType.dbValue,
      'taskStatus': taskStatus.dbValue,
      'task_status': taskStatus.dbValue,
      if (rejectionReason != null) ...{
        'rejectionReason': rejectionReason,
        'rejection_reason': rejectionReason,
      },
      'delegationCount': delegationCount,
      'delegation_count': delegationCount,
      if (delegatedFromUserId != null) ...{
        'delegatedFromUserId': delegatedFromUserId,
        'delegated_from_user_id': delegatedFromUserId,
      },
      if (originalTaskId != null) ...{
        'originalTaskId': originalTaskId,
        'original_task_id': originalTaskId,
      },
      if (creatorHierarchyRole != null) ...{
        'creatorHierarchyRole': creatorHierarchyRole,
        'creator_hierarchy_role': creatorHierarchyRole,
      },
      if (targetHierarchyRole != null) ...{
        'targetHierarchyRole': targetHierarchyRole,
        'target_hierarchy_role': targetHierarchyRole,
      },
      'isClosedMissed': isClosedMissed,
      'is_closed_missed': isClosedMissed,
      if (closedMissedAt != null) ...{
        'closedMissedAt': Timestamp.fromDate(closedMissedAt!),
        'closed_missed_at': Timestamp.fromDate(closedMissedAt!),
      },
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
          voiceNotePath == other.voiceNotePath &&
          taskType == other.taskType &&
          taskStatus == other.taskStatus &&
          delegationCount == other.delegationCount &&
          rejectionReason == other.rejectionReason;

  @override
  int get hashCode =>
      id.hashCode ^
      familyId.hashCode ^
      status.hashCode ^
      title.hashCode ^
      proofImageUrl.hashCode ^
      requiresProofImage.hashCode ^
      rewardStars.hashCode ^
      voiceNotePath.hashCode ^
      taskType.hashCode ^
      taskStatus.hashCode ^
      delegationCount.hashCode ^
      (rejectionReason?.hashCode ?? 0);
}

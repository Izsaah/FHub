import 'dart:async';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import 'multi_tier_escalation_service.dart';
import 'reminder_exceptions.dart';
import 'reminder_validator.dart';

// Re-export core exceptions for seamless encapsulation
export 'firebase_reminder_repository.dart';
export 'multi_tier_escalation_service.dart';
export 'reminder_exceptions.dart';
export 'supabase_reminder_repository.dart';

abstract class ReminderRepository {
  Future<List<ReminderModel>> getReminders({required String familyId});
  Stream<List<ReminderModel>> watchReminders({required String familyId});
  Future<List<ReminderModel>> getRemindersForFamilies({
    required List<String> familyIds,
  });
  Stream<List<ReminderModel>> watchRemindersForFamilies({
    required List<String> familyIds,
  });
  Future<List<ReminderModel>> getPendingReminders({required String familyId});
  Future<List<ReminderModel>> getCompletedReminders({required String familyId});

  Future<ReminderModel> createReminder({
    required ReminderModel reminder,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
    DateTime? now,
  });

  Future<ReminderModel> updateReminder({
    required ReminderModel reminder,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
    DateTime? now,
  });

  Future<ReminderModel> completeReminder({
    required String reminderId,
    required String currentUserId,
    String? proofImageUrl,
    bool allowFutureCompletion = false,
  });

  Future<ReminderModel> claimOpenTask({
    required String reminderId,
    required String currentUserId,
    required String currentUserName,
  });

  Future<ReminderModel> claimAndCompleteOpenTask({
    required String reminderId,
    required String currentUserId,
    required String currentUserName,
    String? proofImageUrl,
    bool allowFutureCompletion = false,
  });

  Future<bool> deleteReminder({
    required String reminderId,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
  });

  Future<bool> restoreReminder({
    required String reminderId,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
  });

  /// Kiểm tra xung đột lịch trình: Tìm xem thành viên [userId] đã có công việc nào
  /// cùng ngày [date] và cùng giờ [time] ở bất kỳ gia đình nào chưa.
  Future<ReminderModel?> checkScheduleConflict({
    required String userId,
    required String date,
    required String time,
    String? excludeReminderId,
  });

  /// Kiểm tra trùng lặp công việc: Tìm xem trong gia đình [familyId] đã có công việc
  /// cùng [title], [date] và [time] chưa.
  Future<ReminderModel?> findDuplicateReminder({
    required String familyId,
    required String title,
    required String date,
    required String time,
    String? excludeReminderId,
  });

  Future<void> submitTaskWithProof({
    required String taskId,
    required String proofImageUrl,
  });

  Future<void> rejectTaskSubmission({
    required String taskId,
    required String reason,
  });

  Future<ReminderModel> delegateFavorTask({
    required String taskId,
    required String delegatedToUserId,
    required String delegatedToUserName,
    required String currentUserId,
    required String currentUserRole,
    required String targetUserRole,
  });

  Future<void> acceptFavorTask(String taskId);

  Future<void> declineFavorTask(String taskId);

  Future<void> approveTaskSubmission({
    required String taskId,
    required String reviewerId,
    required String reviewerName,
  });
}

/// Returns cultural hierarchy level for role or member:
/// Grandparent = 3, Parent/Owner/Admin = 2, Member = 1, Child = 0
int getMemberHierarchyLevel(dynamic memberOrRole) {
  if (memberOrRole == null) return 1;
  String str = '';
  if (memberOrRole is FamilyMember) {
    if (memberOrRole.isGrandparent) return 3;
    if (memberOrRole.isParent) return 2;
    if (memberOrRole.isChild) return 0;
    str = '${memberOrRole.role} ${memberOrRole.name}';
  } else {
    str = memberOrRole.toString();
  }
  final upper = str.toUpperCase();
  if (upper.contains('GRANDPARENT') ||
      upper.contains('TRƯỞNG BỐI') ||
      upper.contains('TRUONG BOI') ||
      upper.contains('ÔNG') ||
      upper.contains('BÀ')) {
    return 3;
  }
  if (upper.contains('PARENT') ||
      upper.contains('OWNER') ||
      upper.contains('ADMIN') ||
      upper.contains('DAD') ||
      upper.contains('MOM') ||
      upper.contains('BỐ') ||
      upper.contains('MẸ')) {
    return 2;
  }
  if (upper.contains('CHILD') ||
      upper.contains('KID') ||
      upper.contains('CON') ||
      upper.contains('TRẺ')) {
    return 0;
  }
  return 1;
}

class InMemoryReminderRepository implements ReminderRepository {
  final List<ReminderModel> _reminders = [];
  final _controller = StreamController<List<ReminderModel>>.broadcast();

  InMemoryReminderRepository({List<ReminderModel>? initialReminders}) {
    if (initialReminders != null) {
      _reminders.addAll(initialReminders);
    } else {
      _seedDefaultData();
    }
  }

  void _seedDefaultData() {
    final now = DateTime.now();
    final todayStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.day.toString().padLeft(2, '0')}/${yesterday.month.toString().padLeft(2, '0')}/${yesterday.year}';

    _reminders.addAll([
      // 1. Việc nhà cho con: Yêu cầu chụp ảnh nghiệm thu + Thưởng 3 sao
      ReminderModel(
        id: 'rem_chore_1',
        familyId: 'family_1',
        creatorId: 'user_mom',
        creatorName: 'Mom',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Rửa bát & dọn bếp sau bữa tối',
        date: todayStr,
        time: '20:00',
        status: ReminderStatus.pending,
        repeatRule: 'DAILY',
        requiresProofImage: true,
        rewardStars: 3,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      // 2. Việc chung gia đình (Open Task): Cả nhà xung phong nhận việc + 2 sao
      ReminderModel(
        id: 'rem_open_1',
        familyId: 'family_1',
        creatorId: 'user_dad',
        creatorName: 'Dad',
        assignedTo: 'OPEN',
        assignedToName: 'Cả nhà',
        title: 'Dọn dẹp phòng khách đón khách',
        date: todayStr,
        time: '17:30',
        status: ReminderStatus.open,
        repeatRule: 'NONE',
        requiresProofImage: true,
        rewardStars: 2,
        createdAt: now.subtract(const Duration(hours: 4)),
      ),
      // 3. Việc quá hạn
      ReminderModel(
        id: 'rem_overdue_1',
        familyId: 'family_1',
        creatorId: 'user_mom',
        creatorName: 'Mom',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Nộp tiền điện nước tháng này',
        date: yesterdayStr,
        time: '09:00',
        status: ReminderStatus.overdue,
        repeatRule: 'NONE',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      // 4. Lời nhắc uống thuốc hàng ngày (con nhắc mẹ)
      ReminderModel(
        id: 'rem_1',
        familyId: 'family_1',
        creatorId: 'user_minh',
        creatorName: 'Minh',
        assignedTo: 'user_mom',
        assignedToName: 'Mom',
        title: 'Uống thuốc huyết áp buổi sáng',
        date: todayStr,
        time: '08:00',
        status: ReminderStatus.open,
        repeatRule: 'DAILY',
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      // 5. Việc mua sữa hàng tuần (nhờ bố)
      ReminderModel(
        id: 'rem_2',
        familyId: 'family_1',
        creatorId: 'user_minh',
        creatorName: 'Minh',
        assignedTo: 'user_dad',
        assignedToName: 'Dad',
        title: 'Mua sữa hạt và trái cây',
        date: todayStr,
        time: '18:00',
        status: ReminderStatus.pending,
        repeatRule: 'WEEKLY',
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      // 6. Việc đã hoàn thành kèm ảnh nghiệm thu & 2 sao
      ReminderModel(
        id: 'rem_3',
        familyId: 'family_1',
        creatorId: 'user_mom',
        creatorName: 'Mom',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Gấp quần áo & dọn phòng ngủ',
        date: todayStr,
        time: '12:00',
        status: ReminderStatus.completed,
        repeatRule: 'NONE',
        requiresProofImage: true,
        rewardStars: 2,
        proofImageUrl:
            'https://images.unsplash.com/photo-1540518614846-7ede433c4ef4?auto=format&fit=crop&w=400&q=80',
        completedAt: now.subtract(const Duration(minutes: 30)),
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      // 7. Lời nhắc thoại từ Mẹ
      ReminderModel(
        id: 'rem_voice_1',
        familyId: 'family_1',
        creatorId: 'user_mom',
        creatorName: 'Mom',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Lời nhắn thoại từ Mẹ',
        date: todayStr,
        time: '19:30',
        status: ReminderStatus.pending,
        repeatRule: 'NONE',
        voiceNotePath: 'assets/audio/sample_voice_reminder.wav',
        voiceDurationSeconds: 3,
        voiceNoteDescription:
            'Mẹ dặn nhớ uống 2 viên vitamin và ăn tối trước 8h nhé con!',
        createdAt: now.subtract(const Duration(minutes: 40)),
      ),
    ]);
  }

  void _notify(String familyId) {
    final active = _reminders.where((r) => !r.isDeleted).toList();
    _controller.add(List.unmodifiable(active));
  }

  @override
  Future<List<ReminderModel>> getReminders({required String familyId}) async {
    return _reminders
        .where((r) => r.familyId == familyId && !r.isDeleted)
        .toList();
  }

  @override
  Stream<List<ReminderModel>> watchReminders({required String familyId}) async* {
    yield await getReminders(familyId: familyId);
    yield* _controller.stream.map(
      (list) =>
          list.where((r) => r.familyId == familyId && !r.isDeleted).toList(),
    );
  }

  @override
  Future<List<ReminderModel>> getRemindersForFamilies({
    required List<String> familyIds,
  }) async {
    if (familyIds.isEmpty) return [];
    final idSet = familyIds.toSet();
    return _reminders
        .where((r) => idSet.contains(r.familyId) && !r.isDeleted)
        .toList();
  }

  @override
  Stream<List<ReminderModel>> watchRemindersForFamilies({
    required List<String> familyIds,
  }) async* {
    if (familyIds.isEmpty) {
      yield [];
      return;
    }
    final idSet = familyIds.toSet();
    yield await getRemindersForFamilies(familyIds: familyIds);
    yield* _controller.stream.map(
      (list) =>
          list.where((r) => idSet.contains(r.familyId) && !r.isDeleted).toList(),
    );
  }

  @override
  Future<List<ReminderModel>> getPendingReminders({
    required String familyId,
  }) async {
    return _reminders
        .where((r) => r.familyId == familyId && r.isPending)
        .toList();
  }

  @override
  Future<List<ReminderModel>> getCompletedReminders({
    required String familyId,
  }) async {
    return _reminders
        .where((r) => r.familyId == familyId && r.isCompleted)
        .toList();
  }

  @override
  Future<ReminderModel> createReminder({
    required ReminderModel reminder,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
    DateTime? now,
  }) async {
    // 1. Validate Title
    final titleError = ReminderValidator.validateTitle(reminder.title);
    if (titleError != null) {
      throw ReminderValidationException(titleError);
    }

    // 2. Validate Assigned Member if list provided (allow open task: OPEN / ALL)
    if (familyMembers != null &&
        familyMembers.isNotEmpty &&
        reminder.assignedTo != 'OPEN' &&
        reminder.assignedTo != 'ALL' &&
        reminder.assignedTo.isNotEmpty) {
      final memberError = ReminderValidator.validateAssignedMember(
        reminder.assignedTo,
        familyMembers,
      );
      if (memberError != null) {
        throw ReminderValidationException(memberError);
      }
    }

    // 3. Validate Date + Time must be in the future
    final futureError = ReminderValidator.validateFutureDateTimeFromStrings(
      reminder.date,
      reminder.time,
      now: now,
    );
    if (futureError != null) {
      throw ReminderValidationException(futureError);
    }

    // 4. Validate creator matches current user
    if (reminder.creatorId != currentUserId) {
      throw ReminderPermissionException(
        'Only the creator can set their ID as creator',
      );
    }

    // 5. Cultural Hierarchy Check
    if (reminder.taskType == TaskType.assign) {
      int creatorLevel = 1;
      int targetLevel = 1;

      if (reminder.creatorHierarchyRole != null) {
        creatorLevel = getMemberHierarchyLevel(reminder.creatorHierarchyRole);
      } else if (familyMembers != null && familyMembers.isNotEmpty) {
        try {
          final cm = familyMembers.firstWhere((m) => m.id == currentUserId);
          creatorLevel = getMemberHierarchyLevel(cm);
        } catch (_) {}
      }

      if (reminder.targetHierarchyRole != null) {
        targetLevel = getMemberHierarchyLevel(reminder.targetHierarchyRole);
      } else if (familyMembers != null && familyMembers.isNotEmpty) {
        try {
          final tm =
              familyMembers.firstWhere((m) => m.id == reminder.assignedTo);
          targetLevel = getMemberHierarchyLevel(tm);
        } catch (_) {}
      }

      if (reminder.assignedTo != 'OPEN' &&
          reminder.assignedTo != 'ALL' &&
          reminder.assignedTo != currentUserId &&
          reminder.assignedTo.isNotEmpty) {
        if (creatorLevel < targetLevel) {
          throw StateError(
            'CULTURE_HIERARCHY_VIOLATION: Trẻ em không được giao việc bắt buộc có thưởng/phạt cho người lớn.',
          );
        }
      }
    }

    final newReminder = reminder.copyWith(
      id: reminder.id.isEmpty
          ? 'rem_${DateTime.now().millisecondsSinceEpoch}'
          : reminder.id,
      createdAt: now ?? DateTime.now(),
    );

    _reminders.add(newReminder);
    MultiTierEscalationService.instance.scheduleMultiTierEscalation(newReminder);
    _notify(newReminder.familyId);
    return newReminder;
  }

  @override
  Future<ReminderModel> updateReminder({
    required ReminderModel reminder,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
    DateTime? now,
  }) async {
    final index =
        _reminders.indexWhere((r) => r.id == reminder.id && !r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];

    // Rule: Chỉ người tạo (Creator) HOẶC Cha Mẹ/Chủ nhà mới có quyền chỉnh sửa reminder.
    final isCreator = existing.creatorId == currentUserId;
    bool isParentOrOwner = false;
    if (familyMembers != null && familyMembers.isNotEmpty) {
      final currentMember = familyMembers.firstWhere(
        (m) => m.id == currentUserId,
        orElse: () =>
            const FamilyMember(id: '', name: '', role: '', familyId: ''),
      );
      final roleUpper = currentMember.role.toUpperCase();
      isParentOrOwner = roleUpper.contains('PARENT') ||
          roleUpper.contains('OWNER') ||
          roleUpper.contains('GRANDPARENT');
    }

    if (!isCreator && !isParentOrOwner) {
      throw const ReminderPermissionException(
        'Only the creator or a parent/owner can edit this reminder',
      );
    }

    // 1. Validate sanitized Title
    final sanitizedTitle = ReminderValidator.sanitizeTitle(reminder.title);
    final titleError = ReminderValidator.validateTitle(sanitizedTitle);
    if (titleError != null) {
      throw ReminderValidationException(titleError);
    }

    // 2. Validate Assigned Member if list provided (allow open task)
    if (familyMembers != null &&
        familyMembers.isNotEmpty &&
        reminder.assignedTo != 'OPEN' &&
        reminder.assignedTo != 'ALL' &&
        reminder.assignedTo.isNotEmpty) {
      final memberError = ReminderValidator.validateAssignedMember(
        reminder.assignedTo,
        familyMembers,
      );
      if (memberError != null) {
        throw ReminderValidationException(memberError);
      }
    }

    // 3. Validate Date + Time must be in the future (Chỉ kiểm tra nếu ngày hoặc giờ thay đổi)
    final isDateTimeChanged =
        existing.date != reminder.date || existing.time != reminder.time;
    if (isDateTimeChanged) {
      final futureError = ReminderValidator.validateFutureDateTimeFromStrings(
        reminder.date,
        reminder.time,
        now: now,
      );
      if (futureError != null) {
        throw ReminderValidationException(futureError);
      }
    }

    final updated = existing.copyWith(
      title: sanitizedTitle,
      assignedTo: reminder.assignedTo,
      assignedToName: reminder.assignedToName,
      date: reminder.date,
      time: reminder.time,
      repeatRule: reminder.repeatRule,
      requiresProofImage: reminder.requiresProofImage,
      proofImageUrl: reminder.proofImageUrl,
      rewardStars: reminder.rewardStars,
      voiceNotePath: reminder.voiceNotePath,
      voiceDurationSeconds: reminder.voiceDurationSeconds,
      voiceNoteDescription: reminder.voiceNoteDescription,
      clearVoiceNote: reminder.voiceNotePath == null,
      status: reminder.status,
    );

    _reminders[index] = updated;
    MultiTierEscalationService.instance.scheduleMultiTierEscalation(updated);
    _notify(existing.familyId);
    return updated;
  }

  @override
  Future<ReminderModel> claimOpenTask({
    required String reminderId,
    required String currentUserId,
    required String currentUserName,
  }) async {
    final index =
        _reminders.indexWhere((r) => r.id == reminderId && !r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];
    if (existing.isCompleted) {
      throw ReminderValidationException('Công việc này đã hoàn thành!');
    }
    if (!existing.isOpenTask && existing.assignedTo != currentUserId) {
      throw ReminderValidationException(
        'Công việc này đã được ${existing.assignedToName.isNotEmpty ? existing.assignedToName : 'thành viên khác'} nhận trước đó!',
      );
    }

    final updated = existing.copyWith(
      assignedTo: currentUserId,
      assignedToName: currentUserName,
      status: ReminderStatus.pending,
    );

    _reminders[index] = updated;
    MultiTierEscalationService.instance.scheduleMultiTierEscalation(updated);
    _notify(existing.familyId);
    return updated;
  }

  @override
  Future<ReminderModel> claimAndCompleteOpenTask({
    required String reminderId,
    required String currentUserId,
    required String currentUserName,
    String? proofImageUrl,
    bool allowFutureCompletion = false,
  }) async {
    final index =
        _reminders.indexWhere((r) => r.id == reminderId && !r.isDeleted);
    if (index != -1 && !allowFutureCompletion && _reminders[index].isFutureDate) {
      throw ReminderValidationException(
        'Công việc này được lên lịch cho ngày ${_reminders[index].date}. Chỉ có thể đánh dấu hoàn thành khi đến đúng ngày hẹn!',
      );
    }
    await claimOpenTask(
      reminderId: reminderId,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
    );
    return completeReminder(
      reminderId: reminderId,
      currentUserId: currentUserId,
      proofImageUrl: proofImageUrl,
      allowFutureCompletion: allowFutureCompletion,
    );
  }

  DateTime? _calculateNextDueDate(String dateStr, String repeatRule) {
    try {
      final parts = dateStr.trim().split('/');
      if (parts.length != 3) return null;
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      if (repeatRule == 'DAILY') {
        return DateTime(year, month, day + 1);
      } else if (repeatRule == 'WEEKLY') {
        return DateTime(year, month, day + 7);
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<ReminderModel> completeReminder({
    required String reminderId,
    required String currentUserId,
    String? proofImageUrl,
    bool allowFutureCompletion = false,
  }) async {
    final index =
        _reminders.indexWhere((r) => r.id == reminderId && !r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];

    // Rule: Chỉ người được giao reminder mới được Complete.
    if (existing.assignedTo != currentUserId) {
      throw ReminderPermissionException(
        'Only the assigned member can complete this reminder',
      );
    }

    // Rule: Khóa hoàn thành nếu ngày thực hiện nằm ở tương lai (chưa đến ngày hẹn)
    if (!allowFutureCompletion && existing.isFutureDate) {
      throw ReminderValidationException(
        'Công việc này được lên lịch cho ngày ${existing.date}. Chỉ có thể đánh dấu hoàn thành khi đến đúng ngày hẹn!',
      );
    }

    // Rule AC3: Bắt buộc đính kèm ảnh nếu requiresProofImage == true
    final effectiveProof = proofImageUrl ?? existing.proofImageUrl;
    if (existing.requiresProofImage &&
        (effectiveProof == null || effectiveProof.isEmpty)) {
      throw ReminderValidationException(
        'Công việc này bắt buộc phải có ảnh nghiệm thu trước khi hoàn thành!',
      );
    }

    final updated = existing.copyWith(
      status: ReminderStatus.completed,
      completedAt: DateTime.now(),
      proofImageUrl: effectiveProof,
    );

    _reminders[index] = updated;

    // Tự động sinh chu kỳ tiếp theo cho lời nhắc lặp lại (DAILY / WEEKLY)
    final rule = existing.repeatRule;
    if (rule == 'DAILY' || rule == 'WEEKLY') {
      final nextDate = _calculateNextDueDate(existing.date, rule!);
      if (nextDate != null) {
        final nextDateStr =
            '${nextDate.day.toString().padLeft(2, '0')}/${nextDate.month.toString().padLeft(2, '0')}/${nextDate.year}';
        final nextReminder = ReminderModel(
          id: 'rem_${DateTime.now().millisecondsSinceEpoch}_repeat',
          familyId: existing.familyId,
          creatorId: existing.creatorId,
          creatorName: existing.creatorName,
          assignedTo: existing.assignedTo,
          assignedToName: existing.assignedToName,
          title: existing.title,
          date: nextDateStr,
          time: existing.time,
          repeatRule: existing.repeatRule,
          status:
              existing.isOpenTask ? ReminderStatus.open : ReminderStatus.pending,
          requiresProofImage: existing.requiresProofImage,
          rewardStars: 0,
          voiceNotePath: existing.voiceNotePath,
          voiceDurationSeconds: existing.voiceDurationSeconds,
          voiceNoteDescription: existing.voiceNoteDescription,
          createdAt: DateTime.now(),
        );
        _reminders.add(nextReminder);
        MultiTierEscalationService.instance
            .scheduleMultiTierEscalation(nextReminder);
      }
    }

    MultiTierEscalationService.instance.cancelEscalation(reminderId);
    _notify(existing.familyId);
    return updated;
  }

  @override
  Future<bool> deleteReminder({
    required String reminderId,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
  }) async {
    final index =
        _reminders.indexWhere((r) => r.id == reminderId && !r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];

    // Rule: Cho phép xóa nếu là người tạo HOẶC là Bố/Mẹ/Ông/Bà/Chủ nhà
    final isCreator = existing.creatorId == currentUserId;
    bool isParentOrOwner = false;
    if (familyMembers != null && familyMembers.isNotEmpty) {
      final currentMember = familyMembers.firstWhere(
        (m) => m.id == currentUserId,
        orElse: () =>
            const FamilyMember(id: '', name: '', role: '', familyId: ''),
      );
      final roleUpper = currentMember.role.toUpperCase();
      isParentOrOwner = roleUpper.contains('PARENT') ||
          roleUpper.contains('OWNER') ||
          roleUpper.contains('GRANDPARENT');
    }

    if (!isCreator && !isParentOrOwner) {
      throw ReminderPermissionException(
        'Only the creator or a parent/owner can delete this reminder',
      );
    }

    final updated = existing.copyWith(
      status: ReminderStatus.deleted,
    );

    _reminders[index] = updated;
    MultiTierEscalationService.instance.cancelEscalation(reminderId);
    _notify(existing.familyId);
    return true;
  }

  @override
  Future<ReminderModel?> checkScheduleConflict({
    required String userId,
    required String date,
    required String time,
    String? excludeReminderId,
  }) async {
    final cleanDate = date.trim();
    final cleanTime = time.trim();
    return _reminders.where((r) {
      if (r.isDeleted || r.isCompleted) return false;
      if (excludeReminderId != null && r.id == excludeReminderId) return false;
      return r.assignedTo == userId &&
          r.date.trim() == cleanDate &&
          r.time.trim() == cleanTime;
    }).firstOrNull;
  }

  @override
  Future<ReminderModel?> findDuplicateReminder({
    required String familyId,
    required String title,
    required String date,
    required String time,
    String? excludeReminderId,
  }) async {
    final cleanTitle = ReminderValidator.sanitizeTitle(title).toLowerCase();
    final cleanDate = date.trim();
    final cleanTime = time.trim();
    return _reminders.where((r) {
      if (r.isDeleted || r.isCompleted || r.familyId != familyId) return false;
      if (excludeReminderId != null && r.id == excludeReminderId) return false;
      return r.title.trim().toLowerCase() == cleanTitle &&
          r.date.trim() == cleanDate &&
          r.time.trim() == cleanTime;
    }).firstOrNull;
  }

  @override
  Future<bool> restoreReminder({
    required String reminderId,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
  }) async {
    final index =
        _reminders.indexWhere((r) => r.id == reminderId && r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];
    final isCreator = existing.creatorId == currentUserId;
    bool isParentOrOwner = false;
    if (familyMembers != null && familyMembers.isNotEmpty) {
      final currentMember = familyMembers.firstWhere(
        (m) => m.id == currentUserId,
        orElse: () =>
            const FamilyMember(id: '', name: '', role: '', familyId: ''),
      );
      final roleUpper = currentMember.role.toUpperCase();
      isParentOrOwner = roleUpper.contains('PARENT') ||
          roleUpper.contains('OWNER') ||
          roleUpper.contains('GRANDPARENT');
    }

    if (!isCreator && !isParentOrOwner) {
      throw ReminderPermissionException(
        'Only creator or parent/owner can restore this reminder',
      );
    }

    final isOpenTarget = existing.assignedTo == 'OPEN' ||
        existing.assignedTo == 'ALL' ||
        existing.assignedTo.isEmpty;
    final restoredStatus = isOpenTarget
        ? ReminderStatus.open
        : (existing.completedAt != null
            ? ReminderStatus.completed
            : ReminderStatus.pending);

    final updated = existing.copyWith(
      status: restoredStatus,
    );

    _reminders[index] = updated;
    _notify(existing.familyId);
    return true;
  }

  @override
  Future<void> submitTaskWithProof({
    required String taskId,
    required String proofImageUrl,
  }) async {
    final index = _reminders.indexWhere((r) => r.id == taskId && !r.isDeleted);
    if (index == -1) {
      throw const ReminderNotFoundException('Không tìm thấy công việc');
    }
    final existing = _reminders[index];
    final updated = existing.copyWith(
      proofImageUrl: proofImageUrl,
      taskStatus: TaskStatus.submitted,
      status: 'SUBMITTED',
      clearRejectionReason: true,
    );
    _reminders[index] = updated;
    _notify(updated.familyId);
  }

  @override
  Future<void> rejectTaskSubmission({
    required String taskId,
    required String reason,
  }) async {
    final index = _reminders.indexWhere((r) => r.id == taskId && !r.isDeleted);
    if (index == -1) {
      throw const ReminderNotFoundException('Không tìm thấy công việc');
    }
    final existing = _reminders[index];
    final updated = existing.copyWith(
      clearProofImage: true,
      rejectionReason: reason,
      taskStatus: TaskStatus.pending,
      status: ReminderStatus.pending,
    );
    _reminders[index] = updated;
    _notify(updated.familyId);
  }

  @override
  Future<ReminderModel> delegateFavorTask({
    required String taskId,
    required String delegatedToUserId,
    required String delegatedToUserName,
    required String currentUserId,
    required String currentUserRole,
    required String targetUserRole,
  }) async {
    final index = _reminders.indexWhere((r) => r.id == taskId && !r.isDeleted);
    if (index == -1) {
      throw const ReminderNotFoundException('Không tìm thấy công việc');
    }
    final existing = _reminders[index];

    if (existing.delegationCount >= 1) {
      throw StateError(
        'DELEGATION_LIMIT_EXCEEDED: Nhờ vả chỉ được chuyển tiếp tối đa 1 lần.',
      );
    }

    final currentLevel = getMemberHierarchyLevel(currentUserRole);
    final targetLevel = getMemberHierarchyLevel(targetUserRole);

    if (currentLevel < targetLevel && currentLevel == 0) {
      throw StateError(
        'CULTURE_HIERARCHY_VIOLATION: Trẻ em không được chuyển tiếp công việc lên cho người lớn.',
      );
    }
    if (currentLevel < targetLevel) {
      throw StateError(
        'CULTURE_HIERARCHY_VIOLATION: Không được chuyển tiếp công việc lên cấp bậc cao hơn.',
      );
    }

    final updated = existing.copyWith(
      assignedTo: delegatedToUserId,
      assignedToName: delegatedToUserName,
      delegationCount: existing.delegationCount + 1,
      delegatedFromUserId: currentUserId,
      taskType: TaskType.favor,
    );
    _reminders[index] = updated;
    _notify(updated.familyId);
    return updated;
  }

  @override
  Future<void> acceptFavorTask(String taskId) async {
    final index = _reminders.indexWhere((r) => r.id == taskId && !r.isDeleted);
    if (index == -1) {
      throw const ReminderNotFoundException('Không tìm thấy công việc');
    }
    final existing = _reminders[index];
    final updated = existing.copyWith(
      taskStatus: TaskStatus.accepted,
      status: 'ACCEPTED',
    );
    _reminders[index] = updated;
    _notify(updated.familyId);
  }

  @override
  Future<void> declineFavorTask(String taskId) async {
    final index = _reminders.indexWhere((r) => r.id == taskId && !r.isDeleted);
    if (index == -1) {
      throw const ReminderNotFoundException('Không tìm thấy công việc');
    }
    final existing = _reminders[index];
    final updated = existing.copyWith(
      taskStatus: TaskStatus.declined,
      status: 'DECLINED',
    );
    _reminders[index] = updated;
    _notify(updated.familyId);
  }

  @override
  Future<void> approveTaskSubmission({
    required String taskId,
    required String reviewerId,
    required String reviewerName,
  }) async {
    final index = _reminders.indexWhere((r) => r.id == taskId && !r.isDeleted);
    if (index == -1) {
      throw const ReminderNotFoundException('Không tìm thấy công việc');
    }
    final existing = _reminders[index];
    final updated = existing.copyWith(
      taskStatus: TaskStatus.completed,
      status: ReminderStatus.completed,
      completedAt: DateTime.now(),
    );
    _reminders[index] = updated;
    _notify(updated.familyId);
  }

  void dispose() {
    _controller.close();
  }
}

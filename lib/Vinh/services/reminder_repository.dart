import 'dart:async';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import 'reminder_exceptions.dart';
import 'reminder_validator.dart';

// Re-export core exceptions for seamless encapsulation
export 'reminder_exceptions.dart';
export 'supabase_reminder_repository.dart';

abstract class ReminderRepository {
  Future<List<ReminderModel>> getReminders({required String familyId});
  Stream<List<ReminderModel>> watchReminders({required String familyId});
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
  });

  Future<ReminderModel> claimOpenTask({
    required String reminderId,
    required String currentUserId,
    required String currentUserName,
  });

  Future<bool> deleteReminder({
    required String reminderId,
    required String currentUserId,
  });

  Future<bool> restoreReminder({
    required String reminderId,
    required String currentUserId,
  });
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
        voiceNoteDescription: 'Mẹ dặn nhớ uống 2 viên vitamin và ăn tối trước 8h nhé con!',
        createdAt: now.subtract(const Duration(minutes: 40)),
      ),
    ]);
  }

  void _notify(String familyId) {
    final active = _reminders
        .where((r) => r.familyId == familyId && !r.isDeleted)
        .toList();
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
      (list) => list.where((r) => r.familyId == familyId && !r.isDeleted).toList(),
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

    final newReminder = reminder.copyWith(
      id: reminder.id.isEmpty
          ? 'rem_${DateTime.now().millisecondsSinceEpoch}'
          : reminder.id,
      createdAt: now ?? DateTime.now(),
    );

    _reminders.add(newReminder);
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
    final index = _reminders.indexWhere((r) => r.id == reminder.id && !r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];

    // Rule: Chỉ người tạo (Creator) mới có quyền chỉnh sửa reminder.
    if (existing.creatorId != currentUserId) {
      throw ReminderPermissionException(
        'Only the creator can edit this reminder',
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

    // 3. Validate Date + Time must be in the future
    final futureError = ReminderValidator.validateFutureDateTimeFromStrings(
      reminder.date,
      reminder.time,
      now: now,
    );
    if (futureError != null) {
      throw ReminderValidationException(futureError);
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
    );

    _reminders[index] = updated;
    _notify(existing.familyId);
    return updated;
  }

  @override
  Future<ReminderModel> claimOpenTask({
    required String reminderId,
    required String currentUserId,
    required String currentUserName,
  }) async {
    final index = _reminders.indexWhere((r) => r.id == reminderId && !r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];
    if (existing.isCompleted) {
      throw ReminderValidationException('Công việc này đã hoàn thành!');
    }

    final updated = existing.copyWith(
      assignedTo: currentUserId,
      assignedToName: currentUserName,
      status: ReminderStatus.pending,
    );

    _reminders[index] = updated;
    _notify(existing.familyId);
    return updated;
  }

  @override
  Future<ReminderModel> completeReminder({
    required String reminderId,
    required String currentUserId,
    String? proofImageUrl,
  }) async {
    final index = _reminders.indexWhere((r) => r.id == reminderId && !r.isDeleted);
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

    // Rule AC3: Bắt buộc đính kèm ảnh nếu requiresProofImage == true
    final effectiveProof = proofImageUrl ?? existing.proofImageUrl;
    if (existing.requiresProofImage && (effectiveProof == null || effectiveProof.isEmpty)) {
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
    _notify(existing.familyId);
    return updated;
  }

  @override
  Future<bool> deleteReminder({
    required String reminderId,
    required String currentUserId,
  }) async {
    final index = _reminders.indexWhere((r) => r.id == reminderId && !r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];

    // Rule: Chỉ creator được delete: creator == currentUser. Người nhận không được delete.
    if (existing.creatorId != currentUserId) {
      throw ReminderPermissionException(
        'Only creator can delete this reminder',
      );
    }

    final updated = existing.copyWith(
      status: ReminderStatus.deleted,
    );

    _reminders[index] = updated;
    _notify(existing.familyId);
    return true;
  }

  @override
  Future<bool> restoreReminder({
    required String reminderId,
    required String currentUserId,
  }) async {
    final index =
        _reminders.indexWhere((r) => r.id == reminderId && r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];
    if (existing.creatorId != currentUserId) {
      throw ReminderPermissionException(
        'Only creator can restore this reminder',
      );
    }

    final updated = existing.copyWith(
      status: ReminderStatus.pending,
    );

    _reminders[index] = updated;
    _notify(existing.familyId);
    return true;
  }

  void dispose() {
    _controller.close();
  }
}

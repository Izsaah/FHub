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

  Future<ReminderModel> completeReminder({
    required String reminderId,
    required String currentUserId,
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

    _reminders.addAll([
      ReminderModel(
        id: 'rem_1',
        familyId: 'family_1',
        creatorId: 'user_minh',
        creatorName: 'Minh',
        assignedTo: 'user_mom',
        assignedToName: 'Mom',
        title: 'Take medicine',
        date: todayStr,
        time: '08:00',
        status: ReminderStatus.pending,
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      ReminderModel(
        id: 'rem_2',
        familyId: 'family_1',
        creatorId: 'user_minh',
        creatorName: 'Minh',
        assignedTo: 'user_dad',
        assignedToName: 'Dad',
        title: 'Buy milk',
        date: todayStr,
        time: '18:00',
        status: ReminderStatus.pending,
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      ReminderModel(
        id: 'rem_3',
        familyId: 'family_1',
        creatorId: 'user_dad',
        creatorName: 'Dad',
        assignedTo: 'user_minh',
        assignedToName: 'Minh',
        title: 'Buy vegetables',
        date: todayStr,
        time: '12:00',
        status: ReminderStatus.completed,
        completedAt: now.subtract(const Duration(minutes: 30)),
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
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

    // 2. Validate Assigned Member if list provided
    if (familyMembers != null && familyMembers.isNotEmpty) {
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
        'Reminder creator must match current logged-in user',
      );
    }

    final newReminder = reminder.copyWith(
      id: reminder.id.isEmpty
          ? 'rem_${DateTime.now().millisecondsSinceEpoch}'
          : reminder.id,
      status: ReminderStatus.pending,
      createdAt: now ?? DateTime.now(),
    );

    _reminders.add(newReminder);
    _notify(reminder.familyId);
    return newReminder;
  }

  @override
  Future<ReminderModel> completeReminder({
    required String reminderId,
    required String currentUserId,
  }) async {
    final index = _reminders.indexWhere((r) => r.id == reminderId && !r.isDeleted);
    if (index == -1) {
      throw ReminderNotFoundException();
    }

    final existing = _reminders[index];

    // Rule: Chỉ người được giao reminder mới được Complete.
    // currentUser == assignedTo
    if (existing.assignedTo != currentUserId) {
      throw ReminderPermissionException(
        'Only the assigned member can complete this reminder',
      );
    }

    final updated = existing.copyWith(
      status: ReminderStatus.completed,
      completedAt: DateTime.now(),
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

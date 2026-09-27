import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../validators/reminder_validator.dart';
import 'reminder_repository.dart';

class SupabaseReminderRepository implements ReminderRepository {
  final SupabaseClient? _client;
  final InMemoryReminderRepository _fallbackRepository;

  SupabaseReminderRepository({
    SupabaseClient? client,
    InMemoryReminderRepository? fallbackRepository,
  })  : _client = client ?? SupabaseConfig.client,
        _fallbackRepository = fallbackRepository ?? InMemoryReminderRepository();

  @override
  Future<List<ReminderModel>> getReminders({required String familyId}) async {
    final client = _client;
    if (client == null) {
      return _fallbackRepository.getReminders(familyId: familyId);
    }

    try {
      final response = await client
          .from('reminders')
          .select()
          .eq('family_id', familyId)
          .neq('status', ReminderStatus.deleted)
          .order('date', ascending: true);

      final list = (response as List)
          .map((json) => ReminderModel.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      return List.unmodifiable(list);
    } catch (_) {
      return _fallbackRepository.getReminders(familyId: familyId);
    }
  }

  @override
  Stream<List<ReminderModel>> watchReminders({required String familyId}) async* {
    final client = _client;
    if (client == null) {
      yield* _fallbackRepository.watchReminders(familyId: familyId);
      return;
    }

    try {
      yield await getReminders(familyId: familyId);
      yield* client
          .from('reminders')
          .stream(primaryKey: ['id'])
          .eq('family_id', familyId)
          .map((data) => data
              .where((json) => json['status'] != ReminderStatus.deleted)
              .map((json) =>
                  ReminderModel.fromJson(Map<String, dynamic>.from(json)))
              .toList());
    } catch (_) {
      yield* _fallbackRepository.watchReminders(familyId: familyId);
    }
  }

  @override
  Future<List<ReminderModel>> getPendingReminders({
    required String familyId,
  }) async {
    final all = await getReminders(familyId: familyId);
    return all.where((r) => r.isPending).toList();
  }

  @override
  Future<List<ReminderModel>> getCompletedReminders({
    required String familyId,
  }) async {
    final all = await getReminders(familyId: familyId);
    return all.where((r) => r.isCompleted).toList();
  }

  @override
  Future<ReminderModel> createReminder({
    required ReminderModel reminder,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
    DateTime? now,
  }) async {
    final sanitizedTitle = ReminderValidator.sanitizeTitle(reminder.title);
    final titleError = ReminderValidator.validateTitle(sanitizedTitle);
    if (titleError != null) {
      throw ReminderValidationException(titleError);
    }

    if (familyMembers != null && familyMembers.isNotEmpty) {
      final memberError = ReminderValidator.validateAssignedMember(
        reminder.assignedTo,
        familyMembers,
      );
      if (memberError != null) {
        throw ReminderValidationException(memberError);
      }
    }

    final futureError = ReminderValidator.validateFutureDateTimeFromStrings(
      reminder.date,
      reminder.time,
      now: now,
    );
    if (futureError != null) {
      throw ReminderValidationException(futureError);
    }

    if (reminder.creatorId != currentUserId) {
      throw ReminderPermissionException(
        'Reminder creator must match current logged-in user',
      );
    }

    final sanitizedReminder = reminder.copyWith(title: sanitizedTitle);
    final client = _client;

    if (client == null) {
      return _fallbackRepository.createReminder(
        reminder: sanitizedReminder,
        currentUserId: currentUserId,
        familyMembers: familyMembers,
        now: now,
      );
    }

    try {
      final payload = sanitizedReminder.toSupabaseMap();
      final res = await client
          .from('reminders')
          .insert(payload)
          .select()
          .single();

      return ReminderModel.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {
      return _fallbackRepository.createReminder(
        reminder: sanitizedReminder,
        currentUserId: currentUserId,
        familyMembers: familyMembers,
        now: now,
      );
    }
  }

  @override
  Future<ReminderModel> completeReminder({
    required String reminderId,
    required String currentUserId,
  }) async {
    final client = _client;
    if (client == null) {
      return _fallbackRepository.completeReminder(
        reminderId: reminderId,
        currentUserId: currentUserId,
      );
    }

    try {
      final existingRes = await client
          .from('reminders')
          .select()
          .eq('id', reminderId)
          .single();
      final existing = ReminderModel.fromJson(Map<String, dynamic>.from(existingRes));

      if (existing.assignedTo != currentUserId) {
        throw ReminderPermissionException(
          'Only the assigned member can complete this reminder',
        );
      }

      final updateRes = await client
          .from('reminders')
          .update({
            'status': ReminderStatus.completed,
            'completed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', reminderId)
          .select()
          .single();

      return ReminderModel.fromJson(Map<String, dynamic>.from(updateRes));
    } catch (e) {
      if (e is ReminderPermissionException) rethrow;
      return _fallbackRepository.completeReminder(
        reminderId: reminderId,
        currentUserId: currentUserId,
      );
    }
  }

  @override
  Future<bool> deleteReminder({
    required String reminderId,
    required String currentUserId,
  }) async {
    final client = _client;
    if (client == null) {
      return _fallbackRepository.deleteReminder(
        reminderId: reminderId,
        currentUserId: currentUserId,
      );
    }

    try {
      final existingRes = await client
          .from('reminders')
          .select()
          .eq('id', reminderId)
          .single();
      final existing = ReminderModel.fromJson(Map<String, dynamic>.from(existingRes));

      if (existing.creatorId != currentUserId) {
        throw ReminderPermissionException(
          'Only creator can delete this reminder',
        );
      }

      await client
          .from('reminders')
          .update({'status': ReminderStatus.deleted})
          .eq('id', reminderId);

      return true;
    } catch (e) {
      if (e is ReminderPermissionException) rethrow;
      return _fallbackRepository.deleteReminder(
        reminderId: reminderId,
        currentUserId: currentUserId,
      );
    }
  }

  @override
  Future<bool> restoreReminder({
    required String reminderId,
    required String currentUserId,
  }) async {
    final client = _client;
    if (client == null) {
      return _fallbackRepository.restoreReminder(
        reminderId: reminderId,
        currentUserId: currentUserId,
      );
    }

    try {
      final existingRes = await client
          .from('reminders')
          .select()
          .eq('id', reminderId)
          .single();
      final existing = ReminderModel.fromJson(Map<String, dynamic>.from(existingRes));

      if (existing.creatorId != currentUserId) {
        throw ReminderPermissionException(
          'Only creator can restore this reminder',
        );
      }

      await client
          .from('reminders')
          .update({'status': ReminderStatus.pending})
          .eq('id', reminderId);

      return true;
    } catch (e) {
      if (e is ReminderPermissionException) rethrow;
      return _fallbackRepository.restoreReminder(
        reminderId: reminderId,
        currentUserId: currentUserId,
      );
    }
  }
}

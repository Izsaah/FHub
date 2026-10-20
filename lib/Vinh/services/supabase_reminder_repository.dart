import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import 'reminder_repository.dart';
import 'reminder_validator.dart';
import 'supabase_config.dart';

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
  Future<ReminderModel> updateReminder({
    required ReminderModel reminder,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
    DateTime? now,
  }) async {
    final client = _client;
    if (client == null) {
      return _fallbackRepository.updateReminder(
        reminder: reminder,
        currentUserId: currentUserId,
        familyMembers: familyMembers,
        now: now,
      );
    }

    try {
      final existingRes = await client
          .from('reminders')
          .select()
          .eq('id', reminder.id)
          .single();
      final existing = ReminderModel.fromJson(Map<String, dynamic>.from(existingRes));

      if (existing.creatorId != currentUserId) {
        throw ReminderPermissionException(
          'Only the creator can edit this reminder',
        );
      }

      final sanitizedTitle = ReminderValidator.sanitizeTitle(reminder.title);
      final titleError = ReminderValidator.validateTitle(sanitizedTitle);
      if (titleError != null) {
        throw ReminderValidationException(titleError);
      }

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

      final updateMap = {
        'title': sanitizedTitle,
        'assigned_to': reminder.assignedTo,
        'date': reminder.date,
        'time': reminder.time,
        'repeat_rule': reminder.repeatRule ?? 'NONE',
        'requires_proof_image': reminder.requiresProofImage,
        'proof_image_url': reminder.proofImageUrl,
        'reward_stars': reminder.rewardStars,
        'voice_note_path': reminder.voiceNotePath,
        'voice_duration_seconds': reminder.voiceDurationSeconds,
        'voice_note_description': reminder.voiceNoteDescription,
      };

      final updateRes = await client
          .from('reminders')
          .update(updateMap)
          .eq('id', reminder.id)
          .select()
          .single();

      return ReminderModel.fromJson(Map<String, dynamic>.from(updateRes));
    } catch (e) {
      if (e is ReminderPermissionException ||
          e is ReminderValidationException) {
        rethrow;
      }
      return _fallbackRepository.updateReminder(
        reminder: reminder,
        currentUserId: currentUserId,
        familyMembers: familyMembers,
        now: now,
      );
    }
  }

  @override
  Future<ReminderModel> claimOpenTask({
    required String reminderId,
    required String currentUserId,
    required String currentUserName,
  }) async {
    final client = _client;
    if (client == null) {
      return _fallbackRepository.claimOpenTask(
        reminderId: reminderId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
      );
    }

    try {
      final updateRes = await client
          .from('reminders')
          .update({
            'assigned_to': currentUserId,
            'assigned_to_name': currentUserName,
            'status': ReminderStatus.pending,
          })
          .eq('id', reminderId)
          .select()
          .single();

      return ReminderModel.fromJson(Map<String, dynamic>.from(updateRes));
    } catch (_) {
      return _fallbackRepository.claimOpenTask(
        reminderId: reminderId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
      );
    }
  }

  @override
  Future<ReminderModel> claimAndCompleteOpenTask({
    required String reminderId,
    required String currentUserId,
    required String currentUserName,
    String? proofImageUrl,
  }) async {
    await claimOpenTask(
      reminderId: reminderId,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
    );
    return completeReminder(
      reminderId: reminderId,
      currentUserId: currentUserId,
      proofImageUrl: proofImageUrl,
    );
  }

  DateTime? _calculateNextDueDate(String dateStr, String repeatRule) {
    try {
      final parts = dateStr.trim().split('/');
      if (parts.length != 3) return null;
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final cur = DateTime(year, month, day);

      if (repeatRule == 'DAILY') {
        return cur.add(const Duration(days: 1));
      } else if (repeatRule == 'WEEKLY') {
        return cur.add(const Duration(days: 7));
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<ReminderModel> completeReminder({
    required String reminderId,
    required String currentUserId,
    String? proofImageUrl,
  }) async {
    final client = _client;
    if (client == null) {
      return _fallbackRepository.completeReminder(
        reminderId: reminderId,
        currentUserId: currentUserId,
        proofImageUrl: proofImageUrl,
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

      final effectiveProof = proofImageUrl ?? existing.proofImageUrl;
      if (existing.requiresProofImage &&
          (effectiveProof == null || effectiveProof.isEmpty)) {
        throw ReminderValidationException(
          'Công việc này bắt buộc phải có ảnh nghiệm thu trước khi hoàn thành!',
        );
      }

      final updateRes = await client
          .from('reminders')
          .update({
            'status': ReminderStatus.completed,
            'completed_at': DateTime.now().toIso8601String(),
            'proof_image_url': effectiveProof,
          })
          .eq('id', reminderId)
          .select()
          .single();

      // Tự động sinh chu kỳ tiếp theo cho lời nhắc lặp lại (DAILY / WEEKLY)
      final rule = existing.repeatRule;
      if (rule == 'DAILY' || rule == 'WEEKLY') {
        final nextDate = _calculateNextDueDate(existing.date, rule!);
        if (nextDate != null) {
          final nextDateStr =
              '${nextDate.day.toString().padLeft(2, '0')}/${nextDate.month.toString().padLeft(2, '0')}/${nextDate.year}';
          try {
            await client.from('reminders').insert({
              'family_id': existing.familyId,
              'creator_id': existing.creatorId,
              'assigned_to': existing.assignedTo,
              'title': existing.title,
              'date': nextDateStr,
              'time': existing.time,
              'repeat_rule': existing.repeatRule,
              'status': existing.isOpenTask ? ReminderStatus.open : ReminderStatus.pending,
              'requires_proof_image': existing.requiresProofImage,
              'reward_stars': 0,
              'voice_note_path': existing.voiceNotePath,
              'voice_duration_seconds': existing.voiceDurationSeconds,
              'voice_note_description': existing.voiceNoteDescription,
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        }
      }

      return ReminderModel.fromJson(Map<String, dynamic>.from(updateRes));
    } catch (e) {
      if (e is ReminderPermissionException ||
          e is ReminderValidationException) {
        rethrow;
      }
      return _fallbackRepository.completeReminder(
        reminderId: reminderId,
        currentUserId: currentUserId,
        proofImageUrl: proofImageUrl,
      );
    }
  }

  @override
  Future<bool> deleteReminder({
    required String reminderId,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
  }) async {
    final client = _client;
    if (client == null) {
      return _fallbackRepository.deleteReminder(
        reminderId: reminderId,
        currentUserId: currentUserId,
        familyMembers: familyMembers,
      );
    }

    try {
      final existingRes = await client
          .from('reminders')
          .select()
          .eq('id', reminderId)
          .single();
      final existing = ReminderModel.fromJson(Map<String, dynamic>.from(existingRes));

      // Rule: Cho phép xóa nếu là người tạo HOẶC là Bố/Mẹ/Ông/Bà/Chủ nhà
      final isCreator = existing.creatorId == currentUserId;
      bool isParentOrOwner = false;
      if (familyMembers != null && familyMembers.isNotEmpty) {
        final currentMember = familyMembers.firstWhere(
          (m) => m.id == currentUserId,
          orElse: () => const FamilyMember(id: '', name: '', role: '', familyId: ''),
        );
        isParentOrOwner = currentMember.isParent || currentMember.isGrandparent;
      }

      if (!isCreator && !isParentOrOwner) {
        throw ReminderPermissionException(
          'Only the creator or a parent/owner can delete this reminder',
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
        familyMembers: familyMembers,
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

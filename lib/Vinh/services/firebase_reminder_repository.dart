import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/family_member.dart';
import '../models/reminder_model.dart';
import 'reminder_repository.dart';
import 'reminder_validator.dart';

/// Concrete Repository connecting directly to Cloud Firestore.
/// Uses Firestore collection `'reminders'` with real-time snapshots.
class FirebaseReminderRepository implements ReminderRepository {
  final FirebaseFirestore? _customFirestore;
  final InMemoryReminderRepository? fallbackRepository;

  FirebaseReminderRepository({
    FirebaseFirestore? firestore,
    this.fallbackRepository,
  }) : _customFirestore = firestore;

  InMemoryReminderRepository? get _fallbackRepository => fallbackRepository;

  bool get _isFirebaseAvailable {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore? get _firestore {
    if (_customFirestore != null) return _customFirestore;
    if (_isFirebaseAvailable) {
      try {
        return FirebaseFirestore.instance;
      } catch (e) {
        debugPrint(
            'FirebaseReminderRepository: Firestore instance unavailable: $e');
        return null;
      }
    }
    return null;
  }

  CollectionReference<Map<String, dynamic>>? get _remindersCollection {
    final firestore = _firestore;
    if (firestore == null) return null;
    return firestore.collection('reminders');
  }

  // ---------------------------------------------------------------------------
  // READ OPERATIONS
  // ---------------------------------------------------------------------------

  @override
  Future<List<ReminderModel>> getReminders({required String familyId}) async {
    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        return fallback.getReminders(familyId: familyId);
      }
      return [];
    }

    try {
      // Query by camelCase familyId
      final snap1 = await col.where('familyId', isEqualTo: familyId).get();
      final Map<String, ReminderModel> items = {};

      for (final doc in snap1.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        final model = ReminderModel.fromJson(data);
        if (!model.isDeleted) {
          items[doc.id] = model;
        }
      }

      // Also query by snake_case family_id in case records were created by other services
      final snap2 = await col.where('family_id', isEqualTo: familyId).get();
      for (final doc in snap2.docs) {
        if (!items.containsKey(doc.id)) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          final model = ReminderModel.fromJson(data);
          if (!model.isDeleted) {
            items[doc.id] = model;
          }
        }
      }

      final list = items.values.toList();
      list.sort((a, b) {
        final dtA = a.dueDateTime ?? DateTime(2099);
        final dtB = b.dueDateTime ?? DateTime(2099);
        return dtA.compareTo(dtB);
      });

      return List.unmodifiable(list);
    } catch (e) {
      debugPrint('FirebaseReminderRepository getReminders error: $e');
      if (fallback != null) {
        return fallback.getReminders(familyId: familyId);
      }
      return [];
    }
  }

  @override
  Stream<List<ReminderModel>> watchReminders({required String familyId}) async* {
    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        yield* fallback.watchReminders(familyId: familyId);
      } else {
        yield [];
      }
      return;
    }

    try {
      // Initial fetch to yield immediately
      yield await getReminders(familyId: familyId);

      // Real-time snapshot stream
      yield* col
          .where('familyId', isEqualTo: familyId)
          .snapshots()
          .map((snapshot) {
        final list = snapshot.docs
            .map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              return ReminderModel.fromJson(data);
            })
            .where((r) => !r.isDeleted)
            .toList();

        list.sort((a, b) {
          final dtA = a.dueDateTime ?? DateTime(2099);
          final dtB = b.dueDateTime ?? DateTime(2099);
          return dtA.compareTo(dtB);
        });

        return List<ReminderModel>.unmodifiable(list);
      });
    } catch (e) {
      debugPrint('FirebaseReminderRepository watchReminders error: $e');
      if (fallback != null) {
        yield* fallback.watchReminders(familyId: familyId);
      } else {
        yield [];
      }
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

  // ---------------------------------------------------------------------------
  // CREATE
  // ---------------------------------------------------------------------------

  @override
  Future<ReminderModel> createReminder({
    required ReminderModel reminder,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
    DateTime? now,
  }) async {
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

    // 4. Validate creator matches current user
    if (reminder.creatorId != currentUserId) {
      throw const ReminderPermissionException(
        'Only the creator can set their ID as creator',
      );
    }

    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        return fallback.createReminder(
          reminder: reminder,
          currentUserId: currentUserId,
          familyMembers: familyMembers,
          now: now,
        );
      }
      throw Exception('Firestore is not available');
    }

    final docRef = reminder.id.isNotEmpty && !reminder.id.startsWith('rem_')
        ? col.doc(reminder.id)
        : col.doc();

    final newReminder = reminder.copyWith(
      id: docRef.id,
      title: sanitizedTitle,
      createdAt: now ?? DateTime.now(),
    );

    await docRef.set(newReminder.toFirestoreMap());
    MultiTierEscalationService.instance
        .scheduleMultiTierEscalation(newReminder);
    return newReminder;
  }

  // ---------------------------------------------------------------------------
  // UPDATE
  // ---------------------------------------------------------------------------

  @override
  Future<ReminderModel> updateReminder({
    required ReminderModel reminder,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
    DateTime? now,
  }) async {
    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        return fallback.updateReminder(
          reminder: reminder,
          currentUserId: currentUserId,
          familyMembers: familyMembers,
          now: now,
        );
      }
      throw Exception('Firestore is not available');
    }

    final docRef = col.doc(reminder.id);
    final docSnap = await docRef.get();
    if (!docSnap.exists || docSnap.data() == null) {
      throw ReminderNotFoundException();
    }

    final existingData = Map<String, dynamic>.from(docSnap.data()!);
    existingData['id'] = docSnap.id;
    final existing = ReminderModel.fromJson(existingData);

    // Rule: Chỉ người tạo HOẶC Cha Mẹ/Chủ nhà mới được sửa
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

    // 2. Validate Assigned Member if list provided
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

    // 3. Validate Date + Time must be in the future (nếu thay đổi ngày/giờ)
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

    await docRef.set(updated.toFirestoreMap(), SetOptions(merge: true));
    MultiTierEscalationService.instance.scheduleMultiTierEscalation(updated);
    return updated;
  }

  // ---------------------------------------------------------------------------
  // CLAIM OPEN TASK
  // ---------------------------------------------------------------------------

  @override
  Future<ReminderModel> claimOpenTask({
    required String reminderId,
    required String currentUserId,
    required String currentUserName,
  }) async {
    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        return fallback.claimOpenTask(
          reminderId: reminderId,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
        );
      }
      throw Exception('Firestore is not available');
    }

    final docRef = col.doc(reminderId);
    final docSnap = await docRef.get();
    if (!docSnap.exists || docSnap.data() == null) {
      throw ReminderNotFoundException();
    }

    final existingData = Map<String, dynamic>.from(docSnap.data()!);
    existingData['id'] = docSnap.id;
    final existing = ReminderModel.fromJson(existingData);

    if (existing.isCompleted) {
      throw const ReminderValidationException('Công việc này đã hoàn thành!');
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

    await docRef.update({
      'assignedTo': currentUserId,
      'assigned_to': currentUserId,
      'assignedToName': currentUserName,
      'assigned_to_name': currentUserName,
      'status': ReminderStatus.pending,
    });

    MultiTierEscalationService.instance.scheduleMultiTierEscalation(updated);
    return updated;
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

  // ---------------------------------------------------------------------------
  // COMPLETE
  // ---------------------------------------------------------------------------

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
  }) async {
    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        return fallback.completeReminder(
          reminderId: reminderId,
          currentUserId: currentUserId,
          proofImageUrl: proofImageUrl,
        );
      }
      throw Exception('Firestore is not available');
    }

    final docRef = col.doc(reminderId);
    final docSnap = await docRef.get();
    if (!docSnap.exists || docSnap.data() == null) {
      throw ReminderNotFoundException();
    }

    final existingData = Map<String, dynamic>.from(docSnap.data()!);
    existingData['id'] = docSnap.id;
    final existing = ReminderModel.fromJson(existingData);

    // Rule: Chỉ người được giao mới được Complete
    if (existing.assignedTo != currentUserId) {
      throw const ReminderPermissionException(
        'Only the assigned member can complete this reminder',
      );
    }

    // Rule: Bắt buộc đính kèm ảnh nếu requiresProofImage == true
    final effectiveProof = proofImageUrl ?? existing.proofImageUrl;
    if (existing.requiresProofImage &&
        (effectiveProof == null || effectiveProof.isEmpty)) {
      throw const ReminderValidationException(
        'Công việc này bắt buộc phải có ảnh nghiệm thu trước khi hoàn thành!',
      );
    }

    final now = DateTime.now();
    final updated = existing.copyWith(
      status: ReminderStatus.completed,
      completedAt: now,
      proofImageUrl: effectiveProof,
    );

    await docRef.update({
      'status': ReminderStatus.completed,
      'completedAt': Timestamp.fromDate(now),
      'completed_at': Timestamp.fromDate(now),
      if (effectiveProof != null) ...{
        'proofImageUrl': effectiveProof,
        'proof_image_url': effectiveProof,
      },
    });

    // Tự động sinh chu kỳ tiếp theo cho lời nhắc lặp lại (DAILY / WEEKLY)
    final rule = existing.repeatRule;
    if (rule == 'DAILY' || rule == 'WEEKLY') {
      final nextDate = _calculateNextDueDate(existing.date, rule!);
      if (nextDate != null) {
        final nextDateStr =
            '${nextDate.day.toString().padLeft(2, '0')}/${nextDate.month.toString().padLeft(2, '0')}/${nextDate.year}';
        final nextDocRef = col.doc();
        final nextReminder = ReminderModel(
          id: nextDocRef.id,
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
          createdAt: now,
        );
        await nextDocRef.set(nextReminder.toFirestoreMap());
        MultiTierEscalationService.instance
            .scheduleMultiTierEscalation(nextReminder);
      }
    }

    MultiTierEscalationService.instance.cancelEscalation(reminderId);
    return updated;
  }

  // ---------------------------------------------------------------------------
  // DELETE & RESTORE
  // ---------------------------------------------------------------------------

  @override
  Future<bool> deleteReminder({
    required String reminderId,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
  }) async {
    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        return fallback.deleteReminder(
          reminderId: reminderId,
          currentUserId: currentUserId,
          familyMembers: familyMembers,
        );
      }
      throw Exception('Firestore is not available');
    }

    final docRef = col.doc(reminderId);
    final docSnap = await docRef.get();
    if (!docSnap.exists || docSnap.data() == null) {
      throw ReminderNotFoundException();
    }

    final existingData = Map<String, dynamic>.from(docSnap.data()!);
    final existing = ReminderModel.fromJson(existingData);

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
        'Only the creator or a parent/owner can delete this reminder',
      );
    }

    await docRef.update({
      'status': ReminderStatus.deleted,
      'deletedAt': Timestamp.now(),
      'deleted_at': Timestamp.now(),
    });

    MultiTierEscalationService.instance.cancelEscalation(reminderId);
    return true;
  }

  @override
  Future<bool> restoreReminder({
    required String reminderId,
    required String currentUserId,
    List<FamilyMember>? familyMembers,
  }) async {
    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        return fallback.restoreReminder(
          reminderId: reminderId,
          currentUserId: currentUserId,
          familyMembers: familyMembers,
        );
      }
      throw Exception('Firestore is not available');
    }

    final docRef = col.doc(reminderId);
    final docSnap = await docRef.get();
    if (!docSnap.exists || docSnap.data() == null) {
      throw ReminderNotFoundException();
    }

    final existingData = Map<String, dynamic>.from(docSnap.data()!);
    final existing = ReminderModel.fromJson(existingData);

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

    await docRef.update({
      'status': restoredStatus,
    });

    return true;
  }
}

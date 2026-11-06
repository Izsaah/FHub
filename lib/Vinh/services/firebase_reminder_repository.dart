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
  final Map<String, ReminderModel> _mockStore = {};

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
  Future<List<ReminderModel>> getRemindersForFamilies({
    required List<String> familyIds,
  }) async {
    final cleanIds =
        familyIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (cleanIds.isEmpty) return [];
    if (cleanIds.length == 1) {
      return getReminders(familyId: cleanIds.first);
    }

    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        return fallback.getRemindersForFamilies(familyIds: cleanIds);
      }
      return [];
    }

    try {
      final batchIds = cleanIds.take(30).toList();
      final snap1 = await col.where('familyId', whereIn: batchIds).get();
      final Map<String, ReminderModel> items = {};

      for (final doc in snap1.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        final model = ReminderModel.fromJson(data);
        if (!model.isDeleted) {
          items[doc.id] = model;
        }
      }

      final snap2 = await col.where('family_id', whereIn: batchIds).get();
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
      debugPrint('FirebaseReminderRepository getRemindersForFamilies error: $e');
      if (fallback != null) {
        return fallback.getRemindersForFamilies(familyIds: cleanIds);
      }
      return [];
    }
  }

  @override
  Stream<List<ReminderModel>> watchRemindersForFamilies({
    required List<String> familyIds,
  }) async* {
    final cleanIds =
        familyIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (cleanIds.isEmpty) {
      yield [];
      return;
    }
    if (cleanIds.length == 1) {
      yield* watchReminders(familyId: cleanIds.first);
      return;
    }

    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        yield* fallback.watchRemindersForFamilies(familyIds: cleanIds);
      } else {
        yield [];
      }
      return;
    }

    try {
      yield await getRemindersForFamilies(familyIds: cleanIds);

      final batchIds = cleanIds.take(30).toList();
      yield* col
          .where('familyId', whereIn: batchIds)
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
      debugPrint(
          'FirebaseReminderRepository watchRemindersForFamilies error: $e');
      if (fallback != null) {
        yield* fallback.watchRemindersForFamilies(familyIds: cleanIds);
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

    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        final res = await fallback.createReminder(
          reminder: reminder,
          currentUserId: currentUserId,
          familyMembers: familyMembers,
          now: now,
        );
        _mockStore[res.id] = res;
        return res;
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
    _mockStore[newReminder.id] = newReminder;
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
    final firestore = _firestore;
    ReminderModel updated;

    if (firestore != null) {
      updated = await firestore.runTransaction<ReminderModel>((transaction) async {
        final docSnap = await transaction.get(docRef);
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

        final updatedModel = existing.copyWith(
          assignedTo: currentUserId,
          assignedToName: currentUserName,
          status: ReminderStatus.pending,
        );

        transaction.update(docRef, {
          'assignedTo': currentUserId,
          'assigned_to': currentUserId,
          'assignedToName': currentUserName,
          'assigned_to_name': currentUserName,
          'status': ReminderStatus.pending,
        });

        return updatedModel;
      });
    } else {
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

      updated = existing.copyWith(
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
    }

    MultiTierEscalationService.instance.scheduleMultiTierEscalation(updated);
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
    final col = _remindersCollection;
    if (col != null) {
      final docSnap = await col.doc(reminderId).get();
      if (docSnap.exists && docSnap.data() != null) {
        final existingData = Map<String, dynamic>.from(docSnap.data()!);
        existingData['id'] = docSnap.id;
        final existing = ReminderModel.fromJson(existingData);
        if (!allowFutureCompletion && existing.isFutureDate) {
          throw ReminderValidationException(
            'Công việc này được lên lịch cho ngày ${existing.date}. Chỉ có thể đánh dấu hoàn thành khi đến đúng ngày hẹn!',
          );
        }
      }
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
    bool allowFutureCompletion = false,
  }) async {
    final col = _remindersCollection;
    final fallback = _fallbackRepository;
    if (col == null) {
      if (fallback != null) {
        return fallback.completeReminder(
          reminderId: reminderId,
          currentUserId: currentUserId,
          proofImageUrl: proofImageUrl,
          allowFutureCompletion: allowFutureCompletion,
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

    // Rule: Khóa hoàn thành nếu ngày thực hiện nằm ở tương lai (chưa đến ngày hẹn)
    if (!allowFutureCompletion && existing.isFutureDate) {
      throw ReminderValidationException(
        'Công việc này được lên lịch cho ngày ${existing.date}. Chỉ có thể đánh dấu hoàn thành khi đến đúng ngày hẹn!',
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
  Future<ReminderModel?> checkScheduleConflict({
    required String userId,
    required String date,
    required String time,
    String? excludeReminderId,
  }) async {
    final col = _remindersCollection;
    if (col == null) {
      return _fallbackRepository?.checkScheduleConflict(
        userId: userId,
        date: date,
        time: time,
        excludeReminderId: excludeReminderId,
      );
    }
    try {
      final snap = await col
          .where('assignedTo', isEqualTo: userId)
          .where('date', isEqualTo: date.trim())
          .where('time', isEqualTo: time.trim())
          .get();
      for (final doc in snap.docs) {
        if (doc.id == excludeReminderId) continue;
        final data = Map<String, dynamic>.from(doc.data() as Map);
        data['id'] = doc.id;
        final m = ReminderModel.fromJson(data);
        if (!m.isDeleted && !m.isCompleted) return m;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<ReminderModel?> findDuplicateReminder({
    required String familyId,
    required String title,
    required String date,
    required String time,
    String? excludeReminderId,
  }) async {
    final col = _remindersCollection;
    if (col == null) {
      return _fallbackRepository?.findDuplicateReminder(
        familyId: familyId,
        title: title,
        date: date,
        time: time,
        excludeReminderId: excludeReminderId,
      );
    }
    try {
      final snap = await col
          .where('familyId', isEqualTo: familyId)
          .where('date', isEqualTo: date.trim())
          .where('time', isEqualTo: time.trim())
          .get();
      final targetTitle = ReminderValidator.sanitizeTitle(title).toLowerCase();
      for (final doc in snap.docs) {
        if (doc.id == excludeReminderId) continue;
        final data = Map<String, dynamic>.from(doc.data() as Map);
        data['id'] = doc.id;
        final m = ReminderModel.fromJson(data);
        if (!m.isDeleted && !m.isCompleted && m.title.trim().toLowerCase() == targetTitle) {
          return m;
        }
      }
    } catch (_) {}
    return null;
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

  @override
  Future<void> submitTaskWithProof({
    required String taskId,
    required String proofImageUrl,
  }) async {
    final col = _remindersCollection;
    if (col != null) {
      try {
        await col.doc(taskId).update({
          'proofImageUrl': proofImageUrl,
          'proof_image_url': proofImageUrl,
          'taskStatus': TaskStatus.submitted.dbValue,
          'task_status': TaskStatus.submitted.dbValue,
          'status': 'SUBMITTED',
          'isCompleted': false,
          'is_completed': false,
          'rejectionReason': null,
          'rejection_reason': null,
        });
      } catch (_) {}
    }
    final existing = _mockStore[taskId];
    if (existing != null) {
      _mockStore[taskId] = existing.copyWith(
        proofImageUrl: proofImageUrl,
        taskStatus: TaskStatus.submitted,
        status: 'SUBMITTED',
        clearRejectionReason: true,
      );
    }
    final fallback = _fallbackRepository;
    if (fallback != null) {
      await fallback.submitTaskWithProof(
        taskId: taskId,
        proofImageUrl: proofImageUrl,
      );
    }
  }

  @override
  Future<void> rejectTaskSubmission({
    required String taskId,
    required String reason,
  }) async {
    final col = _remindersCollection;
    if (col != null) {
      try {
        await col.doc(taskId).update({
          'proofImageUrl': FieldValue.delete(),
          'proof_image_url': FieldValue.delete(),
          'rejectionReason': reason,
          'rejection_reason': reason,
          'taskStatus': TaskStatus.pending.dbValue,
          'task_status': TaskStatus.pending.dbValue,
          'status': ReminderStatus.pending,
          'isCompleted': false,
          'is_completed': false,
        });
      } catch (_) {}
    }
    final existing = _mockStore[taskId];
    if (existing != null) {
      _mockStore[taskId] = existing.copyWith(
        clearProofImage: true,
        rejectionReason: reason,
        taskStatus: TaskStatus.pending,
        status: ReminderStatus.pending,
      );
    }
    final fallback = _fallbackRepository;
    if (fallback != null) {
      await fallback.rejectTaskSubmission(
        taskId: taskId,
        reason: reason,
      );
    }
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
    int delegationCount = 0;
    ReminderModel? existing = _mockStore[taskId];
    final col = _remindersCollection;

    if (col != null) {
      try {
        final doc = await col.doc(taskId).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          delegationCount = data['delegationCount'] is int
              ? data['delegationCount'] as int
              : (data['delegation_count'] is int
                  ? data['delegation_count'] as int
                  : 0);
          data['id'] = doc.id;
          existing = ReminderModel.fromJson(data);
        }
      } catch (_) {}
    }

    if (existing != null) {
      delegationCount = existing.delegationCount;
    }

    if (delegationCount >= 1) {
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

    if (col != null) {
      try {
        await col.doc(taskId).update({
          'delegationCount': 1,
          'delegation_count': 1,
          'delegatedFromUserId': currentUserId,
          'delegated_from_user_id': currentUserId,
          'assignedTo': delegatedToUserId,
          'assigned_to': delegatedToUserId,
          'assignedToName': delegatedToUserName,
          'assigned_to_name': delegatedToUserName,
          'taskType': TaskType.favor.dbValue,
          'task_type': TaskType.favor.dbValue,
        });
      } catch (_) {}
    }

    ReminderModel result;
    final fallback = _fallbackRepository;
    if (fallback != null) {
      result = await fallback.delegateFavorTask(
        taskId: taskId,
        delegatedToUserId: delegatedToUserId,
        delegatedToUserName: delegatedToUserName,
        currentUserId: currentUserId,
        currentUserRole: currentUserRole,
        targetUserRole: targetUserRole,
      );
    } else if (existing != null) {
      result = existing.copyWith(
        delegationCount: existing.delegationCount + 1,
        delegatedFromUserId: currentUserId,
        assignedTo: delegatedToUserId,
        assignedToName: delegatedToUserName,
        taskType: TaskType.favor,
      );
    } else {
      result = ReminderModel(
        id: taskId,
        familyId: 'default',
        creatorId: currentUserId,
        assignedTo: delegatedToUserId,
        assignedToName: delegatedToUserName,
        title: 'Favor Task',
        date: '01/01/2026',
        time: '12:00',
        delegationCount: 1,
        delegatedFromUserId: currentUserId,
        taskType: TaskType.favor,
      );
    }

    _mockStore[taskId] = result;
    return result;
  }

  @override
  Future<void> acceptFavorTask(String taskId) async {
    final col = _remindersCollection;
    if (col != null) {
      try {
        await col.doc(taskId).update({
          'taskStatus': TaskStatus.accepted.dbValue,
          'task_status': TaskStatus.accepted.dbValue,
          'status': 'ACCEPTED',
        });
      } catch (_) {}
    }
    final existing = _mockStore[taskId];
    if (existing != null) {
      _mockStore[taskId] = existing.copyWith(
        taskStatus: TaskStatus.accepted,
        status: 'ACCEPTED',
      );
    }
    final fallback = _fallbackRepository;
    if (fallback != null) {
      await fallback.acceptFavorTask(taskId);
    }
  }

  @override
  Future<void> declineFavorTask(String taskId) async {
    final col = _remindersCollection;
    if (col != null) {
      try {
        await col.doc(taskId).update({
          'taskStatus': TaskStatus.declined.dbValue,
          'task_status': TaskStatus.declined.dbValue,
          'status': 'DECLINED',
        });
      } catch (_) {}
    }
    final existing = _mockStore[taskId];
    if (existing != null) {
      _mockStore[taskId] = existing.copyWith(
        taskStatus: TaskStatus.declined,
        status: 'DECLINED',
      );
    }
    final fallback = _fallbackRepository;
    if (fallback != null) {
      await fallback.declineFavorTask(taskId);
    }
  }

  @override
  Future<void> approveTaskSubmission({
    required String taskId,
    required String reviewerId,
    required String reviewerName,
  }) async {
    final col = _remindersCollection;
    if (col != null) {
      try {
        await col.doc(taskId).update({
          'taskStatus': TaskStatus.completed.dbValue,
          'task_status': TaskStatus.completed.dbValue,
          'status': ReminderStatus.completed,
          'isCompleted': true,
          'is_completed': true,
          'completedAt': Timestamp.now(),
          'completed_at': Timestamp.now(),
        });
      } catch (_) {}
    }
    final existing = _mockStore[taskId];
    if (existing != null) {
      _mockStore[taskId] = existing.copyWith(
        taskStatus: TaskStatus.completed,
        status: ReminderStatus.completed,
        completedAt: DateTime.now(),
      );
    }
    final fallback = _fallbackRepository;
    if (fallback != null) {
      await fallback.approveTaskSubmission(
        taskId: taskId,
        reviewerId: reviewerId,
        reviewerName: reviewerName,
      );
    }
  }
}

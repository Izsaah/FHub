// lib/Vinh/services/star_economy_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/reminder_model.dart';

/// Exception thrown when member does not have enough stars to claim a wishlist item.
/// Extends [StateError] and implements [Exception] for dual compatibility with
/// system specifications and test assertions.
class InsufficientStarsException extends StateError implements Exception {
  InsufficientStarsException([
    super.message = 'INSUFFICIENT_STARS: Số dư sao không đủ để đổi quà.',
  ]);

  @override
  String toString() => 'InsufficientStarsException: $message';
}

/// Exception thrown when a task approval has already occurred or duplicate reward doc is detected.
class DoubleApprovalException extends StateError implements Exception {
  DoubleApprovalException([
    super.message =
        'DOUBLE_APPROVAL_DETECTED: Công việc này đã được duyệt trước đó rồi ạ!',
  ]);

  @override
  String toString() => 'DoubleApprovalException: $message';
}

/// Exception thrown when a task document cannot be found.
class TaskNotFoundException extends StateError implements Exception {
  TaskNotFoundException([super.message = 'Công việc không tồn tại']);

  @override
  String toString() => 'TaskNotFoundException: $message';
}

/// StarEconomyService provides atomic, race-condition-proof transactions for:
/// 1. Chore task approval with double-award protection (idempotent key `reward_${taskId}`)
/// 2. Wishlist item redemption with double-spending prevention (idempotent key `claim_${claimId}`)
/// 3. Physical gift rejection refund (idempotent key `refund_${claimId}`)
///
/// Conforms to Firestore security rules:
/// - Top-level `star_ledger` collection is strictly immutable.
/// - Top-level `family_members` collection allows `rewardStarsTotal` increments only by Guardians.
class StarEconomyService {
  static final StarEconomyService _instance = StarEconomyService._internal();

  factory StarEconomyService({FirebaseFirestore? firestore}) {
    if (firestore != null) {
      return StarEconomyService._custom(firestore);
    }
    return _instance;
  }

  /// Creates a fresh, isolated in-memory instance (convenient for concurrent unit test suites)
  factory StarEconomyService.inMemory() => StarEconomyService._inMemory();

  StarEconomyService._internal()
      : _customFirestore = null,
        _forceInMemory = false;

  StarEconomyService._custom(FirebaseFirestore firestore)
      : _customFirestore = firestore,
        _forceInMemory = false;

  StarEconomyService._inMemory()
      : _customFirestore = null,
        _forceInMemory = true;

  static StarEconomyService get instance => _instance;

  final FirebaseFirestore? _customFirestore;
  final bool _forceInMemory;

  bool get _isFirebaseAvailable {
    if (_forceInMemory) return false;
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore? get _firestore {
    if (_forceInMemory) return null;
    if (_customFirestore != null) return _customFirestore;
    if (_isFirebaseAvailable) {
      try {
        return FirebaseFirestore.instance;
      } catch (e) {
        debugPrint('StarEconomyService: Firestore instance unavailable: $e');
        return null;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // IN-MEMORY MOCK STORAGE (Fallback for unit testing without live Firebase)
  // ---------------------------------------------------------------------------
  final Map<String, Map<String, dynamic>> reminders = {};
  final Map<String, Map<String, dynamic>> starLedger = {};
  final Map<String, int> memberBalances = {}; // key: ${familyId}_${userId}

  void seedMemberBalance(String familyId, String userId, int stars) {
    memberBalances['${familyId}_$userId'] = stars;
  }

  int getBalance(String familyId, String userId) {
    return memberBalances['${familyId}_$userId'] ?? 0;
  }

  void seedTask(String taskId, Map<String, dynamic> data) {
    reminders[taskId] = Map<String, dynamic>.from(data);
  }

  void resetMockData() {
    reminders.clear();
    starLedger.clear();
    memberBalances.clear();
  }

  // ---------------------------------------------------------------------------
  // 1. APPROVE TASK WITH DOUBLE-AWARD PROTECTION
  // ---------------------------------------------------------------------------
  Future<void> approveTaskWithDoubleAwardProtection({
    required String taskId,
    required String reviewerId,
    required String reviewerName,
    String? familyId,
    String? childId,
    int? stars,
  }) async {
    final firestore = _firestore;
    if (firestore == null) {
      return _approveTaskInMemory(
        taskId: taskId,
        reviewerId: reviewerId,
        reviewerName: reviewerName,
        familyId: familyId,
        childId: childId,
        stars: stars,
      );
    }

    final ledgerRef = firestore.collection('star_ledger').doc('reward_$taskId');
    final taskRef = firestore.collection('reminders').doc(taskId);

    await firestore.runTransaction((transaction) async {
      // 1. All reads must precede all writes in Firestore transactions
      final ledgerSnap = await transaction.get(ledgerRef);
      if (ledgerSnap.exists) {
        throw DoubleApprovalException(
          'DOUBLE_APPROVAL_DETECTED: Giao dịch thưởng sao reward_$taskId đã tồn tại trong sổ cái!',
        );
      }

      final taskSnap = await transaction.get(taskRef);
      if (!taskSnap.exists) {
        throw TaskNotFoundException('Công việc không tồn tại');
      }

      final taskData = taskSnap.data() ?? {};
      final currentStatus =
          (taskData['status'] ?? '').toString().toUpperCase();
      final currentTaskStatus = (taskData['taskStatus'] ??
              taskData['task_status'] ??
              '')
          .toString()
          .toUpperCase();

      if (currentStatus == 'APPROVED' ||
          currentStatus == 'COMPLETED' ||
          currentTaskStatus == 'COMPLETED') {
        final existingApprover = taskData['approvedByName'] ??
            taskData['approvedBy'] ??
            'người khác';
        throw DoubleApprovalException(
          'Công việc này đã được $existingApprover duyệt trước đó rồi ạ!',
        );
      }

      final resolvedFamilyId = familyId ??
          (taskData['familyId'] ?? taskData['family_id'])?.toString() ??
          '';
      final resolvedChildId = childId ??
          (taskData['assignedTo'] ?? taskData['assigned_to'])?.toString() ??
          '';
      final resolvedStars = stars ??
          (taskData['rewardStars'] as num?)?.toInt() ??
          (taskData['reward_stars'] as num?)?.toInt() ??
          0;

      final memberRef = firestore
          .collection('family_members')
          .doc('${resolvedFamilyId}_$resolvedChildId');
      final memberSnap = await transaction.get(memberRef);
      final currentBalance = memberSnap.exists
          ? (memberSnap.data()?['rewardStarsTotal'] as num?)?.toInt() ?? 0
          : 0;

      // 2. Writes
      // a. Update reminder document
      transaction.update(taskRef, {
        'status': 'APPROVED',
        'taskStatus': TaskStatus.completed.dbValue,
        'task_status': TaskStatus.completed.dbValue,
        'isCompleted': true,
        'is_completed': true,
        'approvedBy': reviewerId,
        'approvedByName': reviewerName,
        'approvedAt': FieldValue.serverTimestamp(),
        'completedAt': FieldValue.serverTimestamp(),
      });

      // b. Record idempotent immutable ledger entry
      final ledgerKey = 'reward_$taskId';
      transaction.set(ledgerRef, {
        'id': ledgerKey,
        'txId': ledgerKey,
        'familyId': resolvedFamilyId,
        'userId': resolvedChildId,
        'amount': resolvedStars,
        'type': 'TASK_REWARD',
        'taskId': taskId,
        'sourceId': taskId,
        'approvedBy': reviewerId,
        'reviewerName': reviewerName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // c. Increment child's reward stars
      if (memberSnap.exists) {
        transaction.update(memberRef, {
          'rewardStarsTotal': currentBalance + resolvedStars,
          'reward_stars_total': currentBalance + resolvedStars,
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.set(
          memberRef,
          {
            'familyId': resolvedFamilyId,
            'userId': resolvedChildId,
            'rewardStarsTotal': resolvedStars,
            'reward_stars_total': resolvedStars,
            'lastActiveAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 2. CLAIM WISHLIST ITEM (DOUBLE-SPENDING PROTECTION)
  // ---------------------------------------------------------------------------
  Future<void> claimWishlistItem({
    required String claimId,
    required String familyId,
    required String userId,
    required int cost,
    required String itemName,
  }) async {
    if (cost <= 0) {
      throw ArgumentError('Chi phí đổi quà phải lớn hơn 0');
    }

    final firestore = _firestore;
    if (firestore == null) {
      return _claimWishlistItemInMemory(
        claimId: claimId,
        familyId: familyId,
        userId: userId,
        cost: cost,
        itemName: itemName,
      );
    }

    final ledgerRef = firestore.collection('star_ledger').doc('claim_$claimId');
    final memberRef =
        firestore.collection('family_members').doc('${familyId}_$userId');

    await firestore.runTransaction((transaction) async {
      // 1. Reads
      final ledgerSnap = await transaction.get(ledgerRef);
      if (ledgerSnap.exists) {
        throw StateError('Yêu cầu đổi quà claim_$claimId đã được xử lý!');
      }

      final memberSnap = await transaction.get(memberRef);
      final memberData = memberSnap.data();
      final currentBalance = memberSnap.exists
          ? (memberData?['rewardStarsTotal'] as num?)?.toInt() ?? 0
          : 0;

      if (currentBalance < cost) {
        throw InsufficientStarsException(
          'INSUFFICIENT_STARS: Số dư sao không đủ để đổi quà $itemName (Cần $cost sao, hiện có $currentBalance sao).',
        );
      }

      // 2. Writes
      // a. Deduct balance immediately
      transaction.update(memberRef, {
        'rewardStarsTotal': currentBalance - cost,
        'reward_stars_total': currentBalance - cost,
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

      // b. Record negative amount ledger entry
      final ledgerKey = 'claim_$claimId';
      transaction.set(ledgerRef, {
        'id': ledgerKey,
        'txId': ledgerKey,
        'familyId': familyId,
        'userId': userId,
        'amount': -cost,
        'type': 'WISHLIST_CLAIM',
        'claimId': claimId,
        'itemName': itemName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // 3. REFUND WISHLIST CLAIM (GUARDIAN REJECTION)
  // ---------------------------------------------------------------------------
  Future<void> refundWishlistClaim({
    required String claimId,
    required String familyId,
    required String userId,
    required int refundStars,
    String? reason,
  }) async {
    if (refundStars <= 0) {
      throw ArgumentError('Số sao hoàn lại phải lớn hơn 0');
    }

    final firestore = _firestore;
    if (firestore == null) {
      return _refundWishlistClaimInMemory(
        claimId: claimId,
        familyId: familyId,
        userId: userId,
        refundStars: refundStars,
        reason: reason,
      );
    }

    final ledgerRef =
        firestore.collection('star_ledger').doc('refund_$claimId');
    final memberRef =
        firestore.collection('family_members').doc('${familyId}_$userId');

    await firestore.runTransaction((transaction) async {
      // 1. Reads
      final ledgerSnap = await transaction.get(ledgerRef);
      if (ledgerSnap.exists) {
        throw StateError('Yêu cầu hoàn sao refund_$claimId đã được xử lý!');
      }

      final memberSnap = await transaction.get(memberRef);
      final currentBalance = memberSnap.exists
          ? (memberSnap.data()?['rewardStarsTotal'] as num?)?.toInt() ?? 0
          : 0;

      // 2. Writes
      if (memberSnap.exists) {
        transaction.update(memberRef, {
          'rewardStarsTotal': currentBalance + refundStars,
          'reward_stars_total': currentBalance + refundStars,
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.set(
          memberRef,
          {
            'familyId': familyId,
            'userId': userId,
            'rewardStarsTotal': refundStars,
            'reward_stars_total': refundStars,
            'lastActiveAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      final ledgerKey = 'refund_$claimId';
      transaction.set(ledgerRef, {
        'id': ledgerKey,
        'txId': ledgerKey,
        'familyId': familyId,
        'userId': userId,
        'amount': refundStars,
        'type': 'CLAIM_REFUND',
        'claimId': claimId,
        'reason': reason ?? 'GUARDIAN_REJECTED',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // IN-MEMORY IMPLEMENTATION (For offline testing)
  // ---------------------------------------------------------------------------
  Future<void> _approveTaskInMemory({
    required String taskId,
    required String reviewerId,
    required String reviewerName,
    String? familyId,
    String? childId,
    int? stars,
  }) async {
    final task = reminders[taskId];
    if (task == null) {
      throw TaskNotFoundException('Công việc không tồn tại');
    }

    final currentStatus = (task['status'] ?? '').toString().toUpperCase();
    final currentTaskStatus =
        (task['taskStatus'] ?? '').toString().toUpperCase();
    if (currentStatus == 'APPROVED' ||
        currentStatus == 'COMPLETED' ||
        currentTaskStatus == 'COMPLETED') {
      final approvedByName = task['approvedByName'] ?? 'người khác';
      throw DoubleApprovalException(
        'Công việc này đã được $approvedByName duyệt trước đó rồi ạ!',
      );
    }

    final ledgerKey = 'reward_$taskId';
    if (starLedger.containsKey(ledgerKey)) {
      throw DoubleApprovalException(
        'DOUBLE_APPROVAL_DETECTED: Giao dịch thưởng sao reward_$taskId đã tồn tại trong sổ cái!',
      );
    }

    final resolvedFamilyId =
        familyId ?? task['familyId'] as String? ?? '';
    final resolvedChildId =
        childId ?? task['assignedTo'] as String? ?? '';
    final resolvedStars =
        stars ?? (task['rewardStars'] as num?)?.toInt() ?? 0;

    task['status'] = 'APPROVED';
    task['approvedBy'] = reviewerId;
    task['approvedByName'] = reviewerName;
    task['approvedAt'] = DateTime.now();
    task['taskStatus'] = 'COMPLETED';
    task['isCompleted'] = true;

    starLedger[ledgerKey] = {
      'id': ledgerKey,
      'txId': ledgerKey,
      'familyId': resolvedFamilyId,
      'userId': resolvedChildId,
      'amount': resolvedStars,
      'type': 'TASK_REWARD',
      'sourceId': taskId,
      'taskId': taskId,
      'approvedBy': reviewerId,
      'reviewerName': reviewerName,
      'createdAt': DateTime.now(),
    };

    final memberKey = '${resolvedFamilyId}_$resolvedChildId';
    memberBalances[memberKey] =
        (memberBalances[memberKey] ?? 0) + resolvedStars;
  }

  Future<void> _claimWishlistItemInMemory({
    required String claimId,
    required String familyId,
    required String userId,
    required int cost,
    required String itemName,
  }) async {
    final memberKey = '${familyId}_$userId';
    final currentBalance = memberBalances[memberKey] ?? 0;
    if (currentBalance < cost) {
      throw InsufficientStarsException(
        'INSUFFICIENT_STARS: Số dư sao không đủ để đổi quà $itemName (Cần $cost sao, hiện có $currentBalance sao).',
      );
    }

    final ledgerKey = 'claim_$claimId';
    if (starLedger.containsKey(ledgerKey)) {
      throw StateError('Yêu cầu đổi quà claim_$claimId đã được xử lý!');
    }

    memberBalances[memberKey] = currentBalance - cost;
    starLedger[ledgerKey] = {
      'id': ledgerKey,
      'txId': ledgerKey,
      'familyId': familyId,
      'userId': userId,
      'amount': -cost,
      'type': 'WISHLIST_CLAIM',
      'claimId': claimId,
      'itemName': itemName,
      'createdAt': DateTime.now(),
    };
  }

  Future<void> _refundWishlistClaimInMemory({
    required String claimId,
    required String familyId,
    required String userId,
    required int refundStars,
    String? reason,
  }) async {
    final ledgerKey = 'refund_$claimId';
    if (starLedger.containsKey(ledgerKey)) {
      throw StateError('Yêu cầu hoàn sao refund_$claimId đã được xử lý!');
    }

    final memberKey = '${familyId}_$userId';
    memberBalances[memberKey] =
        (memberBalances[memberKey] ?? 0) + refundStars;
    starLedger[ledgerKey] = {
      'id': ledgerKey,
      'txId': ledgerKey,
      'familyId': familyId,
      'userId': userId,
      'amount': refundStars,
      'type': 'CLAIM_REFUND',
      'claimId': claimId,
      'reason': reason ?? 'GUARDIAN_REJECTED',
      'createdAt': DateTime.now(),
    };
  }
}

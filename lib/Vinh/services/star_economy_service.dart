// lib/Vinh/services/star_economy_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/reminder_model.dart';
import '../models/family_member.dart';
import '../models/wishlist_models.dart';
import '../../Danh/services/notification_service.dart';

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
  final Map<String, WishlistRewardItem> wishlistCatalog = {};
  final Map<String, WishlistClaimRecord> wishlistClaims = {};
  final Map<String, int> familyStarPools = {}; // key: familyId -> jackpot star pool

  void seedMemberBalance(String familyId, String userId, int stars) {
    memberBalances['${familyId}_$userId'] = stars;
  }

  int getBalance(String familyId, String userId) {
    return memberBalances['${familyId}_$userId'] ?? 0;
  }

  int getFamilyStarPool(String familyId) {
    return familyStarPools[familyId] ?? 0;
  }

  void seedTask(String taskId, Map<String, dynamic> data) {
    reminders[taskId] = Map<String, dynamic>.from(data);
  }

  void resetMockData() {
    reminders.clear();
    starLedger.clear();
    memberBalances.clear();
    wishlistCatalog.clear();
    wishlistClaims.clear();
    familyStarPools.clear();
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
    String? creatorId,
    bool? isGuardian,
    String? reviewerRole,
    List<dynamic>? familyMembers,
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
        creatorId: creatorId,
        isGuardian: isGuardian,
        reviewerRole: reviewerRole,
        familyMembers: familyMembers,
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
      final resolvedCreatorId = creatorId ??
          (taskData['creatorId'] ?? taskData['creator_id'])?.toString() ??
          '';
      final resolvedStars = stars ??
          (taskData['rewardStars'] as num?)?.toInt() ??
          (taskData['reward_stars'] as num?)?.toInt() ??
          0;

      // Anti-Exploit Guard 1: Self-creation & self-approval farming
      if (resolvedCreatorId.isNotEmpty &&
          resolvedCreatorId == reviewerId &&
          resolvedChildId.isNotEmpty &&
          resolvedChildId == reviewerId) {
        throw StateError(
          'ANTI_EXPLOIT_SELF_APPROVAL: Người tạo việc không thể tự giao việc rồi tự duyệt để nhận sao.',
        );
      }

      // Anti-Exploit Guard 2: Self-awarding
      if (resolvedChildId.isNotEmpty && reviewerId == resolvedChildId) {
        throw StateError(
          'ANTI_EXPLOIT_SELF_AWARDING: Người thực hiện không được tự cấp sao cho chính mình.',
        );
      }

      // Anti-Exploit Guard 3: Guardian authorization
      bool effectiveIsGuardian = isGuardian ?? true;
      if (familyMembers != null && familyMembers.isNotEmpty) {
        try {
          final m = familyMembers.firstWhere((dynamic x) {
            if (x is FamilyMember) return x.id == reviewerId;
            if (x is Map) return x['id'] == reviewerId;
            return false;
          });
          if (m is FamilyMember) {
            effectiveIsGuardian = m.isGuardian && !m.isRelative;
          } else if (m is Map) {
            final role = (m['role'] ?? m['hierarchyRole'] ?? '').toString().toUpperCase();
            effectiveIsGuardian = (m['isGuardian'] == true ||
                    role.contains('PARENT') ||
                    role.contains('OWNER') ||
                    role.contains('GRANDPARENT')) &&
                !role.contains('RELATIVE') &&
                !role.contains('CHILD');
          }
        } catch (_) {}
      } else if (reviewerRole != null) {
        final rUpper = reviewerRole.toUpperCase();
        if (rUpper.contains('CHILD') || rUpper.contains('RELATIVE')) {
          effectiveIsGuardian = false;
        }
      } else if (reviewerId.toLowerCase().contains('child') ||
          reviewerId.toLowerCase().contains('relative')) {
        effectiveIsGuardian = false;
      }

      if (!effectiveIsGuardian) {
        throw StateError(
          'ANTI_EXPLOIT_GUARDIAN_REQUIRED: Chỉ Người giám hộ (Bố Mẹ, Ông Bà) mới có quyền duyệt việc và thưởng sao.',
        );
      }

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
  // 4. RELATIVE / GUARDIAN STAR SPONSORING (LÌ XÌ / TẶNG SAO KHÍCH LỆ)
  // ---------------------------------------------------------------------------
  /// Cho phép Cô / Dì / Chú / Bác (`RELATIVE`) hoặc Phụ huynh / Ông bà (`PARENT`, `GRANDPARENT`)
  /// tặng sao khích lệ (`stars > 0`) cho con cháu, ghi nhận vào `star_ledger`.
  /// Nghiêm cấm `RELATIVE` trừ sao phạt (`stars <= 0`) hoặc `CHILD` tự tặng sao.
  Future<void> giftStarsToChild({
    required String familyId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String childId,
    String? childName,
    required int stars,
    String? giftId,
    String? note,
  }) async {
    final roleUpper = senderRole.trim().toUpperCase();
    if (roleUpper.contains('CHILD') || roleUpper == 'CON') {
      throw StateError(
        'ANTI_EXPLOIT_CHILD_CANNOT_SPONSOR: Con cái không có quyền tặng sao khích lệ.',
      );
    }
    if (senderId == childId) {
      throw StateError(
        'ANTI_EXPLOIT_SELF_SPONSOR: Không thể tự tặng sao cho chính mình.',
      );
    }
    if (stars <= 0) {
      if (roleUpper.contains('RELATIVE') ||
          roleUpper.contains('UNCLE') ||
          roleUpper.contains('AUNT')) {
        throw StateError(
          'CULTURE_GOVERNANCE_VIOLATION: Cô / Dì / Chú / Bác chỉ có quyền TẶNG SAO khích lệ (> 0), tuyệt đối không có quyền trừ sao phạt cháu!',
        );
      }
      throw ArgumentError('Số sao lì xì / khích lệ phải lớn hơn 0.');
    }

    final effectiveGiftId =
        giftId ?? '${senderId}_${childId}_${DateTime.now().microsecondsSinceEpoch}';
    final ledgerKey = 'sponsor_$effectiveGiftId';

    final firestore = _firestore;
    if (firestore == null) {
      if (starLedger.containsKey(ledgerKey)) {
        throw StateError('Giao dịch lì xì sao $ledgerKey đã được thực hiện!');
      }
      final memberKey = '${familyId}_$childId';
      memberBalances[memberKey] = (memberBalances[memberKey] ?? 0) + stars;
      starLedger[ledgerKey] = {
        'id': ledgerKey,
        'txId': ledgerKey,
        'familyId': familyId,
        'userId': childId,
        'userName': childName ?? 'Cháu',
        'amount': stars,
        'type': 'RELATIVE_SPONSOR',
        'sourceId': effectiveGiftId,
        'senderId': senderId,
        'senderName': senderName,
        'senderRole': senderRole,
        'note': note ?? 'Lì xì sao khích lệ chăm ngoan',
        'createdAt': DateTime.now(),
      };
      return;
    }

    final ledgerRef = firestore.collection('star_ledger').doc(ledgerKey);
    final memberRef =
        firestore.collection('family_members').doc('${familyId}_$childId');

    await firestore.runTransaction((transaction) async {
      final ledgerSnap = await transaction.get(ledgerRef);
      if (ledgerSnap.exists) {
        throw StateError('Giao dịch lì xì sao $ledgerKey đã được thực hiện!');
      }

      final memberSnap = await transaction.get(memberRef);
      final currentBalance = memberSnap.exists
          ? (memberSnap.data()?['rewardStarsTotal'] as num?)?.toInt() ?? 0
          : 0;

      if (memberSnap.exists) {
        transaction.update(memberRef, {
          'rewardStarsTotal': currentBalance + stars,
          'reward_stars_total': currentBalance + stars,
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.set(
          memberRef,
          {
            'familyId': familyId,
            'userId': childId,
            'rewardStarsTotal': stars,
            'reward_stars_total': stars,
            'lastActiveAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      transaction.set(ledgerRef, {
        'id': ledgerKey,
        'txId': ledgerKey,
        'familyId': familyId,
        'userId': childId,
        'userName': childName ?? 'Cháu',
        'amount': stars,
        'type': 'RELATIVE_SPONSOR',
        'sourceId': effectiveGiftId,
        'senderId': senderId,
        'senderName': senderName,
        'senderRole': senderRole,
        'note': note ?? 'Lì xì sao khích lệ chăm ngoan',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // 5. JACKPOT STAR POOL & WIN CREDITING (NỔ HŨ SAO GIA ĐÌNH)
  // ---------------------------------------------------------------------------
  /// Đóng góp hoặc tích lũy sao vào Hũ Sao Gia Đình
  Future<int> contributeStarsToJackpotPool({
    required String familyId,
    required String contributorId,
    required String contributorName,
    required int stars,
    String? sourceTaskId,
  }) async {
    if (stars <= 0) {
      throw ArgumentError('Số sao nạp vào Hũ phải lớn hơn 0.');
    }
    final nextPool = (familyStarPools[familyId] ?? 0) + stars;
    familyStarPools[familyId] = nextPool;

    final txKey = sourceTaskId != null
        ? 'jackpot_contrib_task_$sourceTaskId'
        : 'jackpot_contrib_${contributorId}_${DateTime.now().microsecondsSinceEpoch}';

    if (_firestore == null) {
      starLedger[txKey] = {
        'id': txKey,
        'txId': txKey,
        'familyId': familyId,
        'userId': contributorId,
        'userName': contributorName,
        'amount': stars,
        'type': 'JACKPOT_CONTRIBUTE',
        'sourceId': sourceTaskId ?? txKey,
        'actorId': contributorId,
        'actorName': contributorName,
        'note': sourceTaskId != null
            ? 'Tích lũy tự động từ nhiệm vụ hoàn thành'
            : 'Góp sao vào Hũ Niềm Vui Gia Đình',
        'createdAt': DateTime.now(),
      };
      return nextPool;
    }

    try {
      await _firestore!.collection('star_ledger').doc(txKey).set({
        'id': txKey,
        'txId': txKey,
        'familyId': familyId,
        'userId': contributorId,
        'userName': contributorName,
        'amount': stars,
        'type': 'JACKPOT_CONTRIBUTE',
        'sourceId': sourceTaskId ?? txKey,
        'actorId': contributorId,
        'actorName': contributorName,
        'note': sourceTaskId != null
            ? 'Tích lũy tự động từ nhiệm vụ hoàn thành'
            : 'Góp sao vào Hũ Niềm Vui Gia Đình',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('contributeStarsToJackpotPool error: $e');
    }
    return nextPool;
  }

  /// Cộng sao trúng thưởng từ Nổ Hũ Sao vào tài khoản thành viên và ghi Sổ cái `star_ledger`
  Future<void> creditJackpotStarWin({
    required String familyId,
    required String winnerId,
    String? winnerName,
    required int wonStars,
    required String roundId,
    bool isFirstPrize = false,
  }) async {
    if (wonStars <= 0) return;
    final ledgerKey = 'jackpot_${roundId}_$winnerId';

    final firestore = _firestore;
    if (firestore == null) {
      if (starLedger.containsKey(ledgerKey)) return; // Idempotent
      final memberKey = '${familyId}_$winnerId';
      memberBalances[memberKey] = (memberBalances[memberKey] ?? 0) + wonStars;
      starLedger[ledgerKey] = {
        'id': ledgerKey,
        'txId': ledgerKey,
        'familyId': familyId,
        'userId': winnerId,
        'userName': winnerName ?? 'Thành viên',
        'amount': wonStars,
        'type': 'JACKPOT_WIN',
        'sourceId': roundId,
        'note': isFirstPrize
            ? 'Giải Nhất Nổ Hũ Sao Gia Đình 👑'
            : 'Thưởng lắc Hũ Sao Gia Đình 🎉',
        'createdAt': DateTime.now(),
      };
      return;
    }

    final ledgerRef = firestore.collection('star_ledger').doc(ledgerKey);
    final memberRef =
        firestore.collection('family_members').doc('${familyId}_$winnerId');

    await firestore.runTransaction((transaction) async {
      final ledgerSnap = await transaction.get(ledgerRef);
      if (ledgerSnap.exists) return;

      final memberSnap = await transaction.get(memberRef);
      final currentBalance = memberSnap.exists
          ? (memberSnap.data()?['rewardStarsTotal'] as num?)?.toInt() ?? 0
          : 0;

      if (memberSnap.exists) {
        transaction.update(memberRef, {
          'rewardStarsTotal': currentBalance + wonStars,
          'reward_stars_total': currentBalance + wonStars,
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.set(
          memberRef,
          {
            'familyId': familyId,
            'userId': winnerId,
            'rewardStarsTotal': wonStars,
            'reward_stars_total': wonStars,
            'lastActiveAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      transaction.set(ledgerRef, {
        'id': ledgerKey,
        'txId': ledgerKey,
        'familyId': familyId,
        'userId': winnerId,
        'userName': winnerName ?? 'Thành viên',
        'amount': wonStars,
        'type': 'JACKPOT_WIN',
        'sourceId': roundId,
        'note': isFirstPrize
            ? 'Giải Nhất Nổ Hũ Sao Gia Đình 👑'
            : 'Thưởng lắc Hũ Sao Gia Đình 🎉',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // 6. WISHLIST CATALOG & REAL-WORLD REWARD REDEMPTION LIFECYCLE (M4)
  // ---------------------------------------------------------------------------
  bool _isGuardianRole(String role, {bool? isGuardianFlag}) {
    if (isGuardianFlag != null) return isGuardianFlag;
    final upper = role.trim().toUpperCase();
    if (upper.contains('CHILD') ||
        upper == 'CON' ||
        upper.contains('RELATIVE') ||
        upper.contains('UNCLE') ||
        upper.contains('AUNT')) {
      return false;
    }
    return upper.contains('PARENT') ||
        upper.contains('GRANDPARENT') ||
        upper.contains('OWNER') ||
        upper.contains('BỐ') ||
        upper.contains('MẸ') ||
        upper.contains('ÔNG') ||
        upper.contains('BÀ');
  }

  /// Khởi tạo danh sách Phúc lợi thực tế mặc định cho gia đình nếu chưa có
  List<WishlistRewardItem> getWishlistCatalog(String familyId) {
    final existing = wishlistCatalog.values
        .where((item) => item.familyId == familyId && item.isActive)
        .toList();
    if (existing.isNotEmpty) {
      existing.sort((a, b) => a.starCost.compareTo(b.starCost));
      return existing;
    }
    final defaults = [
      WishlistRewardItem(
        id: '${familyId}_reward_movie_30m',
        familyId: familyId,
        title: 'Xem phim hoạt hình 30 phút',
        description: 'Được xem TV / iPad thêm 30 phút cuối tuần cùng gia đình',
        starCost: 15,
        iconEmoji: '🎬',
        createdBy: 'system_guardian',
        createdByName: 'Phụ huynh',
        createdAt: DateTime(2026, 11, 1),
      ),
      WishlistRewardItem(
        id: '${familyId}_reward_comic_book',
        familyId: familyId,
        title: 'Mua 1 quyển truyện tranh yêu thích',
        description: 'Bố mẹ dẫn đi nhà sách chọn 1 cuốn truyện tranh mới',
        starCost: 50,
        iconEmoji: '📚',
        createdBy: 'system_guardian',
        createdByName: 'Phụ huynh',
        createdAt: DateTime(2026, 11, 1),
      ),
      WishlistRewardItem(
        id: '${familyId}_reward_park_trip',
        familyId: familyId,
        title: 'Đi công viên / Khu vui chơi cuối tuần',
        description: 'Cả nhà cùng đi dã ngoại công viên hoặc khu trò chơi',
        starCost: 80,
        iconEmoji: '🎡',
        createdBy: 'system_guardian',
        createdByName: 'Phụ huynh',
        createdAt: DateTime(2026, 11, 1),
      ),
      WishlistRewardItem(
        id: '${familyId}_reward_beach_trip',
        familyId: familyId,
        title: 'Chuyến đi chơi biển kỳ nghỉ',
        description: 'Phần thưởng lớn khi con chăm ngoan tích lũy đủ sao',
        starCost: 200,
        iconEmoji: '🏖️',
        createdBy: 'system_guardian',
        createdByName: 'Phụ huynh',
        createdAt: DateTime(2026, 11, 1),
      ),
    ];
    for (final d in defaults) {
      wishlistCatalog[d.id] = d;
    }
    return defaults;
  }

  /// Chỉ Người giám hộ (`PARENT`, `GRANDPARENT`) mới có quyền tạo phúc lợi đổi sao mới
  Future<WishlistRewardItem> createWishlistRewardItem({
    required String familyId,
    required String creatorId,
    required String creatorName,
    required String creatorRole,
    bool? isGuardian,
    required String title,
    String description = '',
    required int starCost,
    String iconEmoji = '🎁',
    String? itemId,
  }) async {
    if (!_isGuardianRole(creatorRole, isGuardianFlag: isGuardian)) {
      throw StateError(
        'GUARDIAN_REQUIRED: Chỉ Bố Mẹ hoặc Ông Bà mới có quyền thêm vật phẩm phúc lợi vào Cửa hàng Đổi Sao.',
      );
    }
    if (title.trim().isEmpty) {
      throw ArgumentError('Tên phúc lợi không được để trống.');
    }
    if (starCost <= 0) {
      throw ArgumentError('Định giá sao của phúc lợi phải lớn hơn 0.');
    }

    final effectiveId =
        itemId ?? 'reward_${familyId}_${DateTime.now().microsecondsSinceEpoch}';
    final item = WishlistRewardItem(
      id: effectiveId,
      familyId: familyId,
      title: title.trim(),
      description: description.trim(),
      starCost: starCost,
      iconEmoji: iconEmoji,
      createdBy: creatorId,
      createdByName: creatorName,
      createdAt: DateTime.now(),
    );

    wishlistCatalog[effectiveId] = item;

    if (_firestore != null) {
      try {
        await _firestore!
            .collection('families')
            .doc(familyId)
            .collection('wishlist_catalog')
            .doc(effectiveId)
            .set(item.toMap());
      } catch (e) {
        debugPrint('createWishlistRewardItem firestore error: $e');
      }
    }
    return item;
  }

  /// Con cái nhấn Đổi Quà (Redeem): Trừ sao ngay lập tức, tạo bản ghi `PENDING` và bắn thông báo cho Phụ huynh
  Future<WishlistClaimRecord> submitWishlistRedemption({
    required String familyId,
    required String childId,
    required String childName,
    required WishlistRewardItem item,
    String? claimId,
  }) async {
    final effectiveClaimId =
        claimId ?? '${childId}_${item.id}_${DateTime.now().microsecondsSinceEpoch}';

    // 1. Trừ sao nguyên tử + ghi sổ cái `claim_${effectiveClaimId}`
    await claimWishlistItem(
      claimId: effectiveClaimId,
      familyId: familyId,
      userId: childId,
      cost: item.starCost,
      itemName: item.title,
    );

    // 2. Lưu trạng thái yêu cầu đổi quà PENDING
    final claimRecord = WishlistClaimRecord(
      id: effectiveClaimId,
      familyId: familyId,
      itemId: item.id,
      itemName: item.title,
      iconEmoji: item.iconEmoji,
      childId: childId,
      childName: childName,
      starCost: item.starCost,
      status: WishlistClaimStatus.pending,
      createdAt: DateTime.now(),
    );
    wishlistClaims[effectiveClaimId] = claimRecord;

    if (_firestore != null) {
      try {
        await _firestore!
            .collection('families')
            .doc(familyId)
            .collection('wishlist_claims')
            .doc(effectiveClaimId)
            .set(claimRecord.toMap());
      } catch (e) {
        debugPrint('submitWishlistRedemption firestore error: $e');
      }
    }

    // 3. Gửi thông báo cho Phụ huynh biết con muốn đổi phúc lợi gì
    unawaited(
      NotificationService.instance.addNotification(
        familyId: familyId,
        title: '🎁 Yêu cầu đổi sao mới từ $childName!',
        titleEn: '🎁 New Star Redemption from $childName!',
        body:
            '$childName vừa dùng ${item.starCost} ⭐ để đổi "${item.title}". Phụ huynh hãy kiểm tra và duyệt cho bé nhé!',
        bodyEn:
            '$childName redeemed ${item.starCost} ⭐ for "${item.title}". Please review and approve!',
        type: 'wishlist_claim',
      ),
    );

    return claimRecord;
  }

  /// Phụ huynh duyệt đồng ý trao phúc lợi thực tế (`APPROVED`)
  Future<WishlistClaimRecord> approveWishlistRedemption({
    required String claimId,
    required String guardianId,
    required String guardianName,
    required String guardianRole,
    bool? isGuardian,
  }) async {
    if (!_isGuardianRole(guardianRole, isGuardianFlag: isGuardian)) {
      throw StateError(
        'GUARDIAN_REQUIRED: Chỉ Người giám hộ (Bố Mẹ, Ông Bà) mới có quyền duyệt yêu cầu đổi quà.',
      );
    }
    final existing = wishlistClaims[claimId];
    if (existing == null) {
      throw StateError('Yêu cầu đổi quà không tồn tại.');
    }
    if (existing.status != WishlistClaimStatus.pending) {
      throw StateError('Yêu cầu đổi quà này đã được xử lý (${existing.status.code}).');
    }

    final updated = existing.copyWith(
      status: WishlistClaimStatus.approved,
      reviewedBy: guardianId,
      reviewedByName: guardianName,
      reviewedAt: DateTime.now(),
    );
    wishlistClaims[claimId] = updated;

    if (_firestore != null) {
      try {
        await _firestore!
            .collection('families')
            .doc(existing.familyId)
            .collection('wishlist_claims')
            .doc(claimId)
            .update({
          'status': WishlistClaimStatus.approved.code,
          'reviewedBy': guardianId,
          'reviewedByName': guardianName,
          'reviewedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('approveWishlistRedemption error: $e');
      }
    }

    unawaited(
      NotificationService.instance.addNotification(
        familyId: existing.familyId,
        targetUserId: existing.childId,
        title: '🎉 Bố/Mẹ đã duyệt quà "${existing.itemName}"!',
        titleEn: '🎉 Your reward "${existing.itemName}" was approved!',
        body: '$guardianName đã đồng ý trao phần thưởng "${existing.itemName}" cho ${existing.childName}!',
        bodyEn: '$guardianName approved your reward "${existing.itemName}"!',
        type: 'wishlist_approved',
      ),
    );

    return updated;
  }

  /// Phụ huynh từ chối yêu cầu đổi quà (`REJECTED`) -> Tự động hoàn lại 100% số sao cho con
  Future<WishlistClaimRecord> rejectWishlistRedemption({
    required String claimId,
    required String guardianId,
    required String guardianName,
    required String guardianRole,
    bool? isGuardian,
    String reason = 'Chưa phù hợp thời điểm này',
  }) async {
    if (!_isGuardianRole(guardianRole, isGuardianFlag: isGuardian)) {
      throw StateError(
        'GUARDIAN_REQUIRED: Chỉ Người giám hộ (Bố Mẹ, Ông Bà) mới có quyền từ chối và hoàn sao đổi quà.',
      );
    }
    final existing = wishlistClaims[claimId];
    if (existing == null) {
      throw StateError('Yêu cầu đổi quà không tồn tại.');
    }
    if (existing.status != WishlistClaimStatus.pending) {
      throw StateError('Yêu cầu đổi quà này đã được xử lý (${existing.status.code}).');
    }

    // 1. Hoàn 100% sao vào ví con + ghi sổ cái `refund_${claimId}`
    await refundWishlistClaim(
      claimId: claimId,
      familyId: existing.familyId,
      userId: existing.childId,
      refundStars: existing.starCost,
      reason: reason,
    );

    // 2. Cập nhật trạng thái REJECTED
    final updated = existing.copyWith(
      status: WishlistClaimStatus.rejected,
      reviewedBy: guardianId,
      reviewedByName: guardianName,
      reviewedAt: DateTime.now(),
      rejectReason: reason,
    );
    wishlistClaims[claimId] = updated;

    if (_firestore != null) {
      try {
        await _firestore!
            .collection('families')
            .doc(existing.familyId)
            .collection('wishlist_claims')
            .doc(claimId)
            .update({
          'status': WishlistClaimStatus.rejected.code,
          'reviewedBy': guardianId,
          'reviewedByName': guardianName,
          'reviewedAt': FieldValue.serverTimestamp(),
          'rejectReason': reason,
        });
      } catch (e) {
        debugPrint('rejectWishlistRedemption error: $e');
      }
    }

    unawaited(
      NotificationService.instance.addNotification(
        familyId: existing.familyId,
        targetUserId: existing.childId,
        title: '🔄 Đã hoàn lại ${existing.starCost} ⭐ từ "${existing.itemName}"',
        titleEn: '🔄 Refunded ${existing.starCost} ⭐ for "${existing.itemName}"',
        body: '$guardianName nhắn: "$reason". Hệ thống đã hoàn lại đủ ${existing.starCost} ⭐ cho con!',
        bodyEn: '$guardianName noted: "$reason". ${existing.starCost} ⭐ has been refunded!',
        type: 'wishlist_rejected',
      ),
    );

    return updated;
  }

  /// Lấy danh sách các yêu cầu đổi quà của gia đình (mới nhất lên đầu)
  List<WishlistClaimRecord> getWishlistClaims(String familyId, {String? childId}) {
    final list = wishlistClaims.values.where((c) {
      if (c.familyId != familyId) return false;
      if (childId != null && childId.isNotEmpty && c.childId != childId) {
        return false;
      }
      return true;
    }).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ---------------------------------------------------------------------------
  // 7. STAR LEDGER AUDIT HISTORY QUERY (M5)
  // ---------------------------------------------------------------------------
  /// Truy vấn lịch sử giao dịch sao (`star_ledger`) của gia đình hoặc từng thành viên
  List<StarLedgerEntryModel> getStarLedgerHistory(
    String familyId, {
    String? userId,
  }) {
    final entries = <StarLedgerEntryModel>[];
    starLedger.forEach((key, map) {
      final entryFam = (map['familyId'] ?? '').toString();
      if (entryFam == familyId) {
        if (userId == null ||
            userId.isEmpty ||
            map['userId']?.toString() == userId) {
          entries.add(StarLedgerEntryModel.fromMap(key, map));
        }
      }
    });
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
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
    String? creatorId,
    bool? isGuardian,
    String? reviewerRole,
    List<dynamic>? familyMembers,
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
    final resolvedCreatorId =
        creatorId ?? task['creatorId'] as String? ?? task['creator_id'] as String? ?? '';
    final resolvedStars =
        stars ?? (task['rewardStars'] as num?)?.toInt() ?? 0;

    // Anti-Exploit Guard 1: Self-creation & self-approval farming
    if (resolvedCreatorId.isNotEmpty &&
        resolvedCreatorId == reviewerId &&
        resolvedChildId.isNotEmpty &&
        resolvedChildId == reviewerId) {
      throw StateError(
        'ANTI_EXPLOIT_SELF_APPROVAL: Người tạo việc không thể tự giao việc rồi tự duyệt để nhận sao.',
      );
    }

    // Anti-Exploit Guard 2: Self-awarding
    if (resolvedChildId.isNotEmpty && reviewerId == resolvedChildId) {
      throw StateError(
        'ANTI_EXPLOIT_SELF_AWARDING: Người thực hiện không được tự cấp sao cho chính mình.',
      );
    }

    // Anti-Exploit Guard 3: Guardian authorization
    bool effectiveIsGuardian = isGuardian ?? true;
    if (familyMembers != null && familyMembers.isNotEmpty) {
      try {
        final m = familyMembers.firstWhere((dynamic x) {
          if (x is FamilyMember) return x.id == reviewerId;
          if (x is Map) return x['id'] == reviewerId;
          return false;
        });
        if (m is FamilyMember) {
          effectiveIsGuardian = m.isGuardian && !m.isRelative;
        } else if (m is Map) {
          final role = (m['role'] ?? m['hierarchyRole'] ?? '').toString().toUpperCase();
          effectiveIsGuardian = (m['isGuardian'] == true ||
                  role.contains('PARENT') ||
                  role.contains('OWNER') ||
                  role.contains('GRANDPARENT')) &&
              !role.contains('RELATIVE') &&
              !role.contains('CHILD');
        }
      } catch (_) {}
    } else if (reviewerRole != null) {
      final rUpper = reviewerRole.toUpperCase();
      if (rUpper.contains('CHILD') || rUpper.contains('RELATIVE')) {
        effectiveIsGuardian = false;
      }
    } else if (reviewerId.toLowerCase().contains('child') ||
        reviewerId.toLowerCase().contains('relative')) {
      effectiveIsGuardian = false;
    }

    if (!effectiveIsGuardian) {
      throw StateError(
        'ANTI_EXPLOIT_GUARDIAN_REQUIRED: Chỉ Người giám hộ (Bố Mẹ, Ông Bà) mới có quyền duyệt việc và thưởng sao.',
      );
    }

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

    // Tự động tích lũy thêm sao thưởng bonus vào Hũ Sao Gia Đình khi công việc có thưởng sao
    if (resolvedStars > 0 && resolvedFamilyId.isNotEmpty) {
      final bonusForPot = resolvedStars >= 5 ? (resolvedStars * 0.2).ceil() : 1;
      familyStarPools[resolvedFamilyId] =
          (familyStarPools[resolvedFamilyId] ?? 0) + bonusForPot;
    }
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

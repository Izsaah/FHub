import '../../Danh/services/family_jackpot_service.dart';
// lib/Vinh/services/star_economy_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  /// Đọc số dư sao thời gian thực của thành viên theo đúng familyId từ Firestore
  Future<int> fetchMemberBalance(String familyId, String userId) async {
    if (_firestore != null) {
      try {
        final doc = await _firestore!
            .collection('family_members')
            .doc('${familyId}_$userId')
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final val = data['rewardStarsTotal'] ?? data['reward_stars_total'] ?? data['stars'];
          final balance = (val as num?)?.toInt() ?? 0;
          seedMemberBalance(familyId, userId, balance);
          return balance;
        }
      } catch (e) {
        debugPrint('fetchMemberBalance error: $e');
      }
    }
    return getBalance(familyId, userId);
  }

  /// Cộng sao khi hoàn thành task reminder (Việc nhà / Chăm sóc)
  /// QUY TẮC CỐT LÕI: Không áp dụng cộng sao cho task trong đó Người tạo là Người hoàn thành
  /// (chống tự tạo việc cho mình rồi tự hoàn thành để farm sao).
  Future<void> awardStarsForCompletedChore({
    required String familyId,
    required String taskId,
    required String completerId,
    String? completerName,
    required String creatorId,
    String? creatorName,
    required int stars,
    String? taskTitle,
  }) async {
    // Chống tự tạo việc cho chính mình rồi tự hoàn thành để nhận sao
    if (creatorId.isNotEmpty && creatorId == completerId) {
      debugPrint('awardStarsForCompletedChore: Người tạo ($creatorId) tự hoàn thành task -> Bỏ qua cộng sao.');
      return;
    }

    if (stars <= 0) return;

    final ledgerKey = 'reward_$taskId';

    final firestore = _firestore;
    if (firestore == null) {
      if (starLedger.containsKey(ledgerKey)) return; // Idempotent
      final memberKey = '${familyId}_$completerId';
      memberBalances[memberKey] = (memberBalances[memberKey] ?? 0) + stars;
      starLedger[ledgerKey] = {
        'id': ledgerKey,
        'txId': ledgerKey,
        'familyId': familyId,
        'userId': completerId,
        'userName': completerName ?? 'Thành viên',
        'amount': stars,
        'type': 'TASK_REWARD',
        'taskId': taskId,
        'sourceId': taskId,
        'creatorId': creatorId,
        'creatorName': creatorName,
        'taskTitle': taskTitle ?? 'Hoàn thành việc nhà',
        'note': 'Thưởng hoàn thành: ${taskTitle ?? 'Công việc'}',
        'createdAt': DateTime.now(),
      };
      return;
    }

    final ledgerRef = firestore.collection('star_ledger').doc(ledgerKey);
    final memberRef =
        firestore.collection('family_members').doc('${familyId}_$completerId');

    try {
      await firestore.runTransaction((transaction) async {
        final ledgerSnap = await transaction.get(ledgerRef);
        if (ledgerSnap.exists) return; // Idempotent: Đã cộng sao cho task này rồi

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
              'userId': completerId,
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
          'userId': completerId,
          'userName': completerName ?? 'Thành viên',
          'amount': stars,
          'type': 'TASK_REWARD',
          'taskId': taskId,
          'sourceId': taskId,
          'creatorId': creatorId,
          'creatorName': creatorName,
          'taskTitle': taskTitle ?? 'Hoàn thành việc nhà',
          'note': 'Thưởng hoàn thành: ${taskTitle ?? 'Công việc'}',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('awardStarsForCompletedChore transaction error: $e');
    }
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
    String? approvedBy,
  }) async {
    if (refundStars <= 0) {
      throw ArgumentError('Số sao hoàn lại phải lớn hơn 0');
    }

    String currentUserId = approvedBy ?? '';
    if (currentUserId.isEmpty) {
      try {
        currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
      } catch (_) {}
    }
    if (currentUserId.isEmpty) {
      currentUserId = 'system';
    }

    final firestore = _firestore;
    if (firestore == null) {
      return _refundWishlistClaimInMemory(
        claimId: claimId,
        familyId: familyId,
        userId: userId,
        refundStars: refundStars,
        reason: reason,
        approvedBy: currentUserId,
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
        'approvedBy': currentUserId,
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
    if (stars > 20) {
      throw ArgumentError('Số sao tặng tối đa mỗi lần là 20 ⭐.');
    }

    final effectiveGiftId =
        giftId ?? '${senderId}_${childId}_${DateTime.now().microsecondsSinceEpoch}';
    final ledgerKey = 'sponsor_$effectiveGiftId';

    final firestore = _firestore;
    if (firestore == null) {
      if (starLedger.containsKey(ledgerKey)) {
        throw StateError('Giao dịch lì xì sao $ledgerKey đã được thực hiện!');
      }
      final senderKey = '${familyId}_$senderId';
      if (memberBalances.containsKey(senderKey)) {
        final senderBalance = memberBalances[senderKey] ?? 0;
        if (stars > senderBalance) {
          throw StateError('Số dư sao không đủ! Bạn chỉ có $senderBalance sao để tặng.');
        }
        memberBalances[senderKey] = senderBalance - stars;
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
        'actorId': senderId,
        'actorName': senderName,
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
    final senderRef =
        firestore.collection('family_members').doc('${familyId}_$senderId');

    await firestore.runTransaction((transaction) async {
      final ledgerSnap = await transaction.get(ledgerRef);
      if (ledgerSnap.exists) {
        throw StateError('Giao dịch lì xì sao $ledgerKey đã được thực hiện!');
      }

      final senderSnap = await transaction.get(senderRef);
      if (senderSnap.exists) {
        final senderBalance =
            (senderSnap.data()?['rewardStarsTotal'] as num?)?.toInt() ??
            (senderSnap.data()?['reward_stars_total'] as num?)?.toInt() ?? 0;

        if (stars > senderBalance) {
          throw StateError('Số dư sao không đủ! Bạn chỉ có $senderBalance sao để tặng.');
        }

        transaction.update(senderRef, {
          'rewardStarsTotal': senderBalance - stars,
          'reward_stars_total': senderBalance - stars,
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
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
        'actorId': senderId,
        'actorName': senderName,
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
    String? note,
  }) async {
    if (stars <= 0) {
      throw ArgumentError('Số sao nạp vào Hũ phải lớn hơn 0.');
    }
    final nextPool = (familyStarPools[familyId] ?? 0) + stars;
    familyStarPools[familyId] = nextPool;

    final txKey = sourceTaskId != null
        ? 'jackpot_contrib_task_$sourceTaskId'
        : 'jackpot_contrib_${contributorId}_${DateTime.now().microsecondsSinceEpoch}';

    final effectiveNote = note ??
        (sourceTaskId != null
            ? 'Tích lũy tự động từ nhiệm vụ hoàn thành'
            : 'Góp sao vào Heo Đất Gia Đình');

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
        'note': effectiveNote,
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
        'note': effectiveNote,
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
            ? 'Thưởng Xuất Sắc Heo Đất Gia Đình 👑'
            : 'Thưởng Heo Đất Gia Đình ⭐',
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
            ? 'Thưởng Xuất Sắc Heo Đất Gia Đình 👑'
            : 'Thưởng Heo Đất Gia Đình ⭐',
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

  /// Lấy danh sách Phúc lợi thực tế của gia đình từ bộ nhớ cache
  /// Tuyệt đối KHÔNG tự động chèn mock data! Nếu gia đình chưa có phần thưởng nào,
  /// hàm sẽ trả về danh sách rỗng [] để giao diện hiển thị Empty State cho Bố Mẹ tạo mới.
  List<WishlistRewardItem> getWishlistCatalog(String familyId) {
    final existing = wishlistCatalog.values
        .where((item) => item.familyId == familyId && item.isActive)
        .toList();
    existing.sort((a, b) => a.starCost.compareTo(b.starCost));
    return existing;
  }

  /// Helper chỉ dành cho unit test môi trường cô lập in-memory
  List<WishlistRewardItem> seedDefaultWishlistRewardsForTest(String familyId) {
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

  /// Tải danh mục Phúc Lợi Thực Tế của gia đình từ Firestore (Không dùng mock data)
  Future<List<WishlistRewardItem>> fetchWishlistCatalog(String familyId) async {
    if (_firestore != null) {
      try {
        final snap = await _firestore!
            .collection('families')
            .doc(familyId)
            .collection('wishlist_rewards')
            .get();
        final list = <WishlistRewardItem>[];
        for (final doc in snap.docs) {
          final item = WishlistRewardItem.fromMap(doc.id, doc.data());
          if (item.isActive) {
            list.add(item);
          }
          wishlistCatalog[doc.id] = item;
        }
        list.sort((a, b) => a.starCost.compareTo(b.starCost));
        return list;
      } catch (e) {
        debugPrint('fetchWishlistCatalog error: $e');
      }
    }
    final local = wishlistCatalog.values
        .where((item) => item.familyId == familyId && item.isActive)
        .toList();
    local.sort((a, b) => a.starCost.compareTo(b.starCost));
    return local;
  }

  /// Lắng nghe Stream danh mục Phúc Lợi Thực Tế thời gian thực từ Firestore
  Stream<List<WishlistRewardItem>> watchWishlistCatalog(String familyId) {
    if (_firestore != null) {
      return _firestore!
          .collection('families')
          .doc(familyId)
          .collection('wishlist_rewards')
          .snapshots()
          .map((snapshot) {
            final list = <WishlistRewardItem>[];
            for (final doc in snapshot.docs) {
              final item = WishlistRewardItem.fromMap(doc.id, doc.data());
              if (item.isActive) {
                list.add(item);
              }
              wishlistCatalog[doc.id] = item;
            }
            list.sort((a, b) => a.starCost.compareTo(b.starCost));
            return list;
          });
    }
    return Stream.value(getWishlistCatalog(familyId));
  }

  /// Lắng nghe Stream yêu cầu đổi quà của gia đình thời gian thực từ Firestore
  Stream<List<WishlistClaimRecord>> watchWishlistClaims(
    String familyId, {
    String? childId,
  }) {
    if (_firestore != null) {
      return _firestore!
          .collection('families')
          .doc(familyId)
          .collection('wishlist_claims')
          .snapshots()
          .map((snapshot) {
            final list = <WishlistClaimRecord>[];
            for (final doc in snapshot.docs) {
              final claim = WishlistClaimRecord.fromMap(doc.id, doc.data());
              if (childId != null && childId.isNotEmpty && claim.childId != childId) {
                continue;
              }
              list.add(claim);
              wishlistClaims[doc.id] = claim;
            }
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list;
          });
    }
    return Stream.value(getWishlistClaims(familyId, childId: childId));
  }

  /// Lắng nghe Stream số dư sao của thành viên thời gian thực
  Stream<int> watchMemberBalance(String familyId, String userId) {
    if (_firestore != null) {
      return _firestore!
          .collection('family_members')
          .doc('${familyId}_$userId')
          .snapshots()
          .map((snapshot) {
            if (!snapshot.exists) return 0;
            final data = snapshot.data();
            final val = data?['rewardStarsTotal'] ?? data?['reward_stars_total'];
            final balance = (val as num?)?.toInt() ?? 0;
            seedMemberBalance(familyId, userId, balance);
            return balance;
          });
    }
    return Stream.value(getBalance(familyId, userId));
  }

  /// Lắng nghe Stream lịch sử giao dịch sao (Sổ cái) của gia đình thời gian thực
  Stream<List<StarLedgerEntryModel>> watchStarLedger(
    String familyId, {
    String? userId,
  }) {
    if (_firestore != null) {
      return _firestore!
          .collection('star_ledger')
          .where('familyId', isEqualTo: familyId)
          .snapshots()
          .map((snapshot) {
            final list = <StarLedgerEntryModel>[];
            for (final doc in snapshot.docs) {
              final entry = StarLedgerEntryModel.fromMap(doc.id, doc.data());
              if (userId != null && userId.isNotEmpty && entry.userId != userId) {
                continue;
              }
              list.add(entry);
              starLedger[doc.id] = doc.data();
            }
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list;
          });
    }
    return Stream.value(getStarLedgerHistory(familyId, userId: userId));
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
            .collection('wishlist_rewards')
            .doc(effectiveId)
            .set(item.toMap());
      } catch (e) {
        debugPrint('createWishlistRewardItem firestore error: $e');
      }
    }
    return item;
  }

  /// Cập nhật Phúc lợi đổi sao thực tế (Edit Wishlist Reward Item)
  /// Chỉ Người giám hộ (`PARENT`, `GRANDPARENT`) mới có quyền chỉnh sửa
  Future<WishlistRewardItem> updateWishlistRewardItem({
    required String familyId,
    required String itemId,
    required String editorId,
    required String editorName,
    required String editorRole,
    bool? isGuardian,
    String? title,
    String? description,
    int? starCost,
    String? iconEmoji,
  }) async {
    final effectiveGuardian = isGuardian ??
        (editorRole.toUpperCase() == 'PARENT' ||
            editorRole.toUpperCase() == 'GRANDPARENT');
    if (!effectiveGuardian) {
      throw StateError(
        'ANTI_EXPLOIT_GUARDIAN_REQUIRED: Chỉ Phụ huynh / Người giám hộ mới có quyền chỉnh sửa phúc lợi thực tế!',
      );
    }

    var existing = wishlistCatalog[itemId];
    if (existing == null && _firestore != null) {
      try {
        final doc = await _firestore!
            .collection('families')
            .doc(familyId)
            .collection('wishlist_rewards')
            .doc(itemId)
            .get();
        if (doc.exists && doc.data() != null) {
          existing = WishlistRewardItem.fromMap(doc.id, doc.data()!);
          wishlistCatalog[itemId] = existing;
        }
      } catch (e) {
        debugPrint('find wishlist item on firestore error: $e');
      }
    }
    if (existing == null) {
      throw StateError('Không tìm thấy phúc lợi cần chỉnh sửa ($itemId)!');
    }

    if (starCost != null && starCost <= 0) {
      throw ArgumentError('Số sao đổi thưởng phải lớn hơn 0!');
    }

    final updated = existing.copyWith(
      title: title != null && title.trim().isNotEmpty ? title.trim() : existing.title,
      description: description != null ? description.trim() : existing.description,
      starCost: starCost ?? existing.starCost,
      iconEmoji: iconEmoji ?? existing.iconEmoji,
    );

    wishlistCatalog[itemId] = updated;

    if (_firestore != null) {
      try {
        await _firestore!
            .collection('families')
            .doc(familyId)
            .collection('wishlist_rewards')
            .doc(itemId)
            .update(updated.toMap());
      } catch (e) {
        debugPrint('updateWishlistRewardItem firestore error: $e');
      }
    }
    return updated;
  }

  /// Xóa Phúc lợi đổi sao thực tế (Remove / Delete Wishlist Reward Item)
  /// Chỉ Người giám hộ (`PARENT`, `GRANDPARENT`) mới có quyền xóa
  Future<void> removeWishlistRewardItem({
    required String familyId,
    required String itemId,
    required String removerId,
    required String removerName,
    required String removerRole,
    bool? isGuardian,
  }) async {
    final effectiveGuardian = isGuardian ??
        (removerRole.toUpperCase() == 'PARENT' ||
            removerRole.toUpperCase() == 'GRANDPARENT');
    if (!effectiveGuardian) {
      throw StateError(
        'ANTI_EXPLOIT_GUARDIAN_REQUIRED: Chỉ Phụ huynh / Người giám hộ mới có quyền xóa phúc lợi thực tế!',
      );
    }

    wishlistCatalog.remove(itemId);

    // Tự động từ chối và hoàn 100% sao cho các yêu cầu đang PENDING của vật phẩm này
    final pendingClaims = wishlistClaims.values
        .where((c) =>
            c.itemId == itemId &&
            c.status == WishlistClaimStatus.pending &&
            c.familyId == familyId)
        .toList();

    for (final claim in pendingClaims) {
      await refundWishlistClaim(
        claimId: claim.id,
        familyId: familyId,
        userId: claim.childId,
        refundStars: claim.starCost,
        reason: 'REWARD_ITEM_REMOVED',
        approvedBy: removerId,
      );
      wishlistClaims[claim.id] = claim.copyWith(
        status: WishlistClaimStatus.rejected,
        reviewedBy: removerId,
        reviewedByName: removerName,
        reviewedAt: DateTime.now(),
        rejectReason: 'Vật phẩm đã bị xóa khỏi cửa hàng',
      );
    }

    if (_firestore != null) {
      try {
        await _firestore!
            .collection('families')
            .doc(familyId)
            .collection('wishlist_rewards')
            .doc(itemId)
            .delete();
      } catch (e) {
        debugPrint('removeWishlistRewardItem firestore error: $e');
      }
    }
  }

  /// Con cái nhấn Đổi Quà (Redeem): Trừ sao ngay lập tức, tạo bản ghi `PENDING` và bắn thông báo cho Phụ huynh
  Future<WishlistClaimRecord> submitWishlistRedemption({
    required String familyId,
    required String childId,
    required String childName,
    required WishlistRewardItem item,
    int? expectedPrice,
    String? claimId,
  }) async {
    final currentInCatalog = wishlistCatalog[item.id];
    final serverPrice = currentInCatalog?.starCost ?? item.starCost;
    if (expectedPrice != null && expectedPrice != serverPrice) {
      throw StateError(
        'ITEM_PRICE_CHANGED: Giá của vật phẩm đã được cập nhật thành $serverPrice ⭐. Vui lòng thử lại với giá mới.',
      );
    }
    if (currentInCatalog != null && currentInCatalog.starCost != item.starCost) {
      throw StateError(
        'ITEM_PRICE_CHANGED: Giá của vật phẩm đã được cập nhật thành ${currentInCatalog.starCost} ⭐. Vui lòng thử lại với giá mới.',
      );
    }

    if (claimId != null &&
        (starLedger.containsKey('claim_$claimId') ||
            wishlistClaims.containsKey(claimId))) {
      throw StateError('Yêu cầu đổi quà claim_$claimId đã được xử lý!');
    }

    final hasPendingClaim = wishlistClaims.values.any((c) =>
        c.itemId == item.id &&
        c.status == WishlistClaimStatus.pending &&
        c.familyId == familyId);
    if (hasPendingClaim) {
      throw StateError(
        'REWARD_ALREADY_CLAIMED: Phần thưởng "${item.title}" đang có người đổi và chờ duyệt. Vui lòng chọn phần thưởng khác!',
      );
    }

    if (currentInCatalog != null && !currentInCatalog.isActive) {
      throw StateError(
        'REWARD_ALREADY_CLAIMED: Phần thưởng "${item.title}" đã được đổi hoặc không còn khả dụng.',
      );
    }

    if (childId.isNotEmpty && childId == item.createdBy) {
      throw StateError(
        'ANTI_EXPLOIT_CREATOR_CANNOT_REDEEM: Người tạo phúc lợi không được tự đổi vật phẩm do chính mình thiết lập.',
      );
    }

    if (_firestore != null) {
      try {
        final rewardRef = _firestore!
            .collection('families')
            .doc(familyId)
            .collection('wishlist_rewards')
            .doc(item.id);
        final rewardSnap = await rewardRef.get();
        if (rewardSnap.exists) {
          final data = rewardSnap.data() ?? {};
          final isActive = data['isActive'] ?? data['is_active'] ?? true;
          if (isActive == false) {
            throw StateError(
              'REWARD_ALREADY_CLAIMED: Phần thưởng "${item.title}" đã được người khác đổi trước bạn.',
            );
          }
        }
      } catch (e) {
        if (e is StateError) rethrow;
      }
    }

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

    // 1b. Khóa/Ẩn phần thưởng để tránh 2 người cùng đổi cùng một lúc
    if (wishlistCatalog.containsKey(item.id)) {
      wishlistCatalog[item.id] = wishlistCatalog[item.id]!.copyWith(isActive: false);
    }
    if (_firestore != null) {
      try {
        await _firestore!
            .collection('families')
            .doc(familyId)
            .collection('wishlist_rewards')
            .doc(item.id)
            .update({
          'isActive': false,
          'is_active': false,
          'claimedBy': childId,
          'claimedByName': childName,
          'claimedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('submitWishlistRedemption deactivate reward error: $e');
      }
    }

    // 2. Lưu trạng thái yêu cầu đổi quà PENDING (Chưa cộng 10% vào Hũ cho tới khi Phụ huynh duyệt)
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

        await _firestore!
            .collection('families')
            .doc(existing.familyId)
            .collection('wishlist_rewards')
            .doc(existing.itemId)
            .delete();
      } catch (e) {
        debugPrint('approveWishlistRedemption error: $e');
      }
    }

    wishlistCatalog.remove(existing.itemId);

    // Tích điểm 10% tổng số sao đổi phúc lợi vào Hũ Niềm Vui Gia Đình (CHỈ CỘNG KHI PHỤ HUYNH CHẤP NHẬN)
    // Quy tắc: Nếu phần lẻ >= 0.5 thì làm tròn lên (ceil), dưới 0.5 thì làm tròn xuống (floor)
    // Nếu quà có giá trị (> 0) mà làm tròn ra 0 thì luôn làm tròn lên tối thiểu 1 ⭐
    final double rawCashback = existing.starCost * 0.1;
    final double remainder = rawCashback - rawCashback.floor();
    int roundedCashback;
    if (remainder >= 0.5) {
      roundedCashback = rawCashback.ceil();
    } else {
      roundedCashback = rawCashback.floor();
    }
    final effectiveCashback =
        roundedCashback > 0 ? roundedCashback : (existing.starCost > 0 ? 1 : 0);

    final rawStr = (rawCashback == rawCashback.toInt())
        ? rawCashback.toInt().toString()
        : rawCashback.toStringAsFixed(1);
    final cashbackNote =
        'Tích điểm 10% đổi phúc lợi (${existing.itemName}): Gốc $rawStr ⭐ -> Làm tròn: +$effectiveCashback ⭐ (Phụ huynh $guardianName duyệt)';

    if (effectiveCashback > 0) {
      unawaited(
        FamilyJackpotService.instance.contributeStars(
          stars: effectiveCashback,
          familyId: existing.familyId,
          memberId: existing.childId,
          memberName: existing.childName,
          sourceTaskId: 'cashback_${existing.id}',
          rawStars: rawCashback,
          note: cashbackNote,
        ),
      );
    }

    unawaited(
      NotificationService.instance.addNotification(
        familyId: existing.familyId,
        targetUserId: existing.childId,
        title: '🎉 Bố/Mẹ đã duyệt quà "${existing.itemName}"!',
        titleEn: '🎉 Your reward "${existing.itemName}" was approved!',
        body:
            '$guardianName đã đồng ý trao phần thưởng "${existing.itemName}" cho ${existing.childName}! ${effectiveCashback > 0 ? "+$effectiveCashback ⭐ đã tích lũy vào Heo Đất Gia Đình!" : ""}',
        bodyEn:
            '$guardianName approved your reward "${existing.itemName}"! ${effectiveCashback > 0 ? "+$effectiveCashback ⭐ added to Family Piggy Bank!" : ""}',
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
      approvedBy: guardianId,
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

        await _firestore!
            .collection('families')
            .doc(existing.familyId)
            .collection('wishlist_rewards')
            .doc(existing.itemId)
            .update({
          'isActive': true,
          'is_active': true,
          'claimedBy': FieldValue.delete(),
          'claimedByName': FieldValue.delete(),
          'claimedAt': FieldValue.delete(),
        });
      } catch (e) {
        debugPrint('rejectWishlistRedemption error: $e');
      }
    }

    if (wishlistCatalog.containsKey(existing.itemId)) {
      wishlistCatalog[existing.itemId] =
          wishlistCatalog[existing.itemId]!.copyWith(isActive: true);
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

    final bool isTaskCreator =
        resolvedCreatorId.isNotEmpty && resolvedCreatorId == reviewerId;
    if (!effectiveIsGuardian && !isTaskCreator) {
      throw StateError(
        'ANTI_EXPLOIT_GUARDIAN_REQUIRED: Chỉ Người giám hộ (Bố Mẹ, Ông Bà) hoặc Người giao việc mới có quyền duyệt việc và thưởng sao.',
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
    String? approvedBy,
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
      'approvedBy': approvedBy ?? 'system',
      'createdAt': DateTime.now(),
    };
  }
}

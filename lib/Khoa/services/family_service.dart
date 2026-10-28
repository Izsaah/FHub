import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/family.dart';
import '../models/family_member.dart';

enum LeaveFamilyResult { memberLeft, familyDeleted }

/// Firestore schema used by the Khoa module:
/// families/{familyId}
/// family_members/{familyId}_{uid}
/// A membership document is unique per user and family.
class FamilyService {
  FamilyService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Random _random = Random.secure();

  CollectionReference<Map<String, dynamic>> get _families =>
      _firestore.collection('families');
  CollectionReference<Map<String, dynamic>> get _members =>
      _firestore.collection('family_members');

  String get currentUserId {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Chưa đăng nhập. Vui lòng đăng nhập lại.');
    return user.uid;
  }

  String _membershipId(String familyId, String uid) => '${familyId}_$uid';

  String _generateJoinCode() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const digits = '0123456789';
    return '${List.generate(4, (_) => letters[_random.nextInt(letters.length)]).join()}-'
        '${List.generate(4, (_) => digits[_random.nextInt(digits.length)]).join()}';
  }

  Future<String> _generateUniqueJoinCode() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final code = _generateJoinCode();
      final existing = await _families.where('joinCode', isEqualTo: code).limit(1).get();
      if (existing.docs.isEmpty) return code;
    }
    throw Exception('Không thể tạo mã gia đình duy nhất. Vui lòng thử lại.');
  }

  Future<Family> createFamily({
    required String name,
    String role = FamilyMember.roleParent,
  }) async {
    final uid = currentUserId;
    final trimmedName = name.trim();
    if (trimmedName.length < 3) throw Exception('Tên gia đình cần ít nhất 3 ký tự.');
    _validateRole(role);

    try {
      final joinCode = await _generateUniqueJoinCode();
      final familyRef = _families.doc();
      final memberRef = _members.doc(_membershipId(familyRef.id, uid));
      final batch = _firestore.batch();

      batch.set(familyRef, {
        'name': trimmedName,
        'joinCode': joinCode,
        'ownerId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(memberRef, {
        'familyId': familyRef.id,
        'userId': uid,
        'role': role,
        'isOwner': true,
        'status': FamilyMember.statusActive,
        'joinedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'lastCheckInAt': null,
        'lastCheckInDate': null,
      });
      await batch.commit();
      return Family(
        id: familyRef.id,
        name: trimmedName,
        joinCode: joinCode,
        ownerId: uid,
        createdAt: DateTime.now(),
      );
    } on FirebaseException catch (e) {
      throw Exception(_friendlyFirebaseError(e, 'Không thể tạo gia đình.'));
    }
  }

  Future<Family?> findFamilyByJoinCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    try {
      final result = await _families.where('joinCode', isEqualTo: normalized).limit(1).get();
      if (result.docs.isEmpty) return null;
      final doc = result.docs.first;
      return Family.fromMap(doc.data(), documentId: doc.id);
    } on FirebaseException catch (e) {
      throw Exception(_friendlyFirebaseError(e, 'Không thể tìm gia đình.'));
    }
  }

  Future<bool> isMemberOfFamily(String familyId) async {
    final snapshot = await _members.doc(_membershipId(familyId, currentUserId)).get();
    return snapshot.exists;
  }

  Future<Family> joinFamily({
    required String joinCode,
    required String role,
  }) async {
    final uid = currentUserId;
    final normalized = joinCode.trim().toUpperCase();
    if (normalized.isEmpty) throw Exception('Vui lòng nhập mã gia đình.');
    _validateRole(role);

    final family = await findFamilyByJoinCode(normalized);
    if (family == null) throw Exception('Không tìm thấy gia đình với mã "$normalized".');

    final memberRef = _members.doc(_membershipId(family.id, uid));
    try {
      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(memberRef);
        if (existing.exists) {
          final data = existing.data() ?? <String, dynamic>{};
          if ((data['status'] as String? ?? FamilyMember.statusActive) == FamilyMember.statusActive) {
            throw Exception('Bạn đã là thành viên của gia đình này.');
          }
          // A deactivated/memorialized membership is not silently reactivated.
          throw Exception('Tài khoản của bạn đã có trạng thái thành viên trong gia đình này. Hãy liên hệ Owner.');
        }

        // Kiểm tra giới hạn thành viên theo gói cước Free (4 người) vs Premium (10 người)
        final familyDoc = await transaction.get(_families.doc(family.id));
        if (!familyDoc.exists) {
          throw Exception('Gia đình này không còn tồn tại.');
        }
        final famData = familyDoc.data() ?? <String, dynamic>{};
        if (famData['deleting'] == true) {
          throw Exception('Gia đình này đang được đóng và không thể tham gia.');
        }
        final bool isPrem = famData['isPremium'] as bool? ?? false;
        final int maxMem = famData['maxMembers'] as int? ?? (isPrem ? 10 : 4);

        final membersQuery = await _members
            .where('familyId', isEqualTo: family.id)
            .where('status', isEqualTo: FamilyMember.statusActive)
            .get();
        if (membersQuery.docs.length >= maxMem) {
          if (!isPrem) {
            throw Exception(
              'Gia đình đã đạt tối đa 4 thành viên (Gói Cơ Bản). Vui lòng nâng cấp lên Family Hub Premium để mời thêm tối đa 10 người!',
            );
          } else {
            throw Exception('Gia đình đã đạt tối đa 10 thành viên của gói Premium.');
          }
        }

        transaction.set(memberRef, {
          'familyId': family.id,
          'userId': uid,
          'role': role,
          'isOwner': false,
          'status': FamilyMember.statusActive,
          'joinedAt': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
          'lastCheckInAt': null,
          'lastCheckInDate': null,
        });
      });
      return family;
    } on FirebaseException catch (e) {
      throw Exception(_friendlyFirebaseError(e, 'Không thể tham gia gia đình.'));
    }
  }

  Future<List<Family>> getMyFamilies() async {
    final uid = currentUserId;
    try {
      final memberDocs = await _members.where('userId', isEqualTo: uid).get();
      final families = <Family>[];
      for (final memberDoc in memberDocs.docs) {
        final memberData = memberDoc.data();
        if ((memberData['status'] as String? ?? FamilyMember.statusActive) != FamilyMember.statusActive) continue;
        final familyId = memberData['familyId'] as String?;
        if (familyId == null || familyId.isEmpty) continue;
        final familyDoc = await _families.doc(familyId).get();
        if (familyDoc.exists && familyDoc.data() != null) {
          families.add(Family.fromMap(familyDoc.data()!, documentId: familyDoc.id));
        }
      }
      families.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return families;
    } on FirebaseException catch (e) {
      throw Exception(_friendlyFirebaseError(e, 'Không thể tải danh sách gia đình.'));
    }
  }

  Future<List<FamilyMember>> getFamilyMembers(String familyId) async {
    try {
      final result = await _members.where('familyId', isEqualTo: familyId).get();
      return result.docs.map((doc) => FamilyMember.fromMap(doc.data())).toList();
    } on FirebaseException catch (e) {
      throw Exception(_friendlyFirebaseError(e, 'Không thể tải thành viên gia đình.'));
    }
  }

  Future<FamilyMember?> getMyMembership(String familyId) async {
    final doc = await _members.doc(_membershipId(familyId, currentUserId)).get();
    if (!doc.exists || doc.data() == null) return null;
    return FamilyMember.fromMap(doc.data()!);
  }

  Future<Family?> getFamilyById(String familyId) async {
    try {
      final doc = await _families.doc(familyId).get();
      if (!doc.exists || doc.data() == null) return null;
      return Family.fromMap(doc.data()!, documentId: doc.id);
    } on FirebaseException catch (e) {
      throw Exception(_friendlyFirebaseError(e, 'Không thể tải thông tin gia đình.'));
    }
  }

  Future<LeaveFamilyResult> leaveFamily({
    required String familyId,
    required bool expectedOwner,
  }) async {
    final uid = currentUserId;
    final familyRef = _families.doc(familyId);
    final myMemberRef = _members.doc(_membershipId(familyId, uid));
    final userRef = _firestore.collection('users').doc(uid);

    try {
      final isOwner = await _firestore.runTransaction((transaction) async {
        final familySnapshot = await transaction.get(familyRef);
        final myMemberSnapshot = await transaction.get(myMemberRef);

        if (!familySnapshot.exists || !myMemberSnapshot.exists) {
          throw Exception('Bạn không còn là thành viên của gia đình này.');
        }

        final familyData = familySnapshot.data()!;
        final memberData = myMemberSnapshot.data()!;
        final status =
            memberData['status'] as String? ?? FamilyMember.statusActive;
        if (status != FamilyMember.statusActive) {
          throw Exception('Bạn không còn là thành viên đang hoạt động của gia đình này.');
        }

        final ownerId = familyData['ownerId']?.toString();
        final memberIsOwner = (memberData['isOwner'] as bool?) == true;
        if (memberIsOwner &&
            ownerId != null &&
            ownerId.isNotEmpty &&
            ownerId != uid) {
          throw Exception(
            'Thông tin Owner không đồng nhất. Vui lòng tải lại trang và thử lại.',
          );
        }
        final isOwner =
            ownerId == uid ||
            ((ownerId == null || ownerId.isEmpty) && memberIsOwner);
        if (isOwner != expectedOwner) {
          throw Exception(
            'Quyền sở hữu gia đình đã thay đổi. Vui lòng tải lại trang và thử lại.',
          );
        }

        final userSnapshot = await transaction.get(userRef);
        if (isOwner) {
          transaction.update(familyRef, {
            'deleting': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.delete(myMemberRef);
          _clearFamilyPointer(transaction, userRef, userSnapshot, familyId);
        }

        return isOwner;
      });

      if (isOwner) {
        await _deleteFamilyAndMemberships(
          familyId: familyId,
          familyRef: familyRef,
          ownerMembershipRef: myMemberRef,
        );
        return LeaveFamilyResult.familyDeleted;
      }
      return LeaveFamilyResult.memberLeft;
    } on FirebaseException catch (e) {
      throw Exception(_friendlyFirebaseError(e, 'Không thể rời gia đình.'));
    }
  }

  Future<void> _deleteFamilyAndMemberships({
    required String familyId,
    required DocumentReference<Map<String, dynamic>> familyRef,
    required DocumentReference<Map<String, dynamic>> ownerMembershipRef,
  }) async {
    final members = await _members.where('familyId', isEqualTo: familyId).get();
    final otherMemberships = members.docs
        .where((member) => member.reference.id != ownerMembershipRef.id)
        .toList();

    for (final member in members.docs) {
      final userId =
          (member.data()['userId'] ?? member.data()['user_id'])?.toString();
      if (userId == null || userId.isEmpty) continue;
      await _firestore.runTransaction((transaction) async {
        final userRef = _firestore.collection('users').doc(userId);
        final userSnapshot = await transaction.get(userRef);
        _clearFamilyPointer(transaction, userRef, userSnapshot, familyId);
      });
    }

    const batchSize = 450;
    for (var start = 0; start < otherMemberships.length; start += batchSize) {
      final end = start + batchSize < otherMemberships.length
          ? start + batchSize
          : otherMemberships.length;
      final batch = _firestore.batch();
      for (final member in otherMemberships.sublist(start, end)) {
        batch.delete(member.reference);
      }
      await batch.commit();
    }

    final finalBatch = _firestore.batch();
    finalBatch.delete(ownerMembershipRef);
    finalBatch.delete(familyRef);
    await finalBatch.commit();
  }

  void _clearFamilyPointer(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> userRef,
    DocumentSnapshot<Map<String, dynamic>> userSnapshot,
    String familyId,
  ) {
    if (!userSnapshot.exists) return;
    final data = userSnapshot.data()!;
    final update = <String, dynamic>{};
    if (data['familyId'] == familyId) {
      update['familyId'] = FieldValue.delete();
    }
    if (data['family_id'] == familyId) {
      update['family_id'] = FieldValue.delete();
    }
    if (update.isNotEmpty) transaction.update(userRef, update);
  }

  /// Owner can deactivate or memorialize a member. Historical data is not deleted.
  Future<void> updateMemberStatus({required String familyId, required String userId, required String status}) async {
    if (![FamilyMember.statusActive, FamilyMember.statusDeactivated, FamilyMember.statusMemorialized].contains(status)) {
      throw Exception('Trạng thái thành viên không hợp lệ.');
    }
    await _requireOwner(familyId);
    final ref = _members.doc(_membershipId(familyId, userId));
    final doc = await ref.get();
    if (!doc.exists) throw Exception('Không tìm thấy thành viên.');
    if ((doc.data()?['isOwner'] as bool? ?? false) && status != FamilyMember.statusActive) {
      throw Exception('Hãy chuyển quyền Owner trước khi thay đổi trạng thái của Owner hiện tại.');
    }
    await ref.update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Owner may transfer ownership to an active PARENT member.
  Future<void> transferOwnership({required String familyId, required String newOwnerUserId}) async {
    final uid = currentUserId;
    await _requireOwner(familyId);
    if (uid == newOwnerUserId) throw Exception('Bạn hiện đã là Owner của gia đình này.');
    final familyRef = _families.doc(familyId);
    final oldMemberRef = _members.doc(_membershipId(familyId, uid));
    final newMemberRef = _members.doc(_membershipId(familyId, newOwnerUserId));

    await _firestore.runTransaction((transaction) async {
      final familyDoc = await transaction.get(familyRef);
      final oldMember = await transaction.get(oldMemberRef);
      final newMember = await transaction.get(newMemberRef);
      if (!familyDoc.exists || !oldMember.exists || !newMember.exists) throw Exception('Không tìm thấy dữ liệu thành viên/gia đình.');
      final target = newMember.data()!;
      if (target['role'] != FamilyMember.roleParent || target['status'] != FamilyMember.statusActive) {
        throw Exception('Chỉ có thể chuyển quyền cho thành viên PARENT đang hoạt động.');
      }
      transaction.update(oldMemberRef, {'isOwner': false, 'updatedAt': FieldValue.serverTimestamp()});
      transaction.update(newMemberRef, {'isOwner': true, 'updatedAt': FieldValue.serverTimestamp()});
      transaction.update(familyRef, {'ownerId': newOwnerUserId, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  Future<void> updateMemberRole({required String familyId, required String userId, required String role}) async {
    _validateRole(role);
    await _requireOwner(familyId);
    final ref = _members.doc(_membershipId(familyId, userId));
    final snapshot = await ref.get();
    if (!snapshot.exists) throw Exception('Không tìm thấy thành viên.');
    if ((snapshot.data()?['isOwner'] as bool? ?? false) && role != FamilyMember.roleParent) {
      // Owner may have any hierarchy role, so this is allowed; ownership remains separate.
    }
    await ref.update({'role': role, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Creates a takeover request only when the current Owner is deactivated or
  /// has not been active for more than 30 days. This does not grant ownership
  /// until the required adult members approve it.
  Future<String> requestOwnershipTakeover({required String familyId}) async {
    final requesterId = currentUserId;
    final requester = await getMyMembership(familyId);
    if (requester == null || !requester.isActive || requester.role != FamilyMember.roleParent || requester.isOwner) {
      throw Exception('Chỉ thành viên PARENT đang hoạt động mới có thể yêu cầu tiếp quản.');
    }
    final family = await getFamilyById(familyId);
    if (family == null) throw Exception('Không tìm thấy gia đình.');
    final ownerMembership = await _members.doc(_membershipId(familyId, family.ownerId)).get();
    if (!ownerMembership.exists) throw Exception('Không tìm thấy thông tin Owner hiện tại.');
    final ownerData = ownerMembership.data()!;
    final ownerStatus = ownerData['status'] as String? ?? FamilyMember.statusActive;
    final lastActive = _dateTimeFrom(ownerData['lastActiveAt']);
    final inactiveFor30Days = lastActive == null || DateTime.now().difference(lastActive) > const Duration(days: 30);
    if (ownerStatus == FamilyMember.statusActive && !inactiveFor30Days) {
      throw Exception('Owner chưa bị tạm ngưng và chưa vắng mặt quá 30 ngày.');
    }

    final requestRef = _families.doc(familyId).collection('ownershipRequests').doc(requesterId);
    final members = await getFamilyMembers(familyId);
    final activeAdults = members.where((m) => m.isActive &&
        [FamilyMember.roleParent, FamilyMember.roleGrandparent].contains(m.role)).toList();

    // If the requester is the only active adult left, approve succession immediately.
    if (activeAdults.length == 1 && activeAdults.single.userId == requesterId) {
      final familyRef = _families.doc(familyId);
      final oldOwnerRef = _members.doc(_membershipId(familyId, family.ownerId));
      final newOwnerRef = _members.doc(_membershipId(familyId, requesterId));
      await _firestore.runTransaction((transaction) async {
        final familySnapshot = await transaction.get(familyRef);
        final newOwnerSnapshot = await transaction.get(newOwnerRef);
        if (!familySnapshot.exists || !newOwnerSnapshot.exists) throw Exception('Không tìm thấy dữ liệu tiếp quản.');
        transaction.set(oldOwnerRef, {'isOwner': false, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        transaction.update(newOwnerRef, {'isOwner': true, 'updatedAt': FieldValue.serverTimestamp()});
        transaction.update(familyRef, {'ownerId': requesterId, 'updatedAt': FieldValue.serverTimestamp()});
        transaction.set(requestRef, {
          'familyId': familyId,
          'requesterId': requesterId,
          'currentOwnerId': family.ownerId,
          'status': 'APPROVED',
          'approvals': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
          'approvedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      return requestRef.id;
    }

    await requestRef.set({
      'familyId': familyId,
      'requesterId': requesterId,
      'currentOwnerId': family.ownerId,
      'status': 'PENDING',
      'approvals': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return requestRef.id;
  }

  /// An active adult (PARENT/GRANDPARENT) can approve a pending takeover.
  /// More than half of eligible active adults other than the requester must
  /// approve. If the requester is the only eligible adult, approval is automatic.
  Future<void> approveOwnershipTakeover({required String familyId, required String requesterId}) async {
    final approverId = currentUserId;
    final approver = await getMyMembership(familyId);
    if (approver == null || !approver.isActive ||
        ![FamilyMember.roleParent, FamilyMember.roleGrandparent].contains(approver.role)) {
      throw Exception('Chỉ thành viên người lớn đang hoạt động mới được xác nhận.');
    }
    if (approverId == requesterId) throw Exception('Người yêu cầu không thể tự xác nhận yêu cầu của mình.');

    final familyRef = _families.doc(familyId);
    final requestRef = familyRef.collection('ownershipRequests').doc(requesterId);
    final members = await getFamilyMembers(familyId);
    final activeAdults = members.where((m) => m.isActive &&
        [FamilyMember.roleParent, FamilyMember.roleGrandparent].contains(m.role)).toList();
    final requester = activeAdults.where((m) => m.userId == requesterId).toList();
    if (requester.isEmpty || requester.single.isOwner) throw Exception('Người yêu cầu không còn đủ điều kiện tiếp quản.');
    if (!activeAdults.any((m) => m.userId == approverId)) throw Exception('Bạn không thuộc nhóm người lớn đủ điều kiện xác nhận.');

    await _firestore.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestRef);
      final familySnapshot = await transaction.get(familyRef);
      if (!requestSnapshot.exists || !familySnapshot.exists) throw Exception('Không tìm thấy yêu cầu tiếp quản.');
      final request = requestSnapshot.data()!;
      if ((request['status'] as String? ?? '') != 'PENDING') throw Exception('Yêu cầu này không còn ở trạng thái chờ.');
      final approvals = List<String>.from(request['approvals'] as List? ?? const <String>[]);
      if (!approvals.contains(approverId)) approvals.add(approverId);
      final eligibleApproversCount = activeAdults.where((m) => m.userId != requesterId).length;
      final requiredApprovals = eligibleApproversCount == 0
          ? 0
          : (eligibleApproversCount ~/ 2) + 1;

      if (eligibleApproversCount == 0 || approvals.length >= requiredApprovals) {
        final newOwnerRef = _members.doc(_membershipId(familyId, requesterId));
        final oldOwnerId = familySnapshot.data()!['ownerId'] as String;
        final oldOwnerRef = _members.doc(_membershipId(familyId, oldOwnerId));
        final newOwnerSnapshot = await transaction.get(newOwnerRef);
        if (!newOwnerSnapshot.exists) throw Exception('Không tìm thấy thành viên tiếp quản.');
        transaction.set(oldOwnerRef, {'isOwner': false, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        transaction.update(newOwnerRef, {'isOwner': true, 'updatedAt': FieldValue.serverTimestamp()});
        transaction.update(familyRef, {'ownerId': requesterId, 'updatedAt': FieldValue.serverTimestamp()});
        transaction.update(requestRef, {
          'approvals': approvals,
          'status': 'APPROVED',
          'approvedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.update(requestRef, {'approvals': approvals, 'updatedAt': FieldValue.serverTimestamp()});
      }
    });
  }

  Future<void> updateLastActiveAt({String? familyId}) async {
    final uid = currentUserId;
    final List<Family> families;

    if (familyId == null) {
      families = await getMyFamilies();
    } else {
      final family = await getFamilyById(familyId);
      families = family == null ? <Family>[] : <Family>[family];
    }

    final batch = _firestore.batch();
    for (final family in families) {
      batch.set(_members.doc(_membershipId(family.id, uid)), {
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (families.isNotEmpty) await batch.commit();
  }

  Future<void> _requireOwner(String familyId) async {
    final membership = await getMyMembership(familyId);
    if (membership == null || !membership.isOwner || !membership.isActive) {
      throw Exception('Bạn không có quyền thực hiện thao tác này.');
    }
  }

  void _validateRole(String role) {
    if (![FamilyMember.roleGrandparent, FamilyMember.roleParent, FamilyMember.roleChild].contains(role)) {
      throw Exception('Vui lòng chọn vai vế hợp lệ.');
    }
  }

  DateTime? _dateTimeFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _friendlyFirebaseError(FirebaseException error, String fallback) {
    switch (error.code) {
      case 'permission-denied': return 'Bạn không có quyền truy cập dữ liệu này. Kiểm tra Firestore Security Rules.';
      case 'unavailable': return 'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng và thử lại.';
      case ' unauthenticated':
      case 'unauthenticated': return 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.';
      default: return error.message?.isNotEmpty == true ? error.message! : fallback;
    }
  }
}

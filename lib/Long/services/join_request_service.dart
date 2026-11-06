import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/join_request_model.dart';
import '../models/family_model.dart';

class JoinRequestService {
  static final JoinRequestService _instance = JoinRequestService._internal();
  factory JoinRequestService({FirebaseFirestore? firestore, FirebaseAuth? auth}) {
    if (firestore != null || auth != null) {
      return JoinRequestService._custom(firestore, auth);
    }
    return _instance;
  }

  JoinRequestService._internal()
      : _customFirestore = null,
        _customAuth = null;

  JoinRequestService._custom(FirebaseFirestore? firestore, FirebaseAuth? auth)
      : _customFirestore = firestore,
        _customAuth = auth;

  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;

  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  // In-memory mock storage for testing when Firebase is unavailable
  static final Map<String, JoinRequestModel> _mockRequests = {};
  static final StreamController<List<JoinRequestModel>> _mockStreamCtrl =
      StreamController<List<JoinRequestModel>>.broadcast();

  static void resetMockData() {
    _mockRequests.clear();
    _mockStreamCtrl.add([]);
  }

  bool get _isFirebaseAvailable {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String get currentUserId {
    if (!_isFirebaseAvailable) return 'mock_user';
    try {
      return _auth.currentUser?.uid ?? 'mock_user';
    } catch (_) {
      return 'mock_user';
    }
  }

  /// 1. Gửi yêu cầu gia nhập (Handshake Initiate)
  Future<void> sendJoinRequest({
    required String familyId,
    required String suggestedRole,
  }) async {
    final uid = currentUserId;
    final userName = _isFirebaseAvailable
        ? (_auth.currentUser?.displayName ??
            (_auth.currentUser?.email?.split('@').first ?? 'Thành viên'))
        : 'Thành viên demo';
    final userEmail = _isFirebaseAvailable ? (_auth.currentUser?.email ?? '') : '';
    final userAvatar = _isFirebaseAvailable ? (_auth.currentUser?.photoURL ?? '') : '';
    final reqId = '${familyId}_$uid';

    if (!_isFirebaseAvailable) {
      final req = JoinRequestModel(
        id: reqId,
        familyId: familyId,
        userId: uid,
        userName: userName,
        userEmail: userEmail,
        userAvatarUrl: userAvatar,
        suggestedRole: suggestedRole.toUpperCase(),
        status: JoinRequestStatus.pending,
        createdAt: DateTime.now(),
      );
      _mockRequests[reqId] = req;
      _mockStreamCtrl.add(_mockRequests.values.toList());
      return;
    }

    // Kiểm tra đã là thành viên ACTIVE chưa
    final memberDoc = await _firestore.collection('family_members').doc(reqId).get();
    if (memberDoc.exists && (memberDoc.data()?['status'] ?? 'ACTIVE') == 'ACTIVE') {
      throw Exception('Bạn đã là thành viên của gia đình này.');
    }

    // Ghi document join_requests với composite ID
    await _firestore.collection('join_requests').doc(reqId).set({
      'id': reqId,
      'familyId': familyId,
      'userId': uid,
      'userName': userName,
      'userEmail': userEmail,
      'userAvatarUrl': userAvatar,
      'suggestedRole': suggestedRole.toUpperCase(),
      'status': JoinRequestStatus.pending,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 2. Lắng nghe Realtime các yêu cầu chờ duyệt theo familyId
  Stream<List<JoinRequestModel>> watchPendingRequests(String familyId) {
    if (!_isFirebaseAvailable) {
      final currentList = _mockRequests.values
          .where((r) => r.familyId == familyId && r.isPending)
          .toList();
      return Stream<List<JoinRequestModel>>.multi((controller) {
        controller.add(currentList);
        final sub = _mockStreamCtrl.stream.listen((list) {
          controller.add(
            list.where((r) => r.familyId == familyId && r.isPending).toList(),
          );
        });
        controller.onCancel = () => sub.cancel();
      });
    }

    return _firestore
        .collection('join_requests')
        .where('familyId', isEqualTo: familyId)
        .where('status', isEqualTo: JoinRequestStatus.pending)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => JoinRequestModel.fromFirestore(d)).toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  /// 3. Guardian Duyệt yêu cầu gia nhập
  Future<void> approveJoinRequest({
    required String requestId,
    required String assignedRole,
    required bool isKid,
  }) async {
    final reviewerId = currentUserId;
    final reviewerName = _isFirebaseAvailable
        ? (_auth.currentUser?.displayName ?? 'Guardian')
        : 'Guardian';

    if (!_isFirebaseAvailable) {
      final req = _mockRequests[requestId];
      if (req != null) {
        _mockRequests[requestId] = JoinRequestModel(
          id: req.id,
          familyId: req.familyId,
          userId: req.userId,
          userName: req.userName,
          userEmail: req.userEmail,
          userAvatarUrl: req.userAvatarUrl,
          suggestedRole: req.suggestedRole,
          status: JoinRequestStatus.approved,
          assignedRole: assignedRole.toUpperCase(),
          isKid: isKid,
          reviewedBy: reviewerId,
          reviewedByName: reviewerName,
          reviewedAt: DateTime.now(),
        );
        _mockStreamCtrl.add(_mockRequests.values.toList());
      }
      return;
    }

    final reqRef = _firestore.collection('join_requests').doc(requestId);

    await _firestore.runTransaction((tx) async {
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) {
        throw Exception('Yêu cầu gia nhập không tồn tại.');
      }
      final data = reqSnap.data()!;
      if (data['status'] != JoinRequestStatus.pending) {
        throw Exception('Yêu cầu này đã được xử lý trước đó.');
      }

      final familyId = data['familyId'] as String;
      final userId = data['userId'] as String;
      final memberDocId = '${familyId}_$userId';
      final memberRef = _firestore.collection('family_members').doc(memberDocId);

      // 1. Tạo bản ghi family_members với trạng thái ACTIVE và vai trò được gán
      tx.set(memberRef, {
        'familyId': familyId,
        'userId': userId,
        'role': 'MEMBER',
        'isOwner': false,
        'hierarchyRole': assignedRole.toUpperCase(),
        'status': 'ACTIVE',
        'isKid': isKid,
        'rewardStarsTotal': 0,
        'joinedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'lastCheckInAt': null,
        'lastCheckInDate': null,
      });

      // 2. Cập nhật join_requests sang APPROVED
      tx.update(reqRef, {
        'status': JoinRequestStatus.approved,
        'assignedRole': assignedRole.toUpperCase(),
        'isKid': isKid,
        'reviewedBy': reviewerId,
        'reviewedByName': reviewerName,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      // 3. Tăng số lượng thành viên trong gia đình
      final famRef = _firestore.collection('families').doc(familyId);
      tx.update(famRef, {'memberCount': FieldValue.increment(1)});
    });

    // 4. Đồng bộ familyIds vào users/{userId} (best-effort write; self-healed by applicant client if needed)
    try {
      final reqDoc = await reqRef.get();
      final targetUid = reqDoc.data()?['userId'] as String?;
      final targetFamId = reqDoc.data()?['familyId'] as String?;
      if (targetUid != null && targetFamId != null) {
        await _firestore.collection('users').doc(targetUid).set({
          'familyIds': FieldValue.arrayUnion([targetFamId]),
          'familyId': targetFamId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Note: users/{uid}.familyIds will self-heal upon user login: $e');
    }
  }

  /// 4. Guardian Từ chối yêu cầu gia nhập
  Future<void> rejectJoinRequest(String requestId) async {
    final reviewerId = currentUserId;
    final reviewerName = _isFirebaseAvailable
        ? (_auth.currentUser?.displayName ?? 'Guardian')
        : 'Guardian';

    if (!_isFirebaseAvailable) {
      final req = _mockRequests[requestId];
      if (req == null) {
        throw Exception('Yêu cầu gia nhập không tồn tại.');
      }
      if (!req.isPending) {
        throw Exception('Yêu cầu này đã được xử lý trước đó.');
      }
      _mockRequests[requestId] = JoinRequestModel(
        id: req.id,
        familyId: req.familyId,
        userId: req.userId,
        userName: req.userName,
        userEmail: req.userEmail,
        userAvatarUrl: req.userAvatarUrl,
        suggestedRole: req.suggestedRole,
        status: JoinRequestStatus.rejected,
        reviewedBy: reviewerId,
        reviewedByName: reviewerName,
        reviewedAt: DateTime.now(),
      );
      _mockStreamCtrl.add(_mockRequests.values.toList());
      return;
    }

    final reqRef = _firestore.collection('join_requests').doc(requestId);
    await _firestore.runTransaction((tx) async {
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) {
        throw Exception('Yêu cầu gia nhập không tồn tại.');
      }
      final data = reqSnap.data()!;
      if (data['status'] != JoinRequestStatus.pending) {
        throw Exception('Yêu cầu này đã được xử lý trước đó.');
      }

      tx.update(reqRef, {
        'status': JoinRequestStatus.rejected,
        'reviewedBy': reviewerId,
        'reviewedByName': reviewerName,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Helper: Tìm gia đình theo mã tham gia 6 ký tự
  Future<FamilyModel?> findFamilyByJoinCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    if (!_isFirebaseAvailable) return null;

    final snap = await _firestore
        .collection('families')
        .where('joinCode', isEqualTo: normalized)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return FamilyModel(
      id: doc.id,
      name: doc.data()['name']?.toString() ?? 'Gia đình',
      joinCode: normalized,
      ownerId: doc.data()['ownerId']?.toString() ?? '',
    );
  }
}

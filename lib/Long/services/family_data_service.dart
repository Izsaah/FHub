import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';
import '../models/hierarchy_role.dart';
import '../models/member_status.dart';
import '../models/check_in_feed_model.dart';
import '../models/check_in_reminder_model.dart';
import 'family_service_interface.dart';
import 'mock_data_service.dart';

/// Central data service bridging Firebase Auth & Firestore with Long's screens
/// (Home, Family, Profile, Reminders, and Jackpot).
/// Implements IFamilyService for full Module 2 & Module 3 support.
/// Automatically falls back to MockDataService when Firebase is not initialized (e.g. during unit tests).
class FamilyDataService implements IFamilyService {
  static final FamilyDataService _instance = FamilyDataService._internal();
  factory FamilyDataService() => _instance;
  FamilyDataService._internal();

  final MockDataService _mock = MockDataService();

  bool get _isFirebaseAvailable {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;

  String? _cachedFamilyId;
  String? _cachedFamilyIdUserId;
  List<FamilyModel>? _cachedFamilies;
  Future<List<FamilyModel>>? _inFlightFamiliesFuture;

  final ValueNotifier<String?> selectedFamilyIdNotifier =
      ValueNotifier<String?>(null);
  final ValueNotifier<int> membershipRevisionNotifier = ValueNotifier<int>(0);

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membershipSub;
  String? _watchedUid;
  String? _lastMembershipSignature;
  DateTime? _lastOwnerActiveUpdatedAt;
  String? _lastOwnerActiveKey;

  bool get hasActiveSelectedFamily =>
      selectedFamilyIdNotifier.value != null &&
      selectedFamilyIdNotifier.value!.isNotEmpty;

  String _computeMembershipSignature(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final parts = <String>[];
    for (final doc in docs) {
      final d = doc.data();
      final fid = (d['familyId'] ?? d['family_id'])?.toString() ?? '';
      if (fid.isEmpty) continue;
      final status = (d['status'] ?? 'ACTIVE').toString().toUpperCase();
      final role = (d['role'] ?? '').toString();
      final isOwner = (d['isOwner'] == true).toString();
      parts.add('$fid:$status:$role:$isOwner');
    }
    parts.sort();
    return parts.join('|');
  }

  /// Khởi tạo lắng nghe realtime trạng thái đăng nhập & danh sách family_members của user
  void ensureRealtimeSync() {
    if (!_isFirebaseAvailable || _authSub != null) return;
    try {
      _authSub = _firebaseAuth.authStateChanges().listen((user) {
        _bindMembershipStream(user?.uid);
      });
      _bindMembershipStream(_firebaseAuth.currentUser?.uid);
    } catch (e) {
      debugPrint('ensureRealtimeSync error: $e');
    }
  }

  void _bindMembershipStream(String? uid) {
    if (_watchedUid == uid && _membershipSub != null) return;
    _membershipSub?.cancel();
    _membershipSub = null;
    _watchedUid = uid;
    _lastMembershipSignature = null;

    if (uid == null || uid.isEmpty) {
      resetAll();
      return;
    }

    try {
      _membershipSub = _firestore
          .collection('family_members')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .listen(
        (snap) async {
          final sig = _computeMembershipSignature(snap.docs);
          // Bỏ qua các cập nhật không làm đổi tư cách thành viên (VD: lastActiveAt, lastCheckInAt)
          if (_lastMembershipSignature == sig) return;
          final isInitialSnapshot = _lastMembershipSignature == null;
          _lastMembershipSignature = sig;

          // Nếu là snapshot đầu tiên và cache đã khớp danh sách ACTIVE hiện tại thì không gây rebuild thừa
          if (isInitialSnapshot && _cachedFamilies != null) {
            final activeIds = snap.docs
                .where((d) =>
                    (d.data()['status'] ?? 'ACTIVE')
                        .toString()
                        .toUpperCase() ==
                    'ACTIVE')
                .map((d) =>
                    (d.data()['familyId'] ?? d.data()['family_id'])
                        ?.toString() ??
                    '')
                .where((id) => id.isNotEmpty)
                .toSet();
            final cachedIds = _cachedFamilies!.map((f) => f.id).toSet();
            if (activeIds.length == cachedIds.length &&
                activeIds.containsAll(cachedIds)) {
              return;
            }
          }

          await getMyFamilies(forceRefresh: true);
          membershipRevisionNotifier.value++;
        },
        onError: (e) {
          debugPrint('FamilyDataService membership stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('Bind membership stream error: $e');
    }
  }

  void clearCache() {
    _cachedFamilies = null;
    _inFlightFamiliesFuture = null;
  }

  void resetAll() {
    final hadState = _cachedFamilyId != null ||
        (_cachedFamilies != null && _cachedFamilies!.isNotEmpty) ||
        selectedFamilyIdNotifier.value != null;
    _cachedFamilyId = null;
    _cachedFamilyIdUserId = null;
    _cachedFamilies = null;
    _inFlightFamiliesFuture = null;
    _lastMembershipSignature = null;
    if (selectedFamilyIdNotifier.value != null) {
      selectedFamilyIdNotifier.value = null;
    }
    if (hadState) {
      membershipRevisionNotifier.value++;
    }
  }

  @override
  String get currentUserId {
    if (!_isFirebaseAvailable) return _mock.currentUserId;
    try {
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser != null) return fbUser.uid;
    } catch (_) {}
    return _mock.currentUserId;
  }

  bool get _isAuthenticated {
    if (!_isFirebaseAvailable) return false;
    try {
      return _firebaseAuth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Multi-Family Management
  // ---------------------------------------------------------------------------

  @override
  Future<List<FamilyModel>> getMyFamilies({bool forceRefresh = false}) async {
    if (!_isFirebaseAvailable || !_isAuthenticated) {
      return _mock.getMyFamilies();
    }

    ensureRealtimeSync();

    final uid = currentUserId;
    if (uid.isEmpty) return <FamilyModel>[];

    if (!forceRefresh &&
        _cachedFamilies != null &&
        _cachedFamilyIdUserId == uid) {
      return _cachedFamilies!;
    }

    if (!forceRefresh && _inFlightFamiliesFuture != null) {
      return _inFlightFamiliesFuture!;
    }

    final future = _fetchMyFamiliesInternal(uid);
    _inFlightFamiliesFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightFamiliesFuture, future)) {
        _inFlightFamiliesFuture = null;
      }
    }
  }

  Future<List<FamilyModel>> _fetchMyFamiliesInternal(String uid) async {
    final List<FamilyModel> resolved = [];
    final Set<String> familyIds = {};

    try {
      // Chỉ chấp nhận tư cách thành viên đang ACTIVE thực tế trong family_members
      final memberDocs = await _firestore
          .collection('family_members')
          .where('userId', isEqualTo: uid)
          .get()
          .timeout(const Duration(seconds: 4));

      for (final doc in memberDocs.docs) {
        final data = doc.data();
        final status = (data['status'] ?? 'ACTIVE').toString().toUpperCase();
        if (status != 'ACTIVE') continue;
        final fid = (data['familyId'] ?? data['family_id'])?.toString();
        if (fid != null && fid.isNotEmpty) {
          familyIds.add(fid);
        }
      }

      for (final fid in familyIds) {
        try {
          final famDoc = await _firestore
              .collection('families')
              .doc(fid)
              .get()
              .timeout(const Duration(seconds: 3));
          if (famDoc.exists && famDoc.data() != null) {
            final data = famDoc.data()!;
            if (data['deleting'] == true) continue;
            resolved.add(
              FamilyModel(
                id: famDoc.id,
                name: data['name']?.toString() ?? 'Gia đình',
                joinCode:
                    (data['joinCode'] ?? data['join_code'])?.toString() ?? '',
                ownerId:
                    (data['ownerId'] ?? data['owner_id'])?.toString() ?? '',
              ),
            );
          }
        } catch (_) {}
      }

      resolved.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      _cachedFamilies = resolved;
      _cachedFamilyIdUserId = uid;

      if (resolved.isEmpty) {
        _cachedFamilyId = null;
        // Tự động xóa con trỏ familyId cũ bị treo trong users/{uid} nếu user đã rời hết gia đình
        _firestore.collection('users').doc(uid).update({
          'familyId': FieldValue.delete(),
          'family_id': FieldValue.delete(),
        }).catchError((_) {});
      } else if (_cachedFamilyId == null ||
          !resolved.any((f) => f.id == _cachedFamilyId)) {
        _cachedFamilyId = resolved.first.id;
      }
      if (selectedFamilyIdNotifier.value != _cachedFamilyId) {
        selectedFamilyIdNotifier.value = _cachedFamilyId;
      }

      return resolved;
    } catch (e) {
      debugPrint('getMyFamilies error: $e');
      return _cachedFamilies ?? <FamilyModel>[];
    }
  }

  Future<void> selectFamily(String familyId) async {
    if (familyId.isEmpty) return;
    _cachedFamilyId = familyId;
    _cachedFamilyIdUserId = currentUserId;
    selectedFamilyIdNotifier.value = familyId;

    if (_isAuthenticated && currentUserId.isNotEmpty) {
      try {
        await _firestore.collection('users').doc(currentUserId).set({
          'familyId': familyId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Persist selected family error: $e');
      }
    }
  }

  @override
  Future<void> switchFamily(String familyId) async {
    await selectFamily(familyId);
    if (!_isFirebaseAvailable) {
      await _mock.switchFamily(familyId);
    }
  }

  String? get selectedFamilyId => _cachedFamilyId;

  Future<String?> _getCurrentFamilyId() async {
    if (_cachedFamilyIdUserId == currentUserId &&
        _cachedFamilyId != null &&
        _cachedFamilies != null &&
        _cachedFamilies!.any((f) => f.id == _cachedFamilyId)) {
      return _cachedFamilyId;
    }

    final families = await getMyFamilies();
    if (families.isEmpty) return null;
    if (_cachedFamilyId != null &&
        families.any((f) => f.id == _cachedFamilyId)) {
      return _cachedFamilyId;
    }
    _cachedFamilyId = families.first.id;
    selectedFamilyIdNotifier.value = _cachedFamilyId;
    return _cachedFamilyId;
  }

  Future<bool> hasFamily() async {
    final families = await getMyFamilies();
    return families.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Current User
  // ---------------------------------------------------------------------------

  @override
  Future<UserModel> getCurrentUser() async {
    if (!_isFirebaseAvailable) return _mock.getCurrentUser();
    try {
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser != null) {
        try {
          final doc = await _firestore
              .collection('users')
              .doc(fbUser.uid)
              .get()
              .timeout(const Duration(seconds: 3));
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            return UserModel(
              id: fbUser.uid,
              name: data['name']?.toString() ??
                  (fbUser.displayName != null && fbUser.displayName!.isNotEmpty
                      ? fbUser.displayName!
                      : (fbUser.email?.isNotEmpty == true
                          ? fbUser.email!.split('@').first
                          : 'Người dùng')),
              email: data['email']?.toString() ?? fbUser.email ?? '',
              avatarType: data['avatar_type']?.toString() ?? 'google',
              avatarUrl:
                  data['avatarUrl']?.toString() ?? fbUser.photoURL ?? '',
            );
          }
        } catch (e) {
          debugPrint('Firestore user fetch error: $e');
        }

        return UserModel(
          id: fbUser.uid,
          name: (fbUser.displayName != null && fbUser.displayName!.isNotEmpty)
              ? fbUser.displayName!
              : (fbUser.email?.isNotEmpty == true
                  ? fbUser.email!.split('@').first
                  : 'Người dùng'),
          email: fbUser.email ?? '',
          avatarType: 'google',
          avatarUrl: fbUser.photoURL ?? '',
        );
      }
    } catch (_) {}

    return _mock.getCurrentUser();
  }

  // ---------------------------------------------------------------------------
  // Current Family
  // ---------------------------------------------------------------------------

  @override
  Future<FamilyModel?> getCurrentFamily({String? familyId}) async {
    final families = await getMyFamilies();
    if (families.isEmpty) return null;

    final targetId = familyId ?? await _getCurrentFamilyId();
    if (targetId == null) return families.first;

    return families.firstWhere(
      (f) => f.id == targetId,
      orElse: () => families.first,
    );
  }

  // ---------------------------------------------------------------------------
  // Create & Join Family (Module 2)
  // ---------------------------------------------------------------------------

  @override
  Future<FamilyModel> createFamily({
    required String name,
    HierarchyRole hierarchyRole = HierarchyRole.parent,
  }) async {
    if (!_isFirebaseAvailable) {
      return _mock.createFamily(name: name, hierarchyRole: hierarchyRole);
    }

    final uid = currentUserId;
    final joinCode = _generateJoinCode();
    try {
      final docRef = await _firestore.collection('families').add({
        'name': name,
        'joinCode': joinCode,
        'ownerId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _firestore
          .collection('family_members')
          .doc('${docRef.id}_$uid')
          .set({
        'familyId': docRef.id,
        'userId': uid,
        'role': 'OWNER',
        'isOwner': true,
        'hierarchyRole': hierarchyRole.code,
        'status': 'ACTIVE',
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

      clearCache();
      await selectFamily(docRef.id);

      return FamilyModel(
        id: docRef.id,
        name: name,
        joinCode: joinCode,
        ownerId: uid,
      );
    } catch (e) {
      debugPrint('createFamily error: $e');
      return _mock.createFamily(name: name, hierarchyRole: hierarchyRole);
    }
  }

  @override
  Future<FamilyModel> joinFamily({
    required String joinCode,
    HierarchyRole hierarchyRole = HierarchyRole.child,
  }) async {
    if (!_isFirebaseAvailable) {
      return _mock.joinFamily(joinCode: joinCode, hierarchyRole: hierarchyRole);
    }

    final uid = currentUserId;
    try {
      final snap = await _firestore
          .collection('families')
          .where('joinCode', isEqualTo: joinCode.toUpperCase())
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        throw Exception('Mã tham gia không tồn tại');
      }

      final famDoc = snap.docs.first;
      final familyId = famDoc.id;

      // Duplicate check
      final existing = await _firestore
          .collection('family_members')
          .doc('${familyId}_$uid')
          .get();
      if (existing.exists &&
          (existing.data()?['status'] ?? 'ACTIVE') == 'ACTIVE') {
        throw Exception('Bạn đã là thành viên của gia đình này');
      }

      await _firestore
          .collection('family_members')
          .doc('${familyId}_$uid')
          .set({
        'familyId': familyId,
        'userId': uid,
        'role': 'MEMBER',
        'isOwner': false,
        'hierarchyRole': hierarchyRole.code,
        'status': 'ACTIVE',
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

      clearCache();
      await selectFamily(familyId);

      return FamilyModel(
        id: familyId,
        name: famDoc.data()['name']?.toString() ?? 'Gia đình',
        joinCode: joinCode.toUpperCase(),
        ownerId: famDoc.data()['ownerId']?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('joinFamily error: $e');
      return _mock.joinFamily(joinCode: joinCode, hierarchyRole: hierarchyRole);
    }
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(6, (index) => chars[rand.nextInt(chars.length)])
        .join();
  }

  // ---------------------------------------------------------------------------
  // Family Members
  // ---------------------------------------------------------------------------

  @override
  Future<List<FamilyMemberModel>> getFamilyMembers({String? familyId}) async {
    if (!_isFirebaseAvailable || !_isAuthenticated) {
      return _mock.getFamilyMembers(familyId: familyId);
    }

    final myFamilies = await getMyFamilies();
    final targetFamilyId = familyId ?? await _getCurrentFamilyId();
    if (targetFamilyId == null ||
        targetFamilyId.isEmpty ||
        !myFamilies.any((f) => f.id == targetFamilyId)) {
      return <FamilyMemberModel>[];
    }

    try {
      final memberDocs = await _firestore
          .collection('family_members')
          .where('familyId', isEqualTo: targetFamilyId)
          .get()
          .timeout(const Duration(seconds: 4));

      if (memberDocs.docs.isNotEmpty) {
        final List<FamilyMemberModel> members = [];

        for (final memberDoc in memberDocs.docs) {
          final memberData = memberDoc.data();
          final userId =
              (memberData['userId'] ?? memberData['user_id'])?.toString() ?? '';
          if (userId.isEmpty) continue;

          UserModel userModel;
          DateTime? userLastCheckInAt;
          String? userLastCheckInDate;
          try {
            final userDoc =
                await _firestore.collection('users').doc(userId).get();
            if (userDoc.exists && userDoc.data() != null) {
              final userData = userDoc.data()!;
              userModel = UserModel(
                id: userId,
                name: userData['name']?.toString() ?? 'Thành viên',
                email: userData['email']?.toString() ?? '',
                avatarType: userData['avatar_type']?.toString() ?? 'default',
                avatarUrl: userData['avatarUrl']?.toString() ?? '',
              );
              final rawUserCheckIn =
                  userData['lastCheckInAt'] ?? userData['last_check_in_at'];
              if (rawUserCheckIn is Timestamp) {
                userLastCheckInAt = rawUserCheckIn.toDate();
              } else if (rawUserCheckIn is String) {
                userLastCheckInAt = DateTime.tryParse(rawUserCheckIn);
              }
              userLastCheckInDate = userData['lastCheckInDate']?.toString();
            } else {
              userModel = UserModel(
                id: userId,
                name: (memberData['name'] ?? 'Thành viên').toString(),
                email: '',
              );
            }
          } catch (_) {
            userModel = UserModel(
              id: userId,
              name: (memberData['name'] ?? 'Thành viên').toString(),
              email: '',
            );
          }

          final bool isOwner = memberData['isOwner'] as bool? ?? false;
          final role = isOwner ? Role.owner : Role.member;
          final hierarchyRaw = memberData['hierarchyRole'] ??
              memberData['hierarchy_role'] ??
              memberData['role'];
          final statusRaw = memberData['status']?.toString();

          DateTime? lastActiveAt;
          final rawActive =
              memberData['lastActiveAt'] ?? memberData['last_active_at'];
          if (rawActive is Timestamp) {
            lastActiveAt = rawActive.toDate();
          } else if (rawActive is String) {
            lastActiveAt = DateTime.tryParse(rawActive);
          }

          DateTime? lastCheckInAt;
          final rawCheckIn =
              memberData['lastCheckInAt'] ?? memberData['last_check_in_at'];
          if (rawCheckIn is Timestamp) {
            lastCheckInAt = rawCheckIn.toDate();
          } else if (rawCheckIn is String) {
            lastCheckInAt = DateTime.tryParse(rawCheckIn);
          }
          String? lastCheckInDate = memberData['lastCheckInDate']?.toString();

          // Đồng bộ trạng thái Check-in toàn tài khoản từ users/{userId} nếu mới hơn
          if (userLastCheckInAt != null &&
              (lastCheckInAt == null ||
                  userLastCheckInAt.isAfter(lastCheckInAt))) {
            lastCheckInAt = userLastCheckInAt;
            lastCheckInDate = userLastCheckInDate ?? lastCheckInDate;
            // Tự động làm lành (heal) bản ghi family_members trong nền
            memberDoc.reference.update({
              'lastCheckInAt': Timestamp.fromDate(userLastCheckInAt),
              'lastCheckInDate': ?lastCheckInDate,
            }).catchError((_) {});
          } else if (lastCheckInDate == null && userLastCheckInDate != null) {
            lastCheckInDate = userLastCheckInDate;
          }

          members.add(
            FamilyMemberModel(
              familyId: targetFamilyId,
              user: userModel,
              role: role,
              hierarchyRole: HierarchyRole.fromString(hierarchyRaw?.toString()),
              status: MemberStatus.fromString(statusRaw),
              lastActiveAt: lastActiveAt,
              lastCheckInAt: lastCheckInAt,
              lastCheckInDate: lastCheckInDate,
            ),
          );
        }

        return members;
      }
    } catch (e) {
      debugPrint('Firestore family members fetch error: $e');
    }

    return <FamilyMemberModel>[];
  }

  @override
  Stream<List<FamilyMemberModel>> streamFamilyMembers({String? familyId}) {
    if (!_isFirebaseAvailable || !_isAuthenticated) {
      return _mock.streamFamilyMembers(familyId: familyId);
    }
    final targetId = familyId ?? _cachedFamilyId;
    if (targetId == null || targetId.isEmpty) {
      return Stream.value(const <FamilyMemberModel>[]);
    }

    return _firestore
        .collection('family_members')
        .where('familyId', isEqualTo: targetId)
        .snapshots()
        .asyncMap((snap) async {
      return getFamilyMembers(familyId: targetId);
    });
  }

  // ---------------------------------------------------------------------------
  // Status & Ownership Management (Module 2)
  // ---------------------------------------------------------------------------

  @override
  Future<void> updateMemberStatus(
    String targetUserId,
    MemberStatus newStatus, {
    String? familyId,
  }) async {
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (!_isFirebaseAvailable || targetFamId == null) {
      await _mock.updateMemberStatus(targetUserId, newStatus,
          familyId: targetFamId);
      return;
    }

    try {
      await _firestore
          .collection('family_members')
          .doc('${targetFamId}_$targetUserId')
          .update({'status': newStatus.code});
    } catch (_) {
      await _mock.updateMemberStatus(targetUserId, newStatus,
          familyId: targetFamId);
    }
  }

  @override
  Future<void> transferOwnership(
    String newOwnerUserId, {
    String? familyId,
  }) async {
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (!_isFirebaseAvailable || targetFamId == null) {
      await _mock.transferOwnership(newOwnerUserId, familyId: targetFamId);
      return;
    }

    try {
      final members = await getFamilyMembers(familyId: targetFamId);
      final target = members.firstWhere((m) => m.user.id == newOwnerUserId);
      if (target.hierarchyRole != HierarchyRole.parent) {
        throw Exception('Chỉ có thể chuyển quyền Chủ gia đình cho vai vế Bố / Mẹ');
      }

      await _firestore.collection('families').doc(targetFamId).update({
        'ownerId': newOwnerUserId,
      });

      await _firestore
          .collection('family_members')
          .doc('${targetFamId}_$currentUserId')
          .update({'isOwner': false, 'role': 'MEMBER'});

      await _firestore
          .collection('family_members')
          .doc('${targetFamId}_$newOwnerUserId')
          .update({'isOwner': true, 'role': 'OWNER'});
    } catch (_) {
      await _mock.transferOwnership(newOwnerUserId, familyId: targetFamId);
    }
  }

  @override
  bool isTakeoverEligible({String? familyId}) {
    return _mock.isTakeoverEligible(familyId: familyId);
  }

  @override
  Future<void> claimOwnership({String? familyId}) async {
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (!_isFirebaseAvailable || targetFamId == null) {
      await _mock.claimOwnership(familyId: targetFamId);
      return;
    }

    try {
      await _firestore.collection('families').doc(targetFamId).update({
        'ownerId': currentUserId,
      });
      await _firestore
          .collection('family_members')
          .doc('${targetFamId}_$currentUserId')
          .update({'isOwner': true, 'role': 'OWNER'});
    } catch (_) {
      await _mock.claimOwnership(familyId: targetFamId);
    }
  }

  @override
  Future<void> updateOwnerLastActive() async {
    if (!_isFirebaseAvailable) {
      await _mock.updateOwnerLastActive();
      return;
    }
    if (!_isAuthenticated) return;
    final uid = currentUserId;
    final fid = await _getCurrentFamilyId();
    if (uid.isNotEmpty && fid != null && fid.isNotEmpty) {
      final key = '${fid}_$uid';
      final now = DateTime.now();
      if (_lastOwnerActiveKey == key &&
          _lastOwnerActiveUpdatedAt != null &&
          now.difference(_lastOwnerActiveUpdatedAt!) <
              const Duration(minutes: 10)) {
        return;
      }
      _lastOwnerActiveKey = key;
      _lastOwnerActiveUpdatedAt = now;
      try {
        await _firestore
            .collection('family_members')
            .doc(key)
            .update({'lastActiveAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Check-In & Feed (Module 3)
  // ---------------------------------------------------------------------------

  @override
  Future<void> checkIn(
    String userId, {
    String? imageUrl,
    String? caption,
    String? familyId,
  }) async {
    if (!_isFirebaseAvailable || !_isAuthenticated) {
      await _mock.checkIn(userId,
          imageUrl: imageUrl, caption: caption, familyId: familyId);
      return;
    }

    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    try {
      // 1. Tập hợp TẤT CẢ gia đình mà người dùng này đang tham gia (ACTIVE)
      final myFamilies = await getMyFamilies(forceRefresh: true);
      final targetFamilyIds = <String>{
        for (final f in myFamilies)
          if (f.id.trim().isNotEmpty) f.id.trim(),
      };
      final currentFamId = familyId ?? await _getCurrentFamilyId();
      if (currentFamId != null && currentFamId.trim().isNotEmpty) {
        targetFamilyIds.add(currentFamId.trim());
      }

      // Truy vấn tất cả bản ghi family_members của userId để cập nhật đồng loạt
      final updatedDocPaths = <String>{};
      final checkInPayload = <String, dynamic>{
        'lastCheckInAt': Timestamp.fromDate(now),
        'lastCheckInDate': dateStr,
        'lastActiveAt': FieldValue.serverTimestamp(),
      };

      try {
        final snap1 = await _firestore
            .collection('family_members')
            .where('userId', isEqualTo: userId)
            .get();
        for (final doc in snap1.docs) {
          final data = doc.data();
          final status = (data['status'] ?? 'ACTIVE').toString().toUpperCase();
          if (status == 'ACTIVE') {
            final fid =
                (data['familyId'] ?? data['family_id'])?.toString().trim() ?? '';
            if (fid.isNotEmpty) {
              targetFamilyIds.add(fid);
            }
            await doc.reference.update(checkInPayload);
            updatedDocPaths.add(doc.reference.path);
          }
        }
      } catch (_) {}

      try {
        final snap2 = await _firestore
            .collection('family_members')
            .where('user_id', isEqualTo: userId)
            .get();
        for (final doc in snap2.docs) {
          if (updatedDocPaths.contains(doc.reference.path)) continue;
          final data = doc.data();
          final status = (data['status'] ?? 'ACTIVE').toString().toUpperCase();
          if (status == 'ACTIVE') {
            final fid =
                (data['familyId'] ?? data['family_id'])?.toString().trim() ?? '';
            if (fid.isNotEmpty) {
              targetFamilyIds.add(fid);
            }
            await doc.reference.update(checkInPayload);
            updatedDocPaths.add(doc.reference.path);
          }
        }
      } catch (_) {}

      // Đảm bảo mọi familyId trong targetFamilyIds đều được cập nhật theo khóa chuẩn {fid}_{userId}
      for (final fid in targetFamilyIds) {
        final memberRef =
            _firestore.collection('family_members').doc('${fid}_$userId');
        if (!updatedDocPaths.contains(memberRef.path)) {
          try {
            await memberRef.update(checkInPayload);
            updatedDocPaths.add(memberRef.path);
          } catch (_) {}
        }
      }

      // 2. Lưu trạng thái Check-in lên cả hồ sơ users/{userId} để đồng bộ xuyên suốt toàn tài khoản
      try {
        await _firestore.collection('users').doc(userId).set(
          {
            'lastCheckInAt': Timestamp.fromDate(now),
            'lastCheckInDate': dateStr,
            'lastActiveAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}

      // 3. Nếu đính kèm ảnh hoặc lời nhắn, đăng lên bảng tin của TẤT CẢ gia đình đang tham gia
      if ((imageUrl != null || caption != null) && targetFamilyIds.isNotEmpty) {
        final currentUserObj = await getCurrentUser();
        for (final fid in targetFamilyIds) {
          await _firestore.collection('check_in_feeds').add({
            'familyId': fid,
            'userId': userId,
            'userName': currentUserObj.name,
            'imageUrl': imageUrl,
            'caption': caption,
            'createdAt': Timestamp.fromDate(now),
          });
        }
      }

      // 4. Hủy lời nhắc điểm danh trong ngày trên tất cả gia đình & phát tín hiệu cập nhật UI
      for (final fid in targetFamilyIds) {
        _mock.cancelRemindersForUser(userId, familyId: fid);
      }
      membershipRevisionNotifier.value++;
    } catch (e) {
      debugPrint('Firestore checkIn failed: $e');
      rethrow;
    }
  }

  @override
  Future<List<CheckInFeedModel>> getCheckInFeeds({String? familyId}) async {
    if (!_isFirebaseAvailable || !_isAuthenticated) {
      return await _mock.getCheckInFeeds(familyId: familyId);
    }

    final myFamilies = await getMyFamilies();
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (targetFamId == null ||
        targetFamId.isEmpty ||
        !myFamilies.any((f) => f.id == targetFamId)) {
      return <CheckInFeedModel>[];
    }

    try {
      final snap = await _firestore
          .collection('check_in_feeds')
          .where('familyId', isEqualTo: targetFamId)
          .get();

      if (snap.docs.isEmpty) {
        return <CheckInFeedModel>[];
      }

      final List<CheckInFeedModel> feeds = [];
      for (final doc in snap.docs) {
        final d = doc.data();
        DateTime createdAt = DateTime.now();
        final rawCreated = d['createdAt'];
        if (rawCreated is Timestamp) {
          createdAt = rawCreated.toDate();
        }
        feeds.add(CheckInFeedModel(
          id: doc.id,
          familyId: targetFamId,
          userId: d['userId']?.toString() ?? '',
          userName: d['userName']?.toString() ?? 'Thành viên',
          imageUrl: d['imageUrl']?.toString(),
          caption: d['caption']?.toString(),
          createdAt: createdAt,
        ));
      }
      feeds.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return feeds;
    } catch (_) {
      return <CheckInFeedModel>[];
    }
  }

  @override
  List<CheckInReminderItem> getSimulatedReminders({String? familyId}) {
    return _mock.getSimulatedReminders(familyId: familyId);
  }

  @override
  void cancelRemindersForUser(String userId, {String? familyId}) {
    _mock.cancelRemindersForUser(userId, familyId: familyId);
  }

  // ---------------------------------------------------------------------------
  // Reminders
  // ---------------------------------------------------------------------------

  Future<List<ReminderModel>> getMyPendingReminders({
    String? familyId,
    bool acrossAllFamilies = true,
  }) async {
    if (!_isFirebaseAvailable || !_isAuthenticated) {
      return _mock.getMyPendingReminders();
    }
    final uid = currentUserId;
    if (uid.isEmpty) return <ReminderModel>[];

    final families = await getMyFamilies();
    if (families.isEmpty) return <ReminderModel>[];
    final familyNameMap = {for (final f in families) f.id: f.name};

    final targetFamilyId = familyId ?? await _getCurrentFamilyId();
    final allowedFamilyIds = families.map((f) => f.id).toSet();

    try {
      final Map<String, ReminderModel> merged = {};

      Query<Map<String, dynamic>> query1 = _firestore
          .collection('reminders')
          .where('assigned_to', isEqualTo: uid)
          .where('status', isEqualTo: 'PENDING');
      if (!acrossAllFamilies && targetFamilyId != null) {
        query1 = query1.where('family_id', isEqualTo: targetFamilyId);
      }

      final docs1 = await query1.get().timeout(const Duration(seconds: 4));
      for (final doc in docs1.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        final fid = (data['family_id'] ?? data['familyId'])?.toString() ?? '';
        if (fid.isEmpty || !allowedFamilyIds.contains(fid)) {
          continue;
        }
        data['family_name'] ??= familyNameMap[fid];
        merged[doc.id] = ReminderModel.fromJson(data);
      }

      Query<Map<String, dynamic>> query2 = _firestore
          .collection('reminders')
          .where('assignedTo', isEqualTo: uid)
          .where('status', isEqualTo: 'PENDING');
      if (!acrossAllFamilies && targetFamilyId != null) {
        query2 = query2.where('familyId', isEqualTo: targetFamilyId);
      }

      final docs2 = await query2.get().timeout(const Duration(seconds: 4));
      for (final doc in docs2.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        final fid = (data['family_id'] ?? data['familyId'])?.toString() ?? '';
        if (fid.isEmpty || !allowedFamilyIds.contains(fid)) {
          continue;
        }
        data['family_name'] ??= familyNameMap[fid];
        merged[doc.id] = ReminderModel.fromJson(data);
      }

      final result = merged.values.toList();
      result.sort((a, b) => a.date.compareTo(b.date));
      return result;
    } catch (e) {
      debugPrint('Firestore reminders fetch error: $e');
      return <ReminderModel>[];
    }
  }

  // ---------------------------------------------------------------------------
  // Complete Reminder
  // ---------------------------------------------------------------------------

  Future<void> completeReminder(String reminderId) async {
    if (!_isFirebaseAvailable) {
      _mock.completeReminder(reminderId);
      return;
    }
    try {
      final reminderRef = _firestore.collection('reminders').doc(reminderId);
      final reminderDoc = await reminderRef.get();
      if (reminderDoc.exists) {
        await reminderRef.update({
          'status': 'COMPLETED',
          'completed_at': Timestamp.fromDate(DateTime.now()),
          'completedAt': Timestamp.fromDate(DateTime.now()),
        });
      }
    } catch (e) {
      debugPrint('Firestore completeReminder error: $e');
      _mock.completeReminder(reminderId);
    }
  }
}

/// Backward compatibility alias for legacy code referencing SupabaseService
typedef SupabaseService = FamilyDataService;

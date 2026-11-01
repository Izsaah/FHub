import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

/// Central data service bridging Firebase Auth & Firestore with Long's screens
/// (Home, Family, Profile, Reminders, and Jackpot).
/// Hoàn toàn sử dụng Firebase (Auth & Firestore) - KHÔNG dùng mock data.
/// Hỗ trợ 1 người dùng tham gia 1 hoặc nhiều gia đình (N families).
class FamilyDataService implements IFamilyService {
  static final FamilyDataService _instance = FamilyDataService._internal();
  factory FamilyDataService() => _instance;
  FamilyDataService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;

  String? _cachedFamilyId;
  String? _cachedFamilyIdUserId;
  List<FamilyModel>? _cachedFamilies;
  final Map<String, List<FamilyMemberModel>> _cachedFamilyMembers = {};

  /// Notifier phát tín hiệu khi người dùng chuyển đổi gia đình đang xem
  /// hoặc tạo/tham gia/rời gia đình.
  final ValueNotifier<String?> selectedFamilyIdNotifier =
      ValueNotifier<String?>(null);

  void clearCache() {
    _cachedFamilies = null;
    _cachedFamilyMembers.clear();
  }

  void resetAll() {
    _cachedFamilyId = null;
    _cachedFamilyIdUserId = null;
    _cachedFamilies = null;
    _cachedFamilyMembers.clear();
    selectedFamilyIdNotifier.value = null;
  }

  /// Trả về ID của người dùng hiện tại từ Firebase Auth (hoặc chuỗi rỗng nếu chưa đăng nhập).
  @override
  String get currentUserId {
    try {
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser != null) return fbUser.uid;
    } catch (_) {}
    return '';
  }

  /// True khi người dùng đã xác thực bằng Firebase.
  bool get _isAuthenticated {
    try {
      return _firebaseAuth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Multi-Family Management (1 người có thể có 1 hoặc N family)
  // ---------------------------------------------------------------------------

  /// Lấy toàn bộ danh sách gia đình đang ACTIVE của người dùng từ Firestore,
  /// sắp xếp theo bảng chữ cái (A -> Z).
  @override
  Future<List<FamilyModel>> getMyFamilies({bool forceRefresh = false}) async {
    final uid = currentUserId;
    if (uid.isEmpty) return [];

    if (!forceRefresh &&
        _cachedFamilies != null &&
        _cachedFamilyIdUserId == uid) {
      return _cachedFamilies!;
    }

    final List<FamilyModel> resolved = [];
    final Set<String> familyIds = {};

    try {
      // 1. Lấy tất cả các family_members đang ACTIVE của người dùng từ Firestore
      final memberDocs = await _firestore
          .collection('family_members')
          .where('userId', isEqualTo: uid)
          .get()
          .timeout(const Duration(seconds: 4));

      for (final doc in memberDocs.docs) {
        final data = doc.data();
        final status = (data['status'] ?? 'ACTIVE').toString().toUpperCase();
        if (status == 'DEACTIVATED') continue;
        final fid = (data['familyId'] ?? data['family_id'])?.toString();
        if (fid != null && fid.isNotEmpty) {
          familyIds.add(fid);
        }
      }

      // 2. Kiểm tra thêm trường familyId trong users/{uid} (nếu có dữ liệu cũ)
      try {
        final userDoc = await _firestore
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 3));
        if (userDoc.exists && userDoc.data() != null) {
          final fid = (userDoc.data()!['familyId'] ??
                  userDoc.data()!['family_id'])
              ?.toString();
          if (fid != null && fid.isNotEmpty) {
            // Chỉ thêm nếu membership không bị DEACTIVATED
            final memSnap = await _firestore
                .collection('family_members')
                .doc('${fid}_$uid')
                .get();
            if (!memSnap.exists ||
                (memSnap.data()?['status'] ?? 'ACTIVE') != 'DEACTIVATED') {
              familyIds.add(fid);
            }
          }
        }
      } catch (_) {}

      // 3. Tải thông tin từng family từ collection families trên Firestore
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

      // 4. Sắp xếp theo thứ tự bảng chữ cái A -> Z
      resolved.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      _cachedFamilies = resolved;
      _cachedFamilyIdUserId = uid;

      // Đồng bộ _cachedFamilyId: Nếu chưa chọn hoặc family cũ không còn trong danh sách,
      // mặc định chọn family đầu tiên theo bảng chữ cái (A -> Z)
      if (resolved.isEmpty) {
        _cachedFamilyId = null;
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
      return resolved;
    }
  }

  /// Chọn gia đình đang hoạt động (Active Family) khi người dùng có nhiều family
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
  // Current User (Từ Firebase Auth & Firestore users collection)
  // ---------------------------------------------------------------------------

  @override
  Future<UserModel> getCurrentUser() async {
    final uid = currentUserId;
    if (uid.isNotEmpty) {
      try {
        final doc = await _firestore
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final fbUser = _firebaseAuth.currentUser;
          return UserModel(
            id: uid,
            name: data['name']?.toString() ??
                (fbUser?.displayName != null && fbUser!.displayName!.isNotEmpty
                    ? fbUser.displayName!
                    : (fbUser?.email?.isNotEmpty == true
                        ? fbUser!.email!.split('@').first
                        : 'Người dùng')),
            email: data['email']?.toString() ?? fbUser?.email ?? '',
            avatarType: data['avatar_type']?.toString() ?? 'google',
            avatarUrl:
                data['avatarUrl']?.toString() ?? fbUser?.photoURL ?? '',
          );
        }
      } catch (e) {
        debugPrint('Firestore user fetch error: $e');
      }

      final fbUser = _firebaseAuth.currentUser;
      if (fbUser != null) {
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
    }

    return UserModel(
      id: '',
      name: 'Người dùng',
      email: '',
      avatarType: 'default',
      avatarUrl: '',
    );
  }

  // ---------------------------------------------------------------------------
  // Current Family (hoặc family theo familyId truyền vào)
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
  // Create & Join Family (Module 2 - Firestore)
  // ---------------------------------------------------------------------------

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(6, (index) => chars[rand.nextInt(chars.length)])
        .join();
  }

  @override
  Future<FamilyModel> createFamily({
    required String name,
    HierarchyRole hierarchyRole = HierarchyRole.parent,
  }) async {
    final uid = currentUserId;
    if (uid.isEmpty) {
      throw Exception('Vui lòng đăng nhập để tạo gia đình mới');
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Tên gia đình không được để trống');
    }

    // Generate unique 6-character code
    String joinCode = _generateJoinCode();
    for (int i = 0; i < 5; i++) {
      final existing = await _firestore
          .collection('families')
          .where('joinCode', isEqualTo: joinCode)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) break;
      joinCode = _generateJoinCode();
    }

    try {
      final familyRef = _firestore.collection('families').doc();
      final memberRef = _firestore
          .collection('family_members')
          .doc('${familyRef.id}_$uid');
      final userRef = _firestore.collection('users').doc(uid);

      final userObj = await getCurrentUser();

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
        'name': userObj.name,
        'role': 'OWNER',
        'isOwner': true,
        'hierarchyRole': hierarchyRole.code,
        'status': 'ACTIVE',
        'joinedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'lastCheckInAt': null,
        'lastCheckInDate': null,
      });

      batch.set(
        userRef,
        {
          'familyId': familyRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      clearCache();
      await selectFamily(familyRef.id);

      return FamilyModel(
        id: familyRef.id,
        name: trimmedName,
        joinCode: joinCode,
        ownerId: uid,
      );
    } catch (e) {
      debugPrint('Firestore createFamily error: $e');
      rethrow;
    }
  }

  @override
  Future<FamilyModel> joinFamily({
    required String joinCode,
    HierarchyRole hierarchyRole = HierarchyRole.child,
  }) async {
    final uid = currentUserId;
    if (uid.isEmpty) {
      throw Exception('Vui lòng đăng nhập để gia nhập gia đình');
    }

    final normalized = joinCode.trim().toUpperCase();
    if (normalized.length != 6) {
      throw Exception('Mã gia đình phải gồm đúng 6 ký tự (VD: A8K29D)');
    }

    try {
      final snap = await _firestore
          .collection('families')
          .where('joinCode', isEqualTo: normalized)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        throw Exception('Mã gia đình không tồn tại hoặc đã hết hạn');
      }

      final famDoc = snap.docs.first;
      final familyId = famDoc.id;
      final famData = famDoc.data();

      // Check if already an active member
      final memberRef = _firestore
          .collection('family_members')
          .doc('${familyId}_$uid');
      final existingMember = await memberRef.get();
      if (existingMember.exists &&
          (existingMember.data()?['status'] ?? 'ACTIVE') == 'ACTIVE') {
        throw Exception('Bạn đã là thành viên của gia đình này');
      }

      final userObj = await getCurrentUser();

      final batch = _firestore.batch();
      batch.set(
        memberRef,
        {
          'familyId': familyId,
          'userId': uid,
          'name': userObj.name,
          'role': 'MEMBER',
          'isOwner': false,
          'hierarchyRole': hierarchyRole.code,
          'status': 'ACTIVE',
          'joinedAt': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      batch.set(
        _firestore.collection('users').doc(uid),
        {
          'familyId': familyId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      clearCache();
      await selectFamily(familyId);

      return FamilyModel(
        id: familyId,
        name: famData['name']?.toString() ?? 'Gia đình',
        joinCode: normalized,
        ownerId: famData['ownerId']?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('Firestore joinFamily error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Family Members (Đọc trực tiếp từ Firestore family_members & users)
  // ---------------------------------------------------------------------------

  @override
  Future<List<FamilyMemberModel>> getFamilyMembers({String? familyId}) async {
    final targetFamilyId = familyId ?? await _getCurrentFamilyId();
    if (targetFamilyId == null || targetFamilyId.isEmpty) return [];

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
          try {
            final userDoc =
                await _firestore.collection('users').doc(userId).get();
            if (userDoc.exists && userDoc.data() != null) {
              final userData = userDoc.data()!;
              userModel = UserModel(
                id: userId,
                name: userData['name']?.toString() ??
                    memberData['name']?.toString() ??
                    'Thành viên',
                email: userData['email']?.toString() ?? '',
                avatarType: userData['avatar_type']?.toString() ?? 'default',
                avatarUrl: userData['avatarUrl']?.toString() ?? '',
              );
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

          final bool isOwner = memberData['isOwner'] as bool? ??
              ((memberData['role']?.toString().toUpperCase()) == 'OWNER');
          final role = isOwner ? Role.owner : Role.member;
          final hierarchyRaw = memberData['hierarchyRole'] ??
              memberData['hierarchy_role'] ??
              memberData['memberRole'] ??
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

          members.add(
            FamilyMemberModel(
              familyId: targetFamilyId,
              user: userModel,
              role: role,
              hierarchyRole: HierarchyRole.fromString(hierarchyRaw?.toString()),
              status: MemberStatus.fromString(statusRaw),
              lastActiveAt: lastActiveAt,
              lastCheckInAt: lastCheckInAt,
              lastCheckInDate: memberData['lastCheckInDate']?.toString(),
            ),
          );
        }

        _cachedFamilyMembers[targetFamilyId] = members;
        return members;
      }
    } catch (e) {
      debugPrint('Firestore family members fetch error: $e');
    }

    return _cachedFamilyMembers[targetFamilyId] ?? [];
  }

  @override
  Stream<List<FamilyMemberModel>> streamFamilyMembers({String? familyId}) {
    final targetId = familyId ?? _cachedFamilyId;
    if (targetId == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('family_members')
        .where('familyId', isEqualTo: targetId)
        .snapshots()
        .asyncMap((_) => getFamilyMembers(familyId: targetId));
  }

  // ---------------------------------------------------------------------------
  // Status & Ownership Management (Module 2 - Firestore)
  // ---------------------------------------------------------------------------

  @override
  Future<void> updateMemberStatus(
    String targetUserId,
    MemberStatus newStatus, {
    String? familyId,
  }) async {
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (targetFamId == null || targetFamId.isEmpty) return;

    try {
      await _firestore
          .collection('family_members')
          .doc('${targetFamId}_$targetUserId')
          .update({
        'status': newStatus.code,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      clearCache();
    } catch (e) {
      debugPrint('Firestore updateMemberStatus error: $e');
      rethrow;
    }
  }

  @override
  Future<void> transferOwnership(
    String newOwnerUserId, {
    String? familyId,
  }) async {
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (targetFamId == null || targetFamId.isEmpty) return;

    final members = await getFamilyMembers(familyId: targetFamId);
    final target = members.firstWhere(
      (m) => m.user.id == newOwnerUserId,
      orElse: () => throw Exception('Thành viên không tồn tại trong gia đình'),
    );
    if (target.hierarchyRole != HierarchyRole.parent) {
      throw Exception('Chỉ có thể chuyển quyền Chủ gia đình cho vai vế Bố / Mẹ');
    }

    try {
      final batch = _firestore.batch();
      batch.update(_firestore.collection('families').doc(targetFamId), {
        'ownerId': newOwnerUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(
        _firestore
            .collection('family_members')
            .doc('${targetFamId}_$currentUserId'),
        {
          'isOwner': false,
          'role': 'MEMBER',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      batch.update(
        _firestore
            .collection('family_members')
            .doc('${targetFamId}_$newOwnerUserId'),
        {
          'isOwner': true,
          'role': 'OWNER',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
      clearCache();
    } catch (e) {
      debugPrint('Firestore transferOwnership error: $e');
      rethrow;
    }
  }

  @override
  bool isTakeoverEligible({String? familyId}) {
    final targetFamId = familyId ?? _cachedFamilyId;
    if (targetFamId == null) return false;
    final members = _cachedFamilyMembers[targetFamId];
    if (members == null || members.isEmpty) return false;

    final owner = members.firstWhere(
      (m) => m.isOwner,
      orElse: () => members.first,
    );
    if (owner.lastActiveAt == null) return true;
    return DateTime.now().difference(owner.lastActiveAt!).inDays >= 30;
  }

  @override
  Future<void> claimOwnership({String? familyId}) async {
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (targetFamId == null) throw Exception('Chưa chọn gia đình');

    try {
      final batch = _firestore.batch();
      batch.update(_firestore.collection('families').doc(targetFamId), {
        'ownerId': currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(
        _firestore
            .collection('family_members')
            .doc('${targetFamId}_$currentUserId'),
        {
          'isOwner': true,
          'role': 'OWNER',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
      clearCache();
    } catch (e) {
      debugPrint('Firestore claimOwnership error: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateOwnerLastActive() async {
    final uid = currentUserId;
    final fid = await _getCurrentFamilyId();
    if (uid.isNotEmpty && fid != null) {
      try {
        await _firestore
            .collection('family_members')
            .doc('${fid}_$uid')
            .update({'lastActiveAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Check-In & Feed (Module 3 - Firestore)
  // ---------------------------------------------------------------------------

  @override
  Future<void> checkIn(
    String userId, {
    String? imageUrl,
    String? caption,
    String? familyId,
  }) async {
    final targetFamilyId = familyId ?? await _getCurrentFamilyId();
    if (targetFamilyId == null || targetFamilyId.isEmpty) {
      throw Exception('Chưa chọn gia đình để điểm danh');
    }

    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    try {
      final memberDocId = '${targetFamilyId}_$userId';
      final memberRef =
          _firestore.collection('family_members').doc(memberDocId);

      await memberRef.set({
        'lastCheckInAt': Timestamp.fromDate(now),
        'lastCheckInDate': dateStr,
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Lưu bài viết ảnh vào Firestore check_in_feeds
      if (imageUrl != null || caption != null) {
        final currentUserObj = await getCurrentUser();
        await _firestore.collection('check_in_feeds').add({
          'familyId': targetFamilyId,
          'userId': userId,
          'userName': currentUserObj.name,
          'imageUrl': imageUrl,
          'caption': caption,
          'createdAt': Timestamp.fromDate(now),
        });
      }

      clearCache();
    } catch (e) {
      debugPrint('Firestore checkIn error: $e');
      rethrow;
    }
  }

  @override
  Future<List<CheckInFeedModel>> getCheckInFeeds({String? familyId}) async {
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (targetFamId == null || targetFamId.isEmpty) return [];

    try {
      final snap = await _firestore
          .collection('check_in_feeds')
          .where('familyId', isEqualTo: targetFamId)
          .get()
          .timeout(const Duration(seconds: 4));

      final List<CheckInFeedModel> feeds = [];
      for (final doc in snap.docs) {
        final d = doc.data();
        DateTime createdAt = DateTime.now();
        final rawCreated = d['createdAt'];
        if (rawCreated is Timestamp) {
          createdAt = rawCreated.toDate();
        } else if (rawCreated is String) {
          createdAt = DateTime.tryParse(rawCreated) ?? DateTime.now();
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
    } catch (e) {
      debugPrint('Firestore getCheckInFeeds error: $e');
      return [];
    }
  }

  @override
  List<CheckInReminderItem> getSimulatedReminders({String? familyId}) {
    final targetFamId = familyId ?? _cachedFamilyId;
    if (targetFamId == null) return [];
    final famMembers = _cachedFamilyMembers[targetFamId] ?? [];

    final grandparents = famMembers.where(
      (m) =>
          m.hierarchyRole == HierarchyRole.grandparent &&
          m.status == MemberStatus.active,
    );

    final parents = famMembers.where(
      (m) =>
          m.hierarchyRole == HierarchyRole.parent &&
          m.status == MemberStatus.active,
    );

    final List<CheckInReminderItem> results = [];
    final now = DateTime.now();

    for (var gp in grandparents) {
      final isCheckedIn = gp.isCheckedInToday;

      results.add(CheckInReminderItem(
        id: 'rem_${gp.user.id}_8am',
        familyId: targetFamId,
        targetMemberId: gp.user.id,
        targetMemberName: gp.user.name,
        recipientMemberId: gp.user.id,
        recipientMemberName: gp.user.name,
        slot: ReminderTimeSlot.slot8AM,
        message:
            'Chào buổi sáng ${gp.user.name}! Hãy bấm "✓ I\'M OK" để con cháu yên tâm nhé.',
        isVibration: false,
        isCancelled: isCheckedIn,
        scheduledTime: DateTime(now.year, now.month, now.day, 8, 0),
      ));

      results.add(CheckInReminderItem(
        id: 'rem_${gp.user.id}_2pm',
        familyId: targetFamId,
        targetMemberId: gp.user.id,
        targetMemberName: gp.user.name,
        recipientMemberId: gp.user.id,
        recipientMemberName: gp.user.name,
        slot: ReminderTimeSlot.slot2PM,
        message:
            'Đã 14:00 rồi! ${gp.user.name} chưa check-in hôm nay, gia đình đang lo lắng đó ạ.',
        isVibration: true,
        isCancelled: isCheckedIn,
        scheduledTime: DateTime(now.year, now.month, now.day, 14, 0),
      ));

      for (var p in parents) {
        results.add(CheckInReminderItem(
          id: 'rem_${gp.user.id}_8pm_${p.user.id}',
          familyId: targetFamId,
          targetMemberId: gp.user.id,
          targetMemberName: gp.user.name,
          recipientMemberId: p.user.id,
          recipientMemberName: p.user.name,
          slot: ReminderTimeSlot.slot8PM,
          message:
              'Cảnh báo: Đã quá 12 tiếng từ giờ hẹn nhưng ${gp.user.name} chưa check-in hôm nay, gia đình hãy gọi điện kiểm tra nhé!',
          isVibration: true,
          isCancelled: isCheckedIn,
          scheduledTime: DateTime(now.year, now.month, now.day, 20, 0),
        ));
      }
    }

    return results;
  }

  @override
  void cancelRemindersForUser(String userId, {String? familyId}) {
    // When member is checked in today, isCheckedInToday becomes true, cancelling reminders
    clearCache();
  }

  // ---------------------------------------------------------------------------
  // Reminders (Đọc trực tiếp từ Firestore reminders collection)
  // ---------------------------------------------------------------------------

  Future<List<ReminderModel>> getMyPendingReminders({
    String? familyId,
    bool acrossAllFamilies = true,
  }) async {
    final uid = currentUserId;
    if (uid.isEmpty) return [];

    final families = await getMyFamilies();
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
        if (allowedFamilyIds.isNotEmpty &&
            fid.isNotEmpty &&
            !allowedFamilyIds.contains(fid)) {
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
        if (allowedFamilyIds.isNotEmpty &&
            fid.isNotEmpty &&
            !allowedFamilyIds.contains(fid)) {
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
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Complete Reminder (Cập nhật trực tiếp lên Firestore reminders collection)
  // ---------------------------------------------------------------------------

  Future<void> completeReminder(String reminderId) async {
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
      rethrow;
    }
  }
}

/// Backward compatibility alias for legacy code referencing SupabaseService
typedef SupabaseService = FamilyDataService;

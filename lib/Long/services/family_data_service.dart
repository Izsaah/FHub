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

  final ValueNotifier<String?> selectedFamilyIdNotifier =
      ValueNotifier<String?>(null);

  void clearCache() {
    _cachedFamilies = null;
  }

  void resetAll() {
    _cachedFamilyId = null;
    _cachedFamilyIdUserId = null;
    _cachedFamilies = null;
    selectedFamilyIdNotifier.value = null;
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
    if (!_isFirebaseAvailable) return _mock.getMyFamilies();

    final uid = currentUserId;
    if (uid.isEmpty) return _mock.getMyFamilies();

    if (!forceRefresh &&
        _cachedFamilies != null &&
        _cachedFamilyIdUserId == uid) {
      return _cachedFamilies!;
    }

    final List<FamilyModel> resolved = [];
    final Set<String> familyIds = {};

    try {
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
      } else if (_cachedFamilyId == null ||
          !resolved.any((f) => f.id == _cachedFamilyId)) {
        _cachedFamilyId = resolved.first.id;
      }
      if (selectedFamilyIdNotifier.value != _cachedFamilyId) {
        selectedFamilyIdNotifier.value = _cachedFamilyId;
      }

      return resolved.isNotEmpty ? resolved : await _mock.getMyFamilies();
    } catch (e) {
      debugPrint('getMyFamilies error: $e');
      return _cachedFamilies ?? await _mock.getMyFamilies();
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
    if (!_isFirebaseAvailable) {
      return _mock.getFamilyMembers(familyId: familyId);
    }

    final targetFamilyId = familyId ?? await _getCurrentFamilyId();
    if (targetFamilyId == null || targetFamilyId.isEmpty) {
      return _mock.getFamilyMembers(familyId: familyId);
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

        return members;
      }
    } catch (e) {
      debugPrint('Firestore family members fetch error: $e');
    }

    return _mock.getFamilyMembers(familyId: familyId);
  }

  @override
  Stream<List<FamilyMemberModel>> streamFamilyMembers({String? familyId}) {
    if (!_isFirebaseAvailable) {
      return _mock.streamFamilyMembers(familyId: familyId);
    }
    final targetId = familyId ?? _cachedFamilyId;
    if (targetId == null) return _mock.streamFamilyMembers(familyId: familyId);

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
  // Check-In & Feed (Module 3)
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
      await _mock.checkIn(userId,
          imageUrl: imageUrl, caption: caption, familyId: familyId);
      return;
    }

    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    if (!_isFirebaseAvailable) {
      await _mock.checkIn(userId,
          imageUrl: imageUrl, caption: caption, familyId: targetFamilyId);
      return;
    }

    try {
      final memberDocId = '${targetFamilyId}_$userId';
      final memberRef =
          _firestore.collection('family_members').doc(memberDocId);

      await memberRef.update({
        'lastCheckInAt': Timestamp.fromDate(now),
        'lastCheckInDate': dateStr,
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

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
    } catch (e) {
      debugPrint('Firestore checkIn fallback: $e');
      await _mock.checkIn(userId,
          imageUrl: imageUrl, caption: caption, familyId: targetFamilyId);
    }
  }

  @override
  Future<List<CheckInFeedModel>> getCheckInFeeds({String? familyId}) async {
    final targetFamId = familyId ?? await _getCurrentFamilyId();
    if (!_isFirebaseAvailable || targetFamId == null) {
      return await _mock.getCheckInFeeds(familyId: targetFamId);
    }

    try {
      final snap = await _firestore
          .collection('check_in_feeds')
          .where('familyId', isEqualTo: targetFamId)
          .get();

      if (snap.docs.isEmpty) {
        return await _mock.getCheckInFeeds(familyId: targetFamId);
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
      return await _mock.getCheckInFeeds(familyId: targetFamId);
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
    if (!_isFirebaseAvailable) return _mock.getMyPendingReminders();
    final uid = currentUserId;
    if (uid.isEmpty) return _mock.getMyPendingReminders();

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
      return _mock.getMyPendingReminders();
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

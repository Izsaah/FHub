import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';

/// Central data service bridging Firebase Auth & Firestore with Long's screens
/// (Home, Family, Profile, Reminders, and Jackpot).
/// Hoàn toàn sử dụng Firebase (Auth & Firestore) - KHÔNG dùng mock data.
/// Hỗ trợ 1 người dùng tham gia 1 hoặc nhiều gia đình (N families).
class FamilyDataService {
  static final FamilyDataService _instance = FamilyDataService._internal();
  factory FamilyDataService() => _instance;
  FamilyDataService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;

  String? _cachedFamilyId;
  String? _cachedFamilyIdUserId;
  List<FamilyModel>? _cachedFamilies;

  /// Notifier phát tín hiệu khi người dùng chuyển đổi gia đình đang xem
  /// hoặc tạo/tham gia/rời gia đình.
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

  /// Trả về ID của người dùng hiện tại từ Firebase Auth (hoặc chuỗi rỗng nếu chưa đăng nhập).
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
        final status = (data['status'] ?? 'ACTIVE').toString();
        if (status != 'ACTIVE') continue;
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
            // Chỉ thêm nếu membership không bị DEACTIVATED/MEMORIALIZED
            final memSnap = await _firestore
                .collection('family_members')
                .doc('${fid}_$uid')
                .get();
            if (!memSnap.exists ||
                (memSnap.data()?['status'] ?? 'ACTIVE') == 'ACTIVE') {
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

  Future<UserModel> getCurrentUser() async {
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
  // Family Members (Đọc trực tiếp từ Firestore family_members & users)
  // ---------------------------------------------------------------------------

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

          final status = memberData['status']?.toString() ?? 'ACTIVE';
          if (status != 'ACTIVE') continue;

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
          final String memberRole =
              (memberData['role'] ?? 'PARENT').toString().toUpperCase();

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
              memberRole: memberRole,
              lastCheckInAt: lastCheckInAt,
            ),
          );
        }

        return members;
      }
    } catch (e) {
      debugPrint('Firestore family members fetch error: $e');
    }

    return [];
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
  // Check In (Cập nhật trực tiếp lên Firestore family_members collection)
  // ---------------------------------------------------------------------------

  Future<void> checkIn(String userId, {String? familyId}) async {
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
      final memberDoc = await memberRef.get();

      if (memberDoc.exists) {
        await memberRef.update({
          'lastCheckInAt': Timestamp.fromDate(now),
          'lastCheckInDate': dateStr,
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final memberQuery = await _firestore
          .collection('family_members')
          .where('familyId', isEqualTo: targetFamilyId)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      if (memberQuery.docs.isNotEmpty) {
        await memberQuery.docs.first.reference.update({
          'lastCheckInAt': Timestamp.fromDate(now),
          'lastCheckInDate': dateStr,
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
        return;
      }
    } catch (e) {
      debugPrint('Firestore checkIn error: $e');
      rethrow;
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

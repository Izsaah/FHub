import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';
import 'mock_data_service.dart';

/// Central data service bridging Firebase Auth & Firestore with Long's screens
/// (Home, Family, Profile, Reminders, and Jackpot).
class FamilyDataService {
  static final FamilyDataService _instance = FamilyDataService._internal();
  factory FamilyDataService() => _instance;
  FamilyDataService._internal();

  final _firestore = FirebaseFirestore.instance;
  final _firebaseAuth = FirebaseAuth.instance;
  final _mock = MockDataService();
  String? _cachedFamilyId;
  String? _cachedFamilyIdUserId;

  void clearCache() {
    _cachedFamilyId = null;
    _cachedFamilyIdUserId = null;
  }

  /// Returns the current user ID from Firebase Auth first, then Supabase, then mock.
  String get currentUserId {
    final fbUser = _firebaseAuth.currentUser;
    if (fbUser != null) return fbUser.uid;
    try {
      final sbUser = Supabase.instance.client.auth.currentUser;
      if (sbUser != null) return sbUser.id;
    } catch (_) {}
    return _mock.currentUser.id;
  }

  /// True when a real user is authenticated (Firebase or Supabase).
  bool get _isAuthenticated {
    if (_firebaseAuth.currentUser != null) return true;
    try {
      if (Supabase.instance.client.auth.currentUser != null) return true;
    } catch (_) {}
    return false;
  }

  // ---------------------------------------------------------------------------
  // Family ID lookup
  // ---------------------------------------------------------------------------

  Future<String?> _getCurrentFamilyId() async {
    if (!_isAuthenticated) return _mock.currentFamily.id;
    if (_cachedFamilyIdUserId == currentUserId && _cachedFamilyId != null) {
      return _cachedFamilyId;
    }

    try {
      // 1. Check Firestore user document for familyId
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUserId)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final familyId = userDoc.data()!['familyId']?.toString();
        if (familyId != null && familyId.isNotEmpty) { _cachedFamilyIdUserId = currentUserId; _cachedFamilyId = familyId; return familyId; }
      }

      // 2. Check Firestore family_members collection
      final memberDocs = await _firestore
          .collection('family_members')
          .where('userId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'ACTIVE')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 3));
      if (memberDocs.docs.isNotEmpty) {
        final familyId =
            (memberDocs.docs.first.data()['familyId'] ??
                    memberDocs.docs.first.data()['family_id'])
                ?.toString();
        if (familyId != null && familyId.isNotEmpty) { _cachedFamilyIdUserId = currentUserId; _cachedFamilyId = familyId; return familyId; }
      }

      // 3. Supabase fallback
      try {
        final supabase = Supabase.instance.client;
        if (supabase.auth.currentUser != null) {
          final response = await supabase
              .from('family_members')
              .select('family_id')
              .eq('user_id', currentUserId)
              .maybeSingle();
          final familyId = response?['family_id'] as String?;
          if (familyId != null && familyId.isNotEmpty) { _cachedFamilyIdUserId = currentUserId; _cachedFamilyId = familyId; return familyId; }
        }
      } catch (_) {}

      return null;
    } catch (e) {
      debugPrint('_getCurrentFamilyId error: $e');
      return null;
    }
  }

  Future<bool> hasFamily() async {
    final familyId = await _getCurrentFamilyId();
    return familyId != null;
  }

  // ---------------------------------------------------------------------------
  // Current User
  // ---------------------------------------------------------------------------

  Future<UserModel> getCurrentUser() async {
    // 1. Try Firebase Auth + Firestore
    final fbUser = _firebaseAuth.currentUser;
    if (fbUser != null) {
      try {
        final doc = await _firestore.collection('users').doc(fbUser.uid).get().timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          return UserModel(
            id: fbUser.uid,
            name:
                data['name']?.toString() ??
                (fbUser.displayName != null && fbUser.displayName!.isNotEmpty
                    ? fbUser.displayName!
                    : 'Người dùng'),
            email: data['email']?.toString() ?? fbUser.email ?? '',
            avatarType: data['avatar_type']?.toString() ?? 'google',
            avatarUrl: data['avatarUrl']?.toString() ?? fbUser.photoURL ?? '',
          );
        }
      } catch (e) {
        debugPrint('Firestore user fetch error: $e');
      }

      // Fallback to Firebase Auth data only
      return UserModel(
        id: fbUser.uid,
        name: (fbUser.displayName != null && fbUser.displayName!.isNotEmpty)
            ? fbUser.displayName!
            : 'Người dùng',
        email: fbUser.email ?? '',
        avatarType: 'google',
        avatarUrl: fbUser.photoURL ?? '',
      );
    }

    // 2. Try Supabase
    try {
      final supabase = Supabase.instance.client;
      if (supabase.auth.currentUser != null) {
        final response = await supabase
            .from('users')
            .select()
            .eq('id', currentUserId)
            .maybeSingle();
        if (response != null) return UserModel.fromJson(response);
      }
    } catch (_) {}

    // 3. Mock fallback (no authenticated user)
    return _mock.currentUser;
  }

  // ---------------------------------------------------------------------------
  // Current Family
  // ---------------------------------------------------------------------------

  Future<FamilyModel?> getCurrentFamily() async {
    final familyId = await _getCurrentFamilyId();
    if (familyId == null) return null;

    if (!_isAuthenticated) return _mock.currentFamily;

    // 1. Try Firestore
    try {
      final doc = await _firestore.collection('families').doc(familyId).get().timeout(const Duration(seconds: 3));
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return FamilyModel(
          id: doc.id,
          name: data['name']?.toString() ?? '',
          joinCode: (data['joinCode'] ?? data['join_code'])?.toString() ?? '',
          ownerId: (data['ownerId'] ?? data['owner_id'])?.toString() ?? '',
        );
      }
    } catch (e) {
      debugPrint('Firestore family fetch error: $e');
    }

    // 2. Supabase fallback
    try {
      final supabase = Supabase.instance.client;
      if (supabase.auth.currentUser != null) {
        final response = await supabase
            .from('families')
            .select()
            .eq('id', familyId)
            .maybeSingle();
        if (response != null) return FamilyModel.fromJson(response);
      }
    } catch (_) {}

    return null;
  }

  // ---------------------------------------------------------------------------
  // Family Members
  // ---------------------------------------------------------------------------

  Future<List<FamilyMemberModel>> getFamilyMembers() async {
    final familyId = await _getCurrentFamilyId();
    if (familyId == null) return [];

    if (!_isAuthenticated) return _mock.members;

    // 1. Try Firestore
    try {
      final memberDocs = await _firestore
          .collection('family_members')
          .where('familyId', isEqualTo: familyId)
          .get();

      if (memberDocs.docs.isNotEmpty) {
        final List<FamilyMemberModel> members = [];

        for (final memberDoc in memberDocs.docs) {
          final memberData = memberDoc.data();
          final userId =
              (memberData['userId'] ?? memberData['user_id'])?.toString() ?? '';
          if (userId.isEmpty) continue;

          // Skip deactivated/memorialized members
          final status = memberData['status']?.toString() ?? 'ACTIVE';
          if (status != 'ACTIVE') continue;

          // Fetch user profile for this member
          UserModel userModel;
          try {
            final userDoc = await _firestore
                .collection('users')
                .doc(userId)
                .get();
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
              userModel = UserModel(id: userId, name: 'Thành viên', email: '');
            }
          } catch (_) {
            userModel = UserModel(id: userId, name: 'Thành viên', email: '');
          }

          // Determine role
          final bool isOwner = memberData['isOwner'] as bool? ?? false;
          final role = isOwner ? Role.owner : Role.member;

          // Parse last check-in time
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
              familyId: familyId,
              user: userModel,
              role: role,
              lastCheckInAt: lastCheckInAt,
            ),
          );
        }

        return members;
      }
    } catch (e) {
      debugPrint('Firestore family members fetch error: $e');
    }

    // 2. Supabase fallback
    try {
      final supabase = Supabase.instance.client;
      if (supabase.auth.currentUser != null) {
        final response = await supabase
            .from('family_members')
            .select('''
          *,
          user:users(*)
        ''')
            .eq('family_id', familyId);

        return (response as List)
            .map((e) => FamilyMemberModel.fromJson(e))
            .toList();
      }
    } catch (_) {}

    return [];
  }

  // ---------------------------------------------------------------------------
  // Reminders
  // ---------------------------------------------------------------------------

  Future<List<ReminderModel>> getMyPendingReminders() async {
    if (!_isAuthenticated) return _mock.getMyPendingReminders();

    final familyId = await _getCurrentFamilyId();

    // 1. Try Firestore
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('reminders')
          .where('assigned_to', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'PENDING');
      if (familyId != null) {
        query = query.where('family_id', isEqualTo: familyId);
      }

      final docs = await query.get();
      if (docs.docs.isNotEmpty) {
        return docs.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return ReminderModel.fromJson(data);
        }).toList();
      }

      // Also try with assignedTo camelCase key
      Query<Map<String, dynamic>> query2 = _firestore
          .collection('reminders')
          .where('assignedTo', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'PENDING');
      if (familyId != null) {
        query2 = query2.where('familyId', isEqualTo: familyId);
      }

      final docs2 = await query2.get();
      if (docs2.docs.isNotEmpty) {
        return docs2.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return ReminderModel.fromJson(data);
        }).toList();
      }
    } catch (e) {
      debugPrint('Firestore reminders fetch error: $e');
    }

    // 2. Supabase fallback
    try {
      final supabase = Supabase.instance.client;
      if (supabase.auth.currentUser != null) {
        final response = await supabase
            .from('reminders')
            .select()
            .eq('assigned_to', currentUserId)
            .eq('status', 'PENDING');

        return (response as List)
            .map((e) => ReminderModel.fromJson(e))
            .toList();
      }
    } catch (_) {}

    return [];
  }

  // ---------------------------------------------------------------------------
  // Check In
  // ---------------------------------------------------------------------------

  Future<void> checkIn(String userId) async {
    final familyId = await _getCurrentFamilyId();
    if (familyId == null) throw Exception('No family to check into');

    if (!_isAuthenticated) {
      _mock.checkIn(userId);
      return;
    }

    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // 1. Try Firestore
    try {
      // Membership doc ID follows Khoa's schema: {familyId}_{userId}
      final memberDocId = '${familyId}_$userId';
      final memberRef = _firestore
          .collection('family_members')
          .doc(memberDocId);
      final memberDoc = await memberRef.get();

      if (memberDoc.exists) {
        await memberRef.update({
          'lastCheckInAt': Timestamp.fromDate(now),
          'lastCheckInDate': dateStr,
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      // Try finding the member doc by query (in case ID format differs)
      final memberQuery = await _firestore
          .collection('family_members')
          .where('familyId', isEqualTo: familyId)
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
    }

    // 2. Supabase fallback
    try {
      final supabase = Supabase.instance.client;
      if (supabase.auth.currentUser != null) {
        await supabase
            .from('family_members')
            .update({
              'last_check_in_at': now.toIso8601String(),
              'last_check_in_date': dateStr,
            })
            .eq('family_id', familyId)
            .eq('user_id', userId);
        return;
      }
    } catch (e) {
      debugPrint('Supabase checkIn error: $e');
    }

    // 3. Mock fallback
    _mock.checkIn(userId);
  }

  // ---------------------------------------------------------------------------
  // Complete Reminder
  // ---------------------------------------------------------------------------

  Future<void> completeReminder(String reminderId) async {
    if (!_isAuthenticated) {
      _mock.completeReminder(reminderId);
      return;
    }

    // 1. Try Firestore
    try {
      final reminderRef = _firestore.collection('reminders').doc(reminderId);
      final reminderDoc = await reminderRef.get();
      if (reminderDoc.exists) {
        await reminderRef.update({
          'status': 'COMPLETED',
          'completed_at': Timestamp.fromDate(DateTime.now()),
          'completedAt': Timestamp.fromDate(DateTime.now()),
        });
        return;
      }
    } catch (e) {
      debugPrint('Firestore completeReminder error: $e');
    }

    // 2. Supabase fallback
    try {
      final supabase = Supabase.instance.client;
      if (supabase.auth.currentUser != null) {
        await supabase
            .from('reminders')
            .update({
              'status': 'COMPLETED',
              'completed_at': DateTime.now().toIso8601String(),
            })
            .eq('id', reminderId);
        return;
      }
    } catch (e) {
      debugPrint('Supabase completeReminder error: $e');
    }

    // 3. Mock fallback
    _mock.completeReminder(reminderId);
  }
}

/// Backward compatibility alias for legacy code referencing SupabaseService
typedef SupabaseService = FamilyDataService;

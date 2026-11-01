import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

class UserService {
  UserService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get currentUserId {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Chưa đăng nhập.');
    return user.uid;
  }

  Future<UserProfile?> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Chưa đăng nhập.');
    final profile = await getUserById(user.uid);
    if (profile != null) return profile;
    // Fallback to Firebase Auth data if the Firestore profile has not been created yet.
    return UserProfile(
      id: user.uid,
      name: user.displayName ?? 'Thành viên mới',
      email: user.email ?? '',
      avatarType: user.photoURL == null ? 'default' : 'google',
      avatarUrl: user.photoURL,
    );
  }

  Future<UserProfile?> getUserById(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists || doc.data() == null) return null;
      return UserProfile.fromMap(doc.data()!, documentId: doc.id);
    } on FirebaseException catch (e) {
      throw Exception(e.message ?? 'Không thể tải hồ sơ người dùng.');
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static bool googleSignInInProgress = false;
  static bool passwordRecoveryInProgress = false;
  static bool passwordRecoveryNavigationHandled = false;

  static bool get isPasswordRecoveryRedirect {
    if (!kIsWeb) return false;
    return Uri.base.fragment.contains('type=recovery') ||
        Uri.base.queryParameters['type'] == 'recovery';
  }

  static const String webClientId =
      '698012966949-fh7theud75hce128gclnmccshs6iaaf8.apps.googleusercontent.com';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: webClientId,
  );

  /// Stream lắng nghe trạng thái đăng nhập tự động
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Lấy User hiện tại từ FirebaseAuth
  User? getCurrentUser() => _auth.currentUser;

  /// Kiểm tra phiên đăng nhập đã lưu trên máy
  /// AC2: Đóng hoàn toàn ứng dụng và mở lại phải tự động vào thẳng màn hình chính nếu phiên đăng nhập còn hạn.
  Future<bool> hasValidSession() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      // Xác thực token và trạng thái tài khoản với Firebase Auth
      await user.reload();
      return _auth.currentUser != null;
    } catch (e) {
      debugPrint('Session expired or invalid: $e');
      await logout();
      return false;
    }
  }

  /// Đăng nhập bằng Google
  /// Hỗ trợ cả Web (signInWithPopup) và Android/iOS (GoogleSignIn)
  Future<UserCredential?> signInWithGoogle() async {
    try {
      UserCredential userCredential;

      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        // Khởi động giao diện Google Sign-In trên thiết bị
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          // Người dùng hủy đăng nhập
          return null;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        debugPrint(
          'Google Sign-In tokens: accessToken=${googleAuth.accessToken != null ? "OK" : "null"}, idToken=${googleAuth.idToken != null ? "OK" : "null"}',
        );

        if (googleAuth.idToken == null && googleAuth.accessToken == null) {
          throw Exception(
            'Không nhận được token xác thực từ Google. Vui lòng kiểm tra cấu hình SHA-1 trên Firebase Console.',
          );
        }

        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await _auth.signInWithCredential(credential);
      }

      return userCredential;
    } catch (e) {
      debugPrint('Google Sign-In Exception: $e');
      rethrow;
    }
  }

  /// Đảm bảo document của user tồn tại trên Firestore (hoặc cập nhật lastLoginAt)
  Future<void> ensureUserDocumentExists(User user) async {
    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        // Lazy Onboarding: Lấy sẵn Tên, Email, Avatar từ Google và vào app ngay
        await docRef.set({
          'id': user.uid,
          'uid': user.uid,
          'name': user.displayName ?? 'Thành viên mới',
          'email': user.email ?? '',
          'avatarUrl': user.photoURL ?? '',
          'avatar_type': 'google',
          'role': null, // Bổ sung sau khi tạo/tham gia gia đình
          'defaultCheckInTime': null, // Giờ check-in mặc định
          'familyId': null,
          'push_token': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
      } else {
        final data = docSnapshot.data() ?? {};
        final Map<String, dynamic> updates = {
          'lastLoginAt': FieldValue.serverTimestamp(),
        };

        if (user.photoURL != null && user.photoURL!.isNotEmpty) {
          updates['avatarUrl'] = user.photoURL;
          updates['avatar_type'] = 'google';
        }
        if ((data['name'] == null || data['name'] == '') &&
            user.displayName != null) {
          updates['name'] = user.displayName;
        }

        await docRef.update(updates);
      }
    } catch (e) {
      debugPrint('Error syncing user document to Firestore: $e');
    }
  }

  /// Lưu mã định danh thông báo của thiết bị (push_token / onesignal_id) vào Firestore
  Future<void> savePushToken(String pushToken) async {
    final user = _auth.currentUser;
    if (user == null || pushToken.isEmpty) return;

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'push_token': pushToken,
        'onesignal_id': pushToken,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('Push token saved to Firestore: $pushToken');
    } catch (e) {
      debugPrint('Error saving push token to Firestore: $e');
    }
  }

  /// Cập nhật thông tin Lazy Onboarding khi người dùng tạo/tham gia gia đình
  /// AC3: Chỉ yêu cầu người dùng bổ sung thông tin (vai vế, giờ check-in mặc định) tại đúng thời điểm
  Future<void> updateLazyOnboardingInfo({
    required String role,
    String? defaultCheckInTime,
    String? familyId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Người dùng chưa đăng nhập');

    final Map<String, dynamic> updateData = {
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (defaultCheckInTime != null && defaultCheckInTime.isNotEmpty) {
      updateData['defaultCheckInTime'] = defaultCheckInTime;
    }
    if (familyId != null && familyId.isNotEmpty) {
      updateData['familyId'] = familyId;
    }

    await _firestore
        .collection('users')
        .doc(user.uid)
        .set(updateData, SetOptions(merge: true));
  }

  /// Lấy thông tin profile chi tiết của User từ Firestore
  Future<UserModel?> getUserProfile([String? uid]) async {
    final targetUid = uid ?? _auth.currentUser?.uid;
    if (targetUid == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(targetUid).get();
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromFirestore(doc.data()!, doc.id);
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      return null;
    }
  }

  /// Đăng xuất: Xóa phiên cả FirebaseAuth và GoogleSignIn để lần sau đổi tài khoản Google khác
  Future<void> logout() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('FirebaseAuth signOut error: $e');
    }

    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        debugPrint('GoogleSignIn signOut error: $e');
      }

      try {
        if (await _googleSignIn.isSignedIn()) {
          await _googleSignIn.disconnect();
        }
      } catch (e) {
        debugPrint('GoogleSignIn disconnect error: $e');
      }
    }
  }

  /// Đăng nhập bằng Email và Mật khẩu
  Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await ensureUserDocumentExists(user);
      }
      return credential;
    } catch (e) {
      debugPrint('loginWithEmail error: $e');
      rethrow;
    }
  }

  /// Đăng ký tài khoản mới bằng Email và Mật khẩu
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        try {
          await user.updateDisplayName(name);
        } catch (e) {
          debugPrint('updateDisplayName error: $e');
        }
        try {
          await _firestore.collection('users').doc(user.uid).set({
            'id': user.uid,
            'uid': user.uid,
            'name': name,
            'email': email,
            'avatarUrl': '',
            'avatar_type': 'default',
            'role': null,
            'defaultCheckInTime': null,
            'familyId': null,
            'push_token': null,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'lastLoginAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Firestore set user document error: $e');
        }
      }
      return credential;
    } catch (e) {
      debugPrint('registerWithEmail error: $e');
      rethrow;
    }
  }

  /// Gửi email đặt lại mật khẩu
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint('resetPassword error: $e');
      rethrow;
    }
  }

  /// Cập nhật mật khẩu mới cho user hiện tại
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }
    try {
      await user.updatePassword(newPassword);
    } catch (e) {
      debugPrint('updatePassword error: $e');
      rethrow;
    }
  }

  /// Hoàn tất đăng ký khi liên kết tài khoản Google
  Future<void> completeGoogleRegistration({
    required User user,
    required String name,
    required String password,
  }) async {
    try {
      if (name.isNotEmpty) {
        try {
          await user.updateDisplayName(name);
        } catch (e) {
          debugPrint('updateDisplayName error: $e');
        }
      }
      // Nếu user muốn liên kết thêm mật khẩu để đăng nhập bằng email sau này
      if (password.isNotEmpty && user.email != null) {
        try {
          final credential = EmailAuthProvider.credential(
            email: user.email!,
            password: password,
          );
          await user.linkWithCredential(credential);
        } catch (linkError) {
          debugPrint('linkWithCredential error (proceeding anyway): $linkError');
        }
      }
      try {
        await _firestore.collection('users').doc(user.uid).set({
          'id': user.uid,
          'uid': user.uid,
          'name': name.isNotEmpty ? name : (user.displayName ?? 'Thành viên mới'),
          'email': user.email ?? '',
          'avatarUrl': user.photoURL ?? '',
          'avatar_type': 'google',
          'role': null,
          'defaultCheckInTime': null,
          'familyId': null,
          'push_token': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore set user document error: $e');
      }
    } catch (e) {
      debugPrint('completeGoogleRegistration error: $e');
      rethrow;
    }
  }

  /// Kiểm tra user profile đã tồn tại trên Firestore
  Future<bool> hasUserProfile(User user) async {
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      return doc.exists;
    } catch (e) {
      debugPrint('hasUserProfile error: $e');
      return false;
    }
  }
}

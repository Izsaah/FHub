import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';

/// Dịch vụ quản lý Thông báo In-app trong Gia đình (Module 6 & Module 7)
/// Lưu trữ tự động 15 ngày trên Firestore để tránh nổ cơ sở dữ liệu
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();
  factory NotificationService() => instance;

  bool get _hasFirebase {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore? get _firestore => _hasFirebase ? FirebaseFirestore.instance : null;

  CollectionReference<Map<String, dynamic>>? _notificationsRef(String familyId) {
    if (_firestore == null) return null;
    return _firestore!
        .collection('families')
        .doc(familyId)
        .collection('notifications');
  }

  /// Gửi một thông báo mới vào Notification Hub của gia đình (Hỗ trợ song ngữ VI / EN)
  Future<NotificationModel?> addNotification({
    required String familyId,
    required String title,
    String? titleEn,
    required String body,
    String? bodyEn,
    required String type,
    String targetUserId = 'ALL',
    Map<String, dynamic>? metadata,
  }) async {
    if (familyId.isEmpty) return null;

    final now = DateTime.now();
    final notifId = 'notif_${now.millisecondsSinceEpoch}_${now.microsecond % 1000}';
    final notif = NotificationModel(
      id: notifId,
      familyId: familyId,
      targetUserId: targetUserId,
      title: title,
      titleEn: titleEn,
      body: body,
      bodyEn: bodyEn,
      type: type,
      isRead: false,
      createdAt: now,
      metadata: metadata,
    );

    if (_notificationsRef(familyId) == null) {
      return notif;
    }

    try {
      await _notificationsRef(familyId)!.doc(notifId).set(notif.toMap());
      // Kích hoạt dọn dẹp các thông báo cũ quá 15 ngày
      unawaited(pruneOldNotifications(familyId));
      return notif;
    } catch (e) {
      debugPrint('NotificationService.addNotification error: $e');
      return notif;
    }
  }

  /// Lắng nghe danh sách thông báo của gia đình trong vòng 15 ngày gần nhất
  Stream<List<NotificationModel>> watchNotifications(
    String familyId, {
    String? currentUserId,
  }) {
    if (familyId.isEmpty || _notificationsRef(familyId) == null) return Stream.value(const []);

    final cutoffDate = DateTime.now().subtract(const Duration(days: 15));

    try {
      return _notificationsRef(familyId)!
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoffDate))
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          return NotificationModel.fromMap(doc.id, doc.data());
        }).where((notif) {
          if (currentUserId == null || currentUserId.isEmpty) return true;
          return notif.targetUserId == 'ALL' || notif.targetUserId == currentUserId;
        }).toList();
      });
    } catch (e) {
      debugPrint('NotificationService.watchNotifications error: $e');
      return Stream.value(const []);
    }
  }

  /// Lắng nghe số lượng thông báo chưa đọc của người dùng hiện tại
  Stream<int> watchUnreadCount(String familyId, {String? currentUserId}) {
    return watchNotifications(familyId, currentUserId: currentUserId).map(
      (list) => list.where((n) => !n.isRead).length,
    );
  }

  /// Đánh dấu 1 thông báo là đã đọc
  Future<void> markAsRead(String familyId, String notificationId) async {
    if (familyId.isEmpty || notificationId.isEmpty || _notificationsRef(familyId) == null) return;
    try {
      await _notificationsRef(familyId)!.doc(notificationId).update({'isRead': true});
    } catch (e) {
      debugPrint('NotificationService.markAsRead error: $e');
    }
  }

  /// Đánh dấu toàn bộ thông báo của người dùng là đã đọc
  Future<void> markAllAsRead(String familyId, {String? currentUserId}) async {
    if (familyId.isEmpty || _notificationsRef(familyId) == null) return;
    try {
      final snap = await _notificationsRef(familyId)!.where('isRead', isEqualTo: false).get();
      final batch = _firestore!.batch();
      for (final doc in snap.docs) {
        final target = doc.data()['targetUserId']?.toString() ?? 'ALL';
        if (currentUserId == null || currentUserId.isEmpty || target == 'ALL' || target == currentUserId) {
          batch.update(doc.reference, {'isRead': true});
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('NotificationService.markAllAsRead error: $e');
    }
  }

  /// Dọn dẹp tự động: Xóa các thông báo cũ hơn 15 ngày để bảo vệ database
  Future<void> pruneOldNotifications(String familyId) async {
    if (familyId.isEmpty || _notificationsRef(familyId) == null) return;
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 15));
      final oldDocs = await _notificationsRef(familyId)!
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .limit(50)
          .get();

      if (oldDocs.docs.isEmpty) return;

      final batch = _firestore!.batch();
      for (final doc in oldDocs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint('NotificationService: Pruned ${oldDocs.docs.length} notifications older than 15 days');
    } catch (e) {
      debugPrint('NotificationService.pruneOldNotifications error: $e');
    }
  }
}

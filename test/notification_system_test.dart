import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/models/notification_model.dart';
import 'package:fhub/Danh/services/notification_service.dart';

void main() {
  group('Notification System Tests (Module 6 & Module 7)', () {
    test('1. NotificationModel serialization toMap and fromMap works seamlessly', () {
      final now = DateTime.now();
      final notif = NotificationModel(
        id: 'notif_1001',
        familyId: 'fam_happy',
        targetUserId: 'ALL',
        title: 'Quỹ Hũ Niềm Vui được nạp thêm',
        body: 'Khoa vừa đóng góp 50.000 đ vào Hũ Niềm Vui!',
        type: 'jackpot_deposit',
        isRead: false,
        createdAt: now,
        metadata: {'amount': 50000, 'member': 'Khoa'},
      );

      final map = notif.toMap();
      expect(map['id'], 'notif_1001');
      expect(map['familyId'], 'fam_happy');
      expect(map['targetUserId'], 'ALL');
      expect(map['title'], contains('Quỹ Hũ'));
      expect(map['isRead'], isFalse);
      expect(map['createdAt'], isA<Timestamp>());
      expect(map['metadata']['amount'], 50000);

      final restored = NotificationModel.fromMap('notif_1001', map);
      expect(restored.id, 'notif_1001');
      expect(restored.familyId, 'fam_happy');
      expect(restored.targetUserId, 'ALL');
      expect(restored.body, contains('Khoa'));
      expect(restored.type, 'jackpot_deposit');
      expect(restored.isRead, isFalse);
      expect(restored.metadata?['amount'], 50000);
    });

    test('2. Unread filtering and user-targeted notifications', () {
      final now = DateTime.now();
      final list = [
        NotificationModel(
          id: 'n1',
          familyId: 'f1',
          targetUserId: 'ALL',
          title: 'Trận chiến Nổ Hũ 30 giây bắt đầu!',
          body: 'Bố vừa phát lệnh!',
          type: 'jackpot_shake',
          isRead: false,
          createdAt: now,
        ),
        NotificationModel(
          id: 'n2',
          familyId: 'f1',
          targetUserId: 'user_child',
          title: 'Thưởng nổ hũ',
          body: 'Bạn nhận được 15.000 đ',
          type: 'jackpot_win',
          isRead: true,
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
        NotificationModel(
          id: 'n3',
          familyId: 'f1',
          targetUserId: 'user_dad',
          title: 'Rút tiền',
          body: 'Đã rút 50.000 đ',
          type: 'wallet_withdraw',
          isRead: false,
          createdAt: now.subtract(const Duration(minutes: 10)),
        ),
      ];

      // For user_child: should see 'ALL' and 'user_child', but NOT 'user_dad'
      final childNotifs = list.where((n) => n.targetUserId == 'ALL' || n.targetUserId == 'user_child').toList();
      expect(childNotifs.length, 2);
      expect(childNotifs.where((n) => !n.isRead).length, 1);

      // For user_dad: should see 'ALL' and 'user_dad'
      final dadNotifs = list.where((n) => n.targetUserId == 'ALL' || n.targetUserId == 'user_dad').toList();
      expect(dadNotifs.length, 2);
      expect(dadNotifs.where((n) => !n.isRead).length, 2);
    });

    test('3. 15-day rolling storage window validation', () {
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(days: 15));

      final recent = NotificationModel(
        id: 'n_recent',
        familyId: 'f1',
        title: 'Gần đây',
        body: 'Vừa xảy ra',
        type: 'system',
        createdAt: now.subtract(const Duration(days: 2)),
      );

      final olderThan15Days = NotificationModel(
        id: 'n_old',
        familyId: 'f1',
        title: 'Cũ',
        body: 'Đã quá 15 ngày',
        type: 'system',
        createdAt: now.subtract(const Duration(days: 16)),
      );

      // Verify cutoff classification
      expect(recent.createdAt.isAfter(cutoff), isTrue);
      expect(olderThan15Days.createdAt.isBefore(cutoff), isTrue);
    });

    test('4. Bilingual notification support (Vietnamese & English localization)', () {
      final notif = NotificationModel(
        id: 'n_bilingual',
        familyId: 'f1',
        title: 'Quỹ Hũ Niềm Vui được nạp thêm',
        titleEn: 'Family Pot Received a Deposit',
        body: 'Khoa vừa đóng góp 20.000 đ vào Hũ Niềm Vui!',
        bodyEn: 'Khoa just deposited 20.000 đ into the Family Pot!',
        type: 'jackpot_deposit',
        createdAt: DateTime.now(),
      );

      // In Vietnamese mode (isEnglish = false)
      expect(notif.localizedTitle(false), 'Quỹ Hũ Niềm Vui được nạp thêm');
      expect(notif.localizedBody(false), contains('Khoa vừa đóng góp'));

      // In English mode (isEnglish = true)
      expect(notif.localizedTitle(true), 'Family Pot Received a Deposit');
      expect(notif.localizedBody(true), contains('Khoa just deposited'));

      // Automatic English fallback for legacy notifications missing titleEn
      final legacyNotif = NotificationModel(
        id: 'n_legacy',
        familyId: 'f1',
        title: 'Trận chiến Nổ Hũ 30 giây bắt đầu!',
        body: 'Cả nhà vào lắc nhận thưởng!',
        type: 'jackpot_shake',
        createdAt: DateTime.now(),
      );
      expect(legacyNotif.localizedTitle(true), contains('30s Pot Shake Battle Has Started!'));
    });

    test('5. Reactive Event Bus & Idempotency Deduplication suppresses rapid duplicate events', () async {
      final notifService = NotificationService.instance;

      NotificationModel? receivedOnBus;
      final sub = notifService.onNotificationDispatched.listen((event) {
        receivedOnBus = event;
      });
      addTearDown(() => sub.cancel());

      // Send first notification
      final first = await notifService.addNotification(
        familyId: 'f_test_bus',
        title: 'Nổ Hũ Test',
        body: 'Thử nghiệm Event Bus',
        type: 'jackpot_shake',
        targetUserId: 'ALL',
      );
      expect(first, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedOnBus?.title, 'Nổ Hũ Test');

      // Send immediate duplicate notification (same family, type, title, target)
      final duplicate = await notifService.addNotification(
        familyId: 'f_test_bus',
        title: 'Nổ Hũ Test',
        body: 'Thử nghiệm Event Bus',
        type: 'jackpot_shake',
        targetUserId: 'ALL',
      );
      // Suppressed by Idempotency Filter
      expect(duplicate, isNull);
    });

    test('6. Resilient Outbox Queue buffers notifications when offline', () async {
      final notifService = NotificationService.instance;
      final initialQueueLength = notifService.outboxQueue.length;

      // When Firebase is not initialized, addNotification buffers to outbox
      final queued = await notifService.addNotification(
        familyId: 'f_offline_test_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Offline Event',
        body: 'Will be buffered in Outbox',
        type: 'system',
      );
      expect(queued, isNotNull);
      expect(notifService.outboxQueue.length, greaterThan(initialQueueLength));
      expect(notifService.outboxQueue.any((n) => n.title == 'Offline Event'), isTrue);
    });
  });
}

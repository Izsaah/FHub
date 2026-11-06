import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Vinh/services/star_economy_service.dart';

void main() {
  group('StarEconomyService - Unit & Integration Tests (Milestone 3)', () {
    late StarEconomyService service;

    setUp(() {
      service = StarEconomyService.inMemory();
      service.resetMockData();
    });

    group('1. Chore Task Approval & Double-Award Protection', () {
      test('1.1 Single chore approval marks task APPROVED, writes ledger reward_{taskId}, and increments balance', () async {
        service.seedMemberBalance('fam_1', 'child_1', 10);
        service.seedTask('chore_wash_dishes', {
          'familyId': 'fam_1',
          'assignedTo': 'child_1',
          'status': 'SUBMITTED',
          'taskStatus': 'SUBMITTED',
          'rewardStars': 5,
        });

        await service.approveTaskWithDoubleAwardProtection(
          taskId: 'chore_wash_dishes',
          reviewerId: 'guardian_dad',
          reviewerName: 'Bố Tuấn',
        );

        final task = service.reminders['chore_wash_dishes'];
        expect(task, isNotNull);
        expect(task!['status'], 'APPROVED');
        expect(task['taskStatus'], 'COMPLETED');
        expect(task['isCompleted'], isTrue);
        expect(task['approvedBy'], 'guardian_dad');
        expect(task['approvedByName'], 'Bố Tuấn');
        expect(task['approvedAt'], isNotNull);

        expect(service.getBalance('fam_1', 'child_1'), 15);

        final ledgerEntry = service.starLedger['reward_chore_wash_dishes'];
        expect(ledgerEntry, isNotNull);
        expect(ledgerEntry!['id'], 'reward_chore_wash_dishes');
        expect(ledgerEntry['amount'], 5);
        expect(ledgerEntry['userId'], 'child_1');
        expect(ledgerEntry['type'], 'TASK_REWARD');
        expect(ledgerEntry['sourceId'], 'chore_wash_dishes');
        expect(ledgerEntry['approvedBy'], 'guardian_dad');
        expect(ledgerEntry['reviewerName'], 'Bố Tuấn');
      });

      test('1.2 Approving an already approved task throws DoubleApprovalException with prior reviewer name', () async {
        service.seedMemberBalance('fam_1', 'child_1', 20);
        service.seedTask('chore_homework', {
          'familyId': 'fam_1',
          'assignedTo': 'child_1',
          'status': 'APPROVED',
          'approvedByName': 'Mẹ Lan',
          'approvedBy': 'guardian_mom',
          'rewardStars': 10,
        });

        expect(
          () => service.approveTaskWithDoubleAwardProtection(
            taskId: 'chore_homework',
            reviewerId: 'guardian_dad',
            reviewerName: 'Bố Tuấn',
          ),
          throwsA(isA<DoubleApprovalException>().having(
            (e) => e.message,
            'message',
            contains('Mẹ Lan'),
          )),
        );

        // Balance remains unchanged
        expect(service.getBalance('fam_1', 'child_1'), 20);
      });

      test('1.3 Approving a task whose reward docId already exists throws DoubleApprovalException', () async {
        service.seedMemberBalance('fam_1', 'child_1', 10);
        service.seedTask('chore_clean_room', {
          'familyId': 'fam_1',
          'assignedTo': 'child_1',
          'status': 'SUBMITTED',
          'rewardStars': 5,
        });
        service.starLedger['reward_chore_clean_room'] = {
          'id': 'reward_chore_clean_room',
          'amount': 5,
          'type': 'TASK_REWARD',
        };

        expect(
          () => service.approveTaskWithDoubleAwardProtection(
            taskId: 'chore_clean_room',
            reviewerId: 'guardian_dad',
            reviewerName: 'Bố Tuấn',
          ),
          throwsA(isA<DoubleApprovalException>().having(
            (e) => e.message,
            'message',
            contains('DOUBLE_APPROVAL_DETECTED'),
          )),
        );

        expect(service.getBalance('fam_1', 'child_1'), 10);
      });

      test('1.4 Approving non-existent task throws TaskNotFoundException', () async {
        expect(
          () => service.approveTaskWithDoubleAwardProtection(
            taskId: 'non_existent_chore',
            reviewerId: 'guardian_dad',
            reviewerName: 'Bố Tuấn',
          ),
          throwsA(isA<TaskNotFoundException>().having(
            (e) => e.message,
            'message',
            contains('Công việc không tồn tại'),
          )),
        );
      });

      test('1.5 Concurrent double-approval race: exactly one succeeds and second throws DoubleApprovalException', () async {
        service.seedMemberBalance('fam_1', 'child_1', 10);
        service.seedTask('chore_water_plants', {
          'familyId': 'fam_1',
          'assignedTo': 'child_1',
          'status': 'SUBMITTED',
          'rewardStars': 8,
        });

        final results = await Future.wait([
          service
              .approveTaskWithDoubleAwardProtection(
                taskId: 'chore_water_plants',
                reviewerId: 'guardian_dad',
                reviewerName: 'Bố Tuấn',
              )
              .then((_) => 'success')
              .catchError((e) => 'error: $e'),
          service
              .approveTaskWithDoubleAwardProtection(
                taskId: 'chore_water_plants',
                reviewerId: 'guardian_mom',
                reviewerName: 'Mẹ Lan',
              )
              .then((_) => 'success')
              .catchError((e) => 'error: $e'),
          service
              .approveTaskWithDoubleAwardProtection(
                taskId: 'chore_water_plants',
                reviewerId: 'grandpa',
                reviewerName: 'Ông Nội',
              )
              .then((_) => 'success')
              .catchError((e) => 'error: $e'),
        ]);

        final successCount = results.where((r) => r == 'success').length;
        final errorCount = results.where((r) => r.startsWith('error:')).length;

        expect(successCount, 1);
        expect(errorCount, 2);
        // Only 1 award credited (10 + 8 = 18)
        expect(service.getBalance('fam_1', 'child_1'), 18);
      });

      test('1.6 Task with 0 reward stars is approved without negative side effects', () async {
        service.seedMemberBalance('fam_1', 'child_1', 50);
        service.seedTask('chore_zero_star', {
          'familyId': 'fam_1',
          'assignedTo': 'child_1',
          'status': 'SUBMITTED',
          'rewardStars': 0,
        });

        await service.approveTaskWithDoubleAwardProtection(
          taskId: 'chore_zero_star',
          reviewerId: 'guardian_dad',
          reviewerName: 'Bố Tuấn',
        );

        expect(service.reminders['chore_zero_star']!['status'], 'APPROVED');
        expect(service.getBalance('fam_1', 'child_1'), 50);
        expect(service.starLedger['reward_chore_zero_star']!['amount'], 0);
      });
    });

    group('2. Wishlist Redemption & Double-Spending Protection', () {
      test('2.1 Valid wishlist claim deducts balance and writes negative ledger claim_{claimId}', () async {
        service.seedMemberBalance('fam_1', 'child_1', 30);

        await service.claimWishlistItem(
          claimId: 'claim_lego_city',
          familyId: 'fam_1',
          userId: 'child_1',
          cost: 20,
          itemName: 'Bộ xếp hình Lego City',
        );

        expect(service.getBalance('fam_1', 'child_1'), 10);
        final ledgerEntry = service.starLedger['claim_claim_lego_city'];
        expect(ledgerEntry, isNotNull);
        expect(ledgerEntry!['amount'], -20);
        expect(ledgerEntry['type'], 'WISHLIST_CLAIM');
        expect(ledgerEntry['claimId'], 'claim_lego_city');
        expect(ledgerEntry['itemName'], 'Bộ xếp hình Lego City');
      });

      test('2.2 Claim with insufficient stars throws InsufficientStarsException and preserves balance', () async {
        service.seedMemberBalance('fam_1', 'child_1', 15);

        expect(
          () => service.claimWishlistItem(
            claimId: 'claim_nintendo_switch',
            familyId: 'fam_1',
            userId: 'child_1',
            cost: 100,
            itemName: 'Máy chơi game Nintendo',
          ),
          throwsA(isA<InsufficientStarsException>().having(
            (e) => e.message,
            'message',
            contains('INSUFFICIENT_STARS'),
          )),
        );

        expect(service.getBalance('fam_1', 'child_1'), 15);
        expect(service.starLedger.containsKey('claim_claim_nintendo_switch'), isFalse);
      });

      test('2.3 Exact balance claim succeeds and leaves balance at exactly 0', () async {
        service.seedMemberBalance('fam_1', 'child_1', 25);

        await service.claimWishlistItem(
          claimId: 'claim_exact_cost',
          familyId: 'fam_1',
          userId: 'child_1',
          cost: 25,
          itemName: 'Balo đi học',
        );

        expect(service.getBalance('fam_1', 'child_1'), 0);
        expect(service.starLedger['claim_claim_exact_cost']!['amount'], -25);
      });

      test('2.4 Invalid cost (<= 0) throws ArgumentError', () async {
        service.seedMemberBalance('fam_1', 'child_1', 50);

        expect(
          () => service.claimWishlistItem(
            claimId: 'claim_invalid_0',
            familyId: 'fam_1',
            userId: 'child_1',
            cost: 0,
            itemName: 'Miễn phí',
          ),
          throwsArgumentError,
        );

        expect(
          () => service.claimWishlistItem(
            claimId: 'claim_invalid_neg',
            familyId: 'fam_1',
            userId: 'child_1',
            cost: -10,
            itemName: 'Âm sao',
          ),
          throwsArgumentError,
        );

        expect(service.getBalance('fam_1', 'child_1'), 50);
      });

      test('2.5 Duplicate claimId throws StateError and does not double-debit', () async {
        service.seedMemberBalance('fam_1', 'child_1', 40);

        await service.claimWishlistItem(
          claimId: 'claim_robot_dup',
          familyId: 'fam_1',
          userId: 'child_1',
          cost: 10,
          itemName: 'Robot Mini',
        );
        expect(service.getBalance('fam_1', 'child_1'), 30);

        expect(
          () => service.claimWishlistItem(
            claimId: 'claim_robot_dup',
            familyId: 'fam_1',
            userId: 'child_1',
            cost: 10,
            itemName: 'Robot Mini',
          ),
          throwsStateError,
        );

        // Balance not debited a second time
        expect(service.getBalance('fam_1', 'child_1'), 30);
      });

      test('2.6 Concurrent double-spending race: 2 claims of 15 stars with 20 star balance permits only 1', () async {
        service.seedMemberBalance('fam_1', 'child_1', 20);

        final results = await Future.wait([
          service
              .claimWishlistItem(
                claimId: 'claim_race_a',
                familyId: 'fam_1',
                userId: 'child_1',
                cost: 15,
                itemName: 'Món quà A',
              )
              .then((_) => 'success')
              .catchError((e) => 'error: $e'),
          service
              .claimWishlistItem(
                claimId: 'claim_race_b',
                familyId: 'fam_1',
                userId: 'child_1',
                cost: 15,
                itemName: 'Món quà B',
              )
              .then((_) => 'success')
              .catchError((e) => 'error: $e'),
        ]);

        final successCount = results.where((r) => r == 'success').length;
        final errorCount = results.where((r) => r.startsWith('error:')).length;

        expect(successCount, 1);
        expect(errorCount, 1);
        expect(service.getBalance('fam_1', 'child_1'), 5);
      });
    });

    group('3. Wishlist Claim Refund (Physical Gift Rejection)', () {
      test('3.1 Guardian gift rejection refunds stars and creates positive ledger doc refund_{claimId}', () async {
        service.seedMemberBalance('fam_1', 'child_1', 20);

        await service.claimWishlistItem(
          claimId: 'claim_drone_mini',
          familyId: 'fam_1',
          userId: 'child_1',
          cost: 15,
          itemName: 'Flycam Mini',
        );
        expect(service.getBalance('fam_1', 'child_1'), 5);

        // Guardian rejects physical purchase -> refunds stars
        await service.refundWishlistClaim(
          claimId: 'claim_drone_mini',
          familyId: 'fam_1',
          userId: 'child_1',
          refundStars: 15,
          reason: 'Hết hàng tại nhà sách',
        );

        expect(service.getBalance('fam_1', 'child_1'), 20);
        final refundEntry = service.starLedger['refund_claim_drone_mini'];
        expect(refundEntry, isNotNull);
        expect(refundEntry!['amount'], 15);
        expect(refundEntry['type'], 'CLAIM_REFUND');
        expect(refundEntry['reason'], 'Hết hàng tại nhà sách');
      });

      test('3.2 Re-refunding already refunded claimId throws StateError and does not duplicate stars', () async {
        service.seedMemberBalance('fam_1', 'child_1', 10);

        await service.refundWishlistClaim(
          claimId: 'claim_refund_once',
          familyId: 'fam_1',
          userId: 'child_1',
          refundStars: 10,
        );
        expect(service.getBalance('fam_1', 'child_1'), 20);

        expect(
          () => service.refundWishlistClaim(
            claimId: 'claim_refund_once',
            familyId: 'fam_1',
            userId: 'child_1',
            refundStars: 10,
          ),
          throwsStateError,
        );

        expect(service.getBalance('fam_1', 'child_1'), 20);
      });

      test('3.3 Invalid refundStars (<= 0) throws ArgumentError', () async {
        expect(
          () => service.refundWishlistClaim(
            claimId: 'claim_bad_refund',
            familyId: 'fam_1',
            userId: 'child_1',
            refundStars: 0,
          ),
          throwsArgumentError,
        );

        expect(
          () => service.refundWishlistClaim(
            claimId: 'claim_bad_refund_2',
            familyId: 'fam_1',
            userId: 'child_1',
            refundStars: -5,
          ),
          throwsArgumentError,
        );
      });
    });

    group('4. Service Identity & Exceptions Hierarchy', () {
      test('4.1 InsufficientStarsException satisfies both StateError and Exception contracts', () {
        final err = InsufficientStarsException('Test message');
        expect(err, isA<StateError>());
        expect(err, isA<Exception>());
        expect(err.toString(), contains('InsufficientStarsException: Test message'));
      });

      test('4.2 DoubleApprovalException satisfies both StateError and Exception contracts', () {
        final err = DoubleApprovalException('Double approval');
        expect(err, isA<StateError>());
        expect(err, isA<Exception>());
        expect(err.toString(), contains('DoubleApprovalException: Double approval'));
      });

      test('4.3 TaskNotFoundException satisfies both StateError and Exception contracts', () {
        final err = TaskNotFoundException();
        expect(err, isA<StateError>());
        expect(err, isA<Exception>());
        expect(err.toString(), contains('TaskNotFoundException: Công việc không tồn tại'));
      });

      test('4.4 Singleton vs inMemory isolation', () {
        final s1 = StarEconomyService();
        final s2 = StarEconomyService.instance;
        expect(identical(s1, s2), isTrue);

        final sMem = StarEconomyService.inMemory();
        expect(identical(s1, sMem), isFalse);
      });
    });
  });
}

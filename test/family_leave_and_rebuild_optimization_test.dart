import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/danh_payment_entry.dart';
import 'package:fhub/Danh/services/family_jackpot_service.dart';
import 'package:fhub/Danh/services/payment_service.dart';
import 'package:fhub/Long/services/family_data_service.dart';

void main() {
  group('Family Leave & Background Listener Optimization Tests', () {
    test('FamilyJackpotService.clearFamily cleanly wipes state and cancels listeners', () {
      final jackpot = FamilyJackpotService.instance;
      // Initialize with test id
      jackpot.initForFamily('test_fam_123');
      expect(jackpot.jackpot.familyId, 'test_fam_123');

      // Clear family context
      jackpot.clearFamily();
      expect(jackpot.jackpot.familyId, '');
      expect(jackpot.totalFamilyMembersCount, 1);
      expect(jackpot.shakeVotes.isEmpty, isTrue);
      expect(jackpot.scheduledShakeTime, isNull);
    });

    test('PaymentService.clearFamily triggers FamilyJackpotService.clearFamily', () {
      final payment = PaymentService();
      final jackpot = FamilyJackpotService.instance;

      jackpot.initForFamily('fam_old_456');
      expect(jackpot.jackpot.familyId, 'fam_old_456');

      payment.clearFamily();
      expect(payment.currentFamilyId, '');
      expect(jackpot.jackpot.familyId, '');
    });

    test('DanhPaymentEntry.clearFamilyContext clears both services simultaneously', () {
      final jackpot = FamilyJackpotService.instance;
      jackpot.initForFamily('fam_to_leave');

      DanhPaymentEntry.clearFamilyContext();
      expect(DanhPaymentEntry.service.currentFamilyId, '');
      expect(jackpot.jackpot.familyId, '');
    });

    test('FamilyDataService.resetAll invokes clearFamilyContext and clears family pointers', () {
      final dataService = FamilyDataService();
      dataService.resetAll();

      expect(dataService.selectedFamilyId, isNull);
      expect(dataService.selectedFamilyIdNotifier.value, isNull);
      expect(DanhPaymentEntry.service.currentFamilyId, '');
      expect(FamilyJackpotService.instance.jackpot.familyId, '');
    });
  });
}

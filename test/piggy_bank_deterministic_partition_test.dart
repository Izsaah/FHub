import 'package:flutter_test/flutter_test.dart';
import 'package:fhub/Danh/services/jackpot_algorithm.dart';

void main() {
  group('Phase 4 (Module A) - Piggy Bank Deterministic Partition Tests', () {
    test('4.1 Invariant: sum(shares) == totalPot and no star leakage/creation', () {
      final checkins = {
        'dad': 25,
        'mom': 18,
        'child_1': 10,
        'child_2': 5,
        'child_3': 3,
      };
      final children = ['child_1', 'child_2', 'child_3'];
      const totalPot = 100;

      final shares = JackpotAlgorithm.computeDeterministicPartition(
        totalPot: totalPot,
        checkinCounts: checkins,
        childUids: children,
      );

      final totalAllocated = shares.values.fold(0, (a, b) => a + b);
      expect(totalAllocated, totalPot);
      expect(shares.length, 3);
    });

    test('4.2 Parents strictly excluded: Dad and Mom never receive star shares', () {
      final checkins = {
        'dad_super_shaker': 100,
        'mom_daily_active': 80,
        'child_bo': 10,
        'child_bi': 5,
      };
      final children = ['child_bo', 'child_bi'];
      const totalPot = 200;

      final shares = JackpotAlgorithm.computeDeterministicPartition(
        totalPot: totalPot,
        checkinCounts: checkins,
        childUids: children,
      );

      expect(shares.containsKey('dad_super_shaker'), false);
      expect(shares.containsKey('mom_daily_active'), false);
      expect(shares.containsKey('child_bo'), true);
      expect(shares.containsKey('child_bi'), true);
      expect(shares.values.fold(0, (a, b) => a + b), totalPot);
    });

    test('4.3 60% Effort & 40% Lucky Pool deterministic distribution', () {
      // 100 stars: Effort = 60, Lucky = 40
      // child_A: 10 checkins (100% of child checkins)
      // child_B: 0 checkins
      final checkins = {
        'child_A': 10,
        'child_B': 0,
      };
      final children = ['child_A', 'child_B'];
      const totalPot = 100;

      final shares = JackpotAlgorithm.computeDeterministicPartition(
        totalPot: totalPot,
        checkinCounts: checkins,
        childUids: children,
      );

      // child_A gets: 60 (effort) + 20 (lucky) = 80
      // child_B gets: 0 (effort) + 20 (lucky) = 20
      expect(shares['child_A'], 80);
      expect(shares['child_B'], 20);
      expect(shares['child_A']! + shares['child_B']!, 100);
    });

    test('4.4 Zero child check-ins fallback: splits pot evenly among children', () {
      final checkins = {
        'child_1': 0,
        'child_2': 0,
      };
      final children = ['child_1', 'child_2'];
      const totalPot = 100;

      final shares = JackpotAlgorithm.computeDeterministicPartition(
        totalPot: totalPot,
        checkinCounts: checkins,
        childUids: children,
      );

      expect(shares['child_1'], 50);
      expect(shares['child_2'], 50);
      expect(shares.values.fold(0, (a, b) => a + b), 100);
    });

    test('4.5 Remainder tie-breaking: deterministic remainder distribution', () {
      // 101 stars with 2 children equal checkins: remainder of 1 star goes to child_1 (alphabetical tie-break)
      final checkins = {
        'child_1': 5,
        'child_2': 5,
      };
      final children = ['child_1', 'child_2'];
      const totalPot = 101;

      final shares = JackpotAlgorithm.computeDeterministicPartition(
        totalPot: totalPot,
        checkinCounts: checkins,
        childUids: children,
      );

      expect(shares.values.fold(0, (a, b) => a + b), 101);
      expect(shares['child_1']!, shares['child_2']! + 1);
    });

    test('4.6 Defensive Guards: Empty children or non-positive pot returns empty map', () {
      expect(
        JackpotAlgorithm.computeDeterministicPartition(
          totalPot: 100,
          checkinCounts: {'child_1': 5},
          childUids: [],
        ),
        isEmpty,
      );

      expect(
        JackpotAlgorithm.computeDeterministicPartition(
          totalPot: 0,
          checkinCounts: {'child_1': 5},
          childUids: ['child_1'],
        ),
        isEmpty,
      );

      expect(
        JackpotAlgorithm.computeDeterministicPartition(
          totalPot: -50,
          checkinCounts: {'child_1': 5},
          childUids: ['child_1'],
        ),
        isEmpty,
      );
    });
  });
}

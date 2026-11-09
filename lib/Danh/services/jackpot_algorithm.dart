import 'dart:math';

/// Kết quả tính toán phân bổ giải thưởng sau 30s nổ hũ
class JackpotDistributionResult {
  final Map<String, int> prizes; // {userId: số tiền VND nhận được}
  final String? topShakerId; // Người lắc nhiều nhất
  final int topShakeCount;
  final String? firstPrizeWinnerId; // Người trúng giải nhất
  final bool isTopShakerUnlucky; // Người lắc nhiều nhất nhưng trượt giải nhất -> BẬT ẢNH Ý TRỜI

  const JackpotDistributionResult({
    required this.prizes,
    this.topShakerId,
    this.topShakeCount = 0,
    this.firstPrizeWinnerId,
    this.isTopShakerUnlucky = false,
  });
}

/// Thuật toán chia giải thưởng Hũ Niềm Vui Gia Đình
/// - Nguyên tắc Lắc Tay: Chỉ những thành viên CÓ THAM GIA LẮC (shakeCount > 0) mới được chia tiền thưởng!
///   + Thành viên KHÔNG LẮC (shakeCount == 0): Tuyệt đối KHÔNG ĐƯỢC NHẬN TIỀN THƯỞNG (0 VNĐ).
/// - Cơ chế quay thưởng có trọng số vé:
///   + Mỗi lần lắc = đúng +1 vé cơ hội may mắn.
///   + Nếu chỉ có đúng 1 người lắc: Người đó nhận trọn vẹn 100% quỹ hũ A (không bị chia bớt cho người không lắc).
///   + Nếu nhiều người cùng lắc (>0): Tỷ lệ trúng Giải Nhất tỷ lệ thuận với số lần lắc của mỗi người.
///     Người lắc nhiều nhất có xác suất cao nhất, nhưng người lắc ít hơn vẫn có cơ hội lật kèo may mắn ("Ý Trời")!
///   + Nếu người lắc nhiều nhất bị người lắc ít hơn lật kèo -> Bật poster kỷ niệm "Ý Trời" cho người lắc nhiều nhất.
/// - Phân bổ giải thưởng bậc thang cho các thành viên CÓ LẮC (active):
///   + K = 1: Nhận trọn 100% của A
///   + K = 2: Giải 1 nhận 3/4 A (75%), Giải 2 nhận 1/4 A (25%)
///   + K >= 3: Giải 1 nhận 3/4 A, Giải 2 nhận 3/5 phần còn lại, Giải 3 trở đi chia tiếp, người thứ K nhận toàn bộ phần dư để tổng = 100% A.
class JackpotAlgorithm {
  JackpotAlgorithm._();

  static JackpotDistributionResult calculate({
    required int totalAmount, // Quỹ A
    required Map<String, int> shakeCounts, // {userId: count}
    required List<String> participantIds,
  }) {
    final uniqueParticipants = participantIds.where((id) => id.isNotEmpty).toSet().toList();
    if (totalAmount <= 0 || uniqueParticipants.isEmpty) {
      return const JackpotDistributionResult(prizes: {});
    }

    // 1. Chỉ lọc những thành viên THỰC SỰ CÓ LẮC (shakeCount > 0)
    final List<String> activeParticipants = [];
    for (final uid in uniqueParticipants) {
      final count = max(0, shakeCounts[uid] ?? 0);
      if (count > 0) {
        activeParticipants.add(uid);
      }
    }

    // Nếu không ai lắc trong suốt 30s -> Trả về kết quả rỗng (Hũ được bảo toàn để chơi lại)
    if (activeParticipants.isEmpty) {
      return const JackpotDistributionResult(prizes: {});
    }

    final rand = Random();

    // 2. Xác định quán quân lắc tay (Top Shaker - người lắc nhiều nhất)
    String? topShakerId;
    int maxShakes = 0;
    for (final uid in activeParticipants) {
      final s = shakeCounts[uid] ?? 0;
      if (s > maxShakes) {
        maxShakes = s;
        topShakerId = uid;
      }
    }

    final List<String> rankedUids = [];

    // 3. Rút thăm thứ hạng cho các thành viên CÓ LẮC ĐIỆN THOẠI:
    if (activeParticipants.length == 1) {
      // Chỉ duy nhất 1 người lắc -> Người đó 100% nhận Giải Nhất
      rankedUids.add(activeParticipants.first);
    } else {
      final remainingActives = List<String>.from(activeParticipants);

      while (remainingActives.isNotEmpty) {
        int totalTickets = 0;
        for (final uid in remainingActives) {
          totalTickets += max(1, shakeCounts[uid] ?? 1);
        }

        int winningTicket = rand.nextInt(max(1, totalTickets));
        String chosenUid = remainingActives.first;

        for (final uid in remainingActives) {
          final weight = max(1, shakeCounts[uid] ?? 1);
          if (winningTicket < weight) {
            chosenUid = uid;
            break;
          }
          winningTicket -= weight;
        }

        rankedUids.add(chosenUid);
        remainingActives.remove(chosenUid);
      }
    }

    // TUYỆT ĐỐI KHÔNG thêm thành viên 0 lần lắc vào rankedUids!
    // Người không lắc thì nhận 0 VNĐ.

    final String? firstPrizeWinnerId = rankedUids.isNotEmpty ? rankedUids.first : null;

    // Kích hoạt Sự kiện Ý Trời: Có người lắc nhiều nhất nhưng bị người lắc ít hơn giật Giải Nhất
    final bool isTopShakerUnlucky = (topShakerId != null &&
        firstPrizeWinnerId != null &&
        topShakerId != firstPrizeWinnerId &&
        maxShakes > 0);

    // 4. Phân chia tiền thưởng bậc thang cho những thành viên CÓ LẮC từ tổng quỹ A:
    final Map<String, int> prizes = {};
    final int n = rankedUids.length;
    int remaining = totalAmount;

    for (int i = 0; i < n; i++) {
      final uid = rankedUids[i];

      // Nếu chỉ có 1 người hoặc là người cuối cùng -> nhận toàn bộ phần còn lại để tổng = 100% A
      if (i == n - 1) {
        prizes[uid] = max(0, remaining);
        remaining = 0;
        break;
      }

      double ratio;
      if (i == 0) {
        ratio = 3.0 / 4.0; // Giải Nhất: 3/4 của A (75%)
      } else if (i == 1) {
        ratio = 3.0 / 5.0; // Giải Nhì: 3/5 của phần còn lại
      } else {
        ratio = 3.0 / 4.0; // Giải Ba trở đi: 3/4 của phần còn lại
      }

      int rawPrize = (remaining * ratio).round();
      int roundedPrize = _roundFriendly(rawPrize, remaining, n - i - 1);
      prizes[uid] = roundedPrize;
      remaining -= roundedPrize;
    }

    // Đảm bảo cân đối tuyệt đối 100% tổng quỹ A (chống chênh lệch làm tròn)
    final int sumPrizes = prizes.values.fold(0, (acc, v) => acc + v);
    final int diff = totalAmount - sumPrizes;
    if (diff != 0 && rankedUids.isNotEmpty) {
      final firstUid = rankedUids.first;
      prizes[firstUid] = (prizes[firstUid] ?? 0) + diff;
    }

    return JackpotDistributionResult(
      prizes: prizes,
      topShakerId: topShakerId,
      topShakeCount: maxShakes > 0 ? maxShakes : 0,
      firstPrizeWinnerId: firstPrizeWinnerId,
      isTopShakerUnlucky: isTopShakerUnlucky,
    );
  }

  /// Làm tròn hợp lý (hỗ trợ cả Hũ Sao nhỏ < 1000 sao và Hũ lớn >= 1000) mà vẫn chừa tối thiểu 1 đơn vị cho mỗi người phía sau
  static int _roundFriendly(int val, int available, int membersLeftAfterThis) {
    int result = val;
    if (available >= 1000) {
      if (val >= 10000) {
        result = (val ~/ 500) * 500;
      } else if (val >= 1000) {
        result = (val ~/ 100) * 100;
      }
      final int maxAllowed = available - (membersLeftAfterThis * 100);
      if (maxAllowed > 0 && result > maxAllowed) {
        result = maxAllowed;
      }
      return max(0, result);
    } else {
      // Chế độ Hũ Sao (< 1000 sao): Chừa ít nhất 1 sao cho mỗi thành viên có lắc phía sau nếu quỹ đủ
      final int maxAllowed = available - membersLeftAfterThis;
      if (maxAllowed > 0 && result > maxAllowed) {
        result = maxAllowed;
      }
      return max(0, result);
    }
  }

  /// Thuật toán phân bổ sao Heo Đất Gia Đình tất định (Deterministic Partition):
  /// - 60% Effort Pool (chia theo tỷ lệ đóng góp điểm danh của con).
  /// - 40% Lucky Pool (chia đều cho tất cả các con tham gia).
  /// - Phần dư làm tròn (remainder): phân bổ cho con có đóng góp cao nhất (tie-break theo UID tăng dần).
  /// - BẢO ĐẢM CÁC BẤT BIẾN (INVARIANTS):
  ///   1. Phụ huynh (Bố, Mẹ) tuyệt đối KHÔNG nhận sao từ heo (chỉ con cái trong [childUids] mới được nhận).
  ///   2. Tổng sao phân bổ = đúng 100% totalPot (không sinh sao ảo, không thất thoát sao).
  ///   3. Không âm, hoạt động ngoại tuyến không cần mạng.
  static Map<String, int> computeDeterministicPartition({
    required int totalPot,
    required Map<String, int> checkinCounts,
    required List<String> childUids,
    String settlementId = 'default',
  }) {
    if (totalPot <= 0 || childUids.isEmpty) {
      return {};
    }

    final uniqueChildren =
        childUids.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (uniqueChildren.isEmpty) return {};

    // 1. Lọc chỉ lấy checkin của các con (loại trừ bố mẹ khỏi danh sách nhận sao)
    final validCheckins = <String, int>{};
    for (final cid in uniqueChildren) {
      validCheckins[cid] = max(0, checkinCounts[cid] ?? 0);
    }

    final totalChildCheckins =
        validCheckins.values.fold(0, (a, b) => a + b);

    // 2. Tách Quỹ: 60% Effort + 40% Lucky
    final effortPool = (totalPot * 0.6).round();
    final luckyPool = totalPot - effortPool;

    final shares = <String, int>{};

    // 3. Phân bổ Effort Pool:
    if (totalChildCheckins == 0) {
      final base = effortPool ~/ uniqueChildren.length;
      for (final cid in uniqueChildren) {
        shares[cid] = (shares[cid] ?? 0) + base;
      }
    } else {
      for (final cid in uniqueChildren) {
        final share =
            ((validCheckins[cid]! / totalChildCheckins) * effortPool).floor();
        shares[cid] = (shares[cid] ?? 0) + share;
      }
    }

    // 4. Phân bổ Lucky Pool: Chia đều cho tất cả con
    final baseLucky = luckyPool ~/ uniqueChildren.length;
    for (final cid in uniqueChildren) {
      shares[cid] = (shares[cid] ?? 0) + baseLucky;
    }

    // 5. Cân đối phần dư (Remainder) do làm tròn -> Trao cho con đóng góp cao nhất
    final currentSum = shares.values.fold(0, (a, b) => a + b);
    int remainder = totalPot - currentSum;

    if (remainder > 0) {
      final sortedChildren = List<String>.from(uniqueChildren)
        ..sort((a, b) {
          final diff =
              (validCheckins[b] ?? 0).compareTo(validCheckins[a] ?? 0);
          if (diff != 0) return diff;
          return a.compareTo(b);
        });

      int idx = 0;
      while (remainder > 0 && sortedChildren.isNotEmpty) {
        final target = sortedChildren[idx % sortedChildren.length];
        shares[target] = (shares[target] ?? 0) + 1;
        remainder--;
        idx++;
      }
    }

    return shares;
  }
}

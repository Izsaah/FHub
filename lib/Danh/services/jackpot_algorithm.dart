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

  /// Làm tròn số tiền hợp lý mà vẫn chừa đủ phần dư cho những thành viên phía sau
  static int _roundFriendly(int val, int available, int membersLeftAfterThis) {
    int result = val;
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
  }
}

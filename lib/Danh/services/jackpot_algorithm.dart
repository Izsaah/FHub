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
/// - Rút thăm có trọng số (Weighted Lottery): Mỗi thành viên có vé cơ bản + mỗi lần lắc thêm 1 cơ hội (+1 vé).
///   Người lắc nhiều nhất có xác suất trúng cao nhất nhưng vẫn có kịch tính "Ý Trời"!
/// - Phân bổ giải thưởng theo bậc thang luỹ tiến từ tổng quỹ A:
///   + Giải 1 (Cao nhất): 3/4 của A (75% A), phần còn lại là R1 = 1/4 A
///   + Giải 2: 3/5 của phần còn lại R1, dư ra "2 phần còn lại" R2 = 2/5 R1
///   + Giải 3: 3/4 của 2 phần còn lại R2, dư ra R3 = 1/4 R2
///   + Các thành viên tiếp theo: Chia bậc thang phần dư còn lại, người cuối nhận trọn phần dư
///     để ĐẢM BẢO TỔNG TIỀN CHIA RA BẰNG ĐÚNG 100% TỔNG QUỸ A (không thừa, không thiếu 1 đồng).
class JackpotAlgorithm {
  JackpotAlgorithm._();

  static const int _baseTicketsPerMember = 8;

  static JackpotDistributionResult calculate({
    required int totalAmount, // Quỹ A
    required Map<String, int> shakeCounts, // {userId: count}
    required List<String> participantIds,
  }) {
    final uniqueParticipants = participantIds.where((id) => id.isNotEmpty).toSet().toList();
    if (totalAmount <= 0 || uniqueParticipants.isEmpty) {
      return const JackpotDistributionResult(prizes: {});
    }

    final rand = Random();

    // 1. Xác định người lắc nhiều nhất nhà (Quán Quân Lắc Tay)
    String? topShakerId;
    int maxShakes = -1;
    for (final uid in uniqueParticipants) {
      final s = shakeCounts[uid] ?? 0;
      if (s > maxShakes) {
        maxShakes = s;
        topShakerId = uid;
      }
    }
    if (maxShakes <= 0) topShakerId = null;

    // 2. Rút thăm thứ hạng không hoàn lại theo số vé cơ hội:
    // Mỗi người có _baseTicketsPerMember vé nền + 1 vé cho mỗi lần lắc điện thoại.
    final Map<String, int> ticketPool = {
      for (final uid in uniqueParticipants)
        uid: _baseTicketsPerMember + max(0, shakeCounts[uid] ?? 0),
    };

    final List<String> rankedUids = [];
    final remainingCandidates = List<String>.from(uniqueParticipants);

    while (remainingCandidates.isNotEmpty) {
      int totalTickets = 0;
      for (final uid in remainingCandidates) {
        totalTickets += ticketPool[uid] ?? 1;
      }

      int winningTicket = rand.nextInt(max(1, totalTickets));
      String chosenUid = remainingCandidates.first;

      for (final uid in remainingCandidates) {
        final weight = ticketPool[uid] ?? 1;
        if (winningTicket < weight) {
          chosenUid = uid;
          break;
        }
        winningTicket -= weight;
      }

      rankedUids.add(chosenUid);
      remainingCandidates.remove(chosenUid);
    }

    final String? firstPrizeWinnerId = rankedUids.isNotEmpty ? rankedUids.first : null;

    // Kiểm tra xem người lắc nhiều nhất có bị trượt Giải Nhất không (kích hoạt Poster Ý Trời)
    final bool isTopShakerUnlucky = (topShakerId != null &&
        firstPrizeWinnerId != null &&
        topShakerId != firstPrizeWinnerId &&
        maxShakes > 0);

    // 3. Phân chia tiền thưởng bậc thang từ quỹ A:
    // Giải 1: 3/4 của A -> Giải 2: 3/5 phần còn lại -> Giải 3+: 3/4 của phần còn lại -> Người cuối nhận hết phần dư
    final Map<String, int> prizes = {};
    final int n = rankedUids.length;
    int remaining = totalAmount;

    for (int i = 0; i < n; i++) {
      final uid = rankedUids[i];

      // Người cuối cùng trong danh sách nhận toàn bộ phần tiền còn lại để tổng = 100% A
      if (i == n - 1) {
        prizes[uid] = max(0, remaining);
        remaining = 0;
        break;
      }

      double ratio;
      if (i == 0) {
        ratio = 3.0 / 4.0; // Giải nhiều nhất: 3/4 của A
      } else if (i == 1) {
        ratio = 3.0 / 5.0; // Giải nhì: 3/5 của phần còn lại (chừa lại 2 phần)
      } else {
        ratio = 3.0 / 4.0; // Giải ba trở đi: 3/4 của 2 phần còn lại
      }

      int rawPrize = (remaining * ratio).round();
      int roundedPrize = _roundFriendly(rawPrize, remaining, n - i - 1);
      prizes[uid] = roundedPrize;
      remaining -= roundedPrize;
    }

    // Đảm bảo cân đối tuyệt đối 100% tổng quỹ A
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
    // Đảm bảo những người phía sau luôn có ít nhất tiền thưởng dương
    final int maxAllowed = available - (membersLeftAfterThis * 100);
    if (maxAllowed > 0 && result > maxAllowed) {
      result = maxAllowed;
    }
    return max(0, result);
  }
}

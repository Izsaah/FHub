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
/// - Nguyên tắc Lắc Tay: Mỗi lần lắc = đúng +1 vé cơ hội may mắn.
/// - Phân loại người chơi:
///   + Những thành viên CÓ LẮC (shakeCount > 0): Tham gia quay thưởng vé có trọng số cho các giải cao nhất.
///     * Nếu chỉ có đúng 1 người lắc: Người đó 100% trúng Giải Nhất (không bao giờ bị người không lắc cướp giải).
///     * Nếu nhiều người cùng lắc: Tỷ lệ trúng tỷ lệ thuận với số lần lắc của mỗi người. Người lắc nhiều nhất
///       có xác suất cao nhất, nhưng người lắc ít hơn vẫn có cơ hội lật kèo may mắn ("Ý Trời")!
///     * Nếu người lắc nhiều nhất bị người lắc ít hơn lật kèo -> Bật poster kỷ niệm "Ý Trời".
///   + Những thành viên KHÔNG LẮC (shakeCount == 0): Xếp sau những người có lắc, nhận các giải an ủi
///     và phần dư còn lại của quỹ để đảm bảo "chia đủ số tiền cho tất cả thành viên trong gia đình".
/// - Phân bổ giải thưởng theo bậc thang luỹ tiến từ tổng quỹ A:
///   + Giải 1 (Cao nhất): 3/4 của A (75% A), phần còn lại là R1 = 1/4 A
///   + Giải 2: 3/5 của phần còn lại R1, dư ra 2 phần còn lại R2 = 2/5 R1
///   + Giải 3: 3/4 của 2 phần còn lại R2, dư ra R3 = 1/4 R2
///   + Các thành viên tiếp theo: Chia bậc thang phần dư còn lại, người cuối nhận trọn phần dư
///     để ĐẢM BẢO TỔNG TIỀN CHIA RA BẰNG ĐÚNG 100% TỔNG QUỸ A (không thừa, không thiếu 1 đồng).
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

    final rand = Random();

    // 1. Phân loại: Thành viên có lắc (active) và thành viên không lắc (idle)
    final List<String> activeParticipants = [];
    final List<String> idleParticipants = [];

    for (final uid in uniqueParticipants) {
      final count = max(0, shakeCounts[uid] ?? 0);
      if (count > 0) {
        activeParticipants.add(uid);
      } else {
        idleParticipants.add(uid);
      }
    }

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
    // - Mỗi lần lắc = đúng +1 vé may mắn (shakeCount vé).
    // - Nếu chỉ có 1 người lắc: Người đó nắm 100% vé -> ĐƯƠNG NHIÊN ĐẠT GIẢI NHẤT!
    // - Nếu nhiều người cùng lắc: Quay thăm ngẫu nhiên không hoàn lại theo trọng số vé.
    if (activeParticipants.isNotEmpty) {
      if (activeParticipants.length == 1) {
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
    }

    // 4. Các thành viên KHÔNG LẮC (0 lượt lắc) xếp sau người có lắc,
    // xáo trộn ngẫu nhiên để chia các phần dư / giải an ủi còn lại của quỹ hũ
    if (idleParticipants.isNotEmpty) {
      final shuffledIdles = List<String>.from(idleParticipants)..shuffle(rand);
      rankedUids.addAll(shuffledIdles);
    }

    final String? firstPrizeWinnerId = rankedUids.isNotEmpty ? rankedUids.first : null;

    // Kích hoạt Poster Ý Trời: Có lắc tay (maxShakes > 0) và là Quán quân lắc nhưng trượt Giải Nhất
    final bool isTopShakerUnlucky = (topShakerId != null &&
        firstPrizeWinnerId != null &&
        topShakerId != firstPrizeWinnerId &&
        maxShakes > 0);

    // 5. Phân chia tiền thưởng bậc thang từ tổng quỹ A:
    // Giải 1: 3/4 của A -> Giải 2: 3/5 phần còn lại -> Giải 3+: 3/4 của 2 phần còn lại -> Người cuối nhận hết phần dư
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
    // Đảm bảo những người phía sau luôn có ít nhất tiền thưởng dương
    final int maxAllowed = available - (membersLeftAfterThis * 100);
    if (maxAllowed > 0 && result > maxAllowed) {
      result = maxAllowed;
    }
    return max(0, result);
  }
}

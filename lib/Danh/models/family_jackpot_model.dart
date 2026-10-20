import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_bank_info.dart';

/// Trạng thái của Hũ Niềm Vui Gia Đình
enum JackpotStatus {
  idle,     // Đang tích lũy tiền nạp
  shaking,  // Đang trong trận chiến 30s lắc điện thoại
  suspense, // Vừa hết 30s: Đã lộ diện Quán Quân Lắc Tay, đếm ngược 10s thần may mắn phân xử giải thưởng!
  finished, // Đã nổ hũ xong, hiển thị kết quả trao thưởng
}

/// Model dữ liệu Hũ Niềm Vui Gia Đình (Jackpot)
class FamilyJackpotModel {
  final String familyId;
  final int totalPoolAmount; // Tổng tiền quỹ A
  final JackpotStatus status;
  final String? topContributorId; // Người nạp nhiều nhất
  final String topContributorName;
  final Map<String, int> contributions; // {userId: amount}
  final Map<String, String> memberNames; // {userId: displayName}
  final Map<String, int> shakeCounts; // {userId: số lần lắc}
  final Map<String, int> prizeResults; // {userId: số tiền thưởng nhận được}
  final Map<String, int> memberWallets; // {userId: số dư ví tích lũy trong app}
  final Map<String, UserBankInfo> memberBanks; // {userId: thông tin tài khoản ngân hàng để rút tiền}
  final String? topShakerId; // Người lắc nhiều nhất
  final String? firstPrizeWinnerId; // Người trúng giải 1
  final DateTime? shakeStartTime; // Thời điểm bắt đầu 30s đếm ngược
  final DateTime? suspenseStartTime; // Thời điểm bắt đầu 10s đếm ngược hồi hộp trao thưởng
  final bool lostDueToPremiumExpired; // Đánh dấu nếu hũ bị mất/hủy do gói Premium hết hạn

  const FamilyJackpotModel({
    required this.familyId,
    this.totalPoolAmount = 0,
    this.status = JackpotStatus.idle,
    this.topContributorId,
    this.topContributorName = 'Chưa có',
    this.contributions = const {},
    this.memberNames = const {},
    this.shakeCounts = const {},
    this.prizeResults = const {},
    this.memberWallets = const {},
    this.memberBanks = const {},
    this.topShakerId,
    this.firstPrizeWinnerId,
    this.shakeStartTime,
    this.suspenseStartTime,
    this.lostDueToPremiumExpired = false,
  });

  FamilyJackpotModel copyWith({
    String? familyId,
    int? totalPoolAmount,
    JackpotStatus? status,
    String? topContributorId,
    bool clearTopContributorId = false,
    String? topContributorName,
    Map<String, int>? contributions,
    Map<String, String>? memberNames,
    Map<String, int>? shakeCounts,
    Map<String, int>? prizeResults,
    Map<String, int>? memberWallets,
    Map<String, UserBankInfo>? memberBanks,
    String? topShakerId,
    bool clearTopShakerId = false,
    String? firstPrizeWinnerId,
    bool clearFirstPrizeWinnerId = false,
    DateTime? shakeStartTime,
    bool clearShakeStartTime = false,
    DateTime? suspenseStartTime,
    bool clearSuspenseStartTime = false,
    bool? lostDueToPremiumExpired,
  }) {
    return FamilyJackpotModel(
      familyId: familyId ?? this.familyId,
      totalPoolAmount: totalPoolAmount ?? this.totalPoolAmount,
      status: status ?? this.status,
      topContributorId: clearTopContributorId ? null : (topContributorId ?? this.topContributorId),
      topContributorName: topContributorName ?? this.topContributorName,
      contributions: contributions ?? this.contributions,
      memberNames: memberNames ?? this.memberNames,
      shakeCounts: shakeCounts ?? this.shakeCounts,
      prizeResults: prizeResults ?? this.prizeResults,
      memberWallets: memberWallets ?? this.memberWallets,
      memberBanks: memberBanks ?? this.memberBanks,
      topShakerId: clearTopShakerId ? null : (topShakerId ?? this.topShakerId),
      firstPrizeWinnerId: clearFirstPrizeWinnerId ? null : (firstPrizeWinnerId ?? this.firstPrizeWinnerId),
      shakeStartTime: clearShakeStartTime ? null : (shakeStartTime ?? this.shakeStartTime),
      suspenseStartTime: clearSuspenseStartTime ? null : (suspenseStartTime ?? this.suspenseStartTime),
      lostDueToPremiumExpired: lostDueToPremiumExpired ?? this.lostDueToPremiumExpired,
    );
  }

  bool get isIdle => status == JackpotStatus.idle;
  bool get isShaking => status == JackpotStatus.shaking;
  bool get isSuspense => status == JackpotStatus.suspense;
  bool get isFinished => status == JackpotStatus.finished;

  /// Số giây còn lại trong hiệp 30s lắc
  int get remainingShakeSeconds {
    if (shakeStartTime == null || !isShaking) return 0;
    final elapsed = DateTime.now().difference(shakeStartTime!).inSeconds;
    final left = 30 - elapsed;
    return left > 0 ? left : 0;
  }

  /// Số giây còn lại trong hiệp 10s hồi hộp (sau khi đã công bố ai lắc nhiều nhất)
  int get remainingSuspenseSeconds {
    if (suspenseStartTime == null || !isSuspense) return 0;
    final elapsed = DateTime.now().difference(suspenseStartTime!).inSeconds;
    final left = 10 - elapsed;
    return left > 0 ? left : 0;
  }

  /// Tính số giây còn lại tùy theo giai đoạn (shaking: 30s, suspense: 10s)
  int get remainingSeconds {
    if (isShaking) return remainingShakeSeconds;
    if (isSuspense) return remainingSuspenseSeconds;
    return 0;
  }

  /// Kiểm tra xem người lắc nhiều nhất có bị trượt giải nhất không (kích hoạt meme Ý Trời)
  bool get isTopShakerUnlucky {
    if (topShakerId == null || firstPrizeWinnerId == null) return false;
    final maxShakes = shakeCounts[topShakerId] ?? 0;
    if (maxShakes <= 0) return false;
    return topShakerId != firstPrizeWinnerId;
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'totalPoolAmount': totalPoolAmount,
      'status': status.name,
      'topContributorId': topContributorId,
      'topContributorName': topContributorName,
      'contributions': contributions,
      'memberNames': memberNames,
      'shakeCounts': shakeCounts,
      'prizeResults': prizeResults,
      'memberWallets': memberWallets,
      'memberBanks': memberBanks.map((k, v) => MapEntry(k, v.toMap())),
      'topShakerId': topShakerId,
      'firstPrizeWinnerId': firstPrizeWinnerId,
      'shakeStartTime': shakeStartTime != null ? Timestamp.fromDate(shakeStartTime!) : null,
      'suspenseStartTime': suspenseStartTime != null ? Timestamp.fromDate(suspenseStartTime!) : null,
      'lostDueToPremiumExpired': lostDueToPremiumExpired,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory FamilyJackpotModel.fromMap(String familyId, Map<String, dynamic> data) {
    JackpotStatus parseStatus(String? val) {
      if (val == 'shaking') return JackpotStatus.shaking;
      if (val == 'suspense') return JackpotStatus.suspense;
      if (val == 'finished') return JackpotStatus.finished;
      return JackpotStatus.idle;
    }

    Map<String, int> parseIntMap(dynamic val) {
      if (val is! Map) return {};
      return val.map((k, v) => MapEntry(k.toString(), (v is num) ? v.toInt() : 0));
    }

    Map<String, String> parseStringMap(dynamic val) {
      if (val is! Map) return {};
      return val.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    Map<String, UserBankInfo> parseBankMap(dynamic val) {
      if (val is! Map) return {};
      return val.map((k, v) {
        final map = v is Map<String, dynamic>
            ? v
            : (v is Map ? Map<String, dynamic>.from(v) : null);
        return MapEntry(k.toString(), UserBankInfo.fromMap(map));
      });
    }

    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return FamilyJackpotModel(
      familyId: familyId,
      totalPoolAmount: (data['totalPoolAmount'] as num?)?.toInt() ?? 0,
      status: parseStatus(data['status'] as String?),
      topContributorId: data['topContributorId'] as String?,
      topContributorName: data['topContributorName'] as String? ?? 'Chưa có',
      contributions: parseIntMap(data['contributions']),
      memberNames: parseStringMap(data['memberNames']),
      shakeCounts: parseIntMap(data['shakeCounts']),
      prizeResults: parseIntMap(data['prizeResults']),
      memberWallets: parseIntMap(data['memberWallets']),
      memberBanks: parseBankMap(data['memberBanks']),
      topShakerId: data['topShakerId'] as String?,
      firstPrizeWinnerId: data['firstPrizeWinnerId'] as String?,
      shakeStartTime: parseDate(data['shakeStartTime']),
      suspenseStartTime: parseDate(data['suspenseStartTime']),
      lostDueToPremiumExpired: data['lostDueToPremiumExpired'] as bool? ?? false,
    );
  }
}

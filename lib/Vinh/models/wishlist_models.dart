// lib/Vinh/models/wishlist_models.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Trạng thái yêu cầu đổi quà phúc lợi thực tế từ con cái
enum WishlistClaimStatus {
  pending,
  approved,
  rejected;

  String get code {
    switch (this) {
      case WishlistClaimStatus.pending:
        return 'PENDING';
      case WishlistClaimStatus.approved:
        return 'APPROVED';
      case WishlistClaimStatus.rejected:
        return 'REJECTED';
    }
  }

  static WishlistClaimStatus fromString(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'APPROVED':
        return WishlistClaimStatus.approved;
      case 'REJECTED':
        return WishlistClaimStatus.rejected;
      case 'PENDING':
      default:
        return WishlistClaimStatus.pending;
    }
  }
}

/// Danh mục Phúc lợi thực tế do Phụ huynh / Ông bà thiết lập trong Cửa hàng Đổi Sao
class WishlistRewardItem {
  final String id;
  final String familyId;
  final String title;
  final String description;
  final int starCost;
  final String iconEmoji;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final bool isActive;

  const WishlistRewardItem({
    required this.id,
    required this.familyId,
    required this.title,
    this.description = '',
    required this.starCost,
    this.iconEmoji = '🎁',
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.isActive = true,
  });

  WishlistRewardItem copyWith({
    String? id,
    String? familyId,
    String? title,
    String? description,
    int? starCost,
    String? iconEmoji,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return WishlistRewardItem(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      title: title ?? this.title,
      description: description ?? this.description,
      starCost: starCost ?? this.starCost,
      iconEmoji: iconEmoji ?? this.iconEmoji,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'familyId': familyId,
      'title': title,
      'description': description,
      'starCost': starCost,
      'iconEmoji': iconEmoji,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
    };
  }

  factory WishlistRewardItem.fromMap(String id, Map<String, dynamic> map) {
    DateTime parsedCreatedAt = DateTime.now();
    final rawDate = map['createdAt'];
    if (rawDate is Timestamp) {
      parsedCreatedAt = rawDate.toDate();
    } else if (rawDate is DateTime) {
      parsedCreatedAt = rawDate;
    } else if (rawDate is String) {
      parsedCreatedAt = DateTime.tryParse(rawDate) ?? DateTime.now();
    }

    return WishlistRewardItem(
      id: id,
      familyId: (map['familyId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      starCost: (map['starCost'] as num?)?.toInt() ?? 0,
      iconEmoji: (map['iconEmoji'] ?? '🎁').toString(),
      createdBy: (map['createdBy'] ?? '').toString(),
      createdByName: (map['createdByName'] ?? 'Phụ huynh').toString(),
      createdAt: parsedCreatedAt,
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}

/// Yêu cầu đổi sao lấy phúc lợi thực tế của Con cái
class WishlistClaimRecord {
  final String id;
  final String familyId;
  final String itemId;
  final String itemName;
  final String iconEmoji;
  final String childId;
  final String childName;
  final int starCost;
  final WishlistClaimStatus status;
  final DateTime createdAt;
  final String? reviewedBy;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final String? rejectReason;

  const WishlistClaimRecord({
    required this.id,
    required this.familyId,
    required this.itemId,
    required this.itemName,
    this.iconEmoji = '🎁',
    required this.childId,
    required this.childName,
    required this.starCost,
    this.status = WishlistClaimStatus.pending,
    required this.createdAt,
    this.reviewedBy,
    this.reviewedByName,
    this.reviewedAt,
    this.rejectReason,
  });

  WishlistClaimRecord copyWith({
    String? id,
    String? familyId,
    String? itemId,
    String? itemName,
    String? iconEmoji,
    String? childId,
    String? childName,
    int? starCost,
    WishlistClaimStatus? status,
    DateTime? createdAt,
    String? reviewedBy,
    String? reviewedByName,
    DateTime? reviewedAt,
    String? rejectReason,
  }) {
    return WishlistClaimRecord(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      iconEmoji: iconEmoji ?? this.iconEmoji,
      childId: childId ?? this.childId,
      childName: childName ?? this.childName,
      starCost: starCost ?? this.starCost,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedByName: reviewedByName ?? this.reviewedByName,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      rejectReason: rejectReason ?? this.rejectReason,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'familyId': familyId,
      'itemId': itemId,
      'itemName': itemName,
      'iconEmoji': iconEmoji,
      'childId': childId,
      'childName': childName,
      'starCost': starCost,
      'status': status.code,
      'createdAt': Timestamp.fromDate(createdAt),
      'reviewedBy': reviewedBy,
      'reviewedByName': reviewedByName,
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'rejectReason': rejectReason,
    };
  }

  factory WishlistClaimRecord.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
      return DateTime.now();
    }

    return WishlistClaimRecord(
      id: id,
      familyId: (map['familyId'] ?? '').toString(),
      itemId: (map['itemId'] ?? '').toString(),
      itemName: (map['itemName'] ?? '').toString(),
      iconEmoji: (map['iconEmoji'] ?? '🎁').toString(),
      childId: (map['childId'] ?? '').toString(),
      childName: (map['childName'] ?? 'Con').toString(),
      starCost: (map['starCost'] as num?)?.toInt() ?? 0,
      status: WishlistClaimStatus.fromString(map['status']?.toString()),
      createdAt: parseDate(map['createdAt']),
      reviewedBy: map['reviewedBy']?.toString(),
      reviewedByName: map['reviewedByName']?.toString(),
      reviewedAt: map['reviewedAt'] != null ? parseDate(map['reviewedAt']) : null,
      rejectReason: map['rejectReason']?.toString(),
    );
  }
}

/// Bản ghi giao dịch trong Sổ cái Sao Bất biến (`star_ledger`)
class StarLedgerEntryModel {
  final String id;
  final String familyId;
  final String userId;
  final String? userName;
  final int amount;
  final String type; // TASK_REWARD, JACKPOT_WIN, JACKPOT_CONTRIBUTE, WISHLIST_CLAIM, CLAIM_REFUND, RELATIVE_SPONSOR
  final String? sourceId;
  final String? itemName;
  final String? actorId;
  final String? actorName;
  final String? note;
  final DateTime createdAt;

  const StarLedgerEntryModel({
    required this.id,
    required this.familyId,
    required this.userId,
    this.userName,
    required this.amount,
    required this.type,
    this.sourceId,
    this.itemName,
    this.actorId,
    this.actorName,
    this.note,
    required this.createdAt,
  });

  bool get isPositive => amount >= 0;

  String get displayTitle {
    switch (type.toUpperCase()) {
      case 'TASK_REWARD':
        return 'Thưởng hoàn thành công việc';
      case 'JACKPOT_WIN':
        return 'Trúng thưởng Nổ Hũ Sao 🎉';
      case 'JACKPOT_CONTRIBUTE':
        return 'Tích lũy vào Hũ Sao Gia Đình';
      case 'WISHLIST_CLAIM':
        return 'Đổi quà: ${itemName ?? 'Phúc lợi thực tế'}';
      case 'CLAIM_REFUND':
        return 'Hoàn sao đổi quà (${note ?? 'Từ chối'})';
      case 'RELATIVE_SPONSOR':
        return 'Lì xì / Tặng sao khích lệ từ ${actorName ?? 'Người thân'}';
      default:
        return 'Giao dịch sao ($type)';
    }
  }

  factory StarLedgerEntryModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime parsedDate = DateTime.now();
    final rawDate = map['createdAt'];
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    }

    return StarLedgerEntryModel(
      id: id,
      familyId: (map['familyId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      userName: map['userName']?.toString() ?? map['childName']?.toString(),
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      type: (map['type'] ?? 'UNKNOWN').toString(),
      sourceId: (map['sourceId'] ?? map['taskId'] ?? map['claimId'])?.toString(),
      itemName: map['itemName']?.toString(),
      actorId: (map['approvedBy'] ?? map['senderId'] ?? map['actorId'])?.toString(),
      actorName: (map['reviewerName'] ?? map['senderName'] ?? map['actorName'])?.toString(),
      note: (map['note'] ?? map['reason'])?.toString(),
      createdAt: parsedDate,
    );
  }
}

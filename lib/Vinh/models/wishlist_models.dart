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
      'family_id': familyId,
      'title': title,
      'name': title,
      'description': description,
      'desc': description,
      'starCost': starCost,
      'star_cost': starCost,
      'iconEmoji': iconEmoji,
      'icon_emoji': iconEmoji,
      'createdBy': createdBy,
      'created_by': createdBy,
      'createdByName': createdByName,
      'created_by_name': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'created_at': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'is_active': isActive,
    };
  }

  factory WishlistRewardItem.fromMap(String id, Map<String, dynamic> map) {
    DateTime parsedCreatedAt = DateTime.now();
    final rawDate = map['createdAt'] ?? map['created_at'];
    if (rawDate is Timestamp) {
      parsedCreatedAt = rawDate.toDate();
    } else if (rawDate is DateTime) {
      parsedCreatedAt = rawDate;
    } else if (rawDate is String) {
      parsedCreatedAt = DateTime.tryParse(rawDate) ?? DateTime.now();
    }

    final effectiveTitle =
        (map['title'] ?? map['name'] ?? map['rewardTitle'] ?? '').toString();
    final effectiveDesc =
        (map['description'] ?? map['desc'] ?? map['rewardDesc'] ?? '').toString();
    final rawCost = map['starCost'] ?? map['star_cost'] ?? map['cost'];
    final effectiveCost = (rawCost is num)
        ? rawCost.toInt()
        : (int.tryParse(rawCost?.toString() ?? '') ?? 0);
    final effectiveEmoji =
        (map['iconEmoji'] ?? map['icon_emoji'] ?? '🎁').toString();

    final effectiveFamilyId =
        (map['familyId'] ?? map['family_id'] ?? '').toString();
    final effectiveCreatedBy =
        (map['createdBy'] ?? map['created_by'] ?? '').toString();
    final effectiveCreatedByName =
        (map['createdByName'] ?? map['created_by_name'] ?? 'Phụ huynh').toString();
    final rawActive = map['isActive'] ?? map['is_active'];
    final effectiveIsActive = rawActive is bool ? rawActive : true;

    return WishlistRewardItem(
      id: id,
      familyId: effectiveFamilyId,
      title: effectiveTitle,
      description: effectiveDesc,
      starCost: effectiveCost,
      iconEmoji: effectiveEmoji.trim().isEmpty ? '🎁' : effectiveEmoji.trim(),
      createdBy: effectiveCreatedBy,
      createdByName: effectiveCreatedByName,
      createdAt: parsedCreatedAt,
      isActive: effectiveIsActive,
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
      'family_id': familyId,
      'itemId': itemId,
      'item_id': itemId,
      'itemName': itemName,
      'item_name': itemName,
      'iconEmoji': iconEmoji,
      'icon_emoji': iconEmoji,
      'childId': childId,
      'child_id': childId,
      'childName': childName,
      'child_name': childName,
      'starCost': starCost,
      'star_cost': starCost,
      'status': status.code,
      'createdAt': Timestamp.fromDate(createdAt),
      'created_at': Timestamp.fromDate(createdAt),
      'reviewedBy': reviewedBy,
      'reviewed_by': reviewedBy,
      'reviewedByName': reviewedByName,
      'reviewed_by_name': reviewedByName,
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewed_at': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'rejectReason': rejectReason,
      'reject_reason': rejectReason,
    };
  }

  factory WishlistClaimRecord.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
      return DateTime.now();
    }

    final effectiveFamilyId = (map['familyId'] ?? map['family_id'] ?? '').toString();
    final effectiveItemId = (map['itemId'] ?? map['item_id'] ?? '').toString();
    final effectiveItemName = (map['itemName'] ?? map['item_name'] ?? '').toString();
    final effectiveEmoji = (map['iconEmoji'] ?? map['icon_emoji'] ?? '🎁').toString();
    final effectiveChildId = (map['childId'] ?? map['child_id'] ?? '').toString();
    final effectiveChildName = (map['childName'] ?? map['child_name'] ?? 'Con').toString();
    final rawCost = map['starCost'] ?? map['star_cost'];
    final effectiveCost = (rawCost is num)
        ? rawCost.toInt()
        : (int.tryParse(rawCost?.toString() ?? '') ?? 0);
    final rawCreatedAt = map['createdAt'] ?? map['created_at'];
    final rawReviewedAt = map['reviewedAt'] ?? map['reviewed_at'];

    return WishlistClaimRecord(
      id: id,
      familyId: effectiveFamilyId,
      itemId: effectiveItemId,
      itemName: effectiveItemName,
      iconEmoji: effectiveEmoji.trim().isEmpty ? '🎁' : effectiveEmoji.trim(),
      childId: effectiveChildId,
      childName: effectiveChildName,
      starCost: effectiveCost,
      status: WishlistClaimStatus.fromString(map['status']?.toString()),
      createdAt: parseDate(rawCreatedAt),
      reviewedBy: (map['reviewedBy'] ?? map['reviewed_by'])?.toString(),
      reviewedByName: (map['reviewedByName'] ?? map['reviewed_by_name'])?.toString(),
      reviewedAt: rawReviewedAt != null ? parseDate(rawReviewedAt) : null,
      rejectReason: (map['rejectReason'] ?? map['reject_reason'])?.toString(),
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
        return 'Thưởng Heo Đất Gia Đình ⭐';
      case 'JACKPOT_CONTRIBUTE':
        return 'Tích lũy vào Heo Đất Gia Đình';
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

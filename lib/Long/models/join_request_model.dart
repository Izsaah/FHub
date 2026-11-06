import 'package:cloud_firestore/cloud_firestore.dart';

class JoinRequestStatus {
  static const String pending = 'PENDING_APPROVAL';
  static const String approved = 'APPROVED';
  static const String rejected = 'REJECTED';
}

class JoinRequestModel {
  final String id; // Composite: '${familyId}_${userId}'
  final String familyId;
  final String userId;
  final String userName;
  final String userEmail;
  final String userAvatarUrl;
  final String suggestedRole; // 'GRANDPARENT' | 'PARENT' | 'CHILD'
  final String status; // PENDING_APPROVAL | APPROVED | REJECTED
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? reviewedByName;
  final String? assignedRole;
  final bool? isKid;

  const JoinRequestModel({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.userName,
    this.userEmail = '',
    this.userAvatarUrl = '',
    this.suggestedRole = 'CHILD',
    this.status = JoinRequestStatus.pending,
    this.createdAt,
    this.reviewedAt,
    this.reviewedBy,
    this.reviewedByName,
    this.assignedRole,
    this.isKid,
  });

  bool get isPending => status == JoinRequestStatus.pending;
  bool get isApproved => status == JoinRequestStatus.approved;
  bool get isRejected => status == JoinRequestStatus.rejected;

  factory JoinRequestModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return JoinRequestModel.fromMap(doc.data() ?? {}, documentId: doc.id);
  }

  factory JoinRequestModel.fromMap(Map<String, dynamic> map, {String? documentId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final fid = (map['familyId'] ?? map['family_id'] ?? '').toString();
    final uid = (map['userId'] ?? map['user_id'] ?? '').toString();
    final id = documentId ?? (map['id']?.toString() ?? '${fid}_$uid');

    return JoinRequestModel(
      id: id,
      familyId: fid,
      userId: uid,
      userName: (map['userName'] ?? map['user_name'] ?? 'Thành viên mới').toString(),
      userEmail: (map['userEmail'] ?? map['user_email'] ?? '').toString(),
      userAvatarUrl: (map['userAvatarUrl'] ?? map['user_avatar_url'] ?? '').toString(),
      suggestedRole: (map['suggestedRole'] ?? map['suggested_role'] ?? 'CHILD').toString().toUpperCase(),
      status: (map['status'] ?? JoinRequestStatus.pending).toString().toUpperCase(),
      createdAt: parseDate(map['createdAt'] ?? map['created_at']),
      reviewedAt: parseDate(map['reviewedAt'] ?? map['reviewed_at']),
      reviewedBy: map['reviewedBy']?.toString(),
      reviewedByName: map['reviewedByName']?.toString(),
      assignedRole: map['assignedRole']?.toString(),
      isKid: map['isKid'] as bool?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'familyId': familyId,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'userAvatarUrl': userAvatarUrl,
      'suggestedRole': suggestedRole,
      'status': status,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewedBy': reviewedBy,
      'reviewedByName': reviewedByName,
      'assignedRole': assignedRole,
      'isKid': isKid,
    };
  }
}

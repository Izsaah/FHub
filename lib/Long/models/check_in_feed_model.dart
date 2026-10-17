class CheckInFeedModel {
  final String id;
  final String familyId;
  final String userId;
  final String userName;
  final String? userAvatarType;
  final String? imageUrl;
  final String? caption;
  final DateTime createdAt;

  CheckInFeedModel({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.userName,
    this.userAvatarType,
    this.imageUrl,
    this.caption,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory CheckInFeedModel.fromJson(Map<String, dynamic> json) {
    return CheckInFeedModel(
      id: json['id']?.toString() ?? '',
      familyId: json['family_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? '',
      userAvatarType: json['user_avatar_type']?.toString(),
      imageUrl: json['image_url']?.toString(),
      caption: json['caption']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'family_id': familyId,
      'user_id': userId,
      'user_name': userName,
      'user_avatar_type': userAvatarType,
      'image_url': imageUrl,
      'caption': caption,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

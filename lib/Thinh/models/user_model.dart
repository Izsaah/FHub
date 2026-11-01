import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String name;
  final String email;
  final String avatarUrl;
  final String avatarType;
  final String? role; // 'Ông Bà', 'Bố Mẹ', 'Con' (Lazy Onboarding)
  final String? defaultCheckInTime; // Giờ check-in mặc định e.g. '07:00'
  final String? familyId;
  final String? pushToken; // push_token / onesignal_id
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl = '',
    this.avatarType = 'google',
    this.role,
    this.defaultCheckInTime,
    this.familyId,
    this.pushToken,
    this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return UserModel(
      id: id,
      name: data['name']?.toString() ?? data['displayName']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      avatarUrl: data['avatarUrl']?.toString() ?? data['photoUrl']?.toString() ?? '',
      avatarType: data['avatar_type']?.toString() ?? data['avatarType']?.toString() ?? 'google',
      role: data['role']?.toString(),
      defaultCheckInTime: data['defaultCheckInTime']?.toString() ?? data['default_check_in_time']?.toString(),
      familyId: data['familyId']?.toString() ?? data['family_id']?.toString(),
      pushToken: data['push_token']?.toString() ?? data['pushToken']?.toString() ?? data['onesignal_id']?.toString(),
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel.fromFirestore(json, json['id']?.toString() ?? json['uid']?.toString() ?? '');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': id,
      'name': name,
      'email': email,
      'avatarUrl': avatarUrl,
      'avatar_type': avatarType,
      'role': role,
      'defaultCheckInTime': defaultCheckInTime,
      'familyId': familyId,
      'push_token': pushToken,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'avatar_type': avatarType,
    'avatarUrl': avatarUrl,
    'role': role,
    'defaultCheckInTime': defaultCheckInTime,
    'familyId': familyId,
    'push_token': pushToken,
  };
}

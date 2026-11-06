class UserModel {
  final String id;
  final String name;
  final String email;
  final String avatarType;
  final String avatarUrl;
  final List<String> familyIds;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatarType = 'default',
    this.avatarUrl = '',
    this.familyIds = const [],
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final rawFamilyIds = json['familyIds'] ?? json['family_ids'];
    List<String> parsedFamilyIds = const [];
    if (rawFamilyIds is List) {
      parsedFamilyIds = rawFamilyIds
          .where((e) => e != null)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return UserModel(
      id: json['id']?.toString() ?? json['uid']?.toString() ?? '',
      name: json['name']?.toString() ?? json['displayName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatarType: json['avatar_type']?.toString() ??
          json['avatarType']?.toString() ??
          'default',
      avatarUrl: json['avatarUrl']?.toString() ??
          json['avatar_url']?.toString() ??
          json['photoUrl']?.toString() ??
          json['photoURL']?.toString() ??
          '',
      familyIds: parsedFamilyIds,
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatar_type': avatarType,
      'avatarUrl': avatarUrl,
      'familyIds': familyIds,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': id,
      'name': name,
      'email': email,
      'avatar_type': avatarType,
      'avatarUrl': avatarUrl,
      'familyIds': familyIds,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarType,
    String? avatarUrl,
    List<String>? familyIds,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarType: avatarType ?? this.avatarType,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      familyIds: familyIds ?? this.familyIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? avatarType;
  final String? avatarUrl;
  final List<String> familyIds;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.avatarType,
    this.avatarUrl,
    this.familyIds = const [],
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, {String? documentId}) {
    final rawFamilyIds = map['familyIds'] ?? map['family_ids'];
    List<String> parsedFamilyIds = const [];
    if (rawFamilyIds is List) {
      parsedFamilyIds = rawFamilyIds
          .where((e) => e != null)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return UserProfile(
      id: documentId ?? (map['uid'] ?? map['id'] ?? '') as String,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      avatarType: (map['avatar_type'] ?? map['avatarType']) as String?,
      avatarUrl: (map['avatarUrl'] ?? map['avatar_url']) as String?,
      familyIds: parsedFamilyIds,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json, {String? documentId}) =>
      UserProfile.fromMap(json, documentId: documentId);

  Map<String, dynamic> toMap() => {
        'uid': id,
        'id': id,
        'name': name,
        'email': email,
        'avatar_type': avatarType,
        'avatarUrl': avatarUrl,
        'familyIds': familyIds,
      };

  Map<String, dynamic> toJson() => toMap();

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarType,
    String? avatarUrl,
    List<String>? familyIds,
  }) {
    return UserProfile(
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
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

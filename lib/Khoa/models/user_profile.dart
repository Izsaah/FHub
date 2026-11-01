class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? avatarType;
  final String? avatarUrl;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.avatarType,
    this.avatarUrl,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, {String? documentId}) {
    return UserProfile(
      id: documentId ?? (map['uid'] ?? map['id'] ?? '') as String,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      avatarType: (map['avatar_type'] ?? map['avatarType']) as String?,
      avatarUrl: (map['avatarUrl'] ?? map['avatar_url']) as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': id,
        'id': id,
        'name': name,
        'email': email,
        'avatar_type': avatarType,
        'avatarUrl': avatarUrl,
      };
}

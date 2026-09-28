class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? avatarType;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.avatarType,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      avatarType: map['avatar_type'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'email': email, 'avatar_type': avatarType};
  }
}

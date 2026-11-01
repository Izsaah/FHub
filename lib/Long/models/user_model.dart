class UserModel {
  final String id;
  final String name;
  final String email;
  final String avatarType;
  final String avatarUrl;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatarType = 'default',
    this.avatarUrl = '',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatarType: json['avatar_type']?.toString() ?? 'default',
      avatarUrl: json['avatarUrl']?.toString() ??
          json['photoUrl']?.toString() ??
          json['photoURL']?.toString() ??
          '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatar_type': avatarType,
      'avatarUrl': avatarUrl,
    };
  }
}

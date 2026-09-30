class UserModel {
  final String id;
  final String name;
  final String email;
  final String avatarType;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.avatarType,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      avatarType: json['avatarType'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatarType': avatarType,
    };
  }
}

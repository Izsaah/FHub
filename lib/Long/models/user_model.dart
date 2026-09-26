class UserModel {
  final String id;
  final String name;
  final String email;
  final String avatarType;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatarType = 'default',
  });
}

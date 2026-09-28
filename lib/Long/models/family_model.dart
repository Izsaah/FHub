class FamilyModel {
  final String id;
  final String name;
  final String joinCode;
  final String ownerId;

  FamilyModel({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.ownerId,
  });

  factory FamilyModel.fromJson(Map<String, dynamic> json) {
    return FamilyModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      joinCode: json['join_code']?.toString() ?? '',
      ownerId: json['owner_id']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'join_code': joinCode,
      'owner_id': ownerId,
    };
  }
}

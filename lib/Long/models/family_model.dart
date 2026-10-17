class FamilyModel {
  final String id;
  final String name;
  final String joinCode;
  final String ownerId;
  final DateTime createdAt;

  FamilyModel({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.ownerId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory FamilyModel.fromJson(Map<String, dynamic> json) {
    return FamilyModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      joinCode: json['join_code']?.toString() ?? '',
      ownerId: json['owner_id']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'join_code': joinCode,
      'owner_id': ownerId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  FamilyModel copyWith({
    String? id,
    String? name,
    String? joinCode,
    String? ownerId,
    DateTime? createdAt,
  }) {
    return FamilyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      joinCode: joinCode ?? this.joinCode,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

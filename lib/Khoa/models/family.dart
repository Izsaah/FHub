class Family {
  final String id;
  final String name;
  final String joinCode;
  final String ownerId;
  final DateTime? createdAt;

  const Family({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.ownerId,
    this.createdAt,
  });

  factory Family.fromMap(Map<String, dynamic> map) {
    return Family(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      joinCode: map['join_code'] as String? ?? '',
      ownerId: map['owner_id'] as String,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'join_code': joinCode,
      'owner_id': ownerId,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory Family.fromMap(Map<String, dynamic> map, {String? documentId}) {
    return Family(
      id: documentId ?? (map['id'] as String? ?? ''),
      name: map['name'] as String? ?? '',
      joinCode: (map['joinCode'] ?? map['join_code'] ?? '') as String,
      ownerId: (map['ownerId'] ?? map['owner_id'] ?? '') as String,
      createdAt: _dateTimeFrom(map['createdAt'] ?? map['created_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'joinCode': joinCode,
        'ownerId': ownerId,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
      };

  static DateTime? _dateTimeFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

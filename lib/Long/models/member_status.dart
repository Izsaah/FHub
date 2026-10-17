enum MemberStatus {
  active,
  deactivated,
  memorialized;

  String get displayName {
    switch (this) {
      case MemberStatus.active:
        return 'Hoạt động';
      case MemberStatus.deactivated:
        return 'Tạm ngưng';
      case MemberStatus.memorialized:
        return 'Tưởng niệm';
    }
  }

  String get code {
    switch (this) {
      case MemberStatus.active:
        return 'ACTIVE';
      case MemberStatus.deactivated:
        return 'DEACTIVATED';
      case MemberStatus.memorialized:
        return 'MEMORIALIZED';
    }
  }

  static MemberStatus fromString(String? value) {
    if (value == null) return MemberStatus.active;
    final upper = value.toUpperCase().trim();
    if (upper == 'DEACTIVATED' || upper == 'TAM_NGUNG') {
      return MemberStatus.deactivated;
    }
    if (upper == 'MEMORIALIZED' || upper == 'TUONG_NIEM') {
      return MemberStatus.memorialized;
    }
    return MemberStatus.active;
  }
}

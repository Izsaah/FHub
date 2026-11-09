import '../utils/long_strings.dart';

enum HierarchyRole {
  grandparent,
  parent,
  child,
  relative,
  member;

  String get displayName {
    switch (this) {
      case HierarchyRole.grandparent:
        return 'Ông Bà';
      case HierarchyRole.parent:
        return 'Bố Mẹ';
      case HierarchyRole.child:
        return 'Con cái';
      case HierarchyRole.relative:
        return LongStrings.t('Cô / Dì / Chú / Bác', 'Relative');
      case HierarchyRole.member:
        return LongStrings.t('Bạn bè', 'Friend');
    }
  }

  String get code {
    switch (this) {
      case HierarchyRole.grandparent:
        return 'GRANDPARENT';
      case HierarchyRole.parent:
        return 'PARENT';
      case HierarchyRole.child:
        return 'CHILD';
      case HierarchyRole.relative:
        return 'RELATIVE';
      case HierarchyRole.member:
        return 'MEMBER';
    }
  }

  int get hierarchyLevel {
    switch (this) {
      case HierarchyRole.grandparent:
        return 3;
      case HierarchyRole.parent:
        return 2;
      case HierarchyRole.relative:
        return 2;
      case HierarchyRole.child:
        return 1;
      case HierarchyRole.member:
        return 2;
    }
  }

  bool get isGuardian =>
      this == HierarchyRole.parent || this == HierarchyRole.grandparent;

  bool get canAssignChores => isGuardian;

  String toJson() => code;

  static HierarchyRole fromString(String? value) {
    if (value == null) return HierarchyRole.parent;
    final upper = value.toUpperCase().trim();
    if (upper == 'GRANDPARENT' || upper == 'ONG_BA') {
      return HierarchyRole.grandparent;
    }
    if (upper == 'CHILD' || upper == 'CON_CAI') {
      return HierarchyRole.child;
    }
    if (upper == 'RELATIVE' ||
        upper == 'NGUOI_THAN' ||
        upper == 'CO_DI_CHU_BAC' ||
        upper == 'UNCLE_AUNT' ||
        upper == 'UNCLE' ||
        upper == 'AUNT') {
      return HierarchyRole.relative;
    }
    if (upper == 'MEMBER' ||
        upper == 'BAN_BE' ||
        upper == 'THANH_VIEN' ||
        upper == 'ROOMMATE' ||
        upper == 'FRIEND') {
      return HierarchyRole.member;
    }
    return HierarchyRole.parent;
  }
}


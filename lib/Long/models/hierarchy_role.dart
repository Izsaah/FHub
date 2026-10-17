enum HierarchyRole {
  grandparent,
  parent,
  child;

  String get displayName {
    switch (this) {
      case HierarchyRole.grandparent:
        return 'Ông Bà';
      case HierarchyRole.parent:
        return 'Bố Mẹ';
      case HierarchyRole.child:
        return 'Con cái';
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
    }
  }

  static HierarchyRole fromString(String? value) {
    if (value == null) return HierarchyRole.parent;
    final upper = value.toUpperCase().trim();
    if (upper == 'GRANDPARENT' || upper == 'ONG_BA') {
      return HierarchyRole.grandparent;
    }
    if (upper == 'CHILD' || upper == 'CON_CAI') {
      return HierarchyRole.child;
    }
    return HierarchyRole.parent;
  }
}

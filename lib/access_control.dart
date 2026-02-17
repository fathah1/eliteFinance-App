class AccessControl {
  static const List<String> features = [
    'parties',
    'items',
    'reports',
    'sale',
    'purchase',
    'expense',
    'bills',
  ];

  static bool isSuperUser(Map<String, dynamic>? user) {
    if (user == null) return false;
    final v = user['is_super_user'];
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    return v?.toString() == '1' || v?.toString().toLowerCase() == 'true';
  }

  static Map<String, dynamic> permissionMap(Map<String, dynamic>? user) {
    if (user == null) return {};
    final raw = user['permissions'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();
    return {};
  }

  static bool can(Map<String, dynamic>? user, String feature, String action) {
    if (isSuperUser(user)) return true;
    final map = permissionMap(user);
    final row = map[feature];
    if (row is! Map) return false;
    final v = row[action];
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    return v?.toString() == '1' || v?.toString().toLowerCase() == 'true';
  }

  static bool canView(Map<String, dynamic>? user, String feature) =>
      can(user, feature, 'view');

  static bool canAdd(Map<String, dynamic>? user, String feature) =>
      can(user, feature, 'add');

  static bool canEdit(Map<String, dynamic>? user, String feature) =>
      can(user, feature, 'edit');
}

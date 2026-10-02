import 'package:flutter/foundation.dart';
import 'package:spotterfy_app/models/user_model.dart';
import 'package:spotterfy_app/services/admin_service.dart';

/// Which accounts the list is showing.
enum AdminFilter {
  all('All'),
  banned('Banned'),
  admins('Admins'),
  pending('Pending'),
  active('Active now');

  const AdminFilter(this.label);
  final String label;
}

/// How the user list is ordered.
enum AdminSort {
  newest('Newest'),
  oldest('Oldest'),
  name('Name'),
  active('Active first');

  const AdminSort(this.label);
  final String label;
}

/// Aggregate counts for the stats grid.
class AdminStats {
  final int total;
  final int admins;
  final int banned;
  final int pending;
  final int activeNow;
  final int newThisWeek;
  final int spotifyLinked;
  final int inJam;

  const AdminStats({
    this.total = 0,
    this.admins = 0,
    this.banned = 0,
    this.pending = 0,
    this.activeNow = 0,
    this.newThisWeek = 0,
    this.spotifyLinked = 0,
    this.inJam = 0,
  });
}

/// Powers the admin panel: the user list, derived stats, search/filter/sort and
/// the moderation writes.
///
/// Every action updates the in-memory list optimistically after the write
/// resolves, so the panel reflects a ban immediately instead of needing a
/// refetch that would also drop the current search and filter.
class AdminProvider extends ChangeNotifier {
  final AdminService _service;

  List<UserModel> _users = [];
  bool _isLoading = false;
  String? _error;

  String _query = '';
  AdminFilter _filter = AdminFilter.all;
  AdminSort _sort = AdminSort.newest;

  /// uid currently being moderated, so its row can show a spinner and the
  /// action sheet can block a double-tap from firing twice.
  String? _busyUid;

  AdminProvider([AdminService? service]) : _service = service ?? AdminService();

  List<UserModel> get users => _users;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get query => _query;
  AdminFilter get filter => _filter;
  AdminSort get sort => _sort;
  String? get busyUid => _busyUid;

  int get totalCount => _users.length;

  /// Stats over the whole list, not the filtered view - the grid is an overview
  /// of the user base, not of the current search.
  AdminStats get stats {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return AdminStats(
      total: _users.length,
      admins: _users.where((u) => u.isAdmin).length,
      banned: _users.where((u) => u.isBanned).length,
      pending: _users.where((u) => !u.isApproved).length,
      activeNow: _users.where((u) => u.isActiveNow).length,
      newThisWeek: _users.where((u) => u.createdAt.isAfter(weekAgo)).length,
      spotifyLinked: _users
          .where((u) => u.spotifyProfileUrl.trim().isNotEmpty)
          .length,
      inJam: _users.where((u) => (u.currentJamSession ?? '').isNotEmpty).length,
    );
  }

  /// The rows actually rendered: searched, filtered, then ordered.
  List<UserModel> get visibleUsers {
    final q = _query.trim().toLowerCase();
    var list = _users.where((u) {
      switch (_filter) {
        case AdminFilter.all:
          return true;
        case AdminFilter.banned:
          return u.isBanned;
        case AdminFilter.admins:
          return u.isAdmin;
        case AdminFilter.pending:
          return !u.isApproved;
        case AdminFilter.active:
          return u.isActiveNow;
      }
    }).toList();

    if (q.isNotEmpty) {
      // Match on id too: an admin often has a uid from a log line or a report.
      list = list.where((u) {
        return u.displayName.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            u.uid.toLowerCase().contains(q) ||
            u.spotifyProfileUrl.toLowerCase().contains(q);
      }).toList();
    }

    switch (_sort) {
      case AdminSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case AdminSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case AdminSort.name:
        list.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      case AdminSort.active:
        list.sort((a, b) {
          // Playing users first, then newest within each group.
          if (a.isActiveNow != b.isActiveNow) return a.isActiveNow ? -1 : 1;
          return b.createdAt.compareTo(a.createdAt);
        });
    }
    return list;
  }

  /// Counts per filter chip, so a chip can show "Banned (2)" instead of
  /// hiding the reason the list is short.
  int countFor(AdminFilter f) {
    switch (f) {
      case AdminFilter.all:
        return _users.length;
      case AdminFilter.banned:
        return _users.where((u) => u.isBanned).length;
      case AdminFilter.admins:
        return _users.where((u) => u.isAdmin).length;
      case AdminFilter.pending:
        return _users.where((u) => !u.isApproved).length;
      case AdminFilter.active:
        return _users.where((u) => u.isActiveNow).length;
    }
  }

  void search(String value) {
    _query = value;
    notifyListeners();
  }

  void setFilter(AdminFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  void setSort(AdminSort value) {
    if (_sort == value) return;
    _sort = value;
    notifyListeners();
  }

  UserModel? userByUid(String uid) {
    for (final u in _users) {
      if (u.uid == uid) return u;
    }
    return null;
  }

  Future<void> loadUsers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _users = await _service.getAllUsers();
    } catch (e) {
      _error = '$e';
      debugPrint('[Admin] loadUsers failed: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() => loadUsers();

  /// Suspends [uid] and mirrors the change locally.
  Future<void> banUser(String uid, String reason) => _mutate(uid, (u) {
    u.isBanned = true;
    u.bannedAt = DateTime.now();
    u.bannedReason = reason;
  }, () => _service.banUser(uid, reason));

  Future<void> unbanUser(String uid) => _mutate(uid, (u) {
    u.isBanned = false;
    u.bannedAt = null;
    u.bannedReason = '';
  }, () => _service.unbanUser(uid));

  Future<void> setAdmin(String uid, bool value) => _mutate(
    uid,
    (u) => u.isAdmin = value,
    () => _service.setAdmin(uid, value),
  );

  Future<void> setApproved(String uid, bool value) => _mutate(
    uid,
    (u) => u.isApproved = value,
    () => _service.setApproved(uid, value),
  );

  Future<void> setDisplayName(String uid, String name) => _mutate(
    uid,
    (u) => u.displayName = name,
    () => _service.setDisplayName(uid, name),
  );

  /// Applies [local] to the cached copy, runs [write], and reverts on failure so
  /// the panel never claims a moderation action that did not stick.
  Future<void> _mutate(
    String uid,
    void Function(UserModel) local,
    Future<void> Function() write,
  ) async {
    if (_busyUid != null) return;
    final target = userByUid(uid);
    if (target == null) return;
    _busyUid = uid;
    notifyListeners();
    try {
      await write();
      local(target);
    } catch (e) {
      debugPrint('[Admin] moderation write failed for $uid: $e');
      _error = 'Action failed: $e';
    }
    _busyUid = null;
    notifyListeners();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spotterfy_app/models/feedback_model.dart';
import 'package:spotterfy_app/models/user_model.dart';
import 'package:spotterfy_app/services/admin_service.dart';

/// Which accounts the list is showing.
enum AdminFilter {
  all('All'),
  active('Online'),
  suspended('Suspended'),
  admins('Admins');

  const AdminFilter(this.label);
  final String label;
}

/// How the user list is ordered.
enum AdminSort {
  newest('Newest'),
  oldest('Oldest'),
  name('Name'),
  active('Online first');

  const AdminSort(this.label);
  final String label;
}

/// Filter for feedback items.
enum FeedbackFilter {
  all('All'),
  unread('Unread'),
  read('Read');

  const FeedbackFilter(this.label);
  final String label;
}

/// Aggregate counts for the stats grid.
class AdminStats {
  final int suspended;
  final int newLast30Days;
  final int playlists;
  final int inJam;

  const AdminStats({
    this.suspended = 0,
    this.newLast30Days = 0,
    this.playlists = 0,
    this.inJam = 0,
  });
}

/// Powers the admin panel: the user list, derived stats, search/filter/sort,
/// moderation writes, and reading/managing user feedback.
class AdminProvider extends ChangeNotifier {
  final AdminService _service;

  List<UserModel> _users = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription<List<UserModel>>? _usersSubscription;
  Timer? _onlineRefreshTimer;
  int _playlistCount = 0;

  String _query = '';
  AdminFilter _filter = AdminFilter.all;
  AdminSort _sort = AdminSort.newest;

  /// uid currently being moderated, so its row can show a spinner and the
  /// action sheet can block a double-tap from firing twice.
  String? _busyUid;

  // --- Feedback state ---
  List<FeedbackModel> _feedbacks = [];
  bool _isLoadingFeedback = false;
  String? _feedbackError;
  String _feedbackQuery = '';
  FeedbackFilter _feedbackFilter = FeedbackFilter.all;
  String? _busyFeedbackId;

  AdminProvider([AdminService? service]) : _service = service ?? AdminService();

  List<UserModel> get users => _users;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get query => _query;
  AdminFilter get filter => _filter;
  AdminSort get sort => _sort;
  String? get busyUid => _busyUid;

  // --- Feedback getters ---
  List<FeedbackModel> get feedbacks => _feedbacks;
  bool get isLoadingFeedback => _isLoadingFeedback;
  String? get feedbackError => _feedbackError;
  String get feedbackQuery => _feedbackQuery;
  FeedbackFilter get feedbackFilter => _feedbackFilter;
  String? get busyFeedbackId => _busyFeedbackId;
  int get unreadFeedbackCount => _feedbacks.where((f) => !f.isRead).length;
  int get readFeedbackCount => _feedbacks.where((f) => f.isRead).length;

  int get totalCount => _users.length;

  /// Stats over the whole list, not the filtered view - the grid is an overview
  /// of the user base, not of the current search.
  AdminStats get stats {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    return AdminStats(
      suspended: _users.where((u) => u.isSuspended).length,
      newLast30Days: _users.where((u) => u.createdAt.isAfter(thirtyDaysAgo)).length,
      playlists: _playlistCount,
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
        case AdminFilter.suspended:
          return u.isSuspended;
        case AdminFilter.admins:
          return u.isAdmin;
        case AdminFilter.active:
          return u.isOnlineNow;
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
          // Online users first, then newest within each group.
          if (a.isOnlineNow != b.isOnlineNow) return a.isOnlineNow ? -1 : 1;
          return b.createdAt.compareTo(a.createdAt);
        });
    }
    return list;
  }

  /// Counts per filter chip, so a chip can show "Suspended (2)" instead of
  /// hiding the reason the list is short.
  int countFor(AdminFilter f) {
    switch (f) {
      case AdminFilter.all:
        return _users.length;
      case AdminFilter.suspended:
        return _users.where((u) => u.isSuspended).length;
      case AdminFilter.admins:
        return _users.where((u) => u.isAdmin).length;
      case AdminFilter.active:
        return _users.where((u) => u.isOnlineNow).length;
    }
  }

  /// Filtered feedback list based on current query and unread status filter.
  List<FeedbackModel> get visibleFeedbacks {
    final q = _feedbackQuery.trim().toLowerCase();
    var list = _feedbacks.where((f) {
      switch (_feedbackFilter) {
        case FeedbackFilter.all:
          return true;
        case FeedbackFilter.unread:
          return !f.isRead;
        case FeedbackFilter.read:
          return f.isRead;
      }
    }).toList();

    if (q.isNotEmpty) {
      list = list.where((f) {
        return f.message.toLowerCase().contains(q) ||
            f.userName.toLowerCase().contains(q) ||
            f.userEmail.toLowerCase().contains(q) ||
            f.userId.toLowerCase().contains(q) ||
            f.type.toLowerCase().contains(q);
      }).toList();
    }

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  int feedbackCountFor(FeedbackFilter f) {
    switch (f) {
      case FeedbackFilter.all:
        return _feedbacks.length;
      case FeedbackFilter.unread:
        return unreadFeedbackCount;
      case FeedbackFilter.read:
        return readFeedbackCount;
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

  void searchFeedback(String value) {
    _feedbackQuery = value;
    notifyListeners();
  }

  void setFeedbackFilter(FeedbackFilter value) {
    if (_feedbackFilter == value) return;
    _feedbackFilter = value;
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

  void watchUsers() {
    if (_usersSubscription == null) {
      _isLoading = true;
      notifyListeners();
    }
    _usersSubscription ??= _service.watchAllUsers().listen(
      (users) {
        _users = users;
        _isLoading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object error) {
        _error = '$error';
        _isLoading = false;
        debugPrint('[Admin] watchUsers failed: $error');
        notifyListeners();
      },
    );
    _onlineRefreshTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      notifyListeners();
    });
  }

  void stopWatchingUsers() {
    _usersSubscription?.cancel();
    _usersSubscription = null;
    _onlineRefreshTimer?.cancel();
    _onlineRefreshTimer = null;
  }

  @override
  void dispose() {
    _usersSubscription?.cancel();
    _onlineRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadFeedback() async {
    _isLoadingFeedback = true;
    _feedbackError = null;
    notifyListeners();
    try {
      _feedbacks = await _service.getAllFeedback();
    } catch (e) {
      _feedbackError = '$e';
      debugPrint('[Admin] loadFeedback failed: $e');
    }
    _isLoadingFeedback = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    await Future.wait([
      loadUsers(),
      loadFeedback(),
      loadPlaylistCount(),
    ]);
  }

  Future<void> loadPlaylistCount() async {
    try {
      _playlistCount = await _service.getPlaylistCount();
      notifyListeners();
    } catch (e) {
      debugPrint('[Admin] loadPlaylistCount failed: $e');
    }
  }

  /// Suspends [uid] and mirrors the change locally.
  Future<void> suspendUser(String uid, String reason) => _mutate(uid, (u) {
    u.isSuspended = true;
    u.suspendedAt = DateTime.now();
    u.suspendedReason = reason;
  }, () => _service.suspendUser(uid, reason));

  Future<void> restoreUser(String uid) => _mutate(uid, (u) {
    u.isSuspended = false;
    u.suspendedAt = null;
    u.suspendedReason = '';
  }, () => _service.restoreUser(uid));

  Future<void> setAdmin(String uid, bool value) => _mutate(
    uid,
    (u) => u.isAdmin = value,
    () => _service.setAdmin(uid, value),
  );

  Future<void> setDisplayName(String uid, String name) => _mutate(
    uid,
    (u) => u.displayName = name,
    () => _service.setDisplayName(uid, name),
  );

  /// Toggles read status on a feedback item with optimistic UI update.
  Future<void> markFeedbackRead(String feedbackId, bool isRead) async {
    final idx = _feedbacks.indexWhere((f) => f.id == feedbackId);
    if (idx < 0) return;
    final prev = _feedbacks[idx].isRead;
    _feedbacks[idx].isRead = isRead;
    _busyFeedbackId = feedbackId;
    notifyListeners();
    try {
      await _service.markFeedbackRead(feedbackId, isRead);
    } catch (e) {
      debugPrint('[Admin] markFeedbackRead failed: $e');
      if (idx < _feedbacks.length) {
        _feedbacks[idx].isRead = prev;
      }
      _feedbackError = 'Failed to update feedback: $e';
    }
    _busyFeedbackId = null;
    notifyListeners();
  }

  /// Deletes a feedback item with optimistic UI update.
  Future<void> deleteFeedback(String feedbackId) async {
    final idx = _feedbacks.indexWhere((f) => f.id == feedbackId);
    if (idx < 0) return;
    final removed = _feedbacks.removeAt(idx);
    _busyFeedbackId = feedbackId;
    notifyListeners();
    try {
      await _service.deleteFeedback(feedbackId);
    } catch (e) {
      debugPrint('[Admin] deleteFeedback failed: $e');
      _feedbacks.insert(idx, removed);
      _feedbackError = 'Failed to delete feedback: $e';
    }
    _busyFeedbackId = null;
    notifyListeners();
  }

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


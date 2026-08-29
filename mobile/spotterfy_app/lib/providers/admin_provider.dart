import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spotterfy_app/models/user_model.dart';
import 'package:spotterfy_app/services/auth_service.dart';

class AdminProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  List<UserModel> _users = [];
  bool _isLoading = false;
  int _activeUserCount = 0;

  List<UserModel> get users => _users;
  bool get isLoading => _isLoading;
  int get activeUserCount => _activeUserCount;
  int get pendingApprovalCount => _users.where((u) => !u.isApproved && !u.isAdmin).length;

  Future<void> loadUsers() async {
    _isLoading = true;
    notifyListeners();
    try {
      _users = await _authService.getAllUsers();
      _activeUserCount = await _authService.getActiveUserCount();
    } catch (e) {
      debugPrint('Failed to load users: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> approveUser(String uid) async {
    await _authService.approveUser(uid);
    await loadUsers();
  }

  Future<void> denyUser(String uid) async {
    await _authService.denyUser(uid);
    await loadUsers();
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkStatsService extends ChangeNotifier {
  static NetworkStatsService? instance;
  bool _online = true;
  String _connType = 'wifi';
  int _downBytes = 0;
  int _upBytes = 0;
  int _downSpeed = 0;
  int _upSpeed = 0;
  int _wifiDown = 0;
  int _wifiUp = 0;
  int _cellularDown = 0;
  int _cellularUp = 0;
  String _month = _currentMonth();
  Timer? _speedTimer;
  int _deltaDown = 0;
  int _deltaUp = 0;

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  bool get online => _online;
  String get connType => _connType;
  int get downBytes => _downBytes;
  int get upBytes => _upBytes;
  int get downSpeed => _downSpeed;
  int get upSpeed => _upSpeed;
  int get totalWifi => _wifiDown + _wifiUp;
  int get totalCellular => _cellularDown + _cellularUp;
  int get totalMonth => totalWifi + totalCellular;
  int get wifiDown => _wifiDown;
  int get wifiUp => _wifiUp;
  int get cellularDown => _cellularDown;
  int get cellularUp => _cellularUp;

  NetworkStatsService() {
    instance = this;
    _init();
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _downSpeed = _deltaDown;
      _upSpeed = _deltaUp;
      _deltaDown = 0;
      _deltaUp = 0;
      notifyListeners();
    });
  }

  Future<void> _init() async {
    await _load();
    await _updateConnectivity();
    Connectivity().onConnectivityChanged.listen((results) async {
      await _updateConnectivity();
    });
  }

  Future<void> _updateConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.mobile)) {
        _connType = 'cellular';
      } else if (results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet)) {
        _connType = 'wifi';
      } else if (results.contains(ConnectivityResult.none)) {
        _online = false;
        notifyListeners();
        return;
      } else {
        _connType = 'wifi';
      }
      _online = true;
    } catch (_) {
      _connType = 'wifi';
      _online = true;
    }
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = prefs.getString('network_month');
      if (m != null && m != _month) {
        _wifiDown = 0; _wifiUp = 0; _cellularDown = 0; _cellularUp = 0;
        _month = _currentMonth();
        await prefs.setString('network_month', _month);
        await _persist(prefs);
        return;
      }
      _wifiDown = prefs.getInt('wifiDown') ?? 0;
      _wifiUp = prefs.getInt('wifiUp') ?? 0;
      _cellularDown = prefs.getInt('cellularDown') ?? 0;
      _cellularUp = prefs.getInt('cellularUp') ?? 0;
      _month = m ?? _month;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _persist([SharedPreferences? p]) async {
    try {
      final prefs = p ?? await SharedPreferences.getInstance();
      await prefs.setInt('wifiDown', _wifiDown);
      await prefs.setInt('wifiUp', _wifiUp);
      await prefs.setInt('cellularDown', _cellularDown);
      await prefs.setInt('cellularUp', _cellularUp);
      await prefs.setString('network_month', _month);
    } catch (_) {}
  }

  void addDown(int bytes) {
    if (!_online || bytes <= 0) return;
    _downBytes += bytes;
    _deltaDown += bytes;
    if (_connType == 'cellular') {
      _cellularDown += bytes;
    } else {
      _wifiDown += bytes;
    }
    _persist();
    notifyListeners();
  }

  void addUp(int bytes) {
    if (!_online || bytes <= 0) return;
    _upBytes += bytes;
    _deltaUp += bytes;
    if (_connType == 'cellular') {
      _cellularUp += bytes;
    } else {
      _wifiUp += bytes;
    }
    _persist();
    notifyListeners();
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    super.dispose();
  }
}

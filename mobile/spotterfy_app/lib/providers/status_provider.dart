import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StatusProvider extends ChangeNotifier {
  bool? backendOnline;
  bool? warpConnected;
  Timer? _warpTimer;

  static const String _baseUrl = 'https://spotdl.vervoortkobe.be.eu.org/api';

  StatusProvider() {
    checkAll();
    _warpTimer = Timer.periodic(const Duration(seconds: 30), (_) => checkWarp());
  }

  Future<void> checkAll() async {
    await Future.wait([checkHealth(), checkWarp()]);
  }

  Future<void> checkHealth() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/health')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        backendOnline = data['online'] == true || res.statusCode == 200;
      } else {
        backendOnline = false;
      }
    } catch (_) {
      backendOnline = false;
    }
    notifyListeners();
  }

  Future<void> checkWarp() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/warp-status')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        warpConnected = data['connected'] == true;
      } else {
        warpConnected = false;
      }
    } catch (_) {
      warpConnected = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _warpTimer?.cancel();
    super.dispose();
  }
}

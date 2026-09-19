import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StatusProvider extends ChangeNotifier {
  bool? backendOnline;
  bool? warpConnected;
  Timer? _statusTimer;

  static const String _baseUrl = 'https://spotdl.vervoortkobe.be.eu.org/api';

  StatusProvider() {
    checkStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) => checkStatus());
  }

  /// Single poll: /api/health carries both backend and warp state.
  Future<void> checkStatus() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/health')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        backendOnline = data['online'] == true;
        final warp = data['warp'] as Map<String, dynamic>?;
        warpConnected = warp?['connected'] == true;
      } else {
        backendOnline = false;
        warpConnected = false;
      }
    } catch (_) {
      backendOnline = false;
      warpConnected = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }
}

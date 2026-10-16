import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

/// App-wide settings and the assessor session.
class AppState extends ChangeNotifier {
  static const String defaultServer = 'http://10.0.2.2:8000'; // Android emulator -> host machine

  String lang = 'en';
  String serverUrl = defaultServer;
  bool serverReachable = false;
  String? assessorToken;
  String assessorName = '';
  late final ApiService api;
  SharedPreferences? _prefs;

  AppState() {
    api = ApiService(serverUrl);
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    lang = _prefs!.getString('lang') ?? 'en';
    serverUrl = _prefs!.getString('server') ?? defaultServer;
    assessorToken = _prefs!.getString('assessor_token');
    assessorName = _prefs!.getString('assessor_name') ?? '';
    api.baseUrl = serverUrl;
  }

  Future<void> setLang(String l) async {
    lang = l;
    await _prefs?.setString('lang', l);
    notifyListeners();
  }

  Future<void> setServer(String url) async {
    serverUrl = url.trim();
    api.baseUrl = serverUrl;
    await _prefs?.setString('server', serverUrl);
    notifyListeners();
  }

  void setReachable(bool v) {
    if (v != serverReachable) {
      serverReachable = v;
      notifyListeners();
    }
  }

  Future<bool> checkServer() async {
    final ok = await api.ping();
    if (ok != serverReachable) {
      serverReachable = ok;
      notifyListeners();
    }
    return ok;
  }

  Future<void> assessorLogin(String user, String pass) async {
    final r = await api.authAssessor(user, pass);
    assessorToken = r['token'] as String;
    assessorName = (r['display_name'] ?? user).toString();
    await _prefs?.setString('assessor_token', assessorToken!);
    await _prefs?.setString('assessor_name', assessorName);
    notifyListeners();
  }

  Future<void> assessorLogout() async {
    assessorToken = null;
    assessorName = '';
    await _prefs?.remove('assessor_token');
    await _prefs?.remove('assessor_name');
    notifyListeners();
  }
}

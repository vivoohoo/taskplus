import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the API lives. The trial uses a Cloudflare quick tunnel whose address changes on every restart,
/// so the address can be changed on the sign-in screen and is remembered on the phone.
class AppConfig {
  /// Build-time default: --dart-define=API_BASE_URL=... (10.0.2.2 is the PC as seen from the Android emulator).
  static const defaultApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');

  /// Kept for code that runs outside providers (integration tests).
  static String apiBaseUrl = defaultApiBaseUrl;

  static const _key = 'server_url';

  /// Read the saved address before the app starts.
  static Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      if (saved != null && saved.isNotEmpty) apiBaseUrl = saved;
    } catch (_) {/* first run, or tests */}
  }

  /// "https://x.trycloudflare.com/" -> "https://x.trycloudflare.com"; adds https:// when left out.
  static String normalise(String input) {
    var s = input.trim();
    if (s.isEmpty) return defaultApiBaseUrl;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}

final serverUrlProvider = NotifierProvider<ServerUrl, String>(ServerUrl.new);

class ServerUrl extends Notifier<String> {
  @override
  String build() => AppConfig.apiBaseUrl;

  Future<void> set(String input) async {
    final url = AppConfig.normalise(input);
    AppConfig.apiBaseUrl = url;
    state = url;
    try { await (await SharedPreferences.getInstance()).setString(AppConfig._key, url); } catch (_) {}
  }

  /// A server path such as /v1/files/raw/... becomes a full address on the current server.
  String absolute(String pathOrUrl) => pathOrUrl.startsWith('/') ? '$state$pathOrUrl' : pathOrUrl;
}

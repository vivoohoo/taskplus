/// Build-time settings. Override with --dart-define, e.g.
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080
class AppConfig {
  /// 10.0.2.2 is the PC as seen from the Android emulator.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');
}

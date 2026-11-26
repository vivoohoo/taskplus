import 'package:material_ui/material_ui.dart';

/// Messaging-app look: green accent, light and dark.
class AppTheme {
  static const _seed = Color(0xFF00806A);
  /// Set by the browser demo to its bundled fonts; the phone uses the system font.
  static String? font;
  static List<String>? fallback;

  static ThemeData light() => ThemeData(
        fontFamily: font, fontFamilyFallback: fallback,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        appBarTheme: const AppBarTheme(centerTitle: false),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      );

  static ThemeData dark() => ThemeData(
        fontFamily: font, fontFamilyFallback: fallback,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        appBarTheme: const AppBarTheme(centerTitle: false),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      );
}

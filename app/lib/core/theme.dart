import 'package:material_ui/material_ui.dart';

/// Messaging-app look: green accent, light and dark.
class AppTheme {
  static const _seed = Color(0xFF00806A);

  static ThemeData light() => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        appBarTheme: const AppBarTheme(centerTitle: false),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      );

  static ThemeData dark() => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        appBarTheme: const AppBarTheme(centerTitle: false),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      );
}

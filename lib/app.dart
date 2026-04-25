import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/scheduler/task_scheduler.dart';
import 'ui/screens/home_screen.dart';

/// Root application widget.
///
/// Configures MaterialApp with Material 3 theming, dark/light mode
/// support, Chinese locale fallback, and routes to [HomeScreen].
class AlistHfMigratorApp extends StatefulWidget {
  const AlistHfMigratorApp({super.key});

  @override
  State<AlistHfMigratorApp> createState() => _AlistHfMigratorAppState();
}

class _AlistHfMigratorAppState extends State<AlistHfMigratorApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alist-To-HF Migrator',
      debugShowCheckedModeBanner: false,

      // Theme configuration
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: _themeMode,

      // Locale support
      locale: const Locale('zh', 'CN'), // Chinese locale default
      supportedLocales: const [
        Locale('zh', 'CN'), // Chinese (Simplified)
        Locale('en', 'US'), // English (US)
      ],
      localizationsDelegates: const [
        // Default Material localizations (includes zh_CN)
      ],

      // Routes
      home: _buildHomeScreen(),

      // Builder for global error handling and overlays
      builder: (context, child) {
        return MediaQuery(
          // Disable text scaling to keep UI consistent
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  /// Build the home screen with scheduler injected from Provider.
  Widget _buildHomeScreen() {
    return Consumer<TaskScheduler>(
      builder: (context, scheduler, _) {
        return HomeScreen(scheduler: scheduler);
      },
    );
  }

  /// Build Material 3 light theme.
  ThemeData _buildLightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1565C0), // Blue 800
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 1,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 65,
        elevation: 2,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: DividerThemeData(
        thickness: 0.5,
        color: colorScheme.outlineVariant,
      ),
    );
  }

  /// Build Material 3 dark theme.
  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF42A5F5), // Blue 400
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 1,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 65,
        elevation: 2,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: DividerThemeData(
        thickness: 0.5,
        color: colorScheme.outlineVariant,
      ),
    );
  }
}

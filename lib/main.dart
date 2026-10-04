import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'providers/transaction_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI adapter for desktop (Windows / macOS / Linux).
  // On mobile (Android / iOS) the standard sqflite platform channel is used.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Pre-load providers before app renders.
  final settingsProvider = SettingsProvider();
  await settingsProvider.load();

  final txProvider = TransactionProvider();
  await txProvider.load();

  // Monthly rate download runs in the background; startup doesn't wait.
  unawaited(settingsProvider.autoRefreshRatesIfDue());

  runApp(CashyApp(
    settingsProvider: settingsProvider,
    txProvider: txProvider,
  ));
}

class CashyApp extends StatelessWidget {
  final SettingsProvider settingsProvider;
  final TransactionProvider txProvider;

  const CashyApp({
    super.key,
    required this.settingsProvider,
    required this.txProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: txProvider),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Cashy',
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.system,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            home: const DashboardScreen(),
            routes: {
              '/settings': (_) => const SettingsScreen(),
            },
          );
        },
      ),
    );
  }

  ThemeData _buildLightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0D9488), // warm teal
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // ── AppBar ──
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: colorScheme.onSurface,
        ),
      ),
      // ── Cards ──
      cardTheme: CardThemeData(
        elevation: 0.5,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      // ── Buttons ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(0, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(0, 48),
        ),
      ),
      // ── Inputs ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      // ── Bottom sheet ──
      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        elevation: 2,
      ),
      // ── Text ──
      textTheme: const TextTheme(
        headlineLarge: TextStyle(letterSpacing: -0.5, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(letterSpacing: -0.3, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(letterSpacing: -0.2, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(letterSpacing: -0.1, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(letterSpacing: 0),
        bodyMedium: TextStyle(letterSpacing: 0),
        labelLarge: TextStyle(letterSpacing: 0.3, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(letterSpacing: 0.5, fontWeight: FontWeight.w500),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0D9488),
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(0, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(0, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        elevation: 2,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(letterSpacing: -0.5, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(letterSpacing: -0.3, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(letterSpacing: -0.2, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(letterSpacing: -0.1, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(letterSpacing: 0),
        bodyMedium: TextStyle(letterSpacing: 0),
        labelLarge: TextStyle(letterSpacing: 0.3, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(letterSpacing: 0.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}

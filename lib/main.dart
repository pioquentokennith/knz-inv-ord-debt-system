// ─────────────────────────────────────────────────────────────────────────────
// main.dart — App entry point
// Purpose : Initializes all required services before the Flutter UI launches,
//           then mounts the root widget (KnzScentApp) inside an error-guarded zone.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // ← FIX 1
import 'core/app_constants.dart';
import 'core/app_state.dart';
import 'firebase_options.dart';
import 'repositories/sync_queue.dart';
import 'screens/login_screen.dart';

// Entry point — async so we can await initialization steps before runApp()
void main() async {
  // Required before any async work in main()
  WidgetsFlutterBinding.ensureInitialized();

  // ── FIX 1: Load .env BEFORE Firebase or AppState ──────────────────────
  // This makes BREVO_API_KEY, BREVO_SENDER_EMAIL, BREVO_SENDER_NAME
  // available via dotenv.env[] throughout the app.
  await dotenv.load(fileName: '.env');

  // Initialize Firebase — must run before any Firestore/Crashlytics calls
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── Crashlytics: disable in debug to keep production dashboard clean ──
  // kDebugMode is true only during development builds
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  // ── Crashlytics: catch Flutter framework errors (widget build, etc.) ──
  // Pipes any unhandled Flutter errors straight to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Wire up concrete implementations via the DIP configure() method.
  // Swap any of these with mock implementations during testing.
  AppState().configure();

  // Start monitoring internet connection para sa auto-sync
  // Listens for connectivity changes to trigger pending Firestore uploads
  SyncQueue.instance.startMonitoring();

  // Lock status bar to transparent and navigation bar to match app background
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // ── Crashlytics: catch async/platform errors outside the Flutter zone ─
  // runZonedGuarded wraps runApp so platform/async exceptions are reported
  runZonedGuarded(
    () => runApp(const KnzScentApp()),
    (error, stackTrace) =>
        FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true),
  );
}

// Root widget — stateless because theme and routing never change at runtime
class KnzScentApp extends StatelessWidget {
  const KnzScentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${AppStrings.appName} Admin',
      debugShowCheckedModeBanner: false, // Hides the red DEBUG banner in-app
      theme: _buildTheme(),
      home: const LoginScreen(), // First screen the user sees
    );
  }

  // Centralizes all Material 3 theme configuration for the dark luxury aesthetic
  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        secondary: AppColors.gold,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.sidebar,
        foregroundColor: AppColors.white,
        elevation: 0,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: TextStyle(color: AppColors.white),
      ),
      scrollbarTheme: ScrollbarThemeData(
        // Semi-transparent gold thumb for scrollbars
        thumbColor: WidgetStateProperty.all(
            AppColors.gold.withValues(alpha: 0.4)),
        thickness: WidgetStateProperty.all(4),
        radius: const Radius.circular(4),
      ),
    );
  }
}

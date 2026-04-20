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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── FIX 1: Load .env BEFORE Firebase or AppState ──────────────────────
  // This makes BREVO_API_KEY, BREVO_SENDER_EMAIL, BREVO_SENDER_NAME
  // available via dotenv.env[] throughout the app.
  await dotenv.load(fileName: '.env');

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── Crashlytics: disable in debug to keep production dashboard clean ──
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  // ── Crashlytics: catch Flutter framework errors (widget build, etc.) ──
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Wire up concrete implementations via the DIP configure() method.
  // Swap any of these with mock implementations during testing.
  AppState().configure();

  // Start monitoring internet connection para sa auto-sync
  SyncQueue.instance.startMonitoring();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // ── Crashlytics: catch async/platform errors outside the Flutter zone ─
  runZonedGuarded(
    () => runApp(const KnzScentApp()),
    (error, stackTrace) =>
        FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true),
  );
}

class KnzScentApp extends StatelessWidget {
  const KnzScentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${AppStrings.appName} Admin',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const LoginScreen(),
    );
  }

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
        thumbColor: WidgetStateProperty.all(
            AppColors.gold.withValues(alpha: 0.4)),
        thickness: WidgetStateProperty.all(4),
        radius: const Radius.circular(4),
      ),
    );
  }
}

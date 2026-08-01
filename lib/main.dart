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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'core/app_bootstrap.dart';
import 'core/app_constants.dart';
import 'core/app_state.dart';
import 'core/protected_navigation.dart';
import 'core/startup_gate.dart';
import 'database/database_helper.dart';
import 'firebase_options.dart';
import 'repositories/sync_queue.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/notification_service.dart'; // ← Low-stock push notifications
import 'services/login_rate_limiter.dart'; // ← MINOR 1: persistent lockout

void main() {
  AppBootstrap? bootstrap;
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );

      bootstrap = _createBootstrap();
      runApp(KnzScentApp(bootstrap: bootstrap!));
    },
    (error, stackTrace) {
      if (bootstrap?.isAvailable(StartupCapability.crashlytics) ?? false) {
        unawaited(
          FirebaseCrashlytics.instance
              .recordError(error, stackTrace, fatal: true)
              .catchError((_) {}),
        );
      } else if (kDebugMode) {
        debugPrint('[Unhandled] ${error.runtimeType}');
      }
    },
  );
}

AppBootstrap _createBootstrap() => AppBootstrap(
  initializeDatabase: () async {
    await DatabaseHelper.instance.database;
  },
  initializePreferences: LoginRateLimiter.init,
  configureLocalState: () async => AppState().configure(),
  initializeFirebase: () =>
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
  initializeCrashlytics: () async {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  },
  initializeNotifications: NotificationService.instance.init,
  initializeCloudAuthentication: () async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.isAnonymous ?? false) {
      await FirebaseAuth.instance.signOut();
    } else if (user != null) {
      await AppState().restoreSession();
    }
  },
  startSynchronization: () async {
    if (AppState().isLoggedIn) await SyncQueue.instance.startMonitoring();
  },
  onOptionalFailure: (capability) {
    if (kDebugMode) {
      debugPrint('[Startup] ${capability.name} unavailable.');
    }
  },
);

// Root widget — stateless because theme and routing never change at runtime
class KnzScentApp extends StatelessWidget {
  const KnzScentApp({super.key, required this.bootstrap, this.homeBuilder});

  final AppBootstrap bootstrap;
  final WidgetBuilder? homeBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: ProtectedNavigation.navigatorKey,
      navigatorObservers: [ProtectedNavigation.observer],
      title: '${AppStrings.appName} Admin',
      debugShowCheckedModeBanner: false, // Hides the red DEBUG banner in-app
      theme: _buildTheme(),
      home: StartupGate(
        bootstrap: bootstrap,
        homeBuilder:
            homeBuilder ??
            (_) => ListenableBuilder(
              listenable: AppState(),
              builder: (_, __) => AppState().isLoggedIn
                  ? const MainShell()
                  : LoginScreen(bootstrap: bootstrap),
            ),
      ),
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
          AppColors.gold.withValues(alpha: 0.4),
        ),
        thickness: WidgetStateProperty.all(4),
        radius: const Radius.circular(4),
      ),
    );
  }
}

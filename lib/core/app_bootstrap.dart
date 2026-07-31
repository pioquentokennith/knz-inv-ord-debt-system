import 'dart:async';

import 'package:flutter/foundation.dart';

enum StartupCapability {
  firebase,
  crashlytics,
  notifications,
  cloudAuthentication,
  synchronization,
  emailVerification,
}

class AppBootstrap {
  AppBootstrap({
    required this.initializeDatabase,
    required this.initializePreferences,
    required this.configureLocalState,
    required this.initializeFirebase,
    required this.initializeCrashlytics,
    required this.initializeNotifications,
    required this.initializeCloudAuthentication,
    required this.startSynchronization,
    this.requiredTimeout = const Duration(seconds: 15),
    this.optionalTimeout = const Duration(seconds: 5),
    this.onOptionalFailure,
  });

  final Future<void> Function() initializeDatabase;
  final Future<void> Function() initializePreferences;
  final Future<void> Function() configureLocalState;
  final Future<void> Function() initializeFirebase;
  final Future<void> Function() initializeCrashlytics;
  final Future<void> Function() initializeNotifications;
  final Future<void> Function() initializeCloudAuthentication;
  final Future<void> Function() startSynchronization;
  final Duration requiredTimeout;
  final Duration optionalTimeout;
  final void Function(StartupCapability capability)? onOptionalFailure;

  final ValueNotifier<Set<StartupCapability>> unavailableCapabilities =
      ValueNotifier<Set<StartupCapability>>(<StartupCapability>{});
  final Set<StartupCapability> _availableCapabilities = <StartupCapability>{};

  Future<void>? _requiredInitialization;
  Future<void>? _optionalInitialization;
  Future<bool>? _firebaseInitialization;

  Future<void> initializeRequired() =>
      _requiredInitialization ??= _initializeRequired();

  Future<void> retryRequired() {
    _requiredInitialization = null;
    return initializeRequired();
  }

  Future<void> _initializeRequired() async {
    await initializeDatabase().timeout(requiredTimeout);
    await initializePreferences().timeout(requiredTimeout);
    await configureLocalState().timeout(requiredTimeout);
  }

  void startOptional() {
    unawaited(initializeOptional());
  }

  Future<void> initializeOptional() =>
      _optionalInitialization ??= _initializeOptional();

  Future<bool> ensureFirebaseInitialized({bool retryIfUnavailable = false}) {
    if (retryIfUnavailable &&
        unavailableCapabilities.value.contains(StartupCapability.firebase)) {
      _firebaseInitialization = null;
    }
    return _firebaseInitialization ??= _attempt(
      StartupCapability.firebase,
      initializeFirebase,
    );
  }

  Future<void> _initializeOptional() async {
    final notifications = _attempt(
      StartupCapability.notifications,
      initializeNotifications,
    );

    final firebaseReady = await ensureFirebaseInitialized();
    if (!firebaseReady) {
      _markUnavailable(const {
        StartupCapability.crashlytics,
        StartupCapability.cloudAuthentication,
        StartupCapability.synchronization,
        StartupCapability.emailVerification,
      });
      await notifications;
      return;
    }

    _markAvailable(StartupCapability.emailVerification);
    await Future.wait([
      notifications,
      _attempt(StartupCapability.crashlytics, initializeCrashlytics),
      _attempt(
        StartupCapability.cloudAuthentication,
        initializeCloudAuthentication,
      ),
      _attempt(StartupCapability.synchronization, startSynchronization),
    ]);
  }

  Future<bool> _attempt(
    StartupCapability capability,
    Future<void> Function() initialize,
  ) async {
    try {
      await initialize().timeout(optionalTimeout);
      _markAvailable(capability);
      return true;
    } catch (_) {
      _markUnavailable({capability});
      return false;
    }
  }

  void _markAvailable(StartupCapability capability) {
    _availableCapabilities.add(capability);
    if (!unavailableCapabilities.value.contains(capability)) return;
    final updated = {...unavailableCapabilities.value}..remove(capability);
    unavailableCapabilities.value = Set.unmodifiable(updated);
  }

  void _markUnavailable(Set<StartupCapability> capabilities) {
    final updated = {...unavailableCapabilities.value, ...capabilities};
    if (setEquals(updated, unavailableCapabilities.value)) return;
    unavailableCapabilities.value = Set.unmodifiable(updated);
    for (final capability in capabilities) {
      onOptionalFailure?.call(capability);
    }
  }

  bool isAvailable(StartupCapability capability) =>
      _availableCapabilities.contains(capability);
}

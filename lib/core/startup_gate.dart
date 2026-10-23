import 'dart:async';

import 'package:flutter/material.dart';

import '../repositories/sync_queue.dart';
import '../services/notification_service.dart';
import 'app_bootstrap.dart';
import 'app_state.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.bootstrap,
    required this.homeBuilder,
    this.notifications,
  });

  final AppBootstrap bootstrap;
  final WidgetBuilder homeBuilder;
  final NotificationService? notifications;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> with WidgetsBindingObserver {
  late Future<void> _requiredInitialization;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requiredInitialization = widget.bootstrap.initializeRequired();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      (widget.notifications ?? NotificationService.instance)
          .handleLifecycleState(state),
    );
    final appState = AppState();
    final uid = appState.currentUser?.id;
    if (state != AppLifecycleState.resumed ||
        !appState.isLoggedIn ||
        uid == null) {
      return;
    }
    unawaited(appState.reconcileCloudPrincipal(uid));
    unawaited(appState.refreshNotifications());
    SyncQueue.instance.requestSync();
  }

  void _retry() {
    setState(() {
      _requiredInitialization = widget.bootstrap.retryRequired();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _requiredInitialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storage_outlined, size: 42),
                    const SizedBox(height: 16),
                    const Text(
                      'Local data could not be opened. Your records were not changed.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          );
        }

        widget.bootstrap.startOptional();
        return widget.homeBuilder(context);
      },
    );
  }
}

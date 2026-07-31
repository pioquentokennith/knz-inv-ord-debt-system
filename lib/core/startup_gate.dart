import 'package:flutter/material.dart';

import 'app_bootstrap.dart';
import 'app_constants.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.bootstrap,
    required this.homeBuilder,
  });

  final AppBootstrap bootstrap;
  final WidgetBuilder homeBuilder;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<void> _requiredInitialization;

  @override
  void initState() {
    super.initState();
    _requiredInitialization = widget.bootstrap.initializeRequired();
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
        return ValueListenableBuilder<Set<StartupCapability>>(
          valueListenable: widget.bootstrap.unavailableCapabilities,
          builder: (context, unavailable, _) {
            return Column(
              children: [
                if (unavailable.isNotEmpty)
                  Material(
                    color: AppColors.warning.withValues(alpha: 0.16),
                    child: const SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'Local mode is available. Cloud setup, email verification, sync, or notifications may be unavailable.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                Expanded(child: widget.homeBuilder(context)),
              ],
            );
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NotificationStatusBanner extends StatelessWidget {
  const NotificationStatusBanner({super.key, required this.service});
  final NotificationService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      if (!service.initialized ||
          service.permission == AlertPermission.unavailable ||
          (service.permission == AlertPermission.granted &&
              service.lastError == null)) {
        return const SizedBox.shrink();
      }
      final enabled = service.permission == AlertPermission.granted;
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.notifications_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    enabled
                        ? service.lastError!
                        : 'Notifications are off. Enable stock and Utang alerts in Settings.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: enabled
                      ? () async {
                          try {
                            await service.refresh();
                          } catch (_) {
                            /* Service publishes the failure. */
                          }
                        }
                      : service.openSettings,
                  child: Text(enabled ? 'Retry' : 'Settings'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

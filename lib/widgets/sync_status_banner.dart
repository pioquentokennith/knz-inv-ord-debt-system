import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../repositories/sync_queue.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({
    super.key,
    required this.status,
    this.dataError,
    this.onRetry,
  });

  final SyncStatus status;
  final String? dataError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = status.hasFailures;
    final message = failed
        ? '${status.failedCount} cloud change(s) failed to sync. Local data is safe.'
        : status.hasPending
        ? '${status.pendingCount} cloud change(s) pending.'
        : dataError;
    if (message == null) return const SizedBox.shrink();

    final color = failed ? AppColors.error : AppColors.gold;
    return Material(
      color: color.withValues(alpha: 0.14),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                failed ? Icons.cloud_off_outlined : Icons.cloud_queue_outlined,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (failed && onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('RETRY')),
            ],
          ),
        ),
      ),
    );
  }
}

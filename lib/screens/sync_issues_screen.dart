import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../repositories/sync_issue_repository.dart';
import '../repositories/sync_queue.dart';

class SyncIssuesScreen extends StatefulWidget {
  const SyncIssuesScreen({super.key});

  @override
  State<SyncIssuesScreen> createState() => _SyncIssuesScreenState();
}

class _SyncIssuesScreenState extends State<SyncIssuesScreen> {
  final _repository = SyncIssueRepository();
  late Future<List<SyncIssue>> _issues;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final uid = AppState().currentUser?.id ?? '';
    _issues = _repository.getOpen(uid);
  }

  Future<void> _resolve(SyncIssue issue) async {
    final uid = AppState().currentUser?.id;
    if (uid == null) return;
    await _repository.resolve(issue, uid);
    await SyncQueue.instance.emitCurrentStatus(uid);
    if (mounted) setState(_reload);
  }

  Future<void> _retry(SyncIssue issue) async {
    final uid = AppState().currentUser?.id;
    if (uid == null) return;
    await _repository.retryDeadLetter(issue, uid);
    SyncQueue.instance.requestSync();
    await SyncQueue.instance.emitCurrentStatus(uid);
    if (mounted) setState(_reload);
  }

  Future<void> _confirmResolve(SyncIssue issue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close sync issue?'),
        content: const Text(
          'This only marks the issue reviewed. It does not overwrite local or cloud data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close Issue'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _resolve(issue);
  }

  Future<void> _export(SyncIssue issue) => Share.share(
    '${issue.kind}: ${issue.aggregateKey}\n${issue.reason}\n\n${issue.payload}',
    subject: 'KNZ Scent sync issue',
  );

  void _inspect(SyncIssue issue) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(issue.aggregateKey),
        content: SingleChildScrollView(
          child: SelectableText('${issue.reason}\n\n${issue.payload}'),
        ),
        actions: [
          TextButton(
            onPressed: () => _export(issue),
            child: const Text('Export'),
          ),
          if (issue.kind == 'dead_letter')
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _retry(issue);
              },
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AppState().isAdministrator) {
      return const Scaffold(
        body: Center(child: Text('Administrator access is required.')),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Sync Issues'),
        actions: [
          IconButton(
            tooltip: 'Retry transient changes',
            onPressed: () => AppState().retryFailedSync(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: FutureBuilder<List<SyncIssue>>(
        future: _issues,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final issues = snapshot.data!;
          if (issues.isEmpty) {
            return const Center(child: Text('No sync issues require review.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: issues.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final issue = issues[index];
              return Card(
                child: ListTile(
                  leading: Icon(
                    issue.kind == 'conflict'
                        ? Icons.compare_arrows
                        : Icons.error_outline,
                    color: AppColors.error,
                  ),
                  title: Text(issue.aggregateKey),
                  subtitle: Text(
                    issue.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _inspect(issue),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'inspect') _inspect(issue);
                      if (action == 'export') _export(issue);
                      if (action == 'retry') _retry(issue);
                      if (action == 'resolve') _confirmResolve(issue);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'inspect',
                        child: Text('Inspect'),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: Text('Export'),
                      ),
                      if (issue.kind == 'dead_letter')
                        const PopupMenuItem(
                          value: 'retry',
                          child: Text('Retry once'),
                        ),
                      const PopupMenuItem(
                        value: 'resolve',
                        child: Text('Mark reviewed'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

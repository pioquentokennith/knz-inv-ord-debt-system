import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../services/cloud_auth_service.dart';

class RegistrationRequestsScreen extends StatefulWidget {
  const RegistrationRequestsScreen({super.key});

  @override
  State<RegistrationRequestsScreen> createState() =>
      _RegistrationRequestsScreenState();
}

class _RegistrationRequestsScreenState
    extends State<RegistrationRequestsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await CloudAuthService.instance
          .pendingRegistrationRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Registration requests could not be loaded.';
      });
    }
  }

  Future<void> _review(Map<String, dynamic> request) async {
    final currentStatus = request['status'] as String? ?? 'pending';
    final decisions = switch (currentStatus) {
      'approved' => const {'suspended': 'Suspend'},
      'suspended' => const {'approved': 'Reactivate'},
      'pending' => const {
        'approved': 'Approve',
        'rejected': 'Reject',
        'suspended': 'Suspend',
      },
      _ => const <String, String>{},
    };
    if (decisions.isEmpty) return;
    var decision = decisions.keys.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Review ${request['username'] ?? 'request'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: decision,
                decoration: const InputDecoration(labelText: 'Decision'),
                items: decisions.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) =>
                    setDialogState(() => decision = value ?? decision),
              ),
              const SizedBox(height: 12),
              const Text('Approved registrations receive the Staff role.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await CloudAuthService.instance.reviewRegistration(
        uid: request['uid'] as String,
        decision: decision,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Account Access'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _requests.isEmpty
          ? const Center(child: Text('No account records.'))
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final request = _requests[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      request['status'] == 'approved'
                          ? Icons.verified_user_outlined
                          : request['status'] == 'suspended'
                          ? Icons.person_off_outlined
                          : Icons.person_add_alt_1,
                    ),
                    title: Text(request['name'] as String? ?? 'Unnamed'),
                    subtitle: Text(
                      '${request['email'] ?? ''}\n@${request['username'] ?? ''} • ${request['status'] ?? 'pending'}',
                    ),
                    isThreeLine: true,
                    trailing: request['status'] == 'rejected'
                        ? null
                        : FilledButton(
                            onPressed: () => _review(request),
                            child: Text(
                              request['status'] == 'approved'
                                  ? 'Suspend'
                                  : request['status'] == 'suspended'
                                  ? 'Reactivate'
                                  : 'Review',
                            ),
                          ),
                  ),
                );
              },
            ),
    );
  }
}

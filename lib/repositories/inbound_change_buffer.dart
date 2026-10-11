import 'dart:async';

/// An acknowledged, session-scoped change buffer. Server listener resume tokens
/// (owned by Firestore) are used instead of unsafe client-clock checkpoints.
/// A new session replays the initial snapshot; failed SQLite commits keep all
/// changes pending, and acknowledgment never removes a newer arriving revision.
class InboundChangeBuffer {
  InboundChangeBuffer(this.onChanged);

  final void Function() onChanged;
  final Map<String, Map<String, Map<String, dynamic>>> _pending = {};
  final Map<String, Completer<void>> _ready = {};
  Object? _error;

  void expect(String collection) {
    _ready.putIfAbsent(collection, Completer<void>.new);
  }

  void add(String collection, Iterable<Map<String, dynamic>> changes) {
    final pending = _pending.putIfAbsent(collection, () => {});
    var changed = false;
    for (final data in changes) {
      pending[data['id'] as String] = data;
      changed = true;
    }
    final ready = _ready[collection];
    if (ready != null && !ready.isCompleted) ready.complete();
    if (changed) onChanged();
  }

  void fail(Object error) {
    _error = error;
    // Complete normally and surface through snapshot(), avoiding unhandled
    // asynchronous errors before the first consumer starts awaiting readiness.
    for (final ready in _ready.values) {
      if (!ready.isCompleted) ready.complete();
    }
  }

  Future<List<List<Map<String, dynamic>>>> snapshot(
    List<String> collections,
  ) async {
    await Future.wait(
      _ready.values.map((ready) => ready.future),
    ).timeout(const Duration(seconds: 15));
    if (_error != null) throw _error!;
    return [
      for (final collection in collections)
        _pending[collection]?.values.toList(growable: false) ?? [],
    ];
  }

  void acknowledge(
    List<String> collections,
    List<List<Map<String, dynamic>>> batch,
  ) {
    for (var i = 0; i < collections.length; i++) {
      final pending = _pending[collections[i]];
      for (final record in batch[i]) {
        final id = record['id'] as String;
        if (identical(pending?[id], record)) pending?.remove(id);
      }
    }
  }
}

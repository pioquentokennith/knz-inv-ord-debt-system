import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/repositories/firestore_sync.dart';
import '../support/revision_firestore_fake.dart';

class _Metadata extends Fake implements SnapshotMetadata {
  _Metadata({this.isFromCache = false});
  @override
  final bool isFromCache;
  @override
  bool get hasPendingWrites => false;
}

// ignore: subtype_of_sealed_class
class _Document extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Document(this.id, this.revision);
  @override
  final String id;
  final int revision;
  @override
  Map<String, dynamic> data() => {'id': id, 'revision': revision};
}

// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs, {bool cached = false})
    : metadata = _Metadata(isFromCache: cached);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  final SnapshotMetadata metadata;
  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges => [];
}

void main() {
  late FirestoreSync cloud;
  late String uid;
  late Map<String, StreamController<QuerySnapshot<Map<String, dynamic>>>>
  streams;
  late int subscriptions;
  setUp(() {
    uid = 'a';
    subscriptions = 0;
    streams = {};
    cloud = FirestoreSync.forTesting(
      firestore: RevisionFirestoreFake(),
      currentUid: () => uid,
      inboundSnapshots: (user, collection) {
        subscriptions++;
        return streams
            .putIfAbsent(
              '$user/$collection',
              () =>
                  StreamController<
                    QuerySnapshot<Map<String, dynamic>>
                  >.broadcast(sync: true),
            )
            .stream;
      },
    );
  });
  tearDown(() async {
    await cloud.stopInbound();
    await Future.wait(streams.values.map((controller) => controller.close()));
  });
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  void emit(String owner, {bool cached = false}) {
    for (final collection in FirestoreSync.inboundCollections) {
      streams['$owner/$collection']!.add(
        _Snapshot(
          collection == 'products' ? [_Document('product-$owner', 1)] : [],
          cached: cached,
        ),
      );
    }
  }

  test(
    'concurrent startup shares listeners, ignores cache and replays after reconnect',
    () async {
      final first = cloud.pendingInbound(uid);
      final second = cloud.pendingInbound(uid);
      await tick();
      expect(subscriptions, 7);
      var complete = false;
      unawaited(first.then((_) => complete = true));
      emit(uid, cached: true);
      await tick();
      expect(complete, isFalse);
      emit(uid);
      final batches = await Future.wait([first, second]);
      expect(batches.first.first.first['id'], 'product-a');
      cloud.acknowledgeInbound(uid, batches.first);
      expect(
        (await cloud.pendingInbound(uid)).every((list) => list.isEmpty),
        isTrue,
      );
      await cloud.stopInbound();
      expect(streams.values.every((stream) => !stream.hasListener), isTrue);
      final reconnect = cloud.pendingInbound(uid);
      await tick();
      emit(uid);
      expect((await reconnect).first.first['id'], 'product-a');
      expect(subscriptions, 14);
    },
  );
  test(
    'old account waiter cannot stop or acknowledge new account listeners',
    () async {
      final old = cloud.pendingInbound('a');
      final oldFailure = expectLater(old, throwsStateError);
      await tick();
      uid = 'b';
      final current = cloud.pendingInbound('b');
      await tick();
      await oldFailure;
      emit('b');
      final batch = await current;
      expect(batch.first.first['id'], 'product-b');
      expect(streams['a/products']!.hasListener, isFalse);
      cloud.acknowledgeInbound('a', batch);
      expect((await cloud.pendingInbound('b')).first, isNotEmpty);
    },
  );
  test(
    'cached reconnect changes replay on server confirmation even with empty docChanges',
    () async {
      final initial = cloud.pendingInbound(uid);
      await tick();
      emit(uid);
      cloud.acknowledgeInbound(uid, await initial);
      streams['a/products']!.add(
        _Snapshot([_Document('product-a', 2)], cached: true),
      );
      streams['a/products']!.add(_Snapshot([_Document('product-a', 2)]));
      final batch = await cloud.pendingInbound(uid);
      expect(batch.first.first['revision'], 2);
    },
  );
  test('wrong account cannot start any listeners', () async {
    await expectLater(cloud.pendingInbound('other'), throwsStateError);
    expect(subscriptions, 0);
  });
  test(
    'listener error releases listeners and next attempt gets a complete snapshot',
    () async {
      final failed = cloud.pendingInbound(uid);
      final error = expectLater(failed, throwsStateError);
      await tick();
      streams['a/products']!.addError(StateError('unavailable'));
      await error;
      expect(streams.values.every((stream) => !stream.hasListener), isTrue);
      final retry = cloud.pendingInbound(uid);
      await tick();
      emit(uid);
      expect((await retry).first.first['id'], 'product-a');
    },
  );
}

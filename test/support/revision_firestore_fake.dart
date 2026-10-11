import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Executes the adapter's real transaction callback against a current remote
/// snapshot. Records writes separately from reads, including read-only replays.
class RevisionFirestoreFake extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  int writes = 0;
  int transactions = 0;
  Future<void> Function()? beforeRead;
  Future<void> Function()? afterCommit;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactions++;
    final transaction = _Transaction(this);
    final result = await transactionHandler(transaction);
    for (final entry in transaction.pending.entries) {
      documents[entry.key] = {...?documents[entry.key], ...entry.value};
      writes++;
    }
    await afterCommit?.call();
    return result;
  }
}

// Platform SDK interfaces are intentionally doubled only inside tests.
// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path);
  final RevisionFirestoreFake store;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(store, '${this.path}/$path');
}

// ignore: subtype_of_sealed_class
class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.path);
  final RevisionFirestoreFake store;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  bool operator ==(Object other) =>
      other is _Document && identical(store, other.store) && path == other.path;
  @override
  int get hashCode => Object.hash(store, path);
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(store, '$path/$collectionPath');
}

// ignore: subtype_of_sealed_class
class _Snapshot<T extends Object?> extends Fake implements DocumentSnapshot<T> {
  _Snapshot(this.value);
  final T? value;
  @override
  bool get exists => value != null;
  @override
  T? data() => value;
}

class _Transaction extends Fake implements Transaction {
  _Transaction(this.store);
  final RevisionFirestoreFake store;
  final pending = <String, Map<String, dynamic>>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async {
    await store.beforeRead?.call();
    final value = store.documents[reference.path];
    return _Snapshot<T>(
      value == null ? null : jsonDecode(jsonEncode(value)) as T,
    );
  }

  @override
  Transaction update(DocumentReference reference, Map<String, dynamic> data) {
    pending[reference.path] = {...?pending[reference.path], ...data};
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    pending[reference.path] = Map<String, dynamic>.from(data as Map);
    return this;
  }
}

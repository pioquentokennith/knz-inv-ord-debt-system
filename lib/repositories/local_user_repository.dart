import 'package:sqflite/sqflite.dart';

import '../models/user_model.dart';
import '../models/device_auth_grant.dart';
import 'base_repository.dart';
import 'user_repository.dart';

class LocalUserRepository extends BaseRepository implements UserRepository {
  @override
  Future<AppUser?> getByFirebaseUid(String uid) => safeCall(() async {
    final database = await db.database;
    final rows = await database.query(
      'users',
      where: 'firebase_uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.single);
  });

  @override
  Future<AppUser> cacheAuthorizedProfile(AppUser user) async {
    if (!user.canAccess || user.id.trim().isEmpty) {
      throw StateError('Only approved active Firebase users may be cached.');
    }

    final database = await db.database;
    await database.transaction((txn) async {
      final uidRows = await txn.query(
        'users',
        where: 'firebase_uid = ?',
        whereArgs: [user.id],
        limit: 1,
      );
      if (uidRows.isNotEmpty) {
        await txn.update(
          'users',
          user.toMap()..['migration_state'] = 'mapped',
          where: 'firebase_uid = ?',
          whereArgs: [user.id],
        );
        return;
      }

      final usernameRows = await txn.query(
        'users',
        where: 'username = ? COLLATE NOCASE',
        whereArgs: [user.username],
        limit: 1,
      );
      if (usernameRows.isNotEmpty) {
        throw StateError(
          'This username belongs to quarantined legacy data and requires an owner-approved UID mapping.',
        );
      }

      await txn.insert('users', {
        ...user.toMap(),
        'migration_state': 'mapped',
        'is_synced': 1,
      });
    });
    return user;
  }

  @override
  Future<DeviceAuthGrant?> getDeviceGrant(String uid) => safeCall(() async {
    final database = await db.database;
    final rows = await database.query(
      'device_auth_grants',
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    return rows.isEmpty ? null : DeviceAuthGrant.fromMap(rows.single);
  });

  @override
  Future<AuthRuntimeState> getAuthRuntimeState() => safeCall(() async {
    final database = await db.database;
    final rows = await database.query(
      'auth_runtime_state',
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (rows.isEmpty) {
      await database.insert('auth_runtime_state', {
        'singleton_id': 1,
        'operation_generation': 0,
      });
      return const AuthRuntimeState(operationGeneration: 0);
    }
    return AuthRuntimeState.fromMap(rows.single);
  });

  @override
  Future<void> saveDeviceGrant(DeviceAuthGrant grant) => safeVoidCall(() async {
    final database = await db.database;
    await database.transaction((txn) async {
      await txn.insert('device_auth_grants', {
        'uid': grant.uid,
        'state': grant.state,
        'generation': grant.generation,
        'enrolled_at': grant.enrolledAt.toUtc().toIso8601String(),
        'last_verified_at': grant.lastVerifiedAt.toUtc().toIso8601String(),
        'access_generation': grant.accessGeneration,
        'profile_digest': grant.profileDigest,
        'revoked_at': grant.revokedAt?.toUtc().toIso8601String(),
        'revocation_reason': grant.revocationReason,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update('auth_runtime_state', {
        'last_active_uid': grant.uid,
        'pending_firebase_signout_uid': null,
        'operation_generation': (await _runtimeGeneration(txn)) + 1,
      }, where: 'singleton_id = 1');
    });
  });

  @override
  Future<void> revokeDeviceGrant(String uid, String reason) =>
      safeVoidCall(() async {
        final database = await db.database;
        final changed = await database.update(
          'device_auth_grants',
          {
            'state': 'revoked',
            'revoked_at': DateTime.now().toUtc().toIso8601String(),
            'revocation_reason': reason,
          },
          where: 'uid = ?',
          whereArgs: [uid],
        );
        if (changed > 1)
          throw StateError('Multiple device grants share UID $uid.');
      });

  @override
  Future<void> setPendingFirebaseSignOut(String? uid) => safeVoidCall(() async {
    final database = await db.database;
    await database.transaction((txn) async {
      await txn.update('auth_runtime_state', {
        'pending_firebase_signout_uid': uid,
        'operation_generation': (await _runtimeGeneration(txn)) + 1,
      }, where: 'singleton_id = 1');
    });
  });

  Future<int> _runtimeGeneration(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'auth_runtime_state',
      columns: const ['operation_generation'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.single['operation_generation'] as int;
  }
}

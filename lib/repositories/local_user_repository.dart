import '../models/user_model.dart';
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
}

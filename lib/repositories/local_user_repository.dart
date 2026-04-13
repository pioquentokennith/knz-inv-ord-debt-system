import 'dart:convert';
import 'package:crypto/crypto.dart'; // ← FIX 2: add crypto to pubspec.yaml
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import 'base_repository.dart';
import 'user_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

class LocalUserRepository extends BaseRepository implements UserRepository {
  final _uuid  = const Uuid();
  final _cloud = FirestoreSync.instance;
  final _queue = SyncQueue.instance;

  // ── FIX 2: Hash helper — SHA-256, one-way, consistent ─────────────────
  // All passwords stored in SQLite and Firestore are now hashed.
  // Plain-text passwords are NEVER persisted anywhere.
  static String _hash(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  @override
  Future<AppUser?> login(String username, String password) => safeCall(() async {
    final database = await db.database;
    final hashed = _hash(password); // ← FIX 2: hash before comparing

    // 1. Try local SQLite first (offline-first)
    var maps = await database.query('users',
        where: 'username = ? AND password = ?',
        whereArgs: [username.toLowerCase(), hashed]); // ← FIX 2

    // 2. Kung wala sa local at may internet, subukan sa Firestore
    if (maps.isEmpty && _queue.isOnline) {
      final cloudUser = await _cloud.getUser(username);
      if (cloudUser != null && cloudUser['password'] == hashed) { // ← FIX 2
        await _restoreUserLocally(database, cloudUser);
        maps = await database.query('users',
            where: 'username = ? AND password = ?',
            whereArgs: [username.toLowerCase(), hashed]); // ← FIX 2
      }
    }

    if (maps.isEmpty) return null;
    final m = maps.first;
    return AppUser(
      id:        m['id']        as String,
      username:  m['name']      as String,
      role:      m['role']      as String,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }, null);

  @override
  Future<bool> register(String name, String username, String password, {String? email}) => safeCall(() async {
    final existsLocal = await usernameExists(username);
    if (existsLocal) return false;

    if (_queue.isOnline) {
      final existsCloud = await _cloud.usernameExistsCloud(username);
      if (existsCloud) return false;
    }

    final database = await db.database;
    final id     = _uuid.v4();
    final now    = DateTime.now().toIso8601String();
    final hashed = _hash(password); // ← FIX 2: hash before storing

    final data = {
      'id':         id,
      'username':   username.toLowerCase(),
      'password':   hashed,  // ← FIX 2: stored as hash, never plaintext
      'name':       name,
      'email':      email,
      'role':       'Administrator',
      'is_synced':  0,
      'created_at': now,
    };

    // 1. Save sa SQLite
    await database.insert('users', data);

    if (_queue.isOnline) {
      // 2. May internet — i-sync agad sa Firestore
      final syncedData = {...data, 'is_synced': 1};
      await _cloud.saveUser(syncedData);
      await database.update('users', {'is_synced': 1},
          where: 'id = ?', whereArgs: [id]);
    } else {
      // 3. Walang internet — i-queue para later
      await _queue.enqueue(
        operation:  'save_user',
        collection: 'users',
        userId:     id,
        docId:      id,
        data:       data,
      );
    }

    return true;
  }, false);

  @override
  Future<bool> resetPassword(String username, String newPassword) => safeCall(() async {
    final database = await db.database;
    final hashed = _hash(newPassword); // ← FIX 2: hash before storing

    final count = await database.update('users',
        {'password': hashed, 'is_synced': 0}, // ← FIX 2
        where: 'username = ?', whereArgs: [username.toLowerCase()]);
    if (count == 0) return false;

    if (_queue.isOnline) {
      await _cloud.updateUserPassword(username, hashed); // ← FIX 2
      await database.update('users', {'is_synced': 1},
          where: 'username = ?', whereArgs: [username.toLowerCase()]);
    } else {
      await _queue.enqueue(
        operation:  'update_user_password',
        collection: 'users',
        userId:     username,
        docId:      username,
        data:       {'username': username, 'password': hashed}, // ← FIX 2
      );
    }

    return true;
  }, false);

  @override
  Future<bool> usernameExists(String username) => safeCall(() async {
    final database = await db.database;
    final maps = await database.query('users',
        where: 'username = ?', whereArgs: [username.toLowerCase()]);
    return maps.isNotEmpty;
  }, false);

  Future<void> _restoreUserLocally(dynamic database, Map<String, dynamic> cloudUser) async {
    try {
      await database.insert('users', {
        'id':         cloudUser['id'],
        'username':   cloudUser['username'],
        'password':   cloudUser['password'], // already hashed in Firestore
        'name':       cloudUser['name'],
        'email':      cloudUser['email'],
        'role':       cloudUser['role'] ?? 'Administrator',
        'is_synced':  1,
        'created_at': cloudUser['created_at'],
      });
    } catch (_) {}
  }
}

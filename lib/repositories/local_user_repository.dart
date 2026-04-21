// ─────────────────────────────────────────────────────────────────────────────
// local_user_repository.dart — SQLite-backed user authentication repository
// Purpose : Handles login, registration, and password reset using local SQLite
//           as the primary store with Firestore as the cloud backup/sync target.
//           All passwords are stored as SHA-256 hashes — never as plaintext.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:crypto/crypto.dart'; // SHA-256 hashing
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import 'base_repository.dart';
import 'user_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

// Implements UserRepository against the local SQLite 'users' table
class LocalUserRepository extends BaseRepository implements UserRepository {
  final _uuid  = const Uuid();           // UUID generator for new user IDs
  final _cloud = FirestoreSync.instance; // Firestore adapter for cloud sync
  final _queue = SyncQueue.instance;     // Offline sync queue

  // ── FIX 2: Hash helper — SHA-256, one-way, consistent ─────────────────
  // All passwords stored in SQLite and Firestore are now hashed.
  // Plain-text passwords are NEVER persisted anywhere.
  static String _hash(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  // Validates credentials against SQLite; falls back to Firestore if local record is missing
  @override
  Future<AppUser?> login(String username, String password) => safeCall(() async {
    final database = await db.database;
    final hashed = _hash(password); // Hash before comparing — never compare plaintext

    // Step 1: Try local SQLite first (offline-first approach)
    var maps = await database.query('users',
        where: 'username = ? AND password = ?',
        whereArgs: [username.toLowerCase(), hashed]);

    // Step 2: Not found locally but online — check Firestore and cache the user locally
    if (maps.isEmpty && _queue.isOnline) {
      final cloudUser = await _cloud.getUser(username);
      if (cloudUser != null && cloudUser['password'] == hashed) {
        // Cache the cloud user in SQLite for future offline logins
        await _restoreUserLocally(database, cloudUser);
        maps = await database.query('users',
            where: 'username = ? AND password = ?',
            whereArgs: [username.toLowerCase(), hashed]);
      }
    }

    if (maps.isEmpty) return null; // Credentials do not match any record
    // FIX 8: Uses AppUser.fromMap() — consistent with OOP deserialization pattern
    return AppUser.fromMap(maps.first);
  }, null);

  // Creates a new user account in SQLite and syncs to Firestore when online
  @override
  Future<bool> register(String name, String username, String password, {String? email}) => safeCall(() async {
    // Prevent duplicate usernames locally before hitting the network
    final existsLocal = await usernameExists(username);
    if (existsLocal) return false;

    // Also check Firestore to prevent duplicate across devices
    if (_queue.isOnline) {
      final existsCloud = await _cloud.usernameExistsCloud(username);
      if (existsCloud) return false;
    }

    final database = await db.database;
    final id     = _uuid.v4();                          // Generate unique user ID
    final now    = DateTime.now().toIso8601String();
    final hashed = _hash(password);                     // Hash password before storing

    final data = {
      'id':         id,
      'username':   username.toLowerCase(),              // Always stored lowercase
      'password':   hashed,                              // Stored as hash, never plaintext
      'name':       name,
      'email':      email,
      'role':       'Administrator',
      'is_synced':  0,                                   // 0 = not yet pushed to Firestore
      'created_at': now,
    };

    // Step 1: Save to SQLite immediately (works offline)
    await database.insert('users', data);

    if (_queue.isOnline) {
      // Step 2a: Online — sync directly to Firestore right now
      final syncedData = {...data, 'is_synced': 1};
      await _cloud.saveUser(syncedData);
      await database.update('users', {'is_synced': 1},
          where: 'id = ?', whereArgs: [id]);
    } else {
      // Step 2b: Offline — queue the Firestore write for later
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

  // Updates the stored password hash for a username in SQLite and Firestore
  @override
  Future<bool> resetPassword(String username, String newPassword) => safeCall(() async {
    final database = await db.database;
    final hashed = _hash(newPassword); // Hash the new password before storing

    // Update SQLite first; returns 0 if username does not exist
    final count = await database.update('users',
        {'password': hashed, 'is_synced': 0},
        where: 'username = ?', whereArgs: [username.toLowerCase()]);
    if (count == 0) return false; // Username not found locally

    if (_queue.isOnline) {
      // Sync the new hash to Firestore immediately
      await _cloud.updateUserPassword(username, hashed);
      await database.update('users', {'is_synced': 1},
          where: 'username = ?', whereArgs: [username.toLowerCase()]);
    } else {
      // Queue the password update for when connectivity returns
      await _queue.enqueue(
        operation:  'update_user_password',
        collection: 'users',
        userId:     username,
        docId:      username,
        data:       {'username': username, 'password': hashed},
      );
    }

    return true;
  }, false);

  // Returns true if the username already exists in the local SQLite users table
  @override
  Future<bool> usernameExists(String username) => safeCall(() async {
    final database = await db.database;
    final maps = await database.query('users',
        where: 'username = ?', whereArgs: [username.toLowerCase()]);
    return maps.isNotEmpty;
  }, false);

  // Inserts a Firestore user record into the local SQLite table for offline access
  Future<void> _restoreUserLocally(dynamic database, Map<String, dynamic> cloudUser) async {
    try {
      await database.insert('users', {
        'id':         cloudUser['id'],
        'username':   cloudUser['username'],
        'password':   cloudUser['password'], // Already a SHA-256 hash in Firestore
        'name':       cloudUser['name'],
        'email':      cloudUser['email'],
        'role':       cloudUser['role'] ?? 'Administrator',
        'is_synced':  1,                     // Came from cloud — already synced
        'created_at': cloudUser['created_at'],
      });
    } catch (_) {} // Ignore insert errors (e.g. if already exists from a race condition)
  }
}

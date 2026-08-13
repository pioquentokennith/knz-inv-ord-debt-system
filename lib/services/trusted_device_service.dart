import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/device_auth_grant.dart';
import '../models/user_model.dart';

abstract interface class TrustedDeviceRepository {
  Future<AppUser?> getByFirebaseUid(String uid);
  Future<DeviceAuthGrant?> getDeviceGrant(String uid);
  Future<AuthRuntimeState> getAuthRuntimeState();
  Future<void> saveDeviceGrant(DeviceAuthGrant grant);
  Future<void> revokeDeviceGrant(String uid, String reason);
  Future<void> setPendingFirebaseSignOut(String? uid);
}

abstract interface class SecureDeviceGrantStore {
  Future<String?> readActiveUid();
  Future<String?> readSecret(String uid);
  Future<void> writeGrant(String uid, String secret);
  Future<void> deleteGrant(String uid);
}

class KeystoreDeviceGrantStore implements SecureDeviceGrantStore {
  KeystoreDeviceGrantStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _activeUidKey = 'knz_trusted_device_active_uid';
  static const _secretPrefix = 'knz_trusted_device_secret_';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readActiveUid() => _storage.read(key: _activeUidKey);

  @override
  Future<String?> readSecret(String uid) =>
      _storage.read(key: '$_secretPrefix$uid');

  @override
  Future<void> writeGrant(String uid, String secret) async {
    await _storage.write(key: '$_secretPrefix$uid', value: secret);
    await _storage.write(key: _activeUidKey, value: uid);
  }

  @override
  Future<void> deleteGrant(String uid) async {
    await _storage.delete(key: '$_secretPrefix$uid');
    if (await readActiveUid() == uid) {
      await _storage.delete(key: _activeUidKey);
    }
  }
}

class TrustedDeviceService {
  TrustedDeviceService(
    this._repository, {
    SecureDeviceGrantStore? secureStore,
    DateTime Function()? now,
  }) : _secureStore = secureStore ?? KeystoreDeviceGrantStore(),
       _now = now ?? (() => DateTime.now().toUtc());

  final TrustedDeviceRepository _repository;
  final SecureDeviceGrantStore _secureStore;
  final DateTime Function() _now;

  Future<void> enroll(AppUser user, {required int accessGeneration}) async {
    final current = await _repository.getDeviceGrant(user.id);
    final existingSecret = await _secureStore.readSecret(user.id);
    final canRefresh = current?.isEnabled == true && existingSecret != null;
    final generation = canRefresh
        ? current!.generation
        : (current?.generation ?? 0) + 1;
    final secret = existingSecret ?? _newSecret();
    final now = _now().toUtc();
    final grant = DeviceAuthGrant(
      uid: user.id,
      state: 'enabled',
      generation: generation,
      enrolledAt: canRefresh ? current!.enrolledAt : now,
      lastVerifiedAt: now,
      accessGeneration: accessGeneration,
      profileDigest: _profileDigest(user, secret),
    );

    await _secureStore.writeGrant(user.id, secret);
    try {
      await _repository.saveDeviceGrant(grant);
    } catch (_) {
      if (!canRefresh) await _secureStore.deleteGrant(user.id);
      rethrow;
    }
  }

  Future<AppUser?> restore({String? expectedUid}) async {
    final runtime = await _repository.getAuthRuntimeState();
    if (runtime.pendingFirebaseSignOutUid != null) return null;
    final uid = await _secureStore.readActiveUid();
    if (uid == null || uid.isEmpty) return null;
    if (expectedUid != null && uid != expectedUid) return null;
    final secret = await _secureStore.readSecret(uid);
    final grant = await _repository.getDeviceGrant(uid);
    final user = await _repository.getByFirebaseUid(uid);
    if (secret == null || grant == null || user == null || !grant.isEnabled) {
      return null;
    }
    final expected = _profileDigest(user, secret);
    if (!_constantTimeEquals(expected, grant.profileDigest)) return null;
    return user.canAccess ? user : null;
  }

  Future<void> beginSignOut(String uid, {String reason = 'manual'}) async {
    await _repository.revokeDeviceGrant(uid, reason);
    await _repository.setPendingFirebaseSignOut(uid);
    await _secureStore.deleteGrant(uid);
  }

  Future<void> completeSignOut() => _repository.setPendingFirebaseSignOut(null);

  Future<String?> get pendingFirebaseSignOutUid async =>
      (await _repository.getAuthRuntimeState()).pendingFirebaseSignOutUid;

  Future<String?> get activeUid => _secureStore.readActiveUid();

  String _newSecret() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  String _profileDigest(AppUser user, String secret) {
    final profile = jsonEncode({
      'uid': user.id,
      'email': user.email.trim().toLowerCase(),
      'username': user.username,
      'role': user.role,
      'status': user.accountStatus,
      'active': user.isActive,
    });
    return Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(profile)).toString();
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}

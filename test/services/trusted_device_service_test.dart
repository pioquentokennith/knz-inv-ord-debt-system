import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/device_auth_grant.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/services/trusted_device_service.dart';

class _Repository implements TrustedDeviceRepository {
  AppUser? user;
  DeviceAuthGrant? grant;
  AuthRuntimeState runtime = const AuthRuntimeState(operationGeneration: 0);

  @override
  Future<AppUser?> getByFirebaseUid(String uid) async =>
      user?.id == uid ? user : null;

  @override
  Future<DeviceAuthGrant?> getDeviceGrant(String uid) async =>
      grant?.uid == uid ? grant : null;

  @override
  Future<AuthRuntimeState> getAuthRuntimeState() async => runtime;

  @override
  Future<void> saveDeviceGrant(DeviceAuthGrant value) async {
    grant = value;
    runtime = AuthRuntimeState(
      lastActiveUid: value.uid,
      operationGeneration: runtime.operationGeneration + 1,
    );
  }

  @override
  Future<void> revokeDeviceGrant(String uid, String reason) async {
    final current = grant;
    if (current == null || current.uid != uid) return;
    grant = DeviceAuthGrant(
      uid: current.uid,
      state: 'revoked',
      generation: current.generation,
      enrolledAt: current.enrolledAt,
      lastVerifiedAt: current.lastVerifiedAt,
      accessGeneration: current.accessGeneration,
      profileDigest: current.profileDigest,
      revokedAt: DateTime.utc(2026, 1, 2),
      revocationReason: reason,
    );
  }

  @override
  Future<void> setPendingFirebaseSignOut(String? uid) async {
    runtime = AuthRuntimeState(
      lastActiveUid: runtime.lastActiveUid,
      pendingFirebaseSignOutUid: uid,
      operationGeneration: runtime.operationGeneration + 1,
    );
  }
}

class _SecureStore implements SecureDeviceGrantStore {
  String? activeUid;
  final secrets = <String, String>{};

  @override
  Future<void> deleteGrant(String uid) async {
    secrets.remove(uid);
    if (activeUid == uid) activeUid = null;
  }

  @override
  Future<String?> readActiveUid() async => activeUid;

  @override
  Future<String?> readSecret(String uid) async => secrets[uid];

  @override
  Future<void> writeGrant(String uid, String secret) async {
    activeUid = uid;
    secrets[uid] = secret;
  }
}

AppUser _user({String role = 'Staff'}) => AppUser(
  id: 'firebase-uid',
  username: 'staff_user',
  name: 'Staff User',
  email: 'staff@example.com',
  role: role,
  accountStatus: 'approved',
  isActive: true,
  createdAt: DateTime.utc(2026),
);

void main() {
  test('online enrollment enables automatic trusted-device restore', () async {
    final repository = _Repository()..user = _user();
    final secureStore = _SecureStore();
    final service = TrustedDeviceService(
      repository,
      secureStore: secureStore,
      now: () => DateTime.utc(2026),
    );

    await service.enroll(repository.user!, accessGeneration: 4);

    expect((await service.restore())?.id, 'firebase-uid');
    expect(repository.grant?.accessGeneration, 4);
    expect(secureStore.activeUid, 'firebase-uid');
  });

  test('plain cached approval without secure grant cannot restore', () async {
    final repository = _Repository()..user = _user();
    final service = TrustedDeviceService(
      repository,
      secureStore: _SecureStore(),
    );

    expect(await service.restore(), isNull);
  });

  test('profile tampering invalidates the device grant', () async {
    final repository = _Repository()..user = _user();
    final service = TrustedDeviceService(
      repository,
      secureStore: _SecureStore(),
      now: () => DateTime.utc(2026),
    );
    await service.enroll(repository.user!, accessGeneration: 1);

    repository.user = _user(role: 'Administrator');

    expect(await service.restore(), isNull);
  });

  test('manual sign-out revokes metadata and removes secure secret', () async {
    final repository = _Repository()..user = _user();
    final secureStore = _SecureStore();
    final service = TrustedDeviceService(
      repository,
      secureStore: secureStore,
      now: () => DateTime.utc(2026),
    );
    await service.enroll(repository.user!, accessGeneration: 1);

    await service.beginSignOut('firebase-uid');

    expect(await service.restore(), isNull);
    expect(repository.grant?.state, 'revoked');
    expect(repository.runtime.pendingFirebaseSignOutUid, 'firebase-uid');
    expect(secureStore.activeUid, isNull);
  });

  test('Firebase UID mismatch cannot restore another partition', () async {
    final repository = _Repository()..user = _user();
    final service = TrustedDeviceService(
      repository,
      secureStore: _SecureStore(),
      now: () => DateTime.utc(2026),
    );
    await service.enroll(repository.user!, accessGeneration: 1);

    expect(await service.restore(expectedUid: 'different-uid'), isNull);
  });
}

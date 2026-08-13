import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/device_auth_grant.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/repositories/user_repository.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:knz_scent_admin/services/cloud_auth_service.dart';
import 'package:knz_scent_admin/services/trusted_device_service.dart';

class _Profiles implements UserRepository {
  final profiles = <String, AppUser>{};
  final grants = <String, DeviceAuthGrant>{};
  AuthRuntimeState runtime = const AuthRuntimeState(operationGeneration: 0);

  @override
  Future<AppUser> cacheAuthorizedProfile(AppUser user) async {
    profiles[user.id] = user;
    return user;
  }

  @override
  Future<AppUser?> getByFirebaseUid(String uid) async => profiles[uid];

  @override
  Future<DeviceAuthGrant?> getDeviceGrant(String uid) async => grants[uid];

  @override
  Future<AuthRuntimeState> getAuthRuntimeState() async => runtime;

  @override
  Future<void> saveDeviceGrant(DeviceAuthGrant grant) async {
    grants[grant.uid] = grant;
    runtime = AuthRuntimeState(
      lastActiveUid: grant.uid,
      operationGeneration: runtime.operationGeneration + 1,
    );
  }

  @override
  Future<void> revokeDeviceGrant(String uid, String reason) async {
    grants.remove(uid);
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

class _SwitchingCloud implements ICloudAuthService {
  CloudAuthResult next = const CloudAuthResult(status: 'signed_out');
  String? signedInUid;

  @override
  bool get isAvailable => true;

  @override
  String? get currentUid => signedInUid;

  @override
  Future<CloudAuthResult> completeRegistration() async =>
      const CloudAuthResult(status: 'pending');

  @override
  Future<void> deferRegistration() async => signedInUid = null;

  @override
  Future<CloudAuthResult> login(String email, String password) async {
    signedInUid = next.uid;
    return next;
  }

  @override
  Future<void> signOut() async => signedInUid = null;

  @override
  Future<CloudAuthResult> restoreSession() async => next;

  @override
  Future<CloudAuthResult> revalidateAccess(String uid) async => next;

  @override
  Future<CloudAuthResult> requestRegistration({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async => const CloudAuthResult(status: 'pending');

  @override
  Future<void> sendPasswordReset(String email) async {}
}

CloudAuthResult _approved(String uid) => CloudAuthResult(
  status: 'approved',
  active: true,
  uid: uid,
  email: '$uid@example.com',
  username: '${uid}_user',
  name: 'User $uid',
  role: 'Staff',
  createdAt: DateTime.utc(2026),
);

void main() {
  test(
    'login, logout, and user switching retain separate UID profiles',
    () async {
      final profiles = _Profiles();
      final cloud = _SwitchingCloud();
      final auth = AuthService(
        profiles,
        cloudAuth: cloud,
        trustedDevice: TrustedDeviceService(
          profiles,
          secureStore: _SecureStore(),
          now: () => DateTime.utc(2026),
        ),
      );

      cloud.next = _approved('user-a');
      expect(
        (await auth.login('a@example.com', 'password')).user?.id,
        'user-a',
      );
      await auth.logout();
      expect(cloud.signedInUid, isNull);

      cloud.next = _approved('user-b');
      expect(
        (await auth.login('b@example.com', 'password')).user?.id,
        'user-b',
      );
      expect(profiles.profiles.keys, containsAll(['user-a', 'user-b']));
      expect(profiles.profiles['user-a']?.email, 'user-a@example.com');
      expect(profiles.profiles['user-b']?.email, 'user-b@example.com');
    },
  );
}

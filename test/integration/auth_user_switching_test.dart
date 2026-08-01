import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/repositories/user_repository.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:knz_scent_admin/services/cloud_auth_service.dart';

class _Profiles implements UserRepository {
  final profiles = <String, AppUser>{};

  @override
  Future<AppUser> cacheAuthorizedProfile(AppUser user) async {
    profiles[user.id] = user;
    return user;
  }

  @override
  Future<AppUser?> getByFirebaseUid(String uid) async => profiles[uid];
}

class _SwitchingCloud implements ICloudAuthService {
  CloudAuthResult next = const CloudAuthResult(status: 'signed_out');
  String? signedInUid;

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
      final auth = AuthService(profiles, cloudAuth: cloud);

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

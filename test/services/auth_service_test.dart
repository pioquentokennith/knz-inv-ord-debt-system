import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/device_auth_grant.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/repositories/user_repository.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:knz_scent_admin/services/cloud_auth_service.dart';
import 'package:knz_scent_admin/services/trusted_device_service.dart';

class _UserRepository implements UserRepository {
  AppUser? cached;
  DeviceAuthGrant? grant;
  AuthRuntimeState runtime = const AuthRuntimeState(operationGeneration: 0);

  @override
  Future<AppUser> cacheAuthorizedProfile(AppUser user) async {
    cached = user;
    return user;
  }

  @override
  Future<AppUser?> getByFirebaseUid(String uid) async =>
      cached?.id == uid ? cached : null;

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
      revokedAt: DateTime.utc(2026),
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

AuthService _service(_UserRepository repository, _CloudAuth cloud) =>
    AuthService(
      repository,
      cloudAuth: cloud,
      trustedDevice: TrustedDeviceService(
        repository,
        secureStore: _SecureStore(),
        now: () => DateTime.utc(2026),
      ),
    );

class _CloudAuth implements ICloudAuthService {
  CloudAuthResult loginResult = const CloudAuthResult(status: 'denied');
  CloudAuthResult restoreResult = const CloudAuthResult(status: 'signed_out');
  Object? passwordResetError;
  String? passwordResetEmail;
  bool signedOut = false;
  CloudAuthResult registrationResult = const CloudAuthResult(status: 'pending');
  Map<String, String>? registrationInput;

  bool available = true;

  @override
  bool get isAvailable => available;

  @override
  String? get currentUid => loginResult.uid;

  @override
  Future<CloudAuthResult> completeRegistration() async => registrationResult;

  @override
  Future<void> deferRegistration() async => signedOut = true;

  @override
  Future<CloudAuthResult> login(String email, String password) async =>
      loginResult;

  @override
  Future<CloudAuthResult> requestRegistration({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    registrationInput = {
      'name': name,
      'username': username,
      'email': email,
      'password': password,
    };
    return registrationResult;
  }

  @override
  Future<CloudAuthResult> restoreSession() async => restoreResult;

  @override
  Future<CloudAuthResult> revalidateAccess(String uid) async => restoreResult;

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetEmail = email;
    final error = passwordResetError;
    if (error != null) throw error;
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

CloudAuthResult _approved() => CloudAuthResult(
  status: 'approved',
  active: true,
  uid: 'firebase-uid',
  email: 'staff@example.com',
  username: 'staff_user',
  name: 'Staff User',
  role: 'Staff',
  createdAt: DateTime.utc(2026),
);

void main() {
  test(
    'registration delegates account creation and requires verification',
    () async {
      final cloud = _CloudAuth()
        ..registrationResult = const CloudAuthResult(
          status: 'verification_required',
          error: 'Open the Firebase verification link.',
        );
      final repository = _UserRepository();
      final service = _service(repository, cloud);

      final result = await service.requestRegistration(
        name: 'Pending Staff',
        username: 'pending_staff',
        email: 'staff@example.com',
        password: 'StrongPassword1!',
      );

      expect(result.status, 'verification_required');
      expect(result.success, isFalse);
      expect(cloud.registrationInput, {
        'name': 'Pending Staff',
        'username': 'pending_staff',
        'email': 'staff@example.com',
        'password': 'StrongPassword1!',
      });
    },
  );

  test('caches only approved active Firebase UID profiles', () async {
    final repository = _UserRepository();
    final cloud = _CloudAuth()..loginResult = _approved();
    final service = _service(repository, cloud);

    final result = await service.login('staff@example.com', 'password');

    expect(result.success, isTrue);
    expect(result.user?.id, 'firebase-uid');
    expect(result.user?.role, 'Staff');
    expect(repository.cached?.username, 'staff_user');
  });

  test(
    'pending, rejected, and suspended users never enter protected state',
    () async {
      for (final status in ['pending', 'rejected', 'suspended']) {
        final repository = _UserRepository();
        final cloud = _CloudAuth()
          ..loginResult = CloudAuthResult(
            status: status,
            active: false,
            error: CloudAuthService.accountStatusMessage(status),
          );
        final result = await _service(
          repository,
          cloud,
        ).login('user@example.com', 'password');

        expect(result.success, isFalse, reason: status);
        expect(repository.cached, isNull, reason: status);
        expect(result.message, isNotEmpty, reason: status);
      }
    },
  );

  test(
    'account status messages distinguish pending, rejected, and suspended',
    () {
      expect(
        CloudAuthService.accountStatusMessage('pending'),
        contains('pending administrator approval'),
      );
      expect(
        CloudAuthService.accountStatusMessage('rejected'),
        contains('rejected'),
      );
      expect(
        CloudAuthService.accountStatusMessage('suspended'),
        contains('suspended'),
      );
    },
  );

  test('offline restore uses only a previously approved cached UID', () async {
    final repository = _UserRepository()
      ..cached = AppUser(
        id: 'firebase-uid',
        username: 'staff_user',
        name: 'Staff User',
        email: 'staff@example.com',
        role: 'Staff',
        accountStatus: 'approved',
        isActive: true,
        createdAt: DateTime.utc(2026),
      );
    final cloud = _CloudAuth()
      ..restoreResult = const CloudAuthResult(
        status: 'offline',
        uid: 'firebase-uid',
        mayUseOfflineCache: true,
      );

    final secureStore = _SecureStore();
    final trusted = TrustedDeviceService(
      repository,
      secureStore: secureStore,
      now: () => DateTime.utc(2026),
    );
    await trusted.enroll(repository.cached!, accessGeneration: 1);
    final result = await AuthService(
      repository,
      cloudAuth: cloud,
      trustedDevice: trusted,
    ).restoreSession();

    expect(result.success, isTrue);
    expect(result.user?.id, 'firebase-uid');
  });

  test('logout ends the Firebase session', () async {
    final cloud = _CloudAuth();
    final repository = _UserRepository();
    await _service(repository, cloud).logout();
    expect(cloud.signedOut, isTrue);
  });

  test(
    'unavailable Firebase leaves durable sign-out cleanup pending',
    () async {
      final repository = _UserRepository()
        ..cached = AppUser(
          id: 'firebase-uid',
          username: 'staff_user',
          name: 'Staff User',
          email: 'staff@example.com',
          role: 'Staff',
          accountStatus: 'approved',
          isActive: true,
          createdAt: DateTime.utc(2026),
        );
      final secureStore = _SecureStore();
      final trusted = TrustedDeviceService(
        repository,
        secureStore: secureStore,
        now: () => DateTime.utc(2026),
      );
      await trusted.enroll(repository.cached!, accessGeneration: 1);
      final cloud = _CloudAuth()..available = false;
      final service = AuthService(
        repository,
        cloudAuth: cloud,
        trustedDevice: trusted,
      );

      await service.logout();

      expect(repository.runtime.pendingFirebaseSignOutUid, 'firebase-uid');
      expect(await trusted.restore(), isNull);
    },
  );

  test('password-reset delivery failures propagate to the caller', () async {
    final cloud = _CloudAuth()
      ..passwordResetError = const AuthOperationException('Reset failed.');
    final repository = _UserRepository();
    final service = _service(repository, cloud);

    await expectLater(
      service.sendPasswordReset('staff@example.com'),
      throwsA(isA<AuthOperationException>()),
    );
  });

  test('successful password-reset requests reach the cloud service', () async {
    final cloud = _CloudAuth();
    final repository = _UserRepository();
    final service = _service(repository, cloud);

    await service.sendPasswordReset('staff@example.com');

    expect(cloud.passwordResetEmail, 'staff@example.com');
  });
}

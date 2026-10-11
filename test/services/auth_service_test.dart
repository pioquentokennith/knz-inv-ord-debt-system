import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:knz_scent_admin/core/app_state.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/models/cloud_authorization.dart';
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
  int revalidationCalls = 0;
  Object? revalidationError;
  Object? signOutError;

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
  Future<CloudAuthResult> revalidateAccess(String uid) async {
    revalidationCalls++;
    if (revalidationError != null) throw revalidationError!;
    return restoreResult;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetEmail = email;
    final error = passwordResetError;
    if (error != null) throw error;
  }

  @override
  Future<void> signOut() async {
    if (signOutError != null) throw signOutError!;
    signedOut = true;
  }
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first offline login cannot create a trusted local session', () async {
    final repository = _UserRepository();
    final cloud = _CloudAuth()
      ..loginResult = const CloudAuthResult(status: 'offline');
    final service = _service(repository, cloud);
    expect(
      (await service.login('staff@example.com', 'password')).success,
      isFalse,
    );
    expect(repository.cached, isNull);
    expect(repository.grant, isNull);
    expect((await service.restoreTrustedDevice()).success, isFalse);
  });

  group('trusted local access is independent of cloud reauthentication', () {
    late Directory directory;
    late _UserRepository repository;
    late _SecureStore secureStore;
    late _CloudAuth cloud;
    late AuthService service;
    final state = AppState();

    AuthService reopen() => AuthService(
      repository,
      cloudAuth: cloud,
      trustedDevice: TrustedDeviceService(
        repository,
        secureStore: secureStore,
        now: () => DateTime.utc(2046),
      ),
    );

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      directory = await Directory.systemTemp.createTemp('offline-auth-');
      await databaseFactory.setDatabasesPath(directory.path);
      await DatabaseHelper.instance.database;
    });
    tearDownAll(() async {
      await (await DatabaseHelper.instance.database).close();
      await directory.delete(recursive: true);
    });
    setUp(() async {
      repository = _UserRepository();
      secureStore = _SecureStore();
      cloud = _CloudAuth()..loginResult = _approved();
      service = AuthService(
        repository,
        cloudAuth: cloud,
        trustedDevice: TrustedDeviceService(
          repository,
          secureStore: secureStore,
          now: () => DateTime.utc(2026),
        ),
      );
      expect(
        (await service.login('staff@example.com', 'password')).success,
        isTrue,
      );
      service =
          reopen(); // New services reuse only durable profile/grant/secret.
      state.configure(
        authService: service,
        stopSynchronization: () async {},
        cancelNotifications: () async {},
        syncBusinessAlerts: (_, _) async {},
      );
      await state.restoreTrustedDevice();
    });
    tearDown(() async {
      cloud.signOutError = null;
      await state.logout();
    });

    test(
      'online enrollment reopens offline decades later without Firebase',
      () async {
        expect(state.isLoggedIn, isTrue);
        expect(state.isOfflineSession, isTrue);
        expect(state.currentUser?.role, 'Staff');
        expect(state.activeUser, 'firebase-uid');
        expect(cloud.revalidationCalls, 0);
        expect((await reopen().restoreTrustedDevice()).success, isTrue);
      },
    );

    for (final result in [
      const CloudAuthResult(
        status: 'reauth_required',
        authorization: CloudAuthorization.reauthRequired,
      ),
      const CloudAuthResult(
        status: 'offline',
        authorization: CloudAuthorization.offlineAllowed,
      ),
      const CloudAuthResult(status: 'unavailable'),
    ]) {
      test(
        '${result.status} pauses sync without deleting trusted session',
        () async {
          cloud.restoreResult = result;
          await state.reconcileCloudPrincipal('firebase-uid');
          expect(state.isLoggedIn, isTrue);
          expect(state.isOfflineSession, isTrue);
          expect(state.cloudAuthorization, result.authorization);
          expect(repository.grant?.isEnabled, isTrue);
          expect(secureStore.secrets, isNotEmpty);
          expect((await reopen().restoreTrustedDevice()).success, isTrue);
          expect(cloud.signedOut, isFalse);
        },
      );
    }

    test('timeout exceptions preserve local access', () async {
      cloud.revalidationError = TimeoutException('Firebase unavailable');
      await state.reconcileCloudPrincipal('firebase-uid');
      expect(state.isLoggedIn, isTrue);
      expect(
        state.cloudAuthorization,
        CloudAuthorization.temporarilyUnavailable,
      );
      expect((await reopen().restoreTrustedDevice()).success, isTrue);
    });

    for (final principal in <String?>[null, 'other-uid']) {
      test(
        'principal $principal blocks sync and preserves the trusted UID',
        () async {
          await state.reconcileCloudPrincipal(principal);
          expect(state.isLoggedIn, isTrue);
          expect(state.activeUser, 'firebase-uid');
          expect(state.currentUser?.email, 'staff@example.com');
          expect(state.cloudAuthorization, CloudAuthorization.reauthRequired);
          expect(cloud.revalidationCalls, 0);
          expect(
            (await reopen().restoreTrustedDevice()).user?.id,
            'firebase-uid',
          );
        },
      );
    }

    test(
      'logout revokes trusted UID even if Firebase has a different UID',
      () async {
        cloud.loginResult = const CloudAuthResult(
          status: 'approved',
          uid: 'other-uid',
        );
        await state.logout();
        expect(repository.grant?.isEnabled, isFalse);
        expect(secureStore.secrets, isEmpty);
        expect((await reopen().restoreTrustedDevice()).success, isFalse);
      },
    );

    for (final authorization in CloudAuthorization.values.where(
      (a) => a.revokesLocalAccess,
    )) {
      test('confirmed ${authorization.name} revokes local access', () async {
        cloud.restoreResult = CloudAuthResult(
          status: authorization.name,
          authorization: authorization,
        );
        await state.reconcileCloudPrincipal('firebase-uid');
        expect(state.isLoggedIn, isFalse);
        expect(state.currentUser, isNull);
        expect(secureStore.secrets, isEmpty);
        expect((await reopen().restoreTrustedDevice()).success, isFalse);
      });
    }

    test(
      'offline logout removes trust even when Firebase cleanup fails',
      () async {
        cloud.available = false;
        cloud.signOutError = StateError('Firebase not initialized');
        await expectLater(state.logout(), throwsStateError);
        expect(state.isLoggedIn, isFalse);
        expect(secureStore.secrets, isEmpty);
        expect((await reopen().restoreTrustedDevice()).success, isFalse);
      },
    );

    test(
      'wrong UID revalidation result cannot replace cached identity',
      () async {
        cloud.restoreResult = CloudAuthResult(
          status: 'approved',
          active: true,
          uid: 'other-uid',
          email: 'other@example.com',
          username: 'other',
          name: 'Other',
          role: 'Administrator',
        );
        await state.reconcileCloudPrincipal('firebase-uid');
        expect(state.activeUser, 'firebase-uid');
        expect(state.currentUser?.role, 'Staff');
        expect(repository.cached?.id, 'firebase-uid');
        expect(state.cloudAuthorization, CloudAuthorization.reauthRequired);
      },
    );
  });

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

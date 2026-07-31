import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/repositories/user_repository.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:knz_scent_admin/services/cloud_auth_service.dart';

class _UserRepository implements UserRepository {
  AppUser? cached;

  @override
  Future<AppUser> cacheAuthorizedProfile(AppUser user) async {
    cached = user;
    return user;
  }

  @override
  Future<AppUser?> getByFirebaseUid(String uid) async =>
      cached?.id == uid ? cached : null;
}

class _CloudAuth implements ICloudAuthService {
  CloudAuthResult loginResult = const CloudAuthResult(status: 'denied');
  CloudAuthResult restoreResult = const CloudAuthResult(status: 'signed_out');
  Object? passwordResetError;
  String? passwordResetEmail;
  bool signedOut = false;
  CloudAuthResult registrationResult = const CloudAuthResult(status: 'pending');
  Map<String, String>? registrationInput;

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
      final service = AuthService(_UserRepository(), cloudAuth: cloud);

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
    final service = AuthService(repository, cloudAuth: cloud);

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
        final result = await AuthService(
          repository,
          cloudAuth: cloud,
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

    final result = await AuthService(
      repository,
      cloudAuth: cloud,
    ).restoreSession();

    expect(result.success, isTrue);
    expect(result.user?.id, 'firebase-uid');
  });

  test('logout ends the Firebase session', () async {
    final cloud = _CloudAuth();
    await AuthService(_UserRepository(), cloudAuth: cloud).logout();
    expect(cloud.signedOut, isTrue);
  });

  test('password-reset delivery failures propagate to the caller', () async {
    final cloud = _CloudAuth()
      ..passwordResetError = const AuthOperationException('Reset failed.');
    final service = AuthService(_UserRepository(), cloudAuth: cloud);

    await expectLater(
      service.sendPasswordReset('staff@example.com'),
      throwsA(isA<AuthOperationException>()),
    );
  });

  test('successful password-reset requests reach the cloud service', () async {
    final cloud = _CloudAuth();
    final service = AuthService(_UserRepository(), cloudAuth: cloud);

    await service.sendPasswordReset('staff@example.com');

    expect(cloud.passwordResetEmail, 'staff@example.com');
  });
}

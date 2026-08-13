import '../models/user_model.dart';
import '../repositories/user_repository.dart';
import 'cloud_auth_service.dart';
import 'trusted_device_service.dart';

class AuthResult {
  const AuthResult({
    required this.status,
    this.user,
    this.message,
    this.diagnosticCode,
  });

  final String status;
  final AppUser? user;
  final String? message;
  final String? diagnosticCode;

  bool get success => user?.canAccess ?? false;
}

abstract class IAuthService {
  Future<AuthResult> login(String email, String password);
  Future<AuthResult> requestRegistration({
    required String name,
    required String username,
    required String email,
    required String password,
  });
  Future<AuthResult> completeRegistration();
  Future<void> deferRegistration();
  Future<void> sendPasswordReset(String email);
  Future<AuthResult> restoreSession();
  Future<AuthResult> restoreTrustedDevice();
  Future<AuthResult> revalidateAccess(String uid);
  Future<void> completePendingSignOut();
  Future<void> revokeAccess(String uid, String reason);
  Future<void> logout();
}

class AuthService implements IAuthService {
  AuthService(
    this._repo, {
    ICloudAuthService? cloudAuth,
    TrustedDeviceService? trustedDevice,
  }) : _cloudAuth = cloudAuth ?? CloudAuthService.instance,
       _trustedDevice = trustedDevice ?? TrustedDeviceService(_repo);

  final UserRepository _repo;
  final ICloudAuthService _cloudAuth;
  final TrustedDeviceService _trustedDevice;

  @override
  Future<AuthResult> login(String email, String password) async {
    final result = await _cloudAuth.login(email, password);
    return _resolve(result, enrollDevice: true);
  }

  @override
  Future<AuthResult> requestRegistration({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    final result = await _cloudAuth.requestRegistration(
      name: name,
      username: username,
      email: email,
      password: password,
    );
    return AuthResult(
      status: result.status,
      message: result.error,
      diagnosticCode: result.diagnosticCode,
    );
  }

  @override
  Future<AuthResult> completeRegistration() async {
    final result = await _cloudAuth.completeRegistration();
    return AuthResult(
      status: result.status,
      message: result.error,
      diagnosticCode: result.diagnosticCode,
    );
  }

  @override
  Future<void> deferRegistration() => _cloudAuth.deferRegistration();

  @override
  Future<void> sendPasswordReset(String email) =>
      _cloudAuth.sendPasswordReset(email);

  @override
  Future<AuthResult> restoreSession() async {
    final result = await _cloudAuth.restoreSession();
    if (result.mayUseOfflineCache && result.uid != null) {
      final trusted = await _trustedDevice.restore(expectedUid: result.uid);
      if (trusted != null) {
        return AuthResult(status: 'offline', user: trusted);
      }
    }
    return _resolve(result, enrollDevice: result.canAccess);
  }

  @override
  Future<AuthResult> restoreTrustedDevice() async {
    final user = await _trustedDevice.restore();
    return user == null
        ? const AuthResult(status: 'signed_out')
        : AuthResult(status: 'offline', user: user);
  }

  @override
  Future<AuthResult> revalidateAccess(String uid) async {
    final result = await _cloudAuth.revalidateAccess(uid);
    if (result.status == 'offline') {
      return const AuthResult(status: 'offline');
    }
    if (!result.canAccess) {
      return AuthResult(
        status: result.status,
        message: result.error,
        diagnosticCode: result.diagnosticCode,
      );
    }
    return _resolve(result, enrollDevice: true);
  }

  Future<AuthResult> _resolve(
    CloudAuthResult result, {
    bool enrollDevice = false,
  }) async {
    if (!result.canAccess) {
      return AuthResult(
        status: result.status,
        message: result.error,
        diagnosticCode: result.diagnosticCode,
      );
    }
    final user = AppUser(
      id: result.uid!,
      username: result.username!,
      name: result.name!,
      email: result.email!,
      role: result.role!,
      accountStatus: result.status,
      isActive: result.active,
      legacyOwnerKey: result.legacyOwnerKey,
      createdAt: result.createdAt ?? DateTime.now(),
    );
    try {
      final cached = await _repo.cacheAuthorizedProfile(user);
      if (enrollDevice) {
        await _trustedDevice.enroll(
          cached,
          accessGeneration: result.accessGeneration,
        );
      }
      return AuthResult(status: result.status, user: cached);
    } on StateError catch (error) {
      await _cloudAuth.signOut();
      return AuthResult(status: 'migration_required', message: error.message);
    }
  }

  @override
  Future<void> logout() async {
    final uid =
        await _trustedDevice.pendingFirebaseSignOutUid ??
        _cloudAuth.currentUid ??
        await _trustedDevice.activeUid;
    if (uid != null) await _trustedDevice.beginSignOut(uid);
    await _cloudAuth.signOut();
    if (_cloudAuth.isAvailable && _cloudAuth.currentUid == null) {
      await _trustedDevice.completeSignOut();
    }
  }

  @override
  Future<void> completePendingSignOut() async {
    if (await _trustedDevice.pendingFirebaseSignOutUid == null) return;
    await _cloudAuth.signOut();
    if (_cloudAuth.isAvailable && _cloudAuth.currentUid == null) {
      await _trustedDevice.completeSignOut();
    }
  }

  @override
  Future<void> revokeAccess(String uid, String reason) async {
    await _trustedDevice.beginSignOut(uid, reason: reason);
    await _cloudAuth.signOut();
    if (_cloudAuth.isAvailable && _cloudAuth.currentUid == null) {
      await _trustedDevice.completeSignOut();
    }
  }
}

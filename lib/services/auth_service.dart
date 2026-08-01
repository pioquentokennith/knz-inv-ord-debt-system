import '../models/user_model.dart';
import '../repositories/user_repository.dart';
import 'cloud_auth_service.dart';

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
  Future<void> logout();
}

class AuthService implements IAuthService {
  AuthService(this._repo, {ICloudAuthService? cloudAuth})
    : _cloudAuth = cloudAuth ?? CloudAuthService.instance;

  final UserRepository _repo;
  final ICloudAuthService _cloudAuth;

  @override
  Future<AuthResult> login(String email, String password) async {
    final result = await _cloudAuth.login(email, password);
    return _resolve(result);
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
      final cached = await _repo.getByFirebaseUid(result.uid!);
      if (cached?.canAccess ?? false) {
        return AuthResult(status: 'approved', user: cached);
      }
    }
    return _resolve(result);
  }

  Future<AuthResult> _resolve(CloudAuthResult result) async {
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
      return AuthResult(
        status: result.status,
        user: await _repo.cacheAuthorizedProfile(user),
      );
    } on StateError catch (error) {
      await _cloudAuth.signOut();
      return AuthResult(status: 'migration_required', message: error.message);
    }
  }

  @override
  Future<void> logout() => _cloudAuth.signOut();
}

// ─────────────────────────────────────────────────────────────────────────────
// auth_service.dart — Interface + Implementation (Abstraction + Polymorphism)
// IAuthService defines the contract; AuthService implements it.
// FIXED: Removed the anti-pattern cast "(_repo as LocalUserRepository)".
//        register() is now part of UserRepository interface.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/user_model.dart';
import '../repositories/user_repository.dart';

/// Abstract contract for authentication business logic (Abstraction).
abstract class IAuthService {
  Future<AppUser?> login(String username, String password);
  Future<String?>  register(String name, String username, String password,
      String confirm, String email);
  Future<String?>  resetPassword(String username, String newPassword, String confirm);
}

/// Concrete implementation — all auth business logic.
class AuthService implements IAuthService {
  final UserRepository _repo;
  AuthService(this._repo);

  @override
  Future<AppUser?> login(String username, String password) {
    if (username.trim().isEmpty || password.isEmpty) return Future.value(null);
    return _repo.login(username.trim(), password);
  }

  @override
  Future<String?> register(
      String name, String username, String password,
      String confirm, String email) async {
    if (name.trim().isEmpty)     return 'Name is required';
    if (username.trim().isEmpty) return 'Username is required';
    if (password.length < 6)     return 'Password must be at least 6 characters';
    if (password != confirm)     return 'Passwords do not match';

    final exists = await _repo.usernameExists(username);
    if (exists) return 'Username already taken';

    // Delegates to repo — no direct cast needed (DIP: depend on abstraction)
    final success = await _repo.register(
      name.trim(),
      username.trim(),
      password,
      email: email,
    );
    return success ? null : 'Registration failed. Please try again.';
  }

  @override
  Future<String?> resetPassword(
      String username, String newPassword, String confirm) async {
    if (username.trim().isEmpty) return 'Username is required';
    if (newPassword.length < 6)  return 'Password must be at least 6 characters';
    if (newPassword != confirm)  return 'Passwords do not match';

    final success = await _repo.resetPassword(username.trim(), newPassword);
    return success ? null : 'Username not found';
  }
}

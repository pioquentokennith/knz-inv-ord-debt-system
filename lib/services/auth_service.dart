// ─────────────────────────────────────────────────────────────────────────────
// auth_service.dart — Authentication business logic
// Purpose : Validates credentials, enforces password rules, and delegates
//           storage operations to UserRepository. Keeps all auth business rules
//           in one place so screens stay thin.
// Interface + Implementation (Abstraction + Polymorphism)
// FIXED: Removed the anti-pattern cast "(_repo as LocalUserRepository)".
//        register() is now part of the UserRepository interface.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/user_model.dart';
import '../repositories/user_repository.dart';

/// Abstract contract for authentication business logic (Abstraction).
/// AppState depends on this interface — not on AuthService directly — so
/// tests can inject a stub without touching SQLite.
abstract class IAuthService {
  // Returns the matching AppUser on success; null if credentials are wrong
  Future<AppUser?> login(String username, String password);

  // Returns null on success; returns an error message string on validation failure
  Future<String?>  register(String name, String username, String password,
      String confirm, String email);

  // Returns null on success; returns an error message string on validation failure
  Future<String?>  resetPassword(String username, String newPassword, String confirm);
}

/// Concrete implementation — all authentication business logic lives here.
class AuthService implements IAuthService {
  final UserRepository _repo; // Depends on the abstract interface (DIP)
  AuthService(this._repo);

  // Validates that fields are non-empty before delegating to the repository
  @override
  Future<AppUser?> login(String username, String password) {
    if (username.trim().isEmpty || password.isEmpty) return Future.value(null);
    return _repo.login(username.trim(), password);
  }

  // Enforces all registration rules before saving to the repository
  @override
  Future<String?> register(
      String name, String username, String password,
      String confirm, String email) async {
    // Validate each field in order — return the first error encountered
    if (name.trim().isEmpty)     return 'Name is required';
    if (username.trim().isEmpty) return 'Username is required';
    if (password.length < 6)     return 'Password must be at least 6 characters';
    if (password != confirm)     return 'Passwords do not match';

    // Check for duplicate username before attempting to register
    final exists = await _repo.usernameExists(username);
    if (exists) return 'Username already taken';

    // Delegates to repo — no direct cast needed (DIP: depend on abstraction)
    final success = await _repo.register(
      name.trim(),
      username.trim(),
      password,
      email: email,
    );
    // Return null (success) or a generic error message for unexpected failures
    return success ? null : 'Registration failed. Please try again.';
  }

  // Enforces password reset rules before delegating to the repository
  @override
  Future<String?> resetPassword(
      String username, String newPassword, String confirm) async {
    if (username.trim().isEmpty) return 'Username is required';
    if (newPassword.length < 6)  return 'Password must be at least 6 characters';
    if (newPassword != confirm)  return 'Passwords do not match';

    final success = await _repo.resetPassword(username.trim(), newPassword);
    // 'Username not found' is returned when the repository finds no matching record
    return success ? null : 'Username not found';
  }
}

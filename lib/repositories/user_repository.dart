// ─────────────────────────────────────────────────────────────────────────────
// user_repository.dart — Abstract UserRepository interface
// Purpose : Defines the data-access contract for user authentication.
//           AuthService depends on this interface — not LocalUserRepository —
//           so test stubs can be injected without touching SQLite.
// FIXED: Added register() with optional email param so AuthService no longer
//        needs to cast (_repo as LocalUserRepository). Eliminates anti-pattern.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/user_model.dart';

abstract class UserRepository {
  // Validates credentials and returns the matching AppUser, or null on failure
  Future<AppUser?> login(String username, String password);

  /// [email] is optional — concrete repo decides whether to persist it.
  /// FIX: Use String? to match LocalUserRepository's nullable override.
  // Creates a new user account; returns false if username is already taken
  Future<bool> register(String name, String username, String password,
      {String? email});

  // Updates the stored (hashed) password for the given username
  Future<bool> resetPassword(String username, String newPassword);

  // Returns true if the username is already registered (used for duplicate check)
  Future<bool> usernameExists(String username);
}

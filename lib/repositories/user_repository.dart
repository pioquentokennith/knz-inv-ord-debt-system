// ─────────────────────────────────────────────────────────────────────────────
// user_repository.dart — Abstract UserRepository interface
// FIXED: Added register() with optional email param so AuthService no longer
//        needs to cast (_repo as LocalUserRepository). Eliminates anti-pattern.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/user_model.dart';

abstract class UserRepository {
  Future<AppUser?> login(String username, String password);

  /// [email] is optional — concrete repo decides whether to persist it.
  /// FIX: Use String? to match LocalUserRepository's nullable override.
  Future<bool> register(String name, String username, String password,
      {String? email});

  Future<bool> resetPassword(String username, String newPassword);
  Future<bool> usernameExists(String username);
}

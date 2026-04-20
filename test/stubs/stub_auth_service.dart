// stub_auth_service.dart — In-memory stub for IAuthService
import 'package:uuid/uuid.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/services/auth_service.dart';

class StubAuthService implements IAuthService {
  static const testUsername = 'testuser';
  static const testPassword = 'password123';
  final _uuid = const Uuid();

  @override
  Future<AppUser?> login(String username, String password) async {
    if (username == testUsername && password == testPassword) {
      return AppUser(
        id: _uuid.v4(), username: username,
        role: 'Administrator', createdAt: DateTime.now(),
      );
    }
    return null;
  }

  @override
  Future<String?> register(String name, String username, String password,
      String confirm, String email) async {
    if (password != confirm) return 'Passwords do not match';
    return null;
  }

  @override
  Future<String?> resetPassword(String username, String newPassword, String confirm) async {
    if (newPassword != confirm) return 'Passwords do not match';
    return null;
  }
}

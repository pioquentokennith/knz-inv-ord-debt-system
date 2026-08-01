import '../models/user_model.dart';

abstract class UserRepository {
  Future<AppUser?> getByFirebaseUid(String uid);

  Future<AppUser> cacheAuthorizedProfile(AppUser user);
}

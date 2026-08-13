import '../models/user_model.dart';
import '../models/device_auth_grant.dart';
import '../services/trusted_device_service.dart';

abstract class UserRepository implements TrustedDeviceRepository {
  @override
  Future<AppUser?> getByFirebaseUid(String uid);

  Future<AppUser> cacheAuthorizedProfile(AppUser user);

  @override
  Future<DeviceAuthGrant?> getDeviceGrant(String uid) async => null;

  @override
  Future<AuthRuntimeState> getAuthRuntimeState() async =>
      const AuthRuntimeState(operationGeneration: 0);

  @override
  Future<void> saveDeviceGrant(DeviceAuthGrant grant) async {
    throw UnsupportedError(
      'Device grants are not supported by this repository.',
    );
  }

  @override
  Future<void> revokeDeviceGrant(String uid, String reason) async {}

  @override
  Future<void> setPendingFirebaseSignOut(String? uid) async {}
}

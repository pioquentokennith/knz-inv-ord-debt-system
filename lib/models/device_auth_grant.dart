class DeviceAuthGrant {
  const DeviceAuthGrant({
    required this.uid,
    required this.state,
    required this.generation,
    required this.enrolledAt,
    required this.lastVerifiedAt,
    required this.accessGeneration,
    required this.profileDigest,
    this.revokedAt,
    this.revocationReason,
  });

  final String uid;
  final String state;
  final int generation;
  final DateTime enrolledAt;
  final DateTime lastVerifiedAt;
  final int accessGeneration;
  final String profileDigest;
  final DateTime? revokedAt;
  final String? revocationReason;

  bool get isEnabled => state == 'enabled';

  factory DeviceAuthGrant.fromMap(Map<String, Object?> map) => DeviceAuthGrant(
    uid: map['uid'] as String,
    state: map['state'] as String,
    generation: map['generation'] as int,
    enrolledAt: DateTime.parse(map['enrolled_at'] as String),
    lastVerifiedAt: DateTime.parse(map['last_verified_at'] as String),
    accessGeneration: map['access_generation'] as int,
    profileDigest: map['profile_digest'] as String,
    revokedAt: map['revoked_at'] == null
        ? null
        : DateTime.parse(map['revoked_at'] as String),
    revocationReason: map['revocation_reason'] as String?,
  );
}

class AuthRuntimeState {
  const AuthRuntimeState({
    this.lastActiveUid,
    this.pendingFirebaseSignOutUid,
    required this.operationGeneration,
  });

  final String? lastActiveUid;
  final String? pendingFirebaseSignOutUid;
  final int operationGeneration;

  factory AuthRuntimeState.fromMap(Map<String, Object?> map) =>
      AuthRuntimeState(
        lastActiveUid: map['last_active_uid'] as String?,
        pendingFirebaseSignOutUid:
            map['pending_firebase_signout_uid'] as String?,
        operationGeneration: map['operation_generation'] as int,
      );
}

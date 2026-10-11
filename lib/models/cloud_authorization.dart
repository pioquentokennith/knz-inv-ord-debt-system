/// Cloud capability is independent of a previously trusted local session.
enum CloudAuthorization {
  verified,
  offlineAllowed,
  reauthRequired,
  temporarilyUnavailable,
  suspended,
  rejected,
  disabled,
  deleted,
  expired,
  unauthorized;

  bool get revokesLocalAccess => switch (this) {
    suspended ||
    rejected ||
    disabled ||
    deleted ||
    expired ||
    unauthorized => true,
    _ => false,
  };
}

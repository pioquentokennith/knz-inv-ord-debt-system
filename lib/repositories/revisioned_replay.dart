/// Conservative comparison for the *serialized cloud payload*, after DTO
/// conversion. No business fields or metadata are discarded. Map ordering is
/// irrelevant; array ordering, missing keys, nulls and scalar values are not.
class RevisionedReplay {
  static bool isExact(
    Map<String, dynamic> pending,
    Map<String, dynamic>? remote,
  ) {
    if (remote == null) return false;
    // Legacy outbox operation_id is not persisted in these cloud documents.
    // Require the existing device + timestamp + revision identity instead,
    // as well as equality of the entire cloud result. Never guess for older
    // records that lack this identity.
    for (final key in ['id', 'user_id', 'writer_device_id', 'updated_at']) {
      final value = pending[key];
      if (value is! String || value.trim().isEmpty) return false;
    }
    if (DateTime.tryParse(pending['updated_at'] as String) == null) {
      return false;
    }
    final base = pending['base_revision'];
    final revision = pending['revision'];
    if (base is! int || base < 0 || revision is! int || revision != base + 1) {
      return false;
    }
    return sameValues(pending, remote);
  }

  static bool sameValues(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) =>
                right.containsKey(key) && sameValues(left[key], right[key]),
          );
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!sameValues(left[i], right[i])) return false;
      }
      return true;
    }
    return left == right;
  }
}

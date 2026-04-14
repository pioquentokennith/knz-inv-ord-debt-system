// ─────────────────────────────────────────────────────────────────────────────
// user_model.dart — AppUser & ActivityLog entities
// Demonstrates: Inheritance (extends BaseModel), Encapsulation (private fields
// exposed via getters — no mutation allowed on user data).
// ─────────────────────────────────────────────────────────────────────────────

import 'base_model.dart';

/// Authenticated user — immutable after creation (Encapsulation).
class AppUser extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String   _username;
  final String   _role;
  final DateTime _createdAt;

  // super.id — Dart super-parameter syntax (fixes use_super_parameters lint)
  const AppUser({
    required super.id,
    required String   username,
    required String   role,
    required DateTime createdAt,
  })  : _username  = username,
        _role      = role,
        _createdAt = createdAt;

  // ── Getters (Encapsulation) ───────────────────────────────────────────────
  String   get username  => _username;
  String   get role      => _role;
  DateTime get createdAt => _createdAt;

  // ── Computed getters ──────────────────────────────────────────────────────
  String get displayName  => _username[0].toUpperCase() + _username.substring(1).toLowerCase();
  String get avatarLetter => _username[0].toUpperCase();

  @override
  Map<String, dynamic> toMap() => {
    'id':        id,
    'username':  _username,
    'role':      _role,
    'createdAt': _createdAt.toIso8601String(),
  };

  // FIX 8: Dinagdag ang fromMap() factory — consistent sa OOP pattern ng
  // Product, Order, at CustomerDebt na lahat ay may fromMap().
  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    id:        m['id']         as String,
    username:  m['name']       as String,
    role:      m['role']       as String,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

/// Activity log entry — immutable record of a past action.
class ActivityLog extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String   _message;
  final DateTime _timestamp;
  final String   _type;

  // super.id — Dart super-parameter syntax (fixes use_super_parameters lint)
  ActivityLog({
    required super.id,
    required String   message,
    required DateTime timestamp,
    required String   type,
  })  : _message   = message,
        _timestamp = timestamp,
        _type      = type;

  // ── Getters (Encapsulation) ───────────────────────────────────────────────
  String   get message   => _message;
  DateTime get timestamp => _timestamp;
  String   get type      => _type;

  // ── Computed getter ───────────────────────────────────────────────────────
  String get timeAgo {
    final diff = DateTime.now().difference(_timestamp);
    if (diff.inSeconds < 60)  return 'just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Map<String, dynamic> toMap() => {
    'id':        id,
    'message':   _message,
    'timestamp': _timestamp.toIso8601String(),
    'type':      _type,
  };
}

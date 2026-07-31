// ─────────────────────────────────────────────────────────────────────────────
// user_model.dart — AppUser and ActivityLog entities
// Purpose : Represents an authenticated admin user and an immutable audit log
//           entry. Both are read-only after construction — no mutation allowed.
// Demonstrates: Inheritance (extends BaseModel), Encapsulation (all fields
// private, exposed via getters only — no public setters).
// ─────────────────────────────────────────────────────────────────────────────

import 'base_model.dart';

/// Authenticated admin user — fully immutable after construction (Encapsulation).
/// Changing user data always requires a new object; no in-place mutation.
class AppUser extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String _username;
  final String _name;
  final String _email;
  final String _role; // e.g. 'Administrator'
  final String _accountStatus;
  final bool _isActive;
  final String? _legacyOwnerKey;
  final DateTime _createdAt;

  const AppUser({
    required super.id,
    required String username,
    required String name,
    required String email,
    required String role,
    required String accountStatus,
    required bool isActive,
    String? legacyOwnerKey,
    required DateTime createdAt,
  }) : _username = username,
       _name = name,
       _email = email,
       _role = role,
       _accountStatus = accountStatus,
       _isActive = isActive,
       _legacyOwnerKey = legacyOwnerKey,
       _createdAt = createdAt;

  // ── Public read-only getters (Encapsulation — no public setters) ──────────
  String get username => _username;
  String get name => _name;
  String get email => _email;
  String get role => _role;
  String get accountStatus => _accountStatus;
  bool get isActive => _isActive;
  String? get legacyOwnerKey => _legacyOwnerKey;
  bool get canAccess => _accountStatus == 'approved' && _isActive;
  DateTime get createdAt => _createdAt;

  // ── Computed display helpers ───────────────────────────────────────────────

  // Capitalizes the first letter of the username for friendly display (e.g. "Admin")
  String get displayName => _name;

  // Single uppercase letter used as the avatar placeholder in the sidebar
  String get avatarLetter => _username[0].toUpperCase();

  // Serializes to a map for storage or Firestore writes
  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'firebase_uid': id,
    'username': _username,
    'name': _name,
    'email': _email,
    'role': _role,
    'account_status': _accountStatus,
    'is_active': _isActive ? 1 : 0,
    'legacy_owner_key': _legacyOwnerKey,
    'created_at': _createdAt.toIso8601String(),
  };

  // FIX 8: Added fromMap() factory — consistent with OOP deserialization pattern
  // used by Product, Order, and CustomerDebt.
  // Note: reads 'name' (not 'username') and 'created_at' to match SQLite column names
  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    id: (m['firebase_uid'] ?? m['id']) as String,
    username: (m['username'] ?? m['name']) as String,
    name: (m['name'] ?? m['username']) as String,
    email: (m['email'] as String?) ?? '',
    role: (m['role'] as String?) ?? 'Staff',
    accountStatus: (m['account_status'] as String?) ?? 'pending',
    isActive: (m['is_active'] as int? ?? 0) == 1,
    legacyOwnerKey: m['legacy_owner_key'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

/// Activity log entry — an immutable record of a past user action.
/// Entries are never updated after creation; audit integrity depends on this.
class ActivityLog extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String _message; // Human-readable description of the action
  final DateTime _timestamp;
  final String
  _type; // Category tag: 'auth', 'product', 'order', 'payment', 'stock'

  ActivityLog({
    required super.id,
    required String message,
    required DateTime timestamp,
    required String type,
  }) : _message = message,
       _timestamp = timestamp,
       _type = type;

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String get message => _message;
  DateTime get timestamp => _timestamp;
  String get type => _type;

  // ── Computed display helper ────────────────────────────────────────────────

  // Returns a friendly relative time string shown in the activity feed (e.g. "5m ago")
  String get timeAgo {
    final diff = DateTime.now().difference(_timestamp);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // Serializes to a map for SQLite activity_logs table or Firestore document
  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'message': _message,
    'timestamp': _timestamp.toIso8601String(),
    'type': _type,
  };
}

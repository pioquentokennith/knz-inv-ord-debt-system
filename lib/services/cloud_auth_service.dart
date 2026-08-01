import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef FirebaseAvailability = bool Function();
typedef RegistrationAccountCreator =
    Future<RegistrationAccount?> Function({
      required String email,
      required String password,
    });
typedef RegistrationBatchWriter =
    Future<void> Function(RegistrationSubmission submission);
typedef RegistrationSubmissionChecker =
    Future<bool> Function(RegistrationSubmission submission);

abstract class ICloudAuthService {
  Future<CloudAuthResult> login(String email, String password);
  Future<CloudAuthResult> requestRegistration({
    required String name,
    required String username,
    required String email,
    required String password,
  });
  Future<CloudAuthResult> completeRegistration();
  Future<void> deferRegistration();
  Future<void> sendPasswordReset(String email);
  Future<CloudAuthResult> restoreSession();
  Future<void> signOut();
}

class CloudAuthService implements ICloudAuthService {
  CloudAuthService({
    FirebaseAvailability? firebaseAvailable,
    RegistrationAccountCreator? registrationAccountCreator,
    RegistrationBatchWriter? registrationBatchWriter,
    RegistrationSubmissionChecker? registrationSubmissionChecker,
    RegistrationDraftStore? registrationDraftStore,
    String? Function()? currentUserUid,
    Future<void> Function()? registrationSignOut,
  }) : _firebaseAvailable =
           firebaseAvailable ?? (() => Firebase.apps.isNotEmpty),
       _registrationAccountCreator = registrationAccountCreator,
       _registrationBatchWriter = registrationBatchWriter,
       _registrationSubmissionChecker = registrationSubmissionChecker,
       _registrationDraftStore =
           registrationDraftStore ?? SharedPreferencesRegistrationDraftStore(),
       _currentUserUid = currentUserUid,
       _registrationSignOut = registrationSignOut;

  static final CloudAuthService instance = CloudAuthService();

  final FirebaseAvailability _firebaseAvailable;
  final RegistrationAccountCreator? _registrationAccountCreator;
  final RegistrationBatchWriter? _registrationBatchWriter;
  final RegistrationSubmissionChecker? _registrationSubmissionChecker;
  final RegistrationDraftStore _registrationDraftStore;
  final String? Function()? _currentUserUid;
  final Future<void> Function()? _registrationSignOut;
  _PendingRegistration? _pendingRegistration;

  static const Duration _timeout = Duration(seconds: 20);

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  Future<CloudAuthResult> login(String email, String password) async {
    if (!_firebaseAvailable()) {
      return const CloudAuthResult(
        status: 'unavailable',
        error: 'Cloud authentication is still starting. Please try again.',
        diagnosticCode: 'firebase-not-initialized',
      );
    }
    final normalizedEmail = _normalizeEmail(email);
    try {
      final credential = await _auth
          .signInWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          )
          .timeout(_timeout);
      final user = credential.user;
      if (user == null || user.isAnonymous) {
        await signOut();
        return const CloudAuthResult.denied('Authentication failed.');
      }
      await user.reload();
      final refreshed = _auth.currentUser;
      if (refreshed?.emailVerified != true) {
        await signOut();
        return const CloudAuthResult(
          status: 'pending',
          error: 'Verify your email before requesting administrator approval.',
        );
      }
      await refreshed!.getIdToken(true);
      var access = await _loadAccess(refreshed.uid);
      if (access.status == 'registration_required') {
        final draft = await _registrationDraftStore.read(refreshed.uid);
        if (draft == null) {
          await signOut();
          return const CloudAuthResult(
            status: 'pending',
            error:
                'Your email is verified, but registration details are missing. Return to registration on the device where the account was created.',
            diagnosticCode: 'registration-draft-missing',
          );
        }
        final registration = RegistrationSubmission(
          uid: refreshed.uid,
          email: _normalizeEmail(refreshed.email ?? ''),
          username: draft.username,
          name: draft.name,
        );
        try {
          await _writePendingRegistration(registration);
          await _registrationDraftStore.delete(refreshed.uid);
          access = await _loadAccess(refreshed.uid);
        } on FirebaseException catch (error) {
          _logDiagnostic('registration-write', error.code);
          await signOut();
          return CloudAuthResult(
            status: 'unavailable',
            error: 'Registration request creation failed (${error.code}).',
            diagnosticCode: error.code,
          );
        } on TimeoutException {
          await signOut();
          return const CloudAuthResult(
            status: 'unavailable',
            error: 'Registration request creation failed (timeout).',
            diagnosticCode: 'timeout',
          );
        } catch (_) {
          await signOut();
          return const CloudAuthResult(
            status: 'unavailable',
            error:
                'Registration request creation failed (registration-write-failed).',
            diagnosticCode: 'registration-write-failed',
          );
        }
      }
      if (!access.canAccess) await signOut();
      return access;
    } on FirebaseAuthException catch (error) {
      _logDiagnostic('login', error.code);
      if (error.code == 'network-request-failed') {
        return CloudAuthResult(
          status: 'offline',
          uid: _auth.currentUser?.uid,
          error: 'Cloud authentication is unavailable.',
          mayUseOfflineCache: true,
          diagnosticCode: error.code,
        );
      }
      await signOut();
      return CloudAuthResult(
        status: 'denied',
        error: 'Invalid email or password.',
        diagnosticCode: error.code,
      );
    } on FirebaseException catch (error) {
      _logDiagnostic('login-access', error.code);
      await signOut();
      return CloudAuthResult(
        status: 'unavailable',
        error: 'Account access could not be loaded (${error.code}).',
        diagnosticCode: error.code,
      );
    } on TimeoutException {
      return CloudAuthResult(
        status: 'offline',
        uid: _auth.currentUser?.uid,
        error: 'Cloud authentication timed out.',
        mayUseOfflineCache: true,
      );
    }
  }

  @override
  Future<CloudAuthResult> requestRegistration({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    if (!_firebaseAvailable()) {
      return const CloudAuthResult(
        status: 'unavailable',
        error: 'Account registration is still starting. Please try again.',
        diagnosticCode: 'firebase-not-initialized',
      );
    }
    final normalizedEmail = _normalizeEmail(email);
    RegistrationAccount? createdUser;
    try {
      final user = await _createRegistrationAccount(
        email: normalizedEmail,
        password: password,
      );
      if (user == null) {
        return const CloudAuthResult.denied('Registration failed.');
      }
      createdUser = user;
      await user.updateDisplayName(name.trim());
      await user.sendEmailVerification();
      final draft = RegistrationDraft(
        username: username.trim().toLowerCase(),
        name: name.trim(),
      );
      await _registrationDraftStore.write(user.uid, draft);
      _pendingRegistration = _PendingRegistration(
        account: user,
        submission: RegistrationSubmission(
          uid: user.uid,
          email: normalizedEmail,
          username: draft.username,
          name: draft.name,
        ),
      );
      return const CloudAuthResult(
        status: 'verification_required',
        error:
            'Firebase sent a verification link to your email. Open it, then return here to create your pending Staff request.',
      );
    } on FirebaseAuthException catch (error) {
      _logDiagnostic('registration', error.code);
      final removed =
          createdUser == null ||
          await _deleteNewlyCreatedCurrentUser(createdUser);
      await _signOutAfterRegistration();
      return CloudAuthResult(
        status: 'denied',
        error: removed
            ? _registrationAuthMessage(error.code)
            : 'Registration failed and the Firebase account could not be cleaned up. Contact an administrator before retrying.',
        diagnosticCode: error.code,
      );
    } catch (error) {
      const code = 'registration-setup-failed';
      _logDiagnostic('registration', code);
      final removed =
          createdUser == null ||
          await _deleteNewlyCreatedCurrentUser(createdUser);
      await _signOutAfterRegistration();
      return CloudAuthResult(
        status: 'denied',
        error: removed
            ? 'Registration setup failed ($code).'
            : 'Registration setup failed ($code) and the new Firebase account could not be cleaned up. Contact an administrator before retrying.',
        diagnosticCode: code,
      );
    }
  }

  @override
  Future<CloudAuthResult> completeRegistration() async {
    final pending = _pendingRegistration;
    if (pending == null) {
      return const CloudAuthResult(
        status: 'denied',
        error: 'No new registration is awaiting email verification.',
        diagnosticCode: 'registration-not-started',
      );
    }
    try {
      await pending.account.reload();
      if (!pending.account.emailVerified) {
        return const CloudAuthResult(
          status: 'verification_required',
          error:
              'Firebase has not confirmed the verification link yet. Open the link, then try again.',
          diagnosticCode: 'email-not-verified',
        );
      }
      await pending.account.refreshIdToken();
      if (await _registrationAlreadySubmitted(pending.submission)) {
        return await _finishPendingRegistration(pending);
      }
      await _writePendingRegistration(pending.submission);
      return await _finishPendingRegistration(pending);
    } on FirebaseException catch (error) {
      return _failedNewRegistration(pending, error.code);
    } on TimeoutException {
      return _failedNewRegistration(pending, 'timeout');
    } catch (_) {
      return _failedNewRegistration(pending, 'registration-write-failed');
    }
  }

  Future<CloudAuthResult> _failedNewRegistration(
    _PendingRegistration pending,
    String code,
  ) async {
    _logDiagnostic('registration-write', code);
    const confirmedRejections = {
      'permission-denied',
      'invalid-argument',
      'failed-precondition',
      'already-exists',
      'unauthenticated',
    };
    if (!confirmedRejections.contains(code)) {
      return CloudAuthResult(
        status: 'registration_retry_required',
        error:
            'Registration request creation could not be confirmed ($code). The Firebase account and local draft were retained for a safe retry.',
        diagnosticCode: code,
      );
    }
    final removed = await _deleteNewlyCreatedCurrentUser(pending.account);
    if (removed) await _registrationDraftStore.delete(pending.submission.uid);
    _pendingRegistration = null;
    await _signOutAfterRegistration();
    return CloudAuthResult(
      status: 'denied',
      error: removed
          ? 'Registration request creation failed ($code). The newly created Firebase account was removed.'
          : 'Registration request creation failed ($code), and the newly created Firebase account could not be removed. Contact an administrator.',
      diagnosticCode: code,
    );
  }

  Future<CloudAuthResult> _finishPendingRegistration(
    _PendingRegistration pending,
  ) async {
    await _registrationDraftStore.delete(pending.submission.uid);
    await _signOutAfterRegistration();
    _pendingRegistration = null;
    return const CloudAuthResult(
      status: 'pending',
      error:
          'Your verified Staff registration is pending Administrator approval.',
    );
  }

  @override
  Future<void> deferRegistration() async {
    _pendingRegistration = null;
    await _signOutAfterRegistration();
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    if (!_firebaseAvailable()) {
      throw const AuthOperationException(
        'Cloud authentication is still starting. Please try again.',
        code: 'firebase-not-initialized',
      );
    }
    try {
      await _auth
          .sendPasswordResetEmail(email: _normalizeEmail(email))
          .timeout(_timeout);
    } on FirebaseAuthException catch (error) {
      _logDiagnostic('password-reset', error.code);
      // Unknown accounts retain the same response as known accounts.
      if (error.code == 'user-not-found') return;
      throw AuthOperationException(
        'Password-reset instructions could not be sent. Please try again.',
        code: error.code,
      );
    } on TimeoutException {
      throw const AuthOperationException(
        'The password-reset service timed out. Please try again.',
      );
    }
  }

  @override
  Future<CloudAuthResult> restoreSession() async {
    if (!_firebaseAvailable()) {
      return const CloudAuthResult(status: 'signed_out');
    }
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      return const CloudAuthResult(status: 'signed_out');
    }
    try {
      final access = await _loadAccess(user.uid).timeout(_timeout);
      if (!access.canAccess) await signOut();
      return access;
    } on FirebaseException catch (error) {
      if (error.code == 'unavailable') {
        return CloudAuthResult(
          status: 'offline',
          uid: user.uid,
          mayUseOfflineCache: true,
        );
      }
      rethrow;
    } on TimeoutException {
      return CloudAuthResult(
        status: 'offline',
        uid: user.uid,
        mayUseOfflineCache: true,
      );
    }
  }

  Future<CloudAuthResult> _loadAccess(String uid) async {
    final snapshot = await _firestore
        .collection('accountAccess')
        .doc(uid)
        .get();
    if (!snapshot.exists) {
      return const CloudAuthResult(
        status: 'registration_required',
        error: 'A verified pending registration request has not been created.',
      );
    }
    final data = snapshot.data()!;
    final status = data['status'] as String? ?? 'pending';
    final active = data['active'] == true;
    if (status != 'approved' || !active) {
      return CloudAuthResult(
        status: status,
        active: active,
        error: accountStatusMessage(status),
      );
    }
    return CloudAuthResult(
      status: status,
      active: active,
      uid: uid,
      email: (data['email'] as String?)?.trim().toLowerCase(),
      username: data['username'] as String?,
      name: data['name'] as String?,
      role: data['role'] as String? ?? 'Staff',
      legacyOwnerKey: data['legacyOwnerKey'] as String?,
      createdAt: _asDateTime(data['createdAt']),
    );
  }

  Future<List<Map<String, dynamic>>> pendingRegistrationRequests() async {
    final snapshot = await _firestore
        .collection('accountAccess')
        .where('status', isEqualTo: 'pending')
        .get();
    return snapshot.docs.map((doc) => {'uid': doc.id, ...doc.data()}).toList();
  }

  Future<void> reviewRegistration({
    required String uid,
    required String decision,
  }) async {
    if (!{'approved', 'rejected', 'suspended'}.contains(decision)) {
      throw StateError('Invalid registration decision.');
    }
    final administratorUid = _auth.currentUser?.uid;
    if (administratorUid == null || administratorUid == uid) {
      throw StateError('Administrators cannot review themselves.');
    }
    final batch = _firestore.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    batch.update(_firestore.collection('accountAccess').doc(uid), {
      'status': decision,
      'active': decision == 'approved',
      'role': 'Staff',
      'reviewedBy': administratorUid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_firestore.collection('users').doc(uid), {
      'role': 'Staff',
      'account_status': decision,
      'is_active': decision == 'approved',
      'updated_at': now,
    });
    await batch.commit().timeout(_timeout);
  }

  @override
  Future<void> signOut() async {
    if (_firebaseAvailable()) await _auth.signOut();
  }

  Future<RegistrationAccount?> _createRegistrationAccount({
    required String email,
    required String password,
  }) async {
    final creator = _registrationAccountCreator;
    if (creator != null) return creator(email: email, password: password);
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    return user == null ? null : _FirebaseRegistrationAccount(user);
  }

  Future<void> _signOutAfterRegistration() async {
    final injectedSignOut = _registrationSignOut;
    if (injectedSignOut != null) {
      await injectedSignOut();
      return;
    }
    await signOut();
  }

  Future<bool> _deleteUnsubmittedUser(RegistrationAccount user) async {
    try {
      await user.delete().timeout(_timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteNewlyCreatedCurrentUser(RegistrationAccount user) async {
    final currentUid = _currentUserUid?.call() ?? _auth.currentUser?.uid;
    if (currentUid != user.uid) return false;
    return _deleteUnsubmittedUser(user);
  }

  Future<void> _writePendingRegistration(
    RegistrationSubmission submission,
  ) async {
    final writer = _registrationBatchWriter;
    if (writer != null) {
      await writer(submission);
      return;
    }
    final batch = _firestore.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    batch.set(_firestore.collection('accountAccess').doc(submission.uid), {
      'uid': submission.uid,
      'email': submission.email,
      'username': submission.username,
      'name': submission.name,
      'role': 'Staff',
      'status': 'pending',
      'active': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_firestore.collection('users').doc(submission.uid), {
      'uid': submission.uid,
      'email': submission.email,
      'username': submission.username,
      'name': submission.name,
      'role': 'Staff',
      'account_status': 'pending',
      'is_active': false,
      'created_at': now,
    });
    batch.set(_firestore.collection('_usernames').doc(submission.username), {
      'uid': submission.uid,
      'reservedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit().timeout(_timeout);
  }

  Future<bool> _registrationAlreadySubmitted(
    RegistrationSubmission submission,
  ) async {
    final checker = _registrationSubmissionChecker;
    if (checker != null) return checker(submission);
    if (_registrationBatchWriter != null) return false;

    final snapshot = await _firestore
        .collection('accountAccess')
        .doc(submission.uid)
        .get(const GetOptions(source: Source.server))
        .timeout(_timeout);
    if (!snapshot.exists) return false;
    final data = snapshot.data()!;
    final status = data['status'];
    final active = data['active'];
    final matchesSubmission =
        data['uid'] == submission.uid &&
        data['email'] == submission.email &&
        data['username'] == submission.username &&
        data['name'] == submission.name &&
        data['role'] == 'Staff' &&
        status is String &&
        {'pending', 'approved', 'rejected', 'suspended'}.contains(status) &&
        active == (status == 'approved');
    if (!matchesSubmission) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'failed-precondition',
        message: 'Existing registration identity does not match this request.',
      );
    }
    return true;
  }

  static String _normalizeEmail(String value) => value.trim().toLowerCase();

  static String _registrationAuthMessage(String code) => switch (code) {
    'weak-password' => 'Use a stronger password with at least 8 characters.',
    'email-already-in-use' =>
      'An account already exists for this email. Sign in or reset its password.',
    'operation-not-allowed' =>
      'Email/password registration is not enabled for this app.',
    'invalid-api-key' || 'app-not-authorized' || 'configuration-not-found' =>
      'Account registration is not configured for this app.',
    'network-request-failed' =>
      'Account registration could not reach Firebase. Check your connection and try again.',
    _ => 'Registration could not be completed. Please try again.',
  };

  static void _logDiagnostic(String operation, String code) {
    if (kDebugMode) debugPrint('[CloudAuthService] $operation failed: $code');
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String accountStatusMessage(String status) => switch (status) {
    'rejected' => 'Your registration request was rejected.',
    'suspended' => 'Your account is suspended. Contact an administrator.',
    _ => 'Your registration request is pending administrator approval.',
  };
}

class AuthOperationException implements Exception {
  const AuthOperationException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class CloudAuthResult {
  const CloudAuthResult({
    required this.status,
    this.uid,
    this.email,
    this.username,
    this.name,
    this.role,
    this.active = false,
    this.legacyOwnerKey,
    this.createdAt,
    this.error,
    this.mayUseOfflineCache = false,
    this.diagnosticCode,
  });

  const CloudAuthResult.denied(String message)
    : this(status: 'denied', error: message);

  final String status;
  final String? uid;
  final String? email;
  final String? username;
  final String? name;
  final String? role;
  final bool active;
  final String? legacyOwnerKey;
  final DateTime? createdAt;
  final String? error;
  final bool mayUseOfflineCache;
  final String? diagnosticCode;

  bool get canAccess =>
      status == 'approved' &&
      active &&
      uid != null &&
      email != null &&
      username != null &&
      name != null;
}

abstract interface class RegistrationAccount {
  String get uid;
  bool get emailVerified;
  Future<void> updateDisplayName(String name);
  Future<void> sendEmailVerification();
  Future<void> reload();
  Future<void> refreshIdToken();
  Future<void> delete();
}

class _FirebaseRegistrationAccount implements RegistrationAccount {
  const _FirebaseRegistrationAccount(this._user);

  final User _user;

  @override
  String get uid => _user.uid;

  @override
  bool get emailVerified => _user.emailVerified;

  @override
  Future<void> updateDisplayName(String name) => _user.updateDisplayName(name);

  @override
  Future<void> sendEmailVerification() => _user.sendEmailVerification();

  @override
  Future<void> reload() => _user.reload();

  @override
  Future<void> refreshIdToken() async {
    await _user.getIdToken(true);
  }

  @override
  Future<void> delete() => _user.delete();
}

class RegistrationSubmission {
  const RegistrationSubmission({
    required this.uid,
    required this.email,
    required this.username,
    required this.name,
  });

  final String uid;
  final String email;
  final String username;
  final String name;
}

class RegistrationDraft {
  const RegistrationDraft({required this.username, required this.name});

  final String username;
  final String name;
}

abstract interface class RegistrationDraftStore {
  Future<void> write(String uid, RegistrationDraft draft);
  Future<RegistrationDraft?> read(String uid);
  Future<void> delete(String uid);
}

class SharedPreferencesRegistrationDraftStore
    implements RegistrationDraftStore {
  static const _keyPrefix = 'pending_registration_';

  @override
  Future<void> write(String uid, RegistrationDraft draft) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      '$_keyPrefix$uid',
      jsonEncode({'username': draft.username, 'name': draft.name}),
    );
    if (!saved) throw StateError('Registration draft could not be saved.');
  }

  @override
  Future<RegistrationDraft?> read(String uid) async {
    final value = (await SharedPreferences.getInstance()).getString(
      '$_keyPrefix$uid',
    );
    if (value == null) return null;
    try {
      final data = jsonDecode(value);
      if (data is! Map) return null;
      final username = data['username'];
      final name = data['name'];
      if (username is! String || name is! String) return null;
      return RegistrationDraft(username: username, name: name);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> delete(String uid) async {
    await (await SharedPreferences.getInstance()).remove('$_keyPrefix$uid');
  }
}

class _PendingRegistration {
  const _PendingRegistration({required this.account, required this.submission});

  final RegistrationAccount account;
  final RegistrationSubmission submission;
}

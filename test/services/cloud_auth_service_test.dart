import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/cloud_authorization.dart';
import 'package:knz_scent_admin/services/cloud_auth_service.dart';

class _FirebaseAuth extends Fake implements FirebaseAuth {
  User? user;
  @override
  User? get currentUser => user;
}

class _FirebaseUser extends Fake implements User {
  _FirebaseUser(this.error);
  final Object? error;
  @override
  String get uid => 'trusted-uid';
  @override
  bool get isAnonymous => false;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    expect(forceRefresh, isTrue);
    if (error != null) throw error!;
    return 'refreshed-token';
  }
}

class _Firestore extends Fake implements FirebaseFirestore {
  _Firestore(this.record);
  final Map<String, dynamic>? record;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    expect(path, 'accountAccess');
    return _AccessCollection(record);
  }
}

// Test doubles exercise server-only reads without platform channels.
// ignore: subtype_of_sealed_class
class _AccessCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _AccessCollection(this.record);
  final Map<String, dynamic>? record;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    expect(path, 'trusted-uid');
    return _AccessDocument(record);
  }
}

// ignore: subtype_of_sealed_class
class _AccessDocument extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _AccessDocument(this.record);
  final Map<String, dynamic>? record;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    expect(options?.source, Source.server);
    return _AccessSnapshot(record);
  }
}

// ignore: subtype_of_sealed_class
class _AccessSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _AccessSnapshot(this.record);
  final Map<String, dynamic>? record;
  @override
  bool get exists => record != null;
  @override
  Map<String, dynamic>? data() => record;
}

class _RegistrationAccount implements RegistrationAccount {
  @override
  String get uid => 'new-uid';
  String? displayName;
  bool verificationSent = false;
  bool deleted = false;
  bool tokenRefreshed = false;

  @override
  bool emailVerified = false;

  @override
  Future<void> delete() async => deleted = true;

  @override
  Future<void> refreshIdToken() async => tokenRefreshed = true;

  @override
  Future<void> reload() async {}

  @override
  Future<void> sendEmailVerification() async => verificationSent = true;

  @override
  Future<void> updateDisplayName(String name) async => displayName = name;
}

class _DraftStore implements RegistrationDraftStore {
  final drafts = <String, RegistrationDraft>{};

  @override
  Future<void> delete(String uid) async => drafts.remove(uid);

  @override
  Future<RegistrationDraft?> read(String uid) async => drafts[uid];

  @override
  Future<void> write(String uid, RegistrationDraft draft) async {
    drafts[uid] = draft;
  }
}

void main() {
  for (final entry in {
    'suspended': CloudAuthorization.suspended,
    'rejected': CloudAuthorization.rejected,
    'disabled': CloudAuthorization.disabled,
    'deleted': CloudAuthorization.deleted,
    'expired': CloudAuthorization.expired,
    'pending': CloudAuthorization.unauthorized,
    'approved': CloudAuthorization.unauthorized, // Confirmed inactive.
  }.entries) {
    test('server confirms ${entry.key} inactive account', () async {
      final result = await CloudAuthService(
        firebaseAuth: _FirebaseAuth()..user = _FirebaseUser(null),
        firebaseAvailable: () => true,
        firestore: _Firestore({'status': entry.key, 'active': false}),
      ).revalidateAccess('trusted-uid');
      expect(result.authorization, entry.value);
      expect(result.authorization.revokesLocalAccess, isTrue);
    });
  }

  test('server confirms missing access record', () async {
    final result = await CloudAuthService(
      firebaseAuth: _FirebaseAuth()..user = _FirebaseUser(null),
      firebaseAvailable: () => true,
      firestore: _Firestore(null),
    ).revalidateAccess('trusted-uid');
    expect(result.authorization, CloudAuthorization.unauthorized);
  });

  test(
    'missing and mismatched Firebase principals only require cloud reauth',
    () async {
      final auth = _FirebaseAuth();
      final service = CloudAuthService(
        firebaseAvailable: () => true,
        firebaseAuth: auth,
      );
      expect(
        (await service.revalidateAccess('trusted-uid')).authorization,
        CloudAuthorization.reauthRequired,
      );
      auth.user = _FirebaseUser(StateError('token must not be requested'));
      expect(
        (await service.revalidateAccess('other-uid')).authorization,
        CloudAuthorization.reauthRequired,
      );
    },
  );

  test('Firebase initialization failure is not revocation', () async {
    final result = await CloudAuthService(
      firebaseAvailable: () => false,
    ).revalidateAccess('trusted-uid');
    expect(result.authorization.revokesLocalAccess, isFalse);
    expect(result.canAccess, isFalse);
  });

  for (final entry in {
    'network-request-failed': CloudAuthorization.offlineAllowed,
    'user-token-expired': CloudAuthorization.reauthRequired,
    'invalid-user-token': CloudAuthorization.reauthRequired,
    'requires-recent-login': CloudAuthorization.reauthRequired,
    'internal-error': CloudAuthorization.temporarilyUnavailable,
    'too-many-requests': CloudAuthorization.temporarilyUnavailable,
    'user-disabled': CloudAuthorization.disabled,
    'user-not-found': CloudAuthorization.deleted,
  }.entries) {
    test('token refresh ${entry.key} maps to ${entry.value.name}', () async {
      final auth = _FirebaseAuth()
        ..user = _FirebaseUser(FirebaseAuthException(code: entry.key));
      final result = await CloudAuthService(
        firebaseAvailable: () => true,
        firebaseAuth: auth,
      ).revalidateAccess('trusted-uid');
      expect(result.authorization, entry.value);
      expect(result.canAccess, isFalse);
    });
  }

  for (final error in <Object>[
    TimeoutException('unreachable'),
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
  ]) {
    test('$error does not establish revocation', () async {
      final auth = _FirebaseAuth()..user = _FirebaseUser(error);
      final result = await CloudAuthService(
        firebaseAvailable: () => true,
        firebaseAuth: auth,
      ).revalidateAccess('trusted-uid');
      expect(result.authorization.revokesLocalAccess, isFalse);
      expect(result.canAccess, isFalse);
    });
  }

  test('registration is unavailable before Firebase initialization', () async {
    var createCalled = false;
    final service = CloudAuthService(
      firebaseAvailable: () => false,
      registrationAccountCreator:
          ({required String email, required String password}) async {
            createCalled = true;
            return _RegistrationAccount();
          },
    );

    final result = await service.requestRegistration(
      name: 'Pending Staff',
      username: 'pending_staff',
      email: 'staff@example.com',
      password: 'StrongPassword1!',
    );

    expect(result.status, 'unavailable');
    expect(result.diagnosticCode, 'firebase-not-initialized');
    expect(createCalled, isFalse);
  });

  test('account creation sends only the Firebase verification link', () async {
    final account = _RegistrationAccount();
    final drafts = _DraftStore();
    var writeCount = 0;
    String? createdEmail;
    final service = CloudAuthService(
      firebaseAvailable: () => true,
      registrationAccountCreator:
          ({required String email, required String password}) async {
            createdEmail = email;
            return account;
          },
      registrationBatchWriter: (_) async => writeCount++,
      registrationDraftStore: drafts,
      currentUserUid: () => account.uid,
      registrationSignOut: () async {},
    );

    final result = await service.requestRegistration(
      name: ' Pending Staff ',
      username: 'Pending_Staff',
      email: ' Staff@Example.COM ',
      password: 'StrongPassword1!',
    );

    expect(result.status, 'verification_required');
    expect(createdEmail, 'staff@example.com');
    expect(account.displayName, 'Pending Staff');
    expect(account.verificationSent, isTrue);
    expect(account.deleted, isFalse);
    expect(writeCount, 0);
    expect(drafts.drafts[account.uid]?.username, 'pending_staff');
    expect(result.error, contains('verification link'));
    expect(result.error, isNot(contains('OTP')));
  });

  test('unverified email cannot create the pending registration', () async {
    final account = _RegistrationAccount();
    var writeCount = 0;
    final service = CloudAuthService(
      firebaseAvailable: () => true,
      registrationAccountCreator:
          ({required String email, required String password}) async => account,
      registrationBatchWriter: (_) async => writeCount++,
      registrationDraftStore: _DraftStore(),
      currentUserUid: () => account.uid,
      registrationSignOut: () async {},
    );
    await service.requestRegistration(
      name: 'Pending Staff',
      username: 'pending_staff',
      email: 'staff@example.com',
      password: 'StrongPassword1!',
    );

    final result = await service.completeRegistration();

    expect(result.status, 'verification_required');
    expect(result.diagnosticCode, 'email-not-verified');
    expect(writeCount, 0);
    expect(account.deleted, isFalse);
  });

  test('verified email creates a pending Staff registration', () async {
    final account = _RegistrationAccount();
    final drafts = _DraftStore();
    RegistrationSubmission? submitted;
    var signOutCount = 0;
    final service = CloudAuthService(
      firebaseAvailable: () => true,
      registrationAccountCreator:
          ({required String email, required String password}) async => account,
      registrationBatchWriter: (submission) async => submitted = submission,
      registrationDraftStore: drafts,
      currentUserUid: () => account.uid,
      registrationSignOut: () async => signOutCount++,
    );
    await service.requestRegistration(
      name: 'Pending Staff',
      username: 'Pending_Staff',
      email: 'Staff@Example.com',
      password: 'StrongPassword1!',
    );
    account.emailVerified = true;

    final result = await service.completeRegistration();

    expect(result.status, 'pending');
    expect(account.tokenRefreshed, isTrue);
    expect(submitted?.uid, account.uid);
    expect(submitted?.email, 'staff@example.com');
    expect(submitted?.username, 'pending_staff');
    expect(submitted?.name, 'Pending Staff');
    expect(drafts.drafts, isEmpty);
    expect(account.deleted, isFalse);
    expect(signOutCount, 1);
  });

  test(
    'failed pending write deletes only the newly created current account',
    () async {
      final account = _RegistrationAccount();
      final drafts = _DraftStore();
      final service = CloudAuthService(
        firebaseAvailable: () => true,
        registrationAccountCreator:
            ({required String email, required String password}) async =>
                account,
        registrationBatchWriter: (_) async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
        registrationDraftStore: drafts,
        currentUserUid: () => account.uid,
        registrationSignOut: () async {},
      );
      await service.requestRegistration(
        name: 'Pending Staff',
        username: 'pending_staff',
        email: 'staff@example.com',
        password: 'StrongPassword1!',
      );
      account.emailVerified = true;

      final result = await service.completeRegistration();

      expect(result.status, 'denied');
      expect(result.diagnosticCode, 'permission-denied');
      expect(result.error, contains('(permission-denied)'));
      expect(account.deleted, isTrue);
      expect(drafts.drafts, isEmpty);
    },
  );

  test(
    'failed pending write never deletes a different current account',
    () async {
      final account = _RegistrationAccount();
      final service = CloudAuthService(
        firebaseAvailable: () => true,
        registrationAccountCreator:
            ({required String email, required String password}) async =>
                account,
        registrationBatchWriter: (_) async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
        registrationDraftStore: _DraftStore(),
        currentUserUid: () => 'different-uid',
        registrationSignOut: () async {},
      );
      await service.requestRegistration(
        name: 'Pending Staff',
        username: 'pending_staff',
        email: 'staff@example.com',
        password: 'StrongPassword1!',
      );
      account.emailVerified = true;

      final result = await service.completeRegistration();

      expect(result.diagnosticCode, 'permission-denied');
      expect(account.deleted, isFalse);
      expect(result.error, contains('could not be removed'));
    },
  );

  test(
    'ambiguous timeout preserves the Auth account and local draft',
    () async {
      final account = _RegistrationAccount();
      final drafts = _DraftStore();
      var signOutCount = 0;
      final service = CloudAuthService(
        firebaseAvailable: () => true,
        registrationAccountCreator:
            ({required String email, required String password}) async =>
                account,
        registrationBatchWriter: (_) async => throw TimeoutException('write'),
        registrationSubmissionChecker: (_) async => false,
        registrationDraftStore: drafts,
        currentUserUid: () => account.uid,
        registrationSignOut: () async => signOutCount++,
      );
      await service.requestRegistration(
        name: 'Pending Staff',
        username: 'pending_staff',
        email: 'staff@example.com',
        password: 'StrongPassword1!',
      );
      account.emailVerified = true;

      final result = await service.completeRegistration();

      expect(result.status, 'registration_retry_required');
      expect(result.diagnosticCode, 'timeout');
      expect(result.error, contains('retained for a safe retry'));
      expect(account.deleted, isFalse);
      expect(drafts.drafts, contains(account.uid));
      expect(signOutCount, 0);
    },
  );

  test('retry succeeds after a timeout before the batch committed', () async {
    final account = _RegistrationAccount();
    final drafts = _DraftStore();
    final accessRecords = <String, RegistrationSubmission>{};
    final profileRecords = <String, RegistrationSubmission>{};
    final usernameRecords = <String, RegistrationSubmission>{};
    var attempts = 0;
    final service = CloudAuthService(
      firebaseAvailable: () => true,
      registrationAccountCreator:
          ({required String email, required String password}) async => account,
      registrationBatchWriter: (submission) async {
        attempts++;
        if (attempts == 1) throw TimeoutException('write');
        accessRecords[submission.uid] = submission;
        profileRecords[submission.uid] = submission;
        usernameRecords[submission.username] = submission;
      },
      registrationSubmissionChecker: (_) async => false,
      registrationDraftStore: drafts,
      currentUserUid: () => account.uid,
      registrationSignOut: () async {},
    );
    await service.requestRegistration(
      name: 'Pending Staff',
      username: 'pending_staff',
      email: 'staff@example.com',
      password: 'StrongPassword1!',
    );
    account.emailVerified = true;

    expect(
      (await service.completeRegistration()).status,
      'registration_retry_required',
    );
    final retry = await service.completeRegistration();

    expect(retry.status, 'pending');
    expect(attempts, 2);
    expect(account.deleted, isFalse);
    expect(drafts.drafts, isEmpty);
    expect(accessRecords, hasLength(1));
    expect(profileRecords, hasLength(1));
    expect(usernameRecords, hasLength(1));
  });

  test(
    'retry reconciles an already committed timeout without duplicates',
    () async {
      final account = _RegistrationAccount();
      final drafts = _DraftStore();
      final accessRecords = <String, RegistrationSubmission>{};
      final profileRecords = <String, RegistrationSubmission>{};
      final usernameRecords = <String, RegistrationSubmission>{};
      var writeAttempts = 0;
      final service = CloudAuthService(
        firebaseAvailable: () => true,
        registrationAccountCreator:
            ({required String email, required String password}) async =>
                account,
        registrationBatchWriter: (submission) async {
          writeAttempts++;
          accessRecords[submission.uid] = submission;
          profileRecords[submission.uid] = submission;
          usernameRecords[submission.username] = submission;
          throw TimeoutException('response lost after commit');
        },
        registrationSubmissionChecker: (submission) async =>
            accessRecords.containsKey(submission.uid),
        registrationDraftStore: drafts,
        currentUserUid: () => account.uid,
        registrationSignOut: () async {},
      );
      await service.requestRegistration(
        name: 'Pending Staff',
        username: 'pending_staff',
        email: 'staff@example.com',
        password: 'StrongPassword1!',
      );
      account.emailVerified = true;

      expect(
        (await service.completeRegistration()).status,
        'registration_retry_required',
      );
      final retry = await service.completeRegistration();

      expect(retry.status, 'pending');
      expect(writeAttempts, 1);
      expect(account.deleted, isFalse);
      expect(drafts.drafts, isEmpty);
      expect(accessRecords, hasLength(1));
      expect(profileRecords, hasLength(1));
      expect(usernameRecords, hasLength(1));
      expect(usernameRecords.keys.single, 'pending_staff');
    },
  );
}

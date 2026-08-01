import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/services/cloud_auth_service.dart';

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

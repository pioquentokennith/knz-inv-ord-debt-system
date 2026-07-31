# Firebase UID Identity Migration Plan

## Safety Boundary

Legacy usernames, local UUIDs, emails, and passwords are not trusted proof of
Firebase identity or Administrator authorization. Phase 2 preserves legacy
business partitions in place and marks their profiles `unmapped`. No signed-in
user receives a legacy partition unless the owner supplies an explicit mapping.

## Required Mapping Record

For every legacy account the owner must approve:

- normalized legacy username and local owner key;
- verified Firebase Authentication UID and normalized email;
- intended role (`Staff` or `Administrator`);
- disposition of conflicting local and cloud records;
- approving Administrator UID and approval timestamp.

The first Administrator is provisioned with `npm run bootstrap:admin` after the
owner creates and verifies the Firebase Auth account. The script refuses to use
an unknown, unverified, or already-provisioned UID.

## Local Migration

SQLite v9 removes the `users.password` column with a transactional table rebuild.
It preserves every profile, normalizes email/username case, sets legacy profiles
to inactive `pending`, records `legacy_owner_key`, and marks them `unmapped`.
Products, orders and items, debts and payments, logs, resellers, custom orders,
and outbox ownership are not rewritten. Credential-shaped fields are removed
from outbox JSON; malformed JSON aborts and rolls back the migration.

After an owner mapping is approved, a later controlled migration must preflight
all seven owner-bearing tables and embedded outbox `user_id` values, pause sync,
copy or rewrite them transactionally, verify row counts, and only then mark the
local profile `mapped`. Phase 2 does not guess or perform that rewrite.

## Cloud Migration

Legacy `/users/{username}` trees must be copied to `/users/{firebaseUid}` by an
Admin SDK migration tool. The copy must include every known subcollection,
record per-document progress, verify counts and hashes, and retain the legacy
tree as a read-only archive. Deletion requires separate owner approval after a
successful backup and verification. Firestore rules deny new username-bound
client access.

## Stop Conditions

Stop before mapping when there are mixed-case collisions, duplicate emails,
orphan owner keys, divergent same-ID local/cloud records, unknown child records,
or an outbox payload that cannot be decoded. Never assign such data to the
currently signed-in user and never delete either source to resolve a conflict.

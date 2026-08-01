# Durable Synchronization Plan

## Release Scope

The supported release is Android-only, local-first, and primarily single-device.
SQLite is authoritative for local operation. Firestore is a UID-scoped backup and
restore target driven by a durable transactional outbox. This release does not
claim complete multi-device conflict resolution.

## Commit Contract

- Every local mutation and corresponding `sync_queue` row commit in one SQLite transaction.
- Connectivity is only a retry trigger; only a confirmed Firestore response completes an outbox row.
- Failed rows retain payload, attempt count, timestamps, error text, status, and idempotency key.
- Processing is ordered by the SQLite autoincrement outbox ID so later snapshots cannot overtake failures.
- Firestore operations use deterministic document IDs and idempotent merge-set or delete operations.

## Entity Coverage

| Entity | Cloud representation | Local outbox operations | Restore and tombstone behavior |
| --- | --- | --- | --- |
| Products | `/users/{uid}/products/{id}` | save, soft delete, hard delete | Active rows and tombstones restore into an empty local partition. Device-local image paths are replaced with `null`; only HTTP(S) references are portable. |
| Orders and line items | `/users/{uid}/orders/{id}` with embedded `items` | full save, soft delete, hard delete | Internal UUID is the document identity. `KNZ-NNN` is monotonic display metadata. Full item snapshots and tombstones restore. |
| Debts and payments | `/users/{uid}/debts/{id}` with embedded `payments` | full save after debt/payment mutation, soft delete, hard delete | Debt and immutable payment snapshots restore together, including tombstones. |
| Resellers | `/users/{uid}/resellers/{id}` | save, soft delete, hard delete | Active rows and tombstones restore into an empty local partition. |
| Custom orders | `/users/{uid}/custom_orders/{id}` | save, soft delete, hard delete | Active rows and tombstones restore into an empty local partition. |
| Activity logs | `/users/{uid}/activity_logs/{id}` | save | Recent logs restore when the local log partition is empty. |

## Conflict Boundary

No revision vectors, merge policy, or complete two-way reconciliation are provided
in this release. Restore runs only for an empty local entity partition and never
overwrites existing local business records. Legacy username-owned partitions stay
quarantined until an owner-approved UID migration exists.

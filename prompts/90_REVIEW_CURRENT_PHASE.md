# Independent Review — Current Phase

**Mode:** Plan  
**Model:** GPT-5.6 Sol  
**Reasoning:** High

Use a fresh session and replace placeholders.

```text
Review only the current remediation phase Git diff.

Follow AGENTS.md strictly.

Do not edit files.
Do not re-audit the complete repository.
Do not begin the next phase.
Do not stage or commit.

Current phase:
[INSERT PHASE NUMBER AND NAME]

Read:
- docs/progress/REMEDIATION_PHASE_[NUMBER]_COMPLETION.md
- git status --short
- git diff --check
- git diff --stat
- git diff --name-status
- targeted diffs for all files changed during this phase

Check:

1. Whether every phase requirement was implemented.
2. Whether the stated root cause was actually corrected.
3. Security and authorization regressions.
4. Data-loss or migration risks.
5. Order, stock, debt, payment, reseller, and accounting integrity.
6. Synchronization and idempotency.
7. Firestore Rules compatibility.
8. Offline behavior.
9. Missing or weak tests.
10. False PASS claims.
11. Swallowed errors.
12. Unrelated changes.
13. Secret or credential exposure.
14. Whether Firebase remains Spark-compatible.
15. Whether the completion report matches the actual code and tests.

Return:

PHASE REVIEW

1. Confirmed Blockers
2. Confirmed Non-Blocking Issues
3. Missing Tests
4. Migration and Data Risks
5. Security Findings
6. Unrelated Changes
7. Validation Accuracy
8. Recommendation: APPROVE, FIX REQUIRED, or INCOMPLETE

Use APPROVE only when no critical requirement remains.
Stop after the review.

When the review returns FIX REQUIRED, send:

Fix only the confirmed issues from the previous phase review.

Do not expand scope.
Do not begin the next remediation phase.
Do not perform unrelated refactoring.
Preserve all existing data.
Add or correct the missing regression tests.
Run the complete validation required for the current phase.
Update the current phase completion report.
Stop after reporting the focused fixes and validation results.

Additional rules:
- Read AGENTS.md.
- Read the exact crosswalk entries assigned to the current phase.
- Do not modify files.
- State whether the next phase is unblocked.
- `APPROVE` unblocks the next phase.
- `FIX REQUIRED` or `INCOMPLETE` keeps the next phase blocked.
```

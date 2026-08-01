# Focused Fix — Review Findings Only

**Mode:** Build  
**Model:** GPT-5.6 Sol  
**Reasoning:** High

```text
Fix only the confirmed issues from the previous phase review.

Follow AGENTS.md strictly.

Do not expand scope.
Do not begin the next remediation phase.
Do not perform unrelated refactoring.
Preserve all existing data.
Do not weaken Firestore Rules.
Do not deploy Cloud Functions or require Firebase Blaze.
Add or correct the missing regression tests.
Run the complete validation required for the current phase.
Update the current phase completion report.
Do not stage or commit.
Stop after reporting the focused fixes and validation results.

Additional rules:
- Read AGENTS.md.
- Read the current phase completion report.
- Use only confirmed findings from the latest independent review.
- Preserve the current phase number.
- Update the same completion report.
- Do not begin the next phase.
- Do not stage or commit.
```

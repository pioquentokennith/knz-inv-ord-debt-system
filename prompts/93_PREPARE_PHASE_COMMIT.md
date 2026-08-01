# Prepare an Approved Phase Commit

Use only after an independent phase review returns `APPROVE`.

```text
Prepare a read-only commit review for the approved current remediation phase.

Follow AGENTS.md strictly.

Do not stage, commit, push, deploy, or publish yet.

Run:
- git status --short
- git diff --check
- git diff --stat
- git diff --name-status
- targeted diffs for every changed file
- a redacted secret scan of proposed tracked files

Classify every path:
1. Safe to stage
2. Requires owner review
3. Must never be staged
4. Generated output
5. Unrelated or uncertain

Provide the exact proposed stage list.
Do not use git add -A.

Ask exactly:

APPROVE PHASE COMMIT?
```

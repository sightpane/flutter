---
trigger: always_on
description: Mandatory code-auditor review, resolution of findings, static verification, and descriptive Git commit whenever an issue or task is completed.
---

# Commit on Issue / Task Completion

Whenever an issue, bug fix, feature, SDK task, refactoring, or user-requested task is finished:

1. **Run `/code-auditor`**:
   - Before committing, invoke the `/code-auditor` skill on all modified, new, and affected files.
   - Review for:
     - 🔴 **Severity 1 (Critical / High Risk)**: Zone/binding initialization crashes, timer leaks, unhandled async exceptions in user code, queue data loss, unauthorized dependencies.
     - 🟠 **Severity 2 (Medium / Structural)**: Unconditional platform imports (`dart:io` or `package:web`), non-clock backoff timing, broken frame mask bounds.
     - 🟡 **Severity 3 (Low / Code Smells)**: Redundant elements, missing unit tests for corner cases.
2. **Resolve All Findings First**:
   - Fix all identified issues (especially Severity 1 and Severity 2) immediately.
   - Do not proceed to commit while audit findings remain unaddressed.
3. **Verify Implementation & Tests**:
   - Static analysis: `flutter analyze` must pass with 0 issues.
   - Automated tests: `flutter test` must pass with zero regressions.
4. **Commit Automatically**:
   - Stage the modified and new files relevant to the completed task (`git add <files>`).
   - Do NOT stage unrelated changes or temporary/scratch files.
   - Create a commit with a clear, conventional commit title and a detailed message body explaining the changes:
     ```bash
     git commit -m "<type>(<scope>): <summary>" -m "<detailed bullet points explaining what was changed, audit fixes applied, and why>"
     ```
   - Types: `fix`, `feat`, `refactor`, `perf`, `test`, `docs`, `chore`.
   - If the task addresses an issue, mention it in the commit footer (e.g., `Fixes #123` or `Closes #123`).
5. **Do Not Push**: Do not run `git push` unless the user explicitly asks to push.

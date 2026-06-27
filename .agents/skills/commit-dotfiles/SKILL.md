---
name: commit-dotfiles
description: Audit, document, validate, and commit the complete current worktree in the ~/.dotfiles repository. Use whenever the user asks to commit dotfiles changes, save the current dotfiles worktree, prepare a dotfiles commit, or check dotfiles changes before committing. Covers tracked, staged, and untracked files; sensitive-information and LF checks; GNU Stow package consistency; README and installation documentation; relevant validation; intentional staging; and the final local commit.
---

# Commit Dotfiles

Commit the entire dotfiles worktree only after proving that the resulting snapshot is safe, documented, installable, and internally consistent.

## Workflow

1. Resolve the repository root with `git rev-parse --show-toplevel` and confirm it is the dotfiles repository. Read applicable `AGENTS.md` files.
2. Inventory everything with `git status --short --branch`, unstaged and staged diffs, and the contents of every untracked file. Treat pre-existing changes as part of the requested commit; do not discard or overwrite them.
3. Explain the themes represented by the worktree. If a file is unclear, inspect its callers, consumers, or live configuration before changing it.
4. Run `scripts/audit-worktree.sh` from this skill. Review every finding; do not dismiss warnings merely to make the audit green.
5. Inspect the implementation for correctness, stale references, inconsistent names, missing files, invalid executable modes, and accidental generated artifacts.
6. Enforce the repository layout for newly added software:
   - Use one top-level GNU Stow package per software/config family.
   - Mirror the home-relative destination under it, normally `<package>/.config/<software>/...`.
   - Keep machine-local output, caches, secrets, databases, and generated state out of Git.
   - Match the established package template instead of inventing a one-off layout.
   - Keep standalone source projects outside `.dotfiles`. Give substantial tools their own repositories; group small coupled helpers in a documented tools workspace.
   - Install companion executables into `~/.local/bin`. Never point configs or installed symlinks at a repository `target/`, `build/`, or virtual-environment directory.
7. Update documentation as part of the same worktree:
   - Add every new software or package name to the `README.md` package inventory or the relevant documented section.
   - Update feature descriptions when user-visible behavior changed.
   - Keep installation instructions accurate, including required packages, optional dependencies, privileged helpers, and any manual post-install step.
   - Confirm `install.sh` discovers only real Stow packages and that every documented example names a package that exists.
   - Update other READMEs only when their scope changed. Do not create release notes or bump a version unless requested.
8. Run validation proportional to the changed files. Prefer repository-native checks, then use syntax tools such as `bash -n`, `zsh -n`, `qmllint`, `cargo test`, or application-specific config checks. Never auto-format unrelated files.
9. Re-read `git diff` and `git status`. Confirm that every worktree file is intended, documented where necessary, and included.
10. Stage the complete worktree with `git add -A`. Review `git diff --cached --stat`, `git diff --cached --summary`, and the full staged patch. Run `git diff --cached --check` and the audit script again.
11. Commit locally with a concise message describing the actual worktree. Never add `Co-Authored-By` or generated-by metadata. Do not push, tag, or create a release unless explicitly requested.
12. Verify the commit with `git status --short --branch` and `git show --stat --oneline --decorate HEAD`. Report the commit hash, validation performed, and any non-blocking caveats.

## Sensitive-information policy

- Scan all changed and untracked regular files, not only the visible diff hunk.
- Treat private-key material, access tokens, API keys, passwords, personal email addresses, and machine-specific identity/path data as review blockers until explained.
- Replace portable hard-coded home paths with `$HOME` or `~` where the target syntax supports expansion.
- Never print a discovered secret in the final response. Report the file and secret category, redact the value, and stop before committing.
- Do not modify credentials automatically.

## Audit script

Run:

```bash
.agents/skills/commit-dotfiles/scripts/audit-worktree.sh
```

The script checks the full commit candidate for conflict markers, CRLF line endings, common secret signatures, identity-specific strings, and Git whitespace errors. It uses `gitleaks` when available and retains a conservative built-in scan when it is not.

Treat exit code `1` as findings requiring review. Exit code `2` means the script could not perform a valid audit.

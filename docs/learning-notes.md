# Learning Notes

## Stage 0 – Repo scaffold & Git hygiene
**Date:** 2026-11-01

### What I built
- Folders `terraform/`, `scripts/`, `docs/`, each with a `.gitkeep` so Git tracks them while empty.
- `.gitignore` and `.gitattributes`, both in place **before** the first commit.

### Key concepts
- **`*` in gitignore** matches any characters (including none) but never crosses a `/`. Put fixed text on both sides so only the varying part is wild: `crash*.log` catches `crash.log` and `crash.123.log`, while `crash*` would also hide files like `crash-recovery.md`.
- **Anchoring:** a `/` at the start *or in the middle* of a pattern anchors it to the repo root. `terraform/.terraform/` only matches that one path; `.terraform/` (slash only at the end) matches the folder at any depth. A trailing `/` means "folders only", which is why `.terraform.lock.hcl` isn't ignored.
- **Commit vs ignore:**
  - Commit `.terraform.lock.hcl`: it pins exact provider versions so every machine and CI run uses the same ones.
  - Ignore `.terraform/` (downloaded providers), `terraform.tfstate*` (state can contain secrets and resource details), `*.tfvars` (real values like subscription ID and my IP), `*.tfplan`, and `crash*.log`.
- **Line endings:** Windows uses CRLF, Linux uses LF. A bash script with CRLF fails with `/bin/bash^M: bad interpreter`. `*.sh text eol=lf` in `.gitattributes` forces LF for shell scripts.

### Mistakes I made & how I fixed them
- `/terraform` would have ignored my **entire** Terraform folder, code included. Fixed with `.terraform/`.
- `terraform.tfstate.*` caught the backup but missed `terraform.tfstate` itself, because it required a dot plus more characters. Fixed with `terraform.tfstate*`.
- `git rm --cached` with no file gave `fatal: No pathspec was given`; Git needs a path.
- My tfvars file got deleted from disk while still staged (`git status` showed `AD` = Added in staging, Deleted on disk). `git restore terraform/terraform.tfvars` brought it back from the staged copy, then `git rm --cached terraform/terraform.tfvars` unstaged it properly.
  - `git rm --cached <file>` removes from staging only; `git rm <file>` removes from staging **and** disk.

### Break-fix challenge
- **Broke:** force-staged my ignored secrets file with `git add -f terraform/terraform.tfvars`.
- **Predicted:** it would show as staged, and Git would track my edits even though `*.tfvars` is ignored. Both correct.
- **Lesson:** `.gitignore` only affects **untracked** files. Once a file is staged or committed, ignore rules don't apply to it.
- **If a secret is already pushed:** `git rm --cached` isn't enough because it stays in history. Rotate the secret first (new key, remove the IP from the firewall), then optionally clean history with `git filter-repo`. Always check `git status` before committing.

### Questions I still have
-

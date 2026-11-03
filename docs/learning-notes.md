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
- Still work a little more on git fundamentals

## Stage 1 – Provider, resource group, variables, outputs
**Date:** 2026-11-02

### What Terraform is (my version)
Terraform is like a standard image or an Intune policy, but for cloud infrastructure. Instead of setting up each resource by hand in the portal and hoping it ends up right, I define the build once in code and every deployment comes out identical. If someone changes a setting outside Terraform, the next `apply` puts it back.

- **Code** (`.tf` files) = the blueprint: what I *want*.
- **State** (`terraform.tfstate`) = Terraform's record of what it *built*.
- **Azure** = reality: what *actually exists*.
- `plan` compares them; `apply` makes reality match the blueprint. Workflow: **Write → Plan → Apply → Destroy**.

### What I built
- `versions.tf`: Terraform `>= 1.16, < 2.0`, azurerm `~> 5.12`.
- `providers.tf`: `features {}`, `subscription_id` from a variable, `storage_use_azuread = true`.
- `variables.tf`: `subscription_id`, `location`, `prefix`, `tags`, `my_public_ip`.
- `main.tf`: resource group `securestg-rg` named with `"${var.prefix}-rg"`.
- `outputs.tf`: resource group name and location.
- `terraform.tfvars` (real values, ignored) and `terraform.tfvars.example` (placeholders, committed).

### Key concepts
- **HCL blocks:** `resource "<type>" "<my nickname>" { argument = value }`. The type comes from the registry docs; the nickname is only used inside my code. References look like `azurerm_resource_group.storage.name`.
- **Pinning:** `~> 5.12` allows 5.12+ but never 6.0, so a breaking major version can't sneak in. The lock file records the exact version installed (5.12.0).
- **`storage_use_azuread = true`:** Terraform uses my Entra ID login for storage data operations. Needed in Stage 2 because Shared Key will be disabled.
- **No defaults for `subscription_id` and `my_public_ip`:** defaults live in committed code. Without a value, Terraform prompts for it (or errors in CI with `-input=false`).
- **Outputs read from the resource, not the variable:** the resource reflects what Azure actually created.
- **`fmt` vs `validate` vs `plan`:** `fmt` = style, `validate` = syntax (it did **not** catch an undeclared variable in the provider block), `plan` = real values against Azure.
- **Plan symbols:** `+` create, `~` update in place, `-` destroy, `-/+` replace. Always read the `X to add, Y to change, Z to destroy` line. `# forces replacement` means the resource will be deleted and recreated. Example: changing `prefix` would destroy the resource group and everything in it.
- **Saved plans:** `plan -out=tfplan` + `apply tfplan` applies exactly what was reviewed. Used in CI.

### Mistakes I made & how I fixed them
- Used 4-space indentation; Terraform's standard is 2. `terraform fmt` fixes it automatically.
- Forgot to save files in the editor, so `variables.tf` was 0 bytes. An empty `.tf` file still passes `validate`.
- Hard-coded `name = "storage"` instead of using the prefix. Fixed with `"${var.prefix}-rg"`.
- Descriptions that just repeated the variable name. Descriptions show up when Terraform prompts for a value, so they should say what it's for.

### Break-fix challenge (drift)
- **Broke:** changed a tag outside Terraform with `az group update --set tags.environment=production`.
- **Expected plan:** `~` update in place, `"production" -> "lab"`, no replacement (tags can be edited live).
- **Fixed:** I used `az` to set it back, and `terraform plan` showed no changes. The better fix is `terraform apply`: it reverts every drifted setting from the code, without me needing to know what changed.
- **Lessons:**
  - If Terraform manages it, change it through Terraform.
  - Terraform only detects drift when I run it, and only on resources in its state.
  - If the portal change was intentional, update the code to match instead.
- Be careful pasting `az` output publicly: the `id` field contains my subscription ID.

### Questions I still have
-

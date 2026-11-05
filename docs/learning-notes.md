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
- Understand a little more about Terraform files, how to write them and understand them a little further.

## Stage 2 – Storage account
**Date:** 2026-11-03

### What I built
- Added the `hashicorp/random` provider (`~> 3.5`, installed 3.9.1) and a `random_string.suffix` (8 characters, lowercase letters and numbers only).
- `azurerm_storage_account.storage` named `"${var.prefix}${random_string.suffix.result}"` (17 characters), Standard tier, LRS.
- Security settings and why:
  - `min_tls_version = "TLS1_2"` and `https_traffic_only_enabled = true`: no old protocols, no plaintext traffic.
  - `shared_access_key_enabled = false`: no account keys, so everyone has to use Entra ID + RBAC.
  - `default_to_oauth_authentication = true`: the portal uses my Entra ID login instead of trying the keys.
  - `allow_nested_items_to_be_public = false`: no container or blob can be made public.
  - `infrastructure_encryption_enabled = true`: a second layer of encryption (defense in depth).
  - `blob_properties`: versioning, plus 7-day soft delete for blobs and containers.
- Outputs: storage account name and ID.

### Key concepts
- **Storage account names** are globally unique across all of Azure, 3–24 characters, lowercase letters and numbers only. No hyphens, so `"${var.prefix}-sa"` can't work. That's why I need a random suffix.
- **Adding a provider needs `init`:** because init is the only command that downloads plugins.
- **The suffix doesn't change on a second apply:** the result is saved in state. It only changes if the `random_string` itself is replaced.
- **Dependency graph:** the storage account's name references `random_string.suffix.result`, so Terraform creates the suffix first. I didn't have to declare the order. It's also why the name shows `(known after apply)` in the plan.
- **Resource ID** = the full address of a resource, like a file path (or an AD distinguished name). A name like `securestg-rg` can exist in many subscriptions, but the ID can only mean one thing: `/subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<name>`. RBAC scopes use IDs, and access inherits down the path. That's why I'll scope my data role to the storage account and not the resource group (least privilege).
- **Arguments vs. attributes:** arguments are what I set; attributes (bottom of the docs page) are what I can read after creation, like `id`. I pass whichever one the argument asks for: `resource_group_name` wants `.name`.
- **Control plane vs. data plane:** Owner manages the *resource* (settings, delete, roles). Reading blobs is data plane and needs *Storage Blob Data Reader/Contributor*. Owner normally "works" because it can run `listKeys` and the portal quietly uses the key. With Shared Key disabled, that's gone, so I got "You do not have permissions to list the data" on the Containers page.
- **Replacement:** changing `infrastructure_encryption_enabled` (or the name) shows `-/+` with `# forces replacement`. Terraform deletes first, then creates, and the data is gone. It recreates the account with the same name because the suffix is still in state. Always stop and read `-/+` on anything that holds data.
- **Soft delete vs. versioning:** soft delete protects against *deletes* (deleted blobs or containers are hidden and restorable for 7 days). Versioning protects against *overwrites*. Both live **inside** the account, like a USB drive's recycle bin, so `terraform destroy` wipes them too. Soft delete doesn't block `destroy`; resource locks, locked immutability policies and Key Vault purge protection do.
- **A second `plan` showing "No changes" matters because:** Because it proves the initial apply worked since there is no changes left.

### Mistakes I made & how I fixed them
- Put `random = { ... }` **inside** the `azurerm = { ... }` object in `required_providers`. Each provider is its own entry; `terraform fmt` indentation showed it.
- `~> 3.8.0` only allows patch versions (3.8.x), not "at least 3.8". `~>` only lets the **last** number I write go up.
- Comment said one version, code said another. Keep them in sync.
- Put a space in the nickname (`"suffix stgacc"`). Names can only have letters, digits, underscores and dashes.
- Wrote `"${var.prefix}random_string.suffix.result` with no `${}` and no closing quote. Validate pointed at the wrong line (`tags`) because the string never closed.
- `TLS1_2` without quotes. Text values need quotes.
- Guessed `shared_key_access_enabled`; the real argument is `shared_access_key_enabled`. Search the docs instead of guessing.

### Break-fix challenge (security drift)
- **Broke:** turned Shared Key back on outside Terraform with `az storage account update --allow-shared-key-access true`.
- **My predictions:**
  - Replacement. **Wrong:** Azure can change this setting on the live account, so the plan showed `~` update in place (`true -> false`). `# forces replacement` is only for settings that can't change after creation.
  - Someone with the key could read data and I'd be locked out. **Half wrong:** nobody gets locked out. The problem is *more* access.
- **What happened:** `az storage container list --auth-mode key` fetched the account key with my Owner permissions and succeeded, even though I have no data role. After `terraform apply`, the same command failed.
- **Lessons:**
  - The account key is a back door around RBAC: it works like a master password, isn't tied to a person in the logs, and never expires on its own.
  - `terraform apply` fixed the drift from the code. I didn't need to know what changed.
  - Terraform only catches drift when I run it, so the back door was open until then. Azure Policy (deny/audit Shared Key access) closes that gap.
  - Storage data-plane logs only exist if diagnostic settings are turned on.

### Questions I still have
- 

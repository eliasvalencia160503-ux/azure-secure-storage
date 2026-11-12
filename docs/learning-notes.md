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


## Stage 3 – RBAC (data-plane access) and a private container
**Date:** 2026-11-06

### What I built
- `data "azurerm_client_config" "current"`: reads who is running Terraform (creates nothing).
- `azurerm_role_assignment.blob_contributor_me`: **Storage Blob Data Contributor**, scoped to the storage account's `.id`, given to my `object_id`.
- `azurerm_storage_container.storage_cont`: `privatecont`, access type `"private"`, `depends_on` the role assignment.
- Outputs: `object_id`, `storage_container_name`.

### Key concepts
- **Data source vs. resource:** a `data` block reads something that already exists, like my current Azure login, and never creates anything. Data sources are read during `plan`, so `principal_id` showed a real value. `scope` showed `(known after apply)` because Azure only assigns the storage account's ID when it creates the account.
- **Principal / object ID:** a principal is any identity that can get a role (user, group, service principal, managed identity). The object ID is its GUID that never changes, like the objectGUID/SID in on-prem AD. My display name or UPN can change; the object ID can't, so RBAC stores the object ID.
- **Why object ID and not tenant ID:** the tenant ID is the whole directory (like the domain), so it can't say *who* gets the role. The object ID is one identity in it.

  | Question | Answer |
  |---|---|
  | Which organization? | `tenant_id` |
  | Which subscription? | `subscription_id` |
  | Which identity gets access? | `object_id` → `principal_id` |

- **Role definition vs. role assignment:** a definition is the role itself (the list of permissions, like "Storage Blob Data Contributor"); an assignment gives that role to one principal at one scope.
- **Scope must be the `.id`:** `.name` is just the short name. RBAC needs the full path (`/subscriptions/.../storageAccounts/...`) so it knows exactly which account. Scoping to the storage account and not the resource group = least privilege: I only get data access to this one account, not everything else in the resource group.
- **Hidden dependencies and `depends_on`:** Terraform only sees order from references. The container uses no value from the role assignment; it only needs the *permission*, so I added `depends_on` because otherwise Terraform could create both at the same time and the container would fail with a 403. RBAC can still take 1–2 minutes to take effect, so a retry may be needed anyway.
- **Order on apply:** RG + suffix (parallel) → storage account → role assignment → container.
- **Later in CI:** `object_id` will be the pipeline's service principal, not me, so the role would go to the pipeline and I'd need a separate assignment for my own user if I still want portal access.

### Mistakes I made & how I fixed them
- Used `azurerm_role_definition` (creates a custom role) instead of `azurerm_role_assignment` (gives a role to someone).
- Scope was `random_string.suffix.result`, then `.name`, then finally `.id`. `validate` passed with `.name` because it only checks that `scope` is a string, not that it's a real resource ID. It would only have failed at `apply`, after other resources were already created.
- Made up the role name "Storage Blob Data Container". Role names must match exactly.
- `private` without quotes, the same mistake as `TLS1_2` in Stage 2.
- `private_cont`: underscores aren't allowed in container names (lowercase letters, numbers, hyphens).
- Put an output in `main.tf` with no description. Outputs go in `outputs.tf`.

### Break-fix challenge (Contributor → Reader)
- **Predicted:** a 2nd assignment gets added, and Reader can't even list.
- **What happened:** `-/+ replace` (`# forces replacement`). Listing worked; upload failed with 403 `AuthorizationPermissionMismatch`.
- **Lessons:**
  - Role assignments can't be edited in Azure, so changing the role deletes the old assignment and creates a new one. For a short time I had no data role at all.
  - `~` vs `-/+` depends on what Azure allows to change on a live resource, not on how big the change looks.
  - Reader = list and read blobs only; Contributor = read, write and delete. Least privilege means giving Reader to anything that only consumes data, and Contributor only to things that actually write.



## Stage 4 – Storage firewall (network rules)
**Date:** 2026-11-09

### What I built
- A `network_rules` block inside `azurerm_storage_account.storage` (inline, like `blob_properties`):
  - `default_action = "Deny"`: anything that doesn't match a rule is blocked.
  - `ip_rules = [var.my_public_ip]`: only my public IP is allowed.
  - `bypass = ["AzureServices"]`: trusted Microsoft services (Backup, Monitor, etc.) can still get through.
- `public_network_access_enabled` stays on. IP rules only apply to the public endpoint, so turning it off would lock everyone out (that's what Private Endpoints are for).
- My real IP lives only in `terraform.tfvars` (gitignored), never in a `.tf` file.

### Key concepts
- **Two locks:** RBAC (Stage 3) checks *who I am*; the firewall checks *where I'm coming from*. Both have to pass. Someone with Storage Blob Data Contributor still gets a 403 from the wrong IP, because the firewall rejects the request before RBAC is even checked.
- **The firewall allows an IP, not a device.** On a different network I have to update `my_public_ip` (`curl -s https://api.ipify.org`) and apply. Azure never updates the rule for me.
- **Management plane vs. data plane (again):** the firewall only guards the data plane (`<account>.blob.core.windows.net`). Terraform changes settings through the management plane (`management.azure.com`), so even with the wrong IP, `terraform apply` still works and I can't lock Terraform out of fixing it. Same for the portal: Overview loads, Containers doesn't.
- **`bypass` and least privilege:** `Metrics` and `Logging` are for classic Storage Analytics, which I don't use. I kept only `AzureServices`.
- **`~` again:** adding firewall rules is an update in place, because Azure can change them on a live account.
- **DNS error vs. firewall error:**
  - `Failed to resolve ... getaddrinfo failed` = DNS. The account name doesn't exist, so the request never reached Azure.
  - HTTP `403 AuthorizationFailure` = the request reached Azure and the firewall (or RBAC) rejected it.
- **Saved plans:** `terraform plan -out=main.tfplan` then `terraform apply main.tfplan` applies exactly what I reviewed, with no new plan and no `yes` prompt. Plain `terraform apply` is fine when I review and apply right away; saved plans matter when time or people come between review and apply, like CI. A saved plan only works once.

### Mistakes I made & how I fixed them
- `ip_rules = var.my_public_ip`: `validate` said "set of string required, but have string". Wrapping it in brackets fixed it: `[var.my_public_ip]`. Variable references never take quotes.
- Started with `bypass = ["Metrics", "Logging", "AzureServices"]`, which allows more than I need. Cut it down to `["AzureServices"]`.
- Passed a GUID (one of my IDs) as `--account-name` and got a DNS error. Fixed by using `terraform output storage_account_name`. Storage account names never have hyphens, so a GUID can't be one.
- Plan file naming: `.gitignore` has `*.tfplan`, so a file named just `tfplan` would **not** be ignored. Name plan files `something.tfplan`.

### Break-fix challenge (wrong IP)
- **Broke:** changed `my_public_ip` in `terraform.tfvars` to `203.0.113.10` (a documentation-only IP) and applied.
- **Predicted:**
  - a. Plan shows `~` update in place. ✅
  - b. Apply succeeds. ✅ (management plane isn't behind the firewall)
  - c. `az storage blob list --auth-mode login` returns 403. ✅
  - d. Portal Overview works, Containers doesn't. ✅
- **Fixed:** put my real IP back in `terraform.tfvars` and applied again; `blob list` worked.
- **Lessons:**
  - The firewall is checked before RBAC; a valid role doesn't help from the wrong network.
  - Moving networks = update the variable and apply.
  - The firewall protects data, not settings. Someone with Owner/Contributor on the management plane can still change the firewall, so who has management roles still matters.



## Stage 5 – Catch-up: lifecycle rule, immutability (WORM), file share
**Date:** 2026-11-09

### Why this stage
My original roadmap had a lifecycle rule in Stage 2 and immutability + a file share in Stage 3, but we skipped them. This stage catches up before moving on to networking (VNet / private endpoint) in Stage 6.

### What I built
- `azurerm_storage_management_policy.cleanup`: one rule, `autocleanup`, for block blobs only (`filters { blob_types = ["blockBlob"] }`):
  - Move to **Cool** after 30 days without changes, **delete** after 365 days.
  - Delete old **versions** after 90 days (versioning is on, so they'd pile up otherwise).
- `azurerm_storage_container_immutability_policy.retention`: time-based retention on `privatecont`, **1 day**, `locked = false`.
- `azurerm_storage_share.fileshare`: Azure Files share `sharefile`, `quota = 1` GB, using `storage_account_id`.
- Output: `file_share_name`.
- Plan: `3 to add, 0 to change, 0 to destroy`. Nothing existing was touched.

### Key concepts
- **Lifecycle management = cost control.** Data I don't touch moves to a cheaper tier automatically and is eventually deleted. It runs about once a day, not instantly.
- **Immutability (WORM = write once, read many):** during retention, a blob can't be **deleted or overwritten** by anyone, not even Owner. It sits above RBAC.
- **Locked vs. unlocked:**
  - Unlocked: the policy can be edited or deleted. Good for testing.
  - Locked: retention can only be **extended**, never shortened or removed. Protected blobs can't be deleted until retention ends, so `terraform destroy` would fail and I'd keep paying. Only lock it when compliance requires it.
- **`protected_append_writes_enabled`:** allows adding to existing blobs while old data stays protected (for logs). I left it at the default (`false`).
- **How the protections stack:**

  | Protection | Stops | Weakness |
  |---|---|---|
  | RBAC | Unauthorized people | Anyone with the right role gets in |
  | Soft delete | Permanent loss from deletes (7-day recycle bin) | Data still gets "deleted" |
  | Versioning | Permanent loss from overwrites (old copy kept) | Old versions can be deleted |
  | Immutability | Any change or delete during retention | Nothing, during retention. Good against ransomware or stolen admin creds |

- **Azure Files and Shared Key:** Terraform created the share fine, because `storage_account_id` goes through the management plane (ARM), no key needed. *Using* the share is different:
  - `az storage file upload` tries the account key by default, and I disabled keys.
  - My **Blob** Data Contributor role doesn't cover files. Files have their own roles ("Storage File Data …"). Data roles are per service.
  - Coming back to this in Stage 7 with the VM + managed identity.
- **Destroy order is the reverse of create order.** The policy references the container, so Terraform creates the container first and deletes the policy first.
- **PowerShell gotcha:** `terraform plan -out=main.tfplan` fails with "Too many command line arguments" because PowerShell splits `-flag=value` at the dot. Quote it: `terraform plan "-out=main.tfplan"`. Bash/Linux doesn't have this problem.
- **Newline at end of file:** text files should end with a newline. Without it, Git shows `\ No newline at end of file` and diffs get messy. VS Code setting "insert final newline" adds it automatically.

### Mistakes I made & how I fixed them
- Lifecycle rule without a `filters` block: `validate` said "At least 1 filters blocks are required". Added `blob_types = ["blockBlob"]`.
- Rule named `rule1`; renamed it `autocleanup` so it says what it does.
- Spelled it **in**mutability (Spanish: *inmutabilidad*) in the resource type, the argument (also missing a letter) and the nickname. Copy names from the docs instead of typing them.
- Lined up `=` signs by hand and was off by one space. Run `terraform fmt` before every check.
- Forgot to save the file, so the reviewer saw nothing (same as Stage 1).
- Tried the upload test against the **file share** instead of the blob **container**; the WORM policy is only on the container.
- `[WinError 2] cannot find the file 'test.txt'`: `--file` is a file on *my computer*, and it didn't exist. Created it in `$env:TEMP` so it stays out of the repo.

### Break-fix challenge (WORM)
- **Test:** uploaded `test.txt` and tried to delete it → `This operation is not permitted as the blob is immutable due to a policy.` Even with Contributor.
- **Prediction 1:** overwriting with `--overwrite` would work and create a new version. ❌ **Blocked.** WORM freezes the content; versioning only keeps old copies *when* an overwrite is allowed, and here it isn't.
- **Prediction 2:** `terraform destroy` with a protected blob still inside would succeed. ✅ Terraform deleted the unlocked policy first, which released the blob, then removed the container, account and resource group. State ended up empty.
- **Lessons:**
  - Immutability blocks overwrites too, not just deletes.
  - `locked = false` is what made destroy possible. A locked policy would have stopped the destroy partway.
  - Always check which resource has a dependency on which; it decides the destroy order.


## Stage 6 – Private networking: VNet, service endpoint, private endpoint, private DNS
**Date:** 2026-11-11

### What I built
- **6a – VNet + service endpoint**
  - `azurerm_virtual_network.stvnet`: `10.0.0.0/16`.
  - `azurerm_subnet.vm`: `10.0.1.0/24`, with a `service_endpoint { service = "Microsoft.Storage" }` block. This is for the Stage 7 VM.
  - `azurerm_subnet.pe`: `10.0.2.0/24`, only for the private endpoint.
  - Storage firewall: added `virtual_network_subnet_ids = [azurerm_subnet.vm.id]` to `network_rules`, and kept `ip_rules` so I don't lock myself out.
- **6b – Private endpoint + private DNS**
  - `azurerm_private_dns_zone.dnszone`: `privatelink.blob.core.windows.net`. The name has to be exactly this.
  - `azurerm_private_dns_zone_virtual_network_link.vnetlink`: connects the zone to the VNet (`registration_enabled = false`).
  - `azurerm_private_endpoint.pe`: in the `pe` subnet, pointing at the **storage account** with `subresource_names = ["blob"]`, `is_manual_connection = false`, plus a `private_dns_zone_group` that holds the zone ID.
  - Outputs: `vnet_name`, `private_endpoint_ip`.
- Plan from empty state: `14 to add` (8 from earlier stages + 3 for 6a + 3 for 6b). The `data` source isn't counted, because it only reads.
- Result: `private_endpoint_ip = 10.0.2.4`. Azure reserves `.0`–`.3` in every subnet, so `.4` is the first free address.

### Key concepts
- **Management plane vs. data plane** (this answers my Stage 4 question):

  | | Management plane | Data plane |
  |---|---|---|
  | What it does: Creates and configures resources | Reads and writes the data inside them 
  | Endpoint | `management.azure.com` (ARM) | `<account>.blob.core.windows.net` |
  | Who uses it | Terraform, portal, `az network …` | `az storage blob …`, apps, the VM |
  | RBAC roles | Owner, Contributor | Storage Blob Data Contributor, Storage File Data … |
  | Storage firewall applies? | No | Yes |

  - The firewall, service endpoints and private endpoints only affect the **data plane**. Terraform keeps working no matter what I put in `network_rules`.
- **Service endpoint vs. private endpoint:**

  | | Service endpoint | Private endpoint |
  |---|---|---|
  | Storage IP | Stays **public** | Gets a **private** IP in my subnet (`10.0.2.4`) |
  | How it works | Traffic from the subnet travels on Azure's backbone, and the firewall allows that subnet | A network card for the storage account sits in my subnet |
  | DNS change | None | Needs the `privatelink` DNS zone |
  | Cost | Free | Charged per hour + data |
  | Works from on-prem / peered VNets | No | Yes |

  - A subnet rule in the firewall only works if the subnet has the `Microsoft.Storage` service endpoint. Without it, Azure rejects the rule.
  - Private endpoint traffic doesn't go through `ip_rules` / `virtual_network_subnet_ids`. An approved endpoint is allowed in by itself.
- **The DNS chain:**
  ```
  <account>.blob.core.windows.net
    └─ CNAME → <account>.privatelink.blob.core.windows.net
                 └─ private zone A record → 10.0.2.4 (only inside the VNet)
  ```
  - The **VNet link** makes the whole VNet (every subnet) use the private zone. Without it the zone exists but nobody asks it anything.
  - The **DNS zone group** makes Azure create the A record automatically (`creator="created by private endpoint securestg-pe"`). Without it the endpoint gets its IP but the name still resolves to the public IP. This is the most common private endpoint mistake.
  - From my laptop, `nslookup` showed the `privatelink` alias but a **public** IP (`20.60.135.196`). My network's DNS (Google, 8.8.8.8) can't see the private zone.
  - In Stage 7, the VM in the `vm` subnet will get `10.0.2.4`, so its blob traffic will go through the private endpoint, not the service endpoint.
- **How Terraform picks a provider:** the resource type name up to the first `_`. `azurerm_subnet` → `azurerm`. A typo like `private_dns_…` makes it look for a provider called `private`.
- **Nested blocks are lists.** To read a value from one I need an index: `azurerm_private_endpoint.pe.private_service_connection[0].private_ip_address`. Attributes (under **Attributes Reference** in the docs) are values Azure returns after creating the resource.
- **`.id` vs. `.name`:** the firewall needs the subnet's full resource ID, because a name like `securestg-vm` could exist in many VNets.

### Mistakes I made & how I fixed them
- Used `service_endpoints = ["Microsoft.Storage"]` (a list, from older provider versions). In azurerm 5.x it's a **block**: `service_endpoint { service = "Microsoft.Storage" }`. Always check the docs for the version I'm actually using.
- Renamed the subnet nicknames (`stsubnetvm` → `vm`) but forgot the reference in `network_rules` → `Reference to undeclared resource`. Renaming a resource means updating every reference to it.
- Wrote the VNet link type as `private_dns_virtual_network_link` → `Missing required provider … hashicorp/private`. Missing the `azurerm_` prefix and the word `zone`. Copy type names from the docs.
- Left the DNS zone name unquoted → Terraform read `privatelink.blob…` as a reference to a resource. Fixed text needs quotes.
- Forgot `name` and `virtual_network_id` on the VNet link. A link needs both ends.
- Thought `private_connection_resource_id` should be the DNS zone. It's the **storage account**. The DNS zone ID goes in `private_dns_zone_group`.
- Missing newline at end of file (again) in `main.tf` and `outputs.tf`.
- `az … record-set a list` said the required arguments were missing because the command got split onto two lines in PowerShell. Paste long commands as one line.

### Break-fix challenge (firewall vs. private endpoint)
- **Change:** removed my IP from `ip_rules` (kept the subnet rule and the private endpoint) and applied.
- **Prediction 1:** `az storage blob list` from my laptop would be **blocked**. ✅ My laptop resolves to the public IP, and nothing allows that path now. The private endpoint only helps clients inside the VNet.
- **Prediction 2:** `terraform plan` would still work. ✅ Terraform uses the management plane, and the storage firewall doesn't guard it.
- **Catch:** I wasn't home, so my public IP was probably already different from `my_public_ip`. To prove the change caused the block, test one change at a time: put my current IP in, confirm it works, then remove it.
- **Lessons:**
  - A private endpoint is not a backdoor for me. It's a private door for things inside the VNet.
  - Firewall rules only control the data plane.
  - My public IP changes when I change networks, so the IP rule breaks when I'm away from home.


# Sprint 2 - Design

## SLI-2. GitHub repository workflow OCI access configuration script/action

Status: Proposed

### Requirement Summary

Two deliverables:

1. `setup_oci_github_access.sh` — local operator script that authenticates with OCI, packs credentials, and uploads them as a GitHub secret.
2. `.github/actions/oci-profile-setup/` — composite action that unpacks the secret and restores OCI credentials on each workflow run.

### Feasibility Analysis

**API Availability:**

- `oci session authenticate` — available in OCI CLI 3.x. Produces a session-token-based config under `~/.oci/sessions/<profile>/`.
- `oci iam region-subscription list` — available; returns `is-home-region` field in each entry.
- `gh secret set` — available in `gh` CLI 2.x; reads value from `--body` or stdin; requires `secrets: write` permission on the repo.
- `base64` encode/decode — GNU coreutils, available on Ubuntu runners and macOS.
- `tar` + `base64` — reliable cross-platform pack/unpack for multi-file payloads.

**Technical Constraints:**

- GitHub secret value limit: 64 KB. OCI session config + key files are well under this limit.
- `oci session authenticate` is interactive (opens browser). The script must guide the operator through this step; it cannot be fully automated.
- Session tokens expire (default ~1 hour for OCI). Documented as a known limitation.

**Risk Assessment:**

- Session expiry: operator must re-run setup script before token expires. Mitigated by clear documentation.
- Multi-profile configs: `~/.oci/config` may contain multiple profiles. Script defaults to `DEFAULT`; operator can override.

### Design Overview

**Architecture:**

```
[Operator machine]                        [GitHub]
setup_oci_github_access.sh
  ├── resolve home region (oci iam ...)
  ├── oci session authenticate
  ├── pack ~/.oci/config + session dir
  │   (tar | base64 → single string)
  └── gh secret set OCI_CONFIG_PAYLOAD ──► GitHub Secret

[GitHub Actions runner]
oci-profile-setup action
  ├── read OCI_CONFIG_PAYLOAD secret
  ├── base64 decode | tar extract → ~/.oci/
  └── verify: ~/.oci/config exists and is readable
```

**Key Components:**

1. `setup_oci_github_access.sh` — operator-run setup script.
2. `.github/actions/oci-profile-setup/action.yml` — composite action definition.
3. `.github/actions/oci-profile-setup/oci_profile_setup.sh` — shell logic for the action.
4. `.github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh` — local round-trip test.
5. `.github/workflows/test-oci-profile-setup.yml` — workflow_dispatch test workflow.

### Technical Specification

**Pack format:**

```bash
# Pack (on operator machine):
tar -czf - -C "$HOME" .oci/config .oci/sessions/<profile>/ | base64 -w 0

# Unpack (in action):
echo "$OCI_CONFIG_PAYLOAD" | base64 -d | tar -xzf - -C "$HOME"
```

**setup_oci_github_access.sh interface:**

```bash
./setup_oci_github_access.sh [--profile PROFILE] [--repo OWNER/REPO] [--secret-name NAME] [--dry-run]
```

- `--profile` — OCI config profile (default: `DEFAULT`)
- `--repo` — GitHub repository in `owner/repo` format (default: detected from `gh repo view`)
- `--secret-name` — GitHub secret name (default: `OCI_CONFIG_PAYLOAD`)
- `--dry-run` — pack and print payload size; do not call `gh secret set`

**oci-profile-setup action inputs:**

| Input | Description | Default |
|-------|-------------|---------|
| `secret-name` | Name of the GitHub secret containing the packed OCI config | `OCI_CONFIG_PAYLOAD` |
| `profile` | OCI profile name to verify after restore | `DEFAULT` |

**Error Handling:**

- Script exits with error if `~/.oci/config` does not exist.
- Script exits with error if `gh` is not authenticated.
- Script exits with error if home region cannot be resolved.
- Action emits `::error::` and exits non-zero if secret is empty or unpack fails.

### Implementation Approach

**setup_oci_github_access.sh:**

1. Validate prerequisites (`oci`, `gh`, `jq`, `base64`, `tar`).
2. Resolve home region: `oci iam region-subscription list --profile "$PROFILE" | jq -r '.data[] | select(."is-home-region") | ."region-name"'`.
3. Run `oci session authenticate --region "$HOME_REGION" --profile "$PROFILE"`.
4. Pack: `tar -czf - -C "$HOME" .oci/config .oci/sessions/$PROFILE/ | base64 -w 0`.
5. If `--dry-run`: print payload size and exit 0.
6. Set secret: `gh secret set "$SECRET_NAME" --body "$PAYLOAD" --repo "$REPO"`.
7. Print confirmation.

**oci_profile_setup.sh:**

1. Read `$OCI_CONFIG_PAYLOAD` from environment.
2. Validate payload is non-empty.
3. `mkdir -p "$HOME/.oci"`.
4. Decode and extract: `echo "$OCI_CONFIG_PAYLOAD" | base64 -d | tar -xzf - -C "$HOME"`.
5. Verify: check that `$HOME/.oci/config` exists and is readable. Emit `::notice::` with confirmation.

### Testing Strategy

**Functional Tests (`test_oci_profile_setup.sh`):**

1. Pack/unpack round-trip: pack a synthetic `~/.oci` tree, unpack to temp dir, verify files match.
2. `--dry-run`: confirm no `gh` call is made, payload size is printed.
3. Missing config: confirm error message and non-zero exit.
4. Malformed payload: confirm action error message.

**GitHub Actions test workflow (`test-oci-profile-setup.yml`):**

- Trigger: `workflow_dispatch`
- Prerequisite: operator has already run `setup_oci_github_access.sh` (human-assisted, browser-based) and `OCI_CONFIG_PAYLOAD` secret is set in the repository.
- Steps: `install-oci-cli` → `oci-profile-setup` (unpacks secret to `~/.oci/`) → verify `~/.oci/config` exists.
- Note: `oci iam region-subscription list` is used **internally** by `setup_oci_github_access.sh` to detect the home region. It is NOT a step in this test workflow.

**Success Criteria:**

- `actionlint` passes on all workflow/action YAML files.
- Local tests pass.
- `workflow_dispatch` run succeeds with OCI CLI authenticated.

### Integration Notes

**Dependencies:**

- `install-oci-cli` action (SLI-1) must run before `oci-profile-setup` in any workflow.
- `emit.sh` will automatically find `~/.oci/config` after `oci-profile-setup` runs.

**Compatibility:**

- Action directory structure mirrors `install-oci-cli` and `sli-event`.
- No changes to existing actions required.

### Documentation Requirements

- `README.md` in `.github/actions/oci-profile-setup/` with usage example.
- `setup_oci_github_access.sh` inline help (`--help` flag).
- Notes on session token expiry and refresh procedure.

### Design Decisions

**Decision 1:** Use `tar | base64` pack format rather than individual secrets per file.
**Rationale:** Keeps the setup to a single GitHub secret; simpler to manage. File count inside `~/.oci/sessions/` can vary.
**Alternatives Considered:** One secret per file — too many secrets, fragile to profile changes.

**Decision 2:** `oci session authenticate` rather than API key auth.
**Rationale:** Requirement explicitly states `oci session authenticate`. Session auth does not require storing long-lived private keys.

### Open Design Questions

None

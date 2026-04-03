# Sprint 2 - Analysis

Status: Complete

## Sprint Overview

Sprint 2 delivers OCI access configuration tooling so GitHub Actions workflows can authenticate with OCI platform. The deliverable is a two-part solution: a local setup script (run once by an operator) that captures OCI session credentials and stores them as GitHub repository secrets, and a composite action (`oci-profile-setup`) that restores those credentials on every workflow run.

## Backlog Items Analysis

### SLI-2. GitHub repository workflow OCI access configuration script/action

**Requirement Summary:**

- A local shell script runs `oci session authenticate` against the home region (resolved via `oci iam region-subscription list` filtering `is-home-region: true`).
- Generated config and key files are base64-packed into a single payload and stored as GitHub repository secret via `gh secret set`.
- A composite action `oci-profile-setup` reads the secret, unpacks config and key files to `~/.oci/`, making OCI CLI ready for subsequent steps.
- A test script validates the full round-trip.
- The composite action is tested with a `workflow_dispatch` GitHub Actions workflow.

**Technical Approach:**

Script: `setup_oci_github_access.sh`

- Detect home region from existing `~/.oci/config` profile using `oci iam region-subscription list`.
- Run `oci session authenticate --region <home_region>` to produce a session-token-based config.
- Pack `~/.oci/config` + session key files into a base64 payload.
- Call `gh secret set OCI_CONFIG_PAYLOAD --body <payload> --repo <owner/repo>`.

Action: `.github/actions/oci-profile-setup/action.yml`

- Input: `oci-config-secret` (name of the GitHub secret, default `OCI_CONFIG_PAYLOAD`).
- Restore `~/.oci/config` and session key files from the payload.
- Verify files are correctly restored (check `~/.oci/config` exists and is readable).

**Dependencies:**

- SLI-1 (`install-oci-cli`): OCI CLI must be installed before `oci-profile-setup` can be used in a workflow.
- `gh` CLI with repository write access for setting secrets.
- `jq`, `base64` (GNU coreutils).

**Testing Strategy:**

- Local test script with `--dry-run` flag validating pack/unpack round-trip without hitting GitHub.

- `setup_oci_github_access.sh` is operator-run (human-assisted: `oci session authenticate` opens a browser). It uses `oci iam region-subscription list` internally to detect the home region — this is not a test step, it is part of the script's logic. The script sets `OCI_CONFIG_PAYLOAD` GitHub secret.

- GitHub Actions test workflow (`workflow_dispatch`) tests only the `oci-profile-setup` action: it assumes the GitHub secret `OCI_CONFIG_PAYLOAD` is already set by `setup_oci_github_access.sh`. The workflow installs OCI CLI, runs the action to restore `~/.oci/`, then verifies `~/.oci/config` and the associated files are present.

- Error cases: malformed payload in secret, missing secret, missing `~/.oci/config` on operator side.

**Risks/Concerns:**

- OCI session tokens expire (typically 1 hour). Documented as a known limitation.
- GitHub secret size limit is 64 KB — well within range for OCI config + key files.
- `gh` CLI must be authenticated on the operator machine before running the setup script.

**Compatibility Notes:**

- Same composite action pattern as SLI-1: `action.yml` + shell script + `tests/` directory under `.github/actions/`.
- `emit.sh` reads OCI config via `oci.config-file` field — `oci-profile-setup` restores to `~/.oci/config` (standard location).

## Overall Sprint Assessment

**Feasibility:** High

**Estimated Complexity:** Moderate — two deliverables (script + action), test script, and workflow test.

**Prerequisites Met:** Yes

**Open Questions:** None

## Recommended Design Focus Areas

- Exact pack/unpack format for the OCI secret payload.
- Handling of multiple OCI profiles (default `DEFAULT`; allow override via input).
- Error messaging when secret is missing or payload is malformed.

## Readiness for Design Phase

Confirmed Ready

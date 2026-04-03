# Sprint 2 - Tests

## Test 1: Local round-trip and setup script smoke tests

**Purpose:** Validate that `oci_profile_setup.sh` correctly restores a packed `~/.oci` tree and that the bundled `setup_oci_github_access.sh` script has basic error handling and help text.

**Expected Outcome:** All local tests pass and report success; no syntax errors in the shell scripts.

**Test Sequence:**

```bash
cd SLI_tracker

# Run local tests for the OCI profile setup action and setup script
bash .github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh
```

**Verification:**

- Output ends with:

  ```text
  Results: 6 / 6 tests passed.
  ```

- No `FAIL:` lines appear in the output.

**Status:** PASS

---

## Test 2: End-to-end GitHub workflow via gh (test-oci-profile-setup)

**Purpose:** Verify that an OCI session packed with `setup_oci_github_access.sh` can be used by the `test-oci-profile-setup.yml` workflow when triggered via GitHub CLI (`gh workflow run`).

**Prerequisites:**

- `oci` CLI installed and configured on the operator machine.
- `gh` CLI installed and authenticated (`gh auth status` succeeds).
- A usable OCI config profile in `~/.oci/config` (for example `[MYTENANCY]`).
- Network access to GitHub and OCI.

**Expected Outcome:** The `Test OCI profile setup` workflow completes successfully on GitHub; the job verifies that `~/.oci/config` and `~/.oci/sessions/<session-profile-name>` exist on the runner.

**Test Sequence (operator machine):**

```bash
cd SLI_tracker

# 1. Create or update the OCI_CONFIG_PAYLOAD secret in the current repo.
#    Replace YOUR_CONFIG_PROFILE with the profile from ~/.oci/config (e.g. MYTENANCY).
#    Optionally change SLI_TEST to another session profile name if desired.

chmod +x .github/actions/oci-profile-setup/setup_oci_github_access.sh

.github/actions/oci-profile-setup/setup_oci_github_access.sh \
  --profile DEFAULT \
  --session-profile-name SLI_TEST \
  --secret-name OCI_CONFIG_PAYLOAD

# 2. Trigger the test workflow using gh.
#    The workflow input "profile" must match the session profile name above (SLI_TEST).

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

gh workflow run test-oci-profile-setup.yml \
  --repo "$REPO" \
  --field profile=SLI_TEST

# 3. Wait for completion and show the result.

gh run watch --repo "$REPO"
gh run list --repo "$REPO" --limit 5
```

**Verification:**

- `gh run watch` finishes with a successful conclusion (no failed jobs).
- In the GitHub Actions UI for `Test OCI profile setup`, the `Verify restored files` step succeeds.
- Logs for the job show that:
  - `~/.oci/config` exists and is readable.
  - `~/.oci/sessions/SLI_TEST` directory exists.

**Status:** PENDING (requires real OCI + GitHub environment to execute)

---

## Test Summary

| Test | Description                                        | Status  |
|------|----------------------------------------------------|---------|
| 1    | Local round-trip and setup script smoke tests      | PASS    |
| 2    | gh-triggered `test-oci-profile-setup` workflow run | PENDING |


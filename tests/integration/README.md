# Integration Tests

End-to-end tests that exercise the full pipeline: GitHub Actions dispatch,
OCI Logging queries, artifact creation, and event verification.

These require live infrastructure (OCI tenancy, GitHub repository access).

## OCI profile and authentication

`test_sli_integration.sh` uses profile **`SLI_TEST`** by default (same session name as
[`.github/actions/oci-profile-setup/setup_oci_github_access.sh`](../../.github/actions/oci-profile-setup/setup_oci_github_access.sh)
`--session-profile-name` and workflow `context-json` `profile`). Override with **`SLI_INTEGRATION_OCI_PROFILE`**
if you only use an API-key profile such as `DEFAULT`.

The script exports **`OCI_CLI_PROFILE`** to that value so **oci_scaffold** and bare `oci` calls use the same identity as the auth gate and T7 `logging-search`.

**Mandatory gate:** the script loops until `oci iam region list --profile <profile> --limit 1` succeeds. To refresh the browser session and pack/upload **`OCI_CONFIG_PAYLOAD`** to the repo with **`gh`**, run `setup_oci_github_access.sh` from the repo root (see script `--help`). Set **`SLI_INTEGRATION_AUTH_NO_LOOP=1`** for a single attempt then exit (e.g. automation).

## Convention

- File naming: `test_<domain>.sh` (one file per domain, not per sprint)
- New sprint test cases are appended to existing files
- Each script exits 0 if all tests pass, nonzero if any fail
- Scripts should produce `test_run_<timestamp>.log` and `oci_logs_<timestamp>.json` artifacts

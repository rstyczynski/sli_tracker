# Sprint 2 - Implementation

Status: Complete

## Deliverables (SLI-2)

| Artifact | Location |
|----------|----------|
| Operator setup script | `.github/actions/oci-profile-setup/setup_oci_github_access.sh` |
| Composite action | `.github/actions/oci-profile-setup/` (`action.yml`, `oci_profile_setup.sh`, `README.md`) |
| Local tests | `.github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh` |
| CI workflow | `.github/workflows/test-oci-profile-setup.yml` |

## Notes

- Composite action accepts `oci_config_payload` (pass `secrets.OCI_CONFIG_PAYLOAD`) because GitHub Actions cannot dereference dynamic secret names inside the action.
- Setup script uses portable base64 encoding (GNU `-w 0` vs BSD `base64` + strip newlines).
- `gh secret set` receives the payload via stdin to avoid command-line length limits.

## Tests run locally

```bash
bash .github/actions/oci-profile-setup/tests/test_oci_profile_setup.sh
```

## Operator checklist

1. Install `oci`, `gh`, `jq` locally; ensure `~/.oci/config` exists for the target profile.
2. Run `.github/actions/oci-profile-setup/setup_oci_github_access.sh` (browser login for `oci session authenticate`).
3. Confirm secret `OCI_CONFIG_PAYLOAD` in the GitHub repo.
4. Run workflow **Test OCI profile setup** via `workflow_dispatch` (requires the secret).

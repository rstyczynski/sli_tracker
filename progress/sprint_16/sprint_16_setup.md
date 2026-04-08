# Sprint 16 — Setup

Sprint: 16 | Mode: YOLO | Backlog: SLI-24

## Contract

Deliver a dedicated OCI IAM user authenticated by API key, with minimal policies required to ingest SLI data into OCI Logging and OCI Monitoring for this project. Update the GitHub access setup flow (`.github/actions/oci-profile-setup/setup_oci_github_access.sh`) to support this account type, and ensure all client emit paths in the repo remain compatible.

Key constraints:

- User and policies must follow an **ensure/teardown** lifecycle consistent with the `oci_scaffold` approach (the `oci_scaffold` project may be extended in this sprint).
- The resulting uploaded GitHub secret/profile must be usable by scheduled workflows without interactive authentication.
- “Client code” compatibility includes scheduled workflows and local tools that push to OCI (logs and metrics).

## Acceptance signal

- A clean repo can be configured using the dedicated ingestion user, and a workflow run can successfully ingest **one log entry** and **one metric datapoint** using that configuration.


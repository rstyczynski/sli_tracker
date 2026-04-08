#!/usr/bin/env bash
# Source-only helper for integration tests.
# Ensures OCI resources used by SLI tests exist, using the oci_scaffold submodule.

set -euo pipefail

ensure_sli_log_resources() {
  local repo_root="${1:?repo_root}"
  local oci_profile="${2:?oci_profile}"
  local name_prefix="${3:?name_prefix}"
  local sli_oci_log_uri="${4:?sli_oci_log_uri}"

  # Exports (for callers):
  #   COMPARTMENT_OCID, LOG_GROUP_OCID, SLI_LOG_OCID, TENANCY

  export OCI_CLI_PROFILE="$oci_profile"
  export NAME_PREFIX="$name_prefix"

  # shellcheck source=../oci_scaffold/do/oci_scaffold.sh
  source "${repo_root}/oci_scaffold/do/oci_scaffold.sh"

  local log_name log_group_name compartment_path rest
  log_name="${sli_oci_log_uri##*/}"
  rest="${sli_oci_log_uri%/*}"
  log_group_name="${rest##*/}"
  compartment_path="${rest%/*}"
  compartment_path="${compartment_path:-/}"

  [[ -z "$log_group_name" || -z "$log_name" ]] && {
    echo "ERROR: SLI_OCI_LOG_URI must be /[compartment/]log_group/log, got: $sli_oci_log_uri" >&2
    return 1
  }

  _state_set '.inputs.compartment_path' "$compartment_path"
  _state_set '.inputs.name_prefix'      "$NAME_PREFIX"
  _state_set '.inputs.log_group_name'   "$log_group_name"
  _state_set '.inputs.log_name'         "$log_name"

  bash "${repo_root}/oci_scaffold/resource/ensure-compartment.sh"
  COMPARTMENT_OCID="$(_state_get '.compartment.ocid')"
  [[ -z "${COMPARTMENT_OCID:-}" || "${COMPARTMENT_OCID:-}" == "null" ]] && {
    echo "ERROR: ensure-compartment.sh did not resolve compartment '$compartment_path'" >&2
    return 1
  }
  export COMPARTMENT_OCID
  _state_set '.inputs.oci_compartment' "$COMPARTMENT_OCID"

  bash "${repo_root}/oci_scaffold/resource/ensure-log_group.sh"
  bash "${repo_root}/oci_scaffold/resource/ensure-log.sh"

  LOG_GROUP_OCID="$(_state_get '.log_group.ocid')"
  SLI_LOG_OCID="$(_state_get '.log.ocid')"
  TENANCY="$(_oci_tenancy_ocid)"

  [[ -z "${LOG_GROUP_OCID:-}" || "${LOG_GROUP_OCID:-}" == "null" ]] && {
    echo "ERROR: ensure-log_group.sh did not resolve '$log_group_name'" >&2
    return 1
  }
  [[ -z "${SLI_LOG_OCID:-}" || "${SLI_LOG_OCID:-}" == "null" ]] && {
    echo "ERROR: ensure-log.sh did not resolve '$log_name'" >&2
    return 1
  }
  export LOG_GROUP_OCID SLI_LOG_OCID TENANCY COMPARTMENT_OCID
}

ensure_set_github_sli_vars() {
  local repo="${1:?owner/repo}"
  local log_ocid="${2:?log_ocid}"
  local log_group_ocid="${3:?log_group_ocid}"
  gh variable set SLI_OCI_LOG_ID       --body "$log_ocid"       -R "$repo"
  gh variable set SLI_OCI_LOG_GROUP_ID --body "$log_group_ocid" -R "$repo"
}

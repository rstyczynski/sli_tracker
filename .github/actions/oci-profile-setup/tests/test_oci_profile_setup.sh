#!/usr/bin/env bash
# Wrapper — tests migrated to tests/unit/test_oci_profile_setup.sh (Sprint 7, SLI-10)
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../../tests/unit/test_oci_profile_setup.sh" "$@"

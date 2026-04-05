#!/usr/bin/env bash
# Wrapper — tests migrated to tests/unit/test_install_oci_cli.sh (Sprint 7, SLI-10)
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../../tests/unit/test_install_oci_cli.sh" "$@"

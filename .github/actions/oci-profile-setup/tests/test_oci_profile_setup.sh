#!/usr/bin/env bash
# Local tests: oci_profile_setup.sh round-trip, error cases; setup script smoke tests.
#
# Usage: bash test_oci_profile_setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SCRIPT="${ACTION_DIR}/setup_oci_github_access.sh"
PROFILE_SETUP="${ACTION_DIR}/oci_profile_setup.sh"

TESTS_RUN=0
TESTS_PASSED=0

pass() { echo "  PASS: $*"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $*" >&2; exit 1; }

b64_encode_nowrap() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w 0
  else
    base64 | tr -d '\n'
  fi
}

echo ""
echo "=== Test: pack/unpack round-trip (synthetic ~/.oci) ==="
TESTS_RUN=$((TESTS_RUN + 1))
SRC_HOME="$(mktemp -d)"
DST_HOME="$(mktemp -d)"
mkdir -p "$SRC_HOME/.oci/sessions/DEFAULT"
printf 'key_file=${{HOME}}/.oci/sessions/DEFAULT/oci_api_key.pem\n' >"$SRC_HOME/.oci/config"
printf 'dummy-key\n' >"$SRC_HOME/.oci/sessions/DEFAULT/oci_api_key.pem"
printf 'dummy-token\n' >"$SRC_HOME/.oci/sessions/DEFAULT/session_token"
PAYLOAD="$( (cd "$SRC_HOME" && tar -czf - .oci/config .oci/sessions/DEFAULT) | b64_encode_nowrap )"
export OCI_CONFIG_PAYLOAD="$PAYLOAD"
HOME="$DST_HOME" OCI_PROFILE_VERIFY=DEFAULT bash "$PROFILE_SETUP"
if grep -q '${{HOME}}' "$DST_HOME/.oci/config"; then
  fail "HOME placeholder was not replaced in extracted config"
fi
if ! cmp -s "$SRC_HOME/.oci/sessions/DEFAULT/session_token" "$DST_HOME/.oci/sessions/DEFAULT/session_token"; then
  fail "session file mismatch after round-trip"
fi
if ! grep -q "$DST_HOME/.oci/sessions/DEFAULT/oci_api_key.pem" "$DST_HOME/.oci/config"; then
  fail "HOME placeholder not replaced in extracted config"
fi
rm -rf "$SRC_HOME" "$DST_HOME"
pass "round-trip restored config and session files"

echo ""
echo "=== Test: empty OCI_CONFIG_PAYLOAD ==="
TESTS_RUN=$((TESTS_RUN + 1))
EMPTY_HOME="$(mktemp -d)"
if OCI_CONFIG_PAYLOAD="" HOME="$EMPTY_HOME" bash "$PROFILE_SETUP" 2>/dev/null; then
  rm -rf "$EMPTY_HOME"
  fail "expected non-zero exit for empty payload"
fi
rm -rf "$EMPTY_HOME"
pass "empty payload rejected"

echo ""
echo "=== Test: malformed payload ==="
TESTS_RUN=$((TESTS_RUN + 1))
BAD_HOME="$(mktemp -d)"
if OCI_CONFIG_PAYLOAD="!!!not-valid-base64!!!" HOME="$BAD_HOME" bash "$PROFILE_SETUP" 2>/dev/null; then
  rm -rf "$BAD_HOME"
  fail "expected non-zero exit for malformed payload"
fi
rm -rf "$BAD_HOME"
pass "malformed payload rejected"

echo ""
echo "=== Test: setup script rejects missing ~/.oci/config ==="
TESTS_RUN=$((TESTS_RUN + 1))
EMPTY_HOME="$(mktemp -d)"
if HOME="$EMPTY_HOME" bash "$SETUP_SCRIPT" --dry-run 2>/dev/null; then
  rm -rf "$EMPTY_HOME"
  fail "expected non-zero exit when ~/.oci/config missing"
fi
rm -rf "$EMPTY_HOME"
pass "missing config rejected"

echo ""
echo "=== Test: setup script --help ==="
TESTS_RUN=$((TESTS_RUN + 1))
if ! bash "$SETUP_SCRIPT" --help | grep -q dry-run; then
  fail "--help output missing expected text"
fi
pass "help text present"

echo ""
echo "=== Test: bash -n on shell scripts ==="
TESTS_RUN=$((TESTS_RUN + 1))
bash -n "$SETUP_SCRIPT"
bash -n "$PROFILE_SETUP"
pass "bash -n OK"

echo ""
echo "Results: $TESTS_PASSED / $TESTS_RUN tests passed."

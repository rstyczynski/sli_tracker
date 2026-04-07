#!/usr/bin/env bash
# Validates install_oci_cli.sh inside a fresh Ubuntu container via podman.
# Migrated from .github/actions/install-oci-cli/tests/test_install_oci_cli.sh (Sprint 7, SLI-10)
#
# Usage: bash tests/unit/test_install_oci_cli.sh [--oci-cli-version VERSION]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SCRIPT="$REPO_ROOT/.github/actions/install-oci-cli/install_oci_cli.sh"

OCI_CLI_VERSION="${OCI_CLI_VERSION:-}"
UBUNTU_IMAGE="ubuntu:22.04"

TESTS_RUN=0
TESTS_PASSED=0

pass() { echo "  PASS: $*"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $*" >&2; exit 1; }

ensure_container_absent() {
    local name="$1"
    podman rm -f "$name" >/dev/null 2>&1 || true
}

pull_image() {
    local image="$1"
    if podman image exists "$image" 2>/dev/null; then
        echo "  Image $image already cached."
    else
        echo "  Pulling image $image..."
        podman pull "$image"
    fi
    echo "  Starting container..."
}

if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: podman not found. Install podman to run these tests." >&2
    exit 1
fi

if ! podman info >/dev/null 2>&1; then
    echo "ERROR: Podman is installed but not reachable." >&2
    echo "  Check: podman system connection list" >&2
    echo "  Fix:   podman machine start" >&2
    exit 1
fi

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    echo "ERROR: install script not found at $INSTALL_SCRIPT" >&2
    exit 1
fi

echo ""
echo "=== Test: OCI CLI install on fresh $UBUNTU_IMAGE ==="
TESTS_RUN=$((TESTS_RUN + 1))

version_arg=""
[[ -n "$OCI_CLI_VERSION" ]] && version_arg="--oci-cli-version $OCI_CLI_VERSION"

pull_image "$UBUNTU_IMAGE"
ensure_container_absent test-install-oci-cli-ubuntu
if ! podman run --rm --name test-install-oci-cli-ubuntu \
    -v "$INSTALL_SCRIPT:/opt/install_oci_cli.sh:ro" \
    "$UBUNTU_IMAGE" \
    bash -c "
        set -euo pipefail
        bash /opt/install_oci_cli.sh $version_arg
        export PATH=\"\$HOME/.venv/oci-cli/bin:\$HOME/.local/bin:\$PATH\"
        oci --version
    "; then
    fail "OCI CLI install failed inside $UBUNTU_IMAGE"
fi
pass "OCI CLI installed and verified inside $UBUNTU_IMAGE"

echo ""
echo "=== Test: VENV_PATH='~/.venv/oci-cli' expansion ==="
TESTS_RUN=$((TESTS_RUN + 1))

pull_image "$UBUNTU_IMAGE"
ensure_container_absent test-install-oci-cli-ubuntu-venv-tilde
if ! podman run --rm --name test-install-oci-cli-ubuntu-venv-tilde \
    -v "$INSTALL_SCRIPT:/opt/install_oci_cli.sh:ro" \
    "$UBUNTU_IMAGE" \
    bash -c "
        set -euo pipefail
        export VENV_PATH=\"~/.venv/oci-cli\"
        bash /opt/install_oci_cli.sh $version_arg
        export PATH=\"\$HOME/.venv/oci-cli/bin:\$HOME/.local/bin:\$PATH\"
        oci --version
    "; then
    fail "OCI CLI install failed inside $UBUNTU_IMAGE when VENV_PATH='~/.venv/oci-cli'"
fi
pass "OCI CLI installed and callable with VENV_PATH='~/.venv/oci-cli'"

echo ""
echo "=== Test: rejected on Alpine (non-GNU toolchain) ==="
TESTS_RUN=$((TESTS_RUN + 1))

pull_image "alpine:latest"
ensure_container_absent test-install-oci-cli-alpine
alpine_output=$(podman run --rm --name test-install-oci-cli-alpine \
    -v "$INSTALL_SCRIPT:/opt/install_oci_cli.sh:ro" \
    alpine:latest \
    sh -c "apk add --no-cache bash >/dev/null 2>&1 && bash /opt/install_oci_cli.sh 2>&1; true" 2>&1 || true)

if ! echo "$alpine_output" | grep -q "::error::"; then
    echo "  Script output was:" >&2
    echo "    ${alpine_output//$'\n'/$'\n    '}" >&2
    fail "Alpine was not rejected with an ERROR message"
fi
pass "Alpine correctly rejected with ERROR message"

echo ""
echo "=== Test: rejected on Fedora (no apt-get) ==="
TESTS_RUN=$((TESTS_RUN + 1))

pull_image "fedora:latest"
ensure_container_absent test-install-oci-cli-fedora
fedora_output=$(podman run --rm --name test-install-oci-cli-fedora \
    -v "$INSTALL_SCRIPT:/opt/install_oci_cli.sh:ro" \
    fedora:latest \
    bash -c "bash /opt/install_oci_cli.sh 2>&1; true" 2>&1 || true)

if ! echo "$fedora_output" | grep -q "::error::"; then
    echo "  Script output was:" >&2
    echo "    ${fedora_output//$'\n'/$'\n    '}" >&2
    fail "Fedora was not rejected with an ERROR message"
fi
pass "Fedora correctly rejected with ERROR message"

if [[ -n "$OCI_CLI_VERSION" ]]; then
    echo ""
    echo "=== Test: pinned version $OCI_CLI_VERSION ==="
    TESTS_RUN=$((TESTS_RUN + 1))

    pull_image "$UBUNTU_IMAGE"
    ensure_container_absent test-install-oci-cli-pinned
    if ! podman run --rm --name test-install-oci-cli-pinned \
        -v "$INSTALL_SCRIPT:/opt/install_oci_cli.sh:ro" \
        "$UBUNTU_IMAGE" \
        bash -c "
            set -euo pipefail
            bash /opt/install_oci_cli.sh --oci-cli-version $OCI_CLI_VERSION
            export PATH=\"\$HOME/.venv/oci-cli/bin:\$HOME/.local/bin:\$PATH\"
            oci --version | grep -q '$OCI_CLI_VERSION'
        "; then
        fail "Pinned version $OCI_CLI_VERSION not installed correctly"
    fi
    pass "Pinned version $OCI_CLI_VERSION installed correctly"
fi

echo ""
echo "Tests passed: $TESTS_PASSED / $TESTS_RUN"
[[ "$TESTS_PASSED" -eq "$TESTS_RUN" ]] || { echo "ERROR: Some tests failed." >&2; exit 1; }
echo "All tests passed."

#!/usr/bin/env bash
# Installs OCI CLI with all prerequisites on a Linux (Ubuntu/Debian) host.
# Non-interactive — designed for GitHub Actions runners and CI environments.
#
# Usage: bash install_oci_cli.sh [-v] [--oci-cli-version VERSION] [--venv-path PATH]
# Env:   OCI_CLI_VERSION  — alternative to --oci-cli-version flag
#        VERBOSE          — set to 1 to enable verbose output
#        VENV_PATH        — venv directory; empty string disables venv (default: ~/.venv/oci-cli)

set -euo pipefail

OCI_CLI_VERSION="${OCI_CLI_VERSION:-}"
VERBOSE="${VERBOSE:-0}"
VENV_PATH="${VENV_PATH:-$HOME/.venv/oci-cli}"

# Use sudo only when not already root
SUDO=""
if [[ "$EUID" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "::error::Not running as root and sudo is not available."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# OS validation
# ---------------------------------------------------------------------------
detect_os() {
    echo "::group::Detect OS"

    local os
    os="$(uname -s)"
    if [[ "$os" != "Linux" ]]; then
        echo "::error::This script requires Linux. Detected: $os"
        echo "::endgroup::"
        exit 1
    fi

    # Require GNU coreutils — reject Alpine/musl and other non-GNU toolchains
    if ! ls --version 2>&1 | grep -q "GNU"; then
        echo "::error::GNU coreutils required. This system appears to use a non-GNU toolchain (e.g. Alpine/musl)."
        echo "::endgroup::"
        exit 1
    fi

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "OS: ${NAME:-unknown} ${VERSION_ID:-}"
    else
        echo "::warning::'/etc/os-release' not found — assuming Debian-compatible."
    fi

    echo "::endgroup::"
}

# ---------------------------------------------------------------------------
# Prerequisites: Python 3, pip, venv, curl, jq
# ---------------------------------------------------------------------------
install_prerequisites() {
    echo "::group::Install prerequisites"

    if ! command -v apt-get >/dev/null 2>&1; then
        echo "::error::apt-get not found. Only Debian/Ubuntu-based systems are supported."
        echo "::endgroup::"
        exit 1
    fi

    local packages="python3 python3-pip python3-venv curl jq"

    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "Updating package lists..."
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get update
        echo "Installing packages: $packages..."
        # shellcheck disable=SC2086
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y $packages
    else
        echo "Updating package lists..."
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -qq
        echo "Installing packages: $packages..."
        # shellcheck disable=SC2086
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq $packages
    fi

    echo "::endgroup::"
}

# ---------------------------------------------------------------------------
# Python version gate (>= 3.6 required by oci-cli)
# ---------------------------------------------------------------------------
check_python() {
    local ver major minor
    ver="$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+'| head -1)"
    major="$(echo "$ver" | cut -d. -f1)"
    minor="$(echo "$ver" | cut -d. -f2)"

    if [[ "$major" -lt 3 || ( "$major" -eq 3 && "$minor" -lt 6 ) ]]; then
        echo "::error::Python 3.6+ required. Found: $ver"
        exit 1
    fi

    echo "Python: $(python3 --version)"
}

# ---------------------------------------------------------------------------
# OCI CLI installation via pip (venv or user)
# ---------------------------------------------------------------------------
install_oci_cli() {
    local pkg="oci-cli"
    [[ -n "$OCI_CLI_VERSION" ]] && pkg="oci-cli==${OCI_CLI_VERSION}"

    echo "::group::Install $pkg"

    if [[ -n "$VENV_PATH" ]]; then
        echo "Creating virtual environment at $VENV_PATH..."
        python3 -m venv "$VENV_PATH"
        if [[ "$VERBOSE" -eq 1 ]]; then
            echo "Upgrading pip..."
            "$VENV_PATH/bin/pip" install --upgrade pip
            echo "Installing $pkg (this may take a minute)..."
            "$VENV_PATH/bin/pip" install "$pkg"
        else
            echo "Upgrading pip..."
            "$VENV_PATH/bin/pip" install --upgrade pip --quiet
            echo "Installing $pkg (this may take a minute)..."
            "$VENV_PATH/bin/pip" install --quiet "$pkg"
        fi
    else
        if [[ "$VERBOSE" -eq 1 ]]; then
            echo "Upgrading pip..."
            pip3 install --upgrade pip
            echo "Installing $pkg (this may take a minute)..."
            pip3 install --user "$pkg"
        else
            echo "Upgrading pip..."
            pip3 install --upgrade pip --quiet
            echo "Installing $pkg (this may take a minute)..."
            pip3 install --user --quiet "$pkg"
        fi
    fi

    echo "::endgroup::"
}

# ---------------------------------------------------------------------------
# Verify oci binary is reachable
# ---------------------------------------------------------------------------
verify_installation() {
    local bin_dir
    if [[ -n "$VENV_PATH" ]]; then
        bin_dir="$VENV_PATH/bin"
    else
        bin_dir="$HOME/.local/bin"
    fi
    export PATH="$bin_dir:$PATH"

    if ! command -v oci >/dev/null 2>&1; then
        echo "::error::oci command not found after installation. bin_dir=$bin_dir"
        exit 1
    fi

    # Persist path for subsequent GitHub Actions steps
    if [[ -n "${GITHUB_PATH:-}" ]]; then
        echo "$bin_dir" >> "$GITHUB_PATH"
    fi

    echo "::notice::OCI CLI $(oci --version) installed — $bin_dir added to PATH."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            --oci-cli-version)
                OCI_CLI_VERSION="$2"
                shift 2
                ;;
            --venv-path)
                VENV_PATH="$2"
                shift 2
                ;;
            --no-venv)
                VENV_PATH=""
                shift
                ;;
            *)
                echo "::error::Unknown argument: $1"
                exit 1
                ;;
        esac
    done

    detect_os
    install_prerequisites
    check_python
    install_oci_cli
    verify_installation
}

main "$@"

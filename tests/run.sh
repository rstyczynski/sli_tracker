#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage: run.sh [OPTIONS]

Run test suites from the centralized tests/ tree.

Suite options (one or more required):
  --smoke          Run smoke tests (tests/smoke/)
  --unit           Run unit tests (tests/unit/)
  --integration    Run integration tests (tests/integration/)
  --all            Run all test suites (smoke + unit + integration)

Filter options:
  --new-only SPEC  Run only test functions listed in the given test spec file.
                   Used for new-code gates (Test: parameter). Without this flag,
                   all tests in the suite run (used for regression gates).

Other:
  --help           Show this help message

Exit code is nonzero if any test fails.

Examples:
  # Regression: run all unit tests (old + new)
  tests/run.sh --unit

  # New-code gate: run only tests listed in sprint's test spec
  tests/run.sh --unit --new-only progress/sprint_7/sprint_7_test_spec.md

  # Full regression
  tests/run.sh --all
EOF
}

run_suite() {
    local suite_name="$1"
    local suite_dir="$SCRIPT_DIR/$suite_name"
    local suite_passed=0
    local suite_failed=0
    local suite_total=0

    if [[ ! -d "$suite_dir" ]]; then
        printf '[%s] directory not found: %s -- skipping\n' "$suite_name" "$suite_dir"
        return 0
    fi

    local scripts
    scripts=$(find "$suite_dir" -maxdepth 1 -name 'test_*.sh' -type f | sort)

    if [[ -z "$scripts" ]]; then
        printf '[%s] no test scripts found -- skipping\n' "$suite_name"
        return 0
    fi

    printf '=== %s tests ===\n' "$suite_name"

    while IFS= read -r script; do
        local script_name
        script_name="$(basename "$script")"

        if [[ -n "$NEW_ONLY_SPEC" ]]; then
            if [[ -z "${MANIFEST_SCRIPTS["${suite_name}:${script_name}"]:-}" ]]; then
                printf '[skip] %s/%s (not in manifest)\n' "$suite_name" "$script_name"
                continue
            fi
        fi

        printf '[run] %s/%s\n' "$suite_name" "$script_name"

        local exit_code=0
        bash "$script" || exit_code=$?

        if [[ "$exit_code" -eq 0 ]]; then
            printf '[PASS] %s/%s\n' "$suite_name" "$script_name"
            suite_passed=$((suite_passed + 1))
        else
            printf '[FAIL] %s/%s (exit code %d)\n' "$suite_name" "$script_name" "$exit_code"
            suite_failed=$((suite_failed + 1))
        fi
        suite_total=$((suite_total + 1))
    done <<< "$scripts"

    printf '=== %s summary: %d scripts, %d passed, %d failed ===\n\n' \
        "$suite_name" "$suite_total" "$suite_passed" "$suite_failed"

    TOTAL_SCRIPTS=$((TOTAL_SCRIPTS + suite_total))
    TOTAL_PASSED=$((TOTAL_PASSED + suite_passed))
    TOTAL_FAILED=$((TOTAL_FAILED + suite_failed))

    return "$suite_failed"
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

RUN_SMOKE=false
RUN_UNIT=false
RUN_INTEGRATION=false
NEW_ONLY_SPEC=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --smoke)       RUN_SMOKE=true ;;
        --unit)        RUN_UNIT=true ;;
        --integration) RUN_INTEGRATION=true ;;
        --all)
            RUN_SMOKE=true
            RUN_UNIT=true
            RUN_INTEGRATION=true
            ;;
        --new-only)
            shift
            NEW_ONLY_SPEC="${1:-}"
            if [[ -z "$NEW_ONLY_SPEC" ]]; then
                printf 'Error: --new-only requires a test spec file path\n' >&2
                exit 1
            fi
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

declare -A MANIFEST_SCRIPTS
if [[ -n "$NEW_ONLY_SPEC" ]]; then
    if [[ ! -f "$NEW_ONLY_SPEC" ]]; then
        printf '[error] manifest file not found: %s\n' "$NEW_ONLY_SPEC" >&2
        exit 1
    fi
    printf '[info] --new-only mode: filtering to tests listed in %s\n' "$NEW_ONLY_SPEC"
    printf '[info] current implementation filters at script level, not function level\n'
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(echo "$line" | xargs)"
        [[ -z "$line" ]] && continue
        suite="${line%%:*}"
        rest="${line#*:}"
        script_name="${rest%%:*}"
        MANIFEST_SCRIPTS["${suite}:${script_name}"]=1
    done < "$NEW_ONLY_SPEC"
fi

TOTAL_SCRIPTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
ANY_FAILURE=0

if $RUN_SMOKE; then
    run_suite "smoke" || ANY_FAILURE=1
fi

if $RUN_UNIT; then
    run_suite "unit" || ANY_FAILURE=1
fi

if $RUN_INTEGRATION; then
    run_suite "integration" || ANY_FAILURE=1
fi

printf '========================================\n'
printf 'TOTAL: %d scripts, %d passed, %d failed\n' \
    "$TOTAL_SCRIPTS" "$TOTAL_PASSED" "$TOTAL_FAILED"
printf '========================================\n'

if [[ "$ANY_FAILURE" -ne 0 ]]; then
    printf 'RESULT: FAIL\n'
    exit 1
else
    printf 'RESULT: PASS\n'
    exit 0
fi

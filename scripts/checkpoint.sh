#!/usr/bin/env bash
# checkpoint.sh — Whole-system ship/no-ship gate.
#
# This is the top-level checkpoint for feature work. It composes the existing
# canonical test, guard, and smoke batteries so regressions fail before later
# development can drift.
#
# Usage:
#   scripts/checkpoint.sh
#   scripts/checkpoint.sh --arch arm64 CC=clang

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BINARY="$ROOT/build/c/codebase-memory-mcp"
FAILURES=0

run_step() {
    local name="$1"
    shift

    echo ""
    echo "=== checkpoint: $name ==="
    if "$@"; then
        echo "=== checkpoint: PASS: $name ==="
    else
        local rc=$?
        echo "=== checkpoint: FAIL: $name (rc=$rc) ===" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

require_prod_binary() {
    if [ -x "$BINARY" ] || [ -f "$BINARY" ]; then
        return 0
    fi
    echo "production binary missing after build: $BINARY" >&2
    return 1
}

echo "=== checkpoint: whole-system gate ==="
echo "root: $ROOT"
echo "binary: $BINARY"

# Enforce the no-skips policy before running the expensive batteries. This keeps
# missing coverage visible instead of normalizing skipped regressions.
run_step "no-skips policy" bash "$ROOT/scripts/check-no-test-skips.sh"

# Canonical clean build + full C test suite + production binary watchdog/security
# regressions. This script is the repository's existing single source of truth
# for unit/integration verification.
run_step "canonical tests" bash "$ROOT/scripts/test.sh" "$@"

run_step "production binary present" require_prod_binary

# Guard query-only behavior before smoke suites: unknown/unindexed projects must
# return guarded errors without creating ghost .db files.
run_step "unknown-project guard and no-ghost-db invariant" bash "$ROOT/tests/smoke_guard.sh"

# Production binary invariant battery: MCP lifecycle, tool list, every tool,
# malformed input, crash/hang supervisor behavior, install dry-run, and clean EOF.
run_step "production binary invariants" bash "$ROOT/scripts/smoke-invariants.sh" "$BINARY"

# End-to-end smoke battery: indexing, search/query/snippet/trace paths, CLI,
# install/update/uninstall dry-runs, and agent config/hook behavior.
run_step "end-to-end smoke" bash "$ROOT/scripts/smoke-test.sh" "$BINARY"

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "=== checkpoint: FAILED ($FAILURES layer(s) failed) ===" >&2
    exit 1
fi

echo "=== checkpoint: PASSED ==="
exit 0

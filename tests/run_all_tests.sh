#!/usr/bin/env bash
# run_all_tests.sh — Unified local test runner for omarchy-snapshots
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
RESET="\033[0m"

echo -e "\n${BLUE}============================================================${RESET}"
echo -e "${BLUE} Running Comprehensive Test Suite: Omarchy Snapshots HUD ${RESET}"
echo -e "${BLUE}============================================================${RESET}\n"

FAILURES=0

run_suite() {
  local name="$1"
  local cmd="$2"

  echo -e "▶ Running: ${name}..."
  if eval "$cmd"; then
    echo -e "${GREEN}✓ ${name} passed!${RESET}\n"
  else
    echo -e "${RED}✗ ${name} FAILED!${RESET}\n"
    FAILURES=$((FAILURES + 1))
  fi
}

# 1. Manifest Validation
run_suite "Official Omarchy Plugin Validator" "omarchy plugin validate \"$PROJECT_ROOT\""

# 2. Python Unit Engine Tests
run_suite "Backend Engine Unit Tests" "python3 -m unittest \"$PROJECT_ROOT/tests/test_unit_engine.py\""

# 3. Backend Core Schema & Subprocess Tests
run_suite "Backend Core JSON Schema Tests" "python3 -m unittest \"$PROJECT_ROOT/tests/test_core.py\""

# 4. CLI Subprocess & Command Tests
run_suite "CLI & Subprocess Tests" "python3 -m unittest \"$PROJECT_ROOT/tests/test_cli_commands.py\""

# 5. QML Syntax, Manifest & Asset Tests
run_suite "QML, Manifest & Static Asset Tests" "python3 -m unittest \"$PROJECT_ROOT/tests/test_qml_and_manifest.py\""

# 6. Live IPC and Desktop Lifecycle Tests
run_suite "Live Desktop & IPC Integration Tests" "python3 -m unittest \"$PROJECT_ROOT/tests/test_ipc_integration.py\""

# 7. Mission-Critical Safety, Rollback & Precision Tests
run_suite "Mission-Critical Safety, Rollback & Precision Tests" "python3 -m unittest \"$PROJECT_ROOT/tests/test_safety_and_precision.py\""

echo -e "${BLUE}============================================================${RESET}"
if (( FAILURES == 0 )); then
  echo -e "${GREEN}★ ALL TEST SUITES PASSED SUCCESSFULLY! (0 failures)${RESET}"
  echo -e "${BLUE}============================================================${RESET}\n"
  exit 0
else
  echo -e "${RED}✘ TEST SUITE FAILED WITH ${FAILURES} FAILURE(S)!${RESET}"
  echo -e "${BLUE}============================================================${RESET}\n"
  exit 1
fi

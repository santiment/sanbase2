#!/bin/bash
# Fail fast on errors, undefined vars, and pipeline failures
set -euo pipefail

PARTITIONS=${1:-4}
FAILURES_DIR="_build/test/failures"

# Validate PARTITIONS is a positive integer
if ! [[ "$PARTITIONS" =~ ^[0-9]+$ ]] || [ "$PARTITIONS" -lt 1 ]; then
  echo "Usage: $0 [PARTITIONS]" >&2
  echo "PARTITIONS must be a positive integer (default: 4)" >&2
  exit 1
fi

# SECONDS is a bash built-in that auto-increments; assigning 0 resets the timer
SECONDS=0

echo "==> Running tests with $PARTITIONS partitions"

rm -rf "$FAILURES_DIR"

echo "==> Running $PARTITIONS test partitions in parallel"

# Run each partition in parallel; pipefail ensures failed mix test propagates
pids=()
for i in $(seq 1 "$PARTITIONS"); do
  MIX_TEST_PARTITION=$i mix test --partitions "$PARTITIONS" \
    --formatter Sanbase.FailedTestFormatter \
    --formatter ExUnit.CLIFormatter \
    --trace \
    2>&1 | sed "s/^/[partition $i] /" &
  pids+=($!)
done

# Capture any partition failure; || prevents set -e from exiting early
exit_code=0
for pid in "${pids[@]}"; do
  wait "$pid" || exit_code=1
done

echo ""
echo "========================================"
echo "  Combined results from all partitions"
echo "========================================"

if ls "$FAILURES_DIR"/partition_*.txt 1>/dev/null 2>&1; then
  error_tests=()
  exit_tests=()
  invalid_tests=()

  # || [[ -n "${kind:-}" ]] handles files without trailing newline (read returns false at EOF)
  for f in "$FAILURES_DIR"/partition_*.txt; do
    while IFS=$'\t' read -r kind test_id || [[ -n "${kind:-}" ]]; do
      case "$kind" in
      error) error_tests+=("$test_id") ;;
      exit) exit_tests+=("$test_id") ;;
      invalid) invalid_tests+=("$test_id") ;;
      esac
    done <"$f"
  done

  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  NC='\033[0m'

  total=$((${#error_tests[@]} + ${#exit_tests[@]} + ${#invalid_tests[@]}))
  echo -e "${RED}$total failing test(s) across all partitions:${NC}"

  if [ ${#error_tests[@]} -gt 0 ]; then
    echo -e "\n${RED}Error tests (${#error_tests[@]}):${NC}"
    for t in "${error_tests[@]}"; do echo "  $t"; done
  fi

  if [ ${#exit_tests[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Exit tests (${#exit_tests[@]}):${NC}"
    for t in "${exit_tests[@]}"; do echo "  $t"; done
  fi

  if [ ${#invalid_tests[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Invalid tests (${#invalid_tests[@]}):${NC}"
    for t in "${invalid_tests[@]}"; do echo "  $t"; done
  fi

  echo ""
  echo "Re-run all failing tests with:"
  all_tests=("${error_tests[@]}" "${exit_tests[@]}" "${invalid_tests[@]}")
  # printf %q safely escapes test names with spaces or special chars for copy-paste
  printf '  mix test'
  printf ' %q' "${all_tests[@]}"
  echo
else
  echo -e "\033[0;32mAll $PARTITIONS partitions passed!\033[0m"
fi

elapsed=$SECONDS
mins=$((elapsed / 60))
secs=$((elapsed % 60))
echo ""
echo "Total time: ${mins}m ${secs}s"

exit $exit_code

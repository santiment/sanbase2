#!/bin/bash
set -euo pipefail

PARTITIONS=${1:-4}
FAILURES_DIR="_build/test/failures"

echo "==> Running tests with $PARTITIONS partitions"

rm -rf "$FAILURES_DIR"

for i in $(seq 1 "$PARTITIONS"); do
  echo "==> Setting up database for partition $i"
  MIX_TEST_PARTITION=$i mix ecto.create -r Sanbase.Repo --quiet 2>/dev/null || true
  MIX_TEST_PARTITION=$i mix ecto.load -r Sanbase.Repo --skip-if-loaded
  MIX_TEST_PARTITION=$i mix run test/test_seeds.exs
done

echo "==> Running $PARTITIONS test partitions in parallel"

pids=()
for i in $(seq 1 "$PARTITIONS"); do
  MIX_TEST_PARTITION=$i mix test --partitions "$PARTITIONS" \
    --formatter Sanbase.FailedTestFormatter \
    --formatter ExUnit.CLIFormatter \
    --slowest 20 \
    2>&1 | sed "s/^/[partition $i] /" &
  pids+=($!)
done

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

  for f in "$FAILURES_DIR"/partition_*.txt; do
    while IFS=$'\t' read -r kind test_id; do
      case "$kind" in
        error)   error_tests+=("$test_id") ;;
        exit)    exit_tests+=("$test_id") ;;
        invalid) invalid_tests+=("$test_id") ;;
      esac
    done < "$f"
  done

  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  NC='\033[0m'

  total=$(( ${#error_tests[@]} + ${#exit_tests[@]} + ${#invalid_tests[@]} ))
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
  echo "  mix test ${all_tests[*]}"
else
  echo -e "\033[0;32mAll $PARTITIONS partitions passed!\033[0m"
fi

exit $exit_code

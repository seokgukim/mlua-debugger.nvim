#!/bin/bash
# Run all tests for mlua-debugger.nvim

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Running mlua-debugger.nvim tests..."
echo "=================================="

FAILED=0

run_test() {
    local test_file="$1"
    echo ""
    echo "Running $test_file..."
    echo "----------------------------------"
    if nvim --headless -u tests/minimal_init.lua -c "luafile $test_file" -c "qa!"; then
        echo "✓ $test_file completed"
    else
        echo "✗ $test_file failed"
        FAILED=1
    fi
}

run_test "tests/test_config.lua"
run_test "tests/test_breakpoints.lua"
run_test "tests/test_protocol.lua"

echo ""
echo "=================================="
if [ $FAILED -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi

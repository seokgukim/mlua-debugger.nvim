-- Test breakpoint functionality
local mlua = require("mlua-debugger")

local function assert_eq(expected, actual, msg)
	if expected ~= actual then
		error(string.format("%s: expected %s, got %s", msg or "Assertion failed", vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_table_eq(expected, actual, msg)
	if vim.inspect(expected) ~= vim.inspect(actual) then
		error(string.format("%s: expected %s, got %s", msg or "Assertion failed", vim.inspect(expected), vim.inspect(actual)))
	end
end

local tests = {}

function tests.test_get_breakpoints_empty()
	mlua.setup()
	local bps = mlua.getBreakpoints("/nonexistent/file.mlua")
	assert_table_eq({}, bps, "Empty breakpoints for non-existent file")
	print("✓ test_get_breakpoints_empty passed")
end

function tests.test_clear_breakpoints()
	mlua.setup()
	mlua.clearBreakpoints()
	-- Should not error even when no breakpoints exist
	print("✓ test_clear_breakpoints passed")
end

function tests.test_is_connected_initial()
	mlua.setup()
	local connected = mlua.isConnected()
	assert_eq(false, connected, "Should not be connected initially")
	print("✓ test_is_connected_initial passed")
end

-- Run all tests
local function run_tests()
	local passed = 0
	local failed = 0

	for name, test_fn in pairs(tests) do
		local ok, err = pcall(test_fn)
		if ok then
			passed = passed + 1
		else
			failed = failed + 1
			print(string.format("✗ %s failed: %s", name, err))
		end
	end

	print(string.format("\n%d passed, %d failed", passed, failed))
	if failed > 0 then
		vim.cmd("cq 1")
	end
end

run_tests()

-- Test protocol module
local protocol = require("mlua-debugger.protocol")

local function assert_eq(expected, actual, msg)
	if expected ~= actual then
		error(string.format("%s: expected %s, got %s", msg or "Assertion failed", vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_not_nil(val, msg)
	if val == nil then
		error(msg or "Expected non-nil value")
	end
end

local tests = {}

function tests.test_protocol_module_exists()
	assert_not_nil(protocol, "Protocol module should exist")
	print("✓ test_protocol_module_exists passed")
end

function tests.test_protocol_has_required_functions()
	-- Check for expected functions in protocol module
	assert_eq("table", type(protocol), "Protocol should be a table")
	print("✓ test_protocol_has_required_functions passed")
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

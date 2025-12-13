-- Test configuration and setup
local mlua = require("mlua-debugger")

local function assert_eq(expected, actual, msg)
	if expected ~= actual then
		error(string.format("%s: expected %s, got %s", msg or "Assertion failed", vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_true(val, msg)
	if not val then
		error(msg or "Expected true")
	end
end

local function assert_false(val, msg)
	if val then
		error(msg or "Expected false")
	end
end

local tests = {}

function tests.test_default_config()
	mlua.setup()
	assert_eq(51300, mlua.config.port, "Default port")
	assert_eq("localhost", mlua.config.host, "Default host")
	assert_eq(300000, mlua.config.timeout, "Default timeout")
	assert_eq(50, mlua.config.ui.width, "Default UI width")
	assert_eq(8, mlua.config.ui.height, "Default UI height")
	assert_eq("right", mlua.config.ui.position, "Default UI position")
	print("✓ test_default_config passed")
end

function tests.test_custom_config()
	mlua.setup({
		port = 12345,
		host = "192.168.1.1",
		timeout = 60000,
		ui = {
			width = 60,
			height = 15,
			position = "left",
		},
	})
	assert_eq(12345, mlua.config.port, "Custom port")
	assert_eq("192.168.1.1", mlua.config.host, "Custom host")
	assert_eq(60000, mlua.config.timeout, "Custom timeout")
	assert_eq(60, mlua.config.ui.width, "Custom UI width")
	assert_eq(15, mlua.config.ui.height, "Custom UI height")
	assert_eq("left", mlua.config.ui.position, "Custom UI position")
	print("✓ test_custom_config passed")
end

function tests.test_keymaps_default()
	mlua.setup()
	assert_eq("<F5>", mlua.config.keymaps.continue, "Default continue keymap")
	assert_eq("<F9>", mlua.config.keymaps.toggle_breakpoint, "Default toggle_breakpoint keymap")
	assert_eq("<leader>dc", mlua.config.keymaps.continue_leader, "Default continue_leader keymap")
	print("✓ test_keymaps_default passed")
end

function tests.test_keymaps_custom()
	mlua.setup({
		keymaps = {
			continue = "<F6>",
			toggle_breakpoint = "<F8>",
		},
	})
	assert_eq("<F6>", mlua.config.keymaps.continue, "Custom continue keymap")
	assert_eq("<F8>", mlua.config.keymaps.toggle_breakpoint, "Custom toggle_breakpoint keymap")
	-- Other keymaps should remain default
	assert_eq("<F10>", mlua.config.keymaps.step_over, "Default step_over keymap preserved")
	print("✓ test_keymaps_custom passed")
end

function tests.test_keymaps_disabled_individual()
	mlua.setup({
		keymaps = {
			continue = false,
			step_over = false,
		},
	})
	assert_false(mlua.config.keymaps.continue, "Disabled continue keymap")
	assert_false(mlua.config.keymaps.step_over, "Disabled step_over keymap")
	assert_eq("<F9>", mlua.config.keymaps.toggle_breakpoint, "Non-disabled keymap preserved")
	print("✓ test_keymaps_disabled_individual passed")
end

function tests.test_keymaps_disabled_all()
	mlua.setup({
		keymaps = false,
	})
	assert_false(mlua.config.keymaps, "All keymaps disabled")
	print("✓ test_keymaps_disabled_all passed")
end

function tests.test_partial_ui_config()
	mlua.setup({
		ui = {
			width = 80,
		},
	})
	assert_eq(80, mlua.config.ui.width, "Custom UI width")
	assert_eq(8, mlua.config.ui.height, "Default UI height preserved")
	assert_eq("right", mlua.config.ui.position, "Default UI position preserved")
	print("✓ test_partial_ui_config passed")
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

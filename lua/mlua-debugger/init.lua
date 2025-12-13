-- mLua Debugger for Neovim
-- Standalone debugger using MSW binary protocol (not DAP JSON-RPC)

local M = {}

---@class MluaDebuggerKeymaps
---@field continue string|false Continue execution (default: "<F5>")
---@field toggle_breakpoint string|false Toggle breakpoint (default: "<F9>")
---@field step_over string|false Step over (default: "<F10>")
---@field step_into string|false Step into (default: "<F11>")
---@field step_out string|false Step out (default: "<S-F11>")
---@field continue_leader string|false Continue with leader (default: "<leader>dc")
---@field toggle_breakpoint_leader string|false Toggle breakpoint with leader (default: "<leader>db")
---@field clear_breakpoints string|false Clear breakpoints (default: "<leader>dB")
---@field step_over_leader string|false Step over with leader (default: "<leader>ds")
---@field step_into_leader string|false Step into with leader (default: "<leader>di")
---@field step_out_leader string|false Step out with leader (default: "<leader>do")
---@field stack_trace string|false Stack trace (default: "<leader>dt")
---@field attach string|false Attach (default: "<leader>da")
---@field disconnect string|false Disconnect (default: "<leader>dd")
---@field toggle_ui string|false Toggle UI (default: "<leader>du")

---@class MluaDebuggerConfig
---@field port number Default port to connect to (default: 51300)
---@field host string Host to connect to (default: "localhost")
---@field timeout number Connection timeout in ms (default: 300000)
---@field ui MluaDebuggerUIConfig|nil UI configuration
---@field keymaps MluaDebuggerKeymaps|false|nil Keymap configuration (false to disable all)
local default_config = {
	port = 51300,
	host = "localhost",
	timeout = 300000,
	ui = {
		width = 50,
		height = 8,
		position = "right",
	},
	keymaps = {
		continue = "<F5>",
		toggle_breakpoint = "<F9>",
		step_over = "<F10>",
		step_into = "<F11>",
		step_out = "<S-F11>",
		continue_leader = "<leader>dc",
		toggle_breakpoint_leader = "<leader>db",
		clear_breakpoints = "<leader>dB",
		step_over_leader = "<leader>ds",
		step_into_leader = "<leader>di",
		step_out_leader = "<leader>do",
		stack_trace = "<leader>dt",
		attach = "<leader>da",
		disconnect = "<leader>dd",
		toggle_ui = "<leader>du",
	},
}

---@type MluaDebuggerConfig
M.config = vim.deepcopy(default_config)

local adapter = require("mlua-debugger.adapter")
local ui = require("mlua-debugger.ui")

-- Breakpoints tracked per file
local tracked_breakpoints = {}

---Setup mLua debugger
---@param opts MluaDebuggerConfig?
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", default_config, opts or {})

	-- Pass timeout to adapter
	adapter.timeout = M.config.timeout

	-- Setup UI
	ui.setup(M.config.ui)

	-- Set up sign column for breakpoints
	vim.fn.sign_define("MluaBreakpoint", { text = "●", texthl = "DiagnosticError", linehl = "", numhl = "" })
	vim.fn.sign_define("MluaBreakpointDisabled", { text = "○", texthl = "DiagnosticHint", linehl = "", numhl = "" })

	-- Create user commands
	vim.api.nvim_create_user_command("MluaDebugAttach", function(args)
		local port = M.config.port
		if args.args and #args.args > 0 then
			port = tonumber(args.args) or port
		end
		M.attach(M.config.host, port)
	end, { nargs = "?", desc = "Attach mLua debugger to MSW" })

	vim.api.nvim_create_user_command("MluaDebugDisconnect", function()
		M.disconnect()
	end, { desc = "Disconnect mLua debugger" })

	vim.api.nvim_create_user_command("MluaDebugContinue", function()
		adapter.continue()
	end, { desc = "Continue execution" })

	vim.api.nvim_create_user_command("MluaDebugStepOver", function()
		adapter.next()
	end, { desc = "Step over" })

	vim.api.nvim_create_user_command("MluaDebugStepInto", function()
		adapter.stepIn()
	end, { desc = "Step into" })

	vim.api.nvim_create_user_command("MluaDebugStepOut", function()
		adapter.stepOut()
	end, { desc = "Step out" })

	vim.api.nvim_create_user_command("MluaDebugToggleBreakpoint", function()
		M.toggleBreakpoint()
	end, { desc = "Toggle breakpoint" })

	vim.api.nvim_create_user_command("MluaDebugClearBreakpoints", function()
		M.clearBreakpoints()
	end, { desc = "Clear all breakpoints" })

	-- Stack trace command
	vim.api.nvim_create_user_command("MluaDebugStackTrace", function()
		local trace = adapter.getStackTrace()
		if trace.totalFrames == 0 then
			vim.notify("No stack trace available", vim.log.levels.INFO)
			return
		end
		local lines = { "Stack Trace:" }
		for i, frame in ipairs(trace.stackFrames) do
			table.insert(lines, string.format("  %d: %s at %s:%d", i, frame.name, frame.source.name, frame.line))
		end
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
	end, { desc = "Show stack trace" })

	-- Evaluate expression command
	vim.api.nvim_create_user_command("MluaDebugEval", function(args)
		if not args.args or #args.args == 0 then
			vim.notify("Usage: MluaDebugEval <expression>", vim.log.levels.WARN)
			return
		end
		adapter.evaluate(args.args, nil, "repl", function(result)
			vim.notify(string.format("%s = %s (%s)", args.args, result.result, result.type or "unknown"))
		end)
	end, { nargs = "+", desc = "Evaluate expression" })

	-- Set up buffer-local keymaps for mlua files (if not disabled)
	if M.config.keymaps ~= false then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "mlua",
			callback = function(args)
				local bufnr = args.buf
				local base_opts = { buffer = bufnr, silent = true }
				local km = M.config.keymaps

				local function set_keymap(key, cmd, desc)
					if key and key ~= false then
						vim.keymap.set("n", key, cmd, vim.tbl_extend("force", base_opts, { desc = desc }))
					end
				end

				-- Debugging keymaps (only for mlua buffers)
				set_keymap(km.continue, "<cmd>MluaDebugContinue<cr>", "Continue")
				set_keymap(km.toggle_breakpoint, "<cmd>MluaDebugToggleBreakpoint<cr>", "Toggle breakpoint")
				set_keymap(km.step_over, "<cmd>MluaDebugStepOver<cr>", "Step over")
				set_keymap(km.step_into, "<cmd>MluaDebugStepInto<cr>", "Step into")
				set_keymap(km.step_out, "<cmd>MluaDebugStepOut<cr>", "Step out")
				set_keymap(km.continue_leader, "<cmd>MluaDebugContinue<cr>", "Debug: Continue")
				set_keymap(km.toggle_breakpoint_leader, "<cmd>MluaDebugToggleBreakpoint<cr>", "Debug: Toggle breakpoint")
				set_keymap(km.clear_breakpoints, "<cmd>MluaDebugClearBreakpoints<cr>", "Debug: Clear breakpoints")
				set_keymap(km.step_over_leader, "<cmd>MluaDebugStepOver<cr>", "Debug: Step over")
				set_keymap(km.step_into_leader, "<cmd>MluaDebugStepInto<cr>", "Debug: Step into")
				set_keymap(km.step_out_leader, "<cmd>MluaDebugStepOut<cr>", "Debug: Step out")
				set_keymap(km.stack_trace, "<cmd>MluaDebugStackTrace<cr>", "Debug: Stack trace")
				set_keymap(km.attach, "<cmd>MluaDebugAttach<cr>", "Debug: Attach")
				set_keymap(km.disconnect, "<cmd>MluaDebugDisconnect<cr>", "Debug: Disconnect")
				set_keymap(km.toggle_ui, "<cmd>MluaDebugUIToggle<cr>", "Debug: Toggle UI")
			end,
		})
	end
end

---Attach to debug server
---@param host string|nil
---@param port number|nil
function M.attach(host, port)
	host = host or M.config.host
	port = port or M.config.port

	adapter.connect(host, port, function(err)
		if err then
			vim.notify("mLua debugger: " .. err, vim.log.levels.ERROR)
			return
		end

		-- Set up event handler to update UI
		adapter.setEventHandler(function(event, body)
			ui.on_event(event, body)
		end)

		-- Send any tracked breakpoints
		for filePath, lines in pairs(tracked_breakpoints) do
			adapter.setBreakpoints(filePath, lines)
		end

		-- Open UI
		ui.open()
		ui.log("info", string.format("Connected to %s:%d", host, port))
	end)
end

---Disconnect from debug server
function M.disconnect()
	adapter.disconnect()
	ui.log("info", "Disconnected")
end

---Toggle a breakpoint at the current cursor position
function M.toggleBreakpoint()
	local bufnr = vim.api.nvim_get_current_buf()
	local filePath = vim.api.nvim_buf_get_name(bufnr)
	local line = vim.api.nvim_win_get_cursor(0)[1]

	-- Initialize breakpoints for this file if needed
	if not tracked_breakpoints[filePath] then
		tracked_breakpoints[filePath] = {}
	end

	-- Check if breakpoint exists at this line
	local found_idx = nil
	for i, bp_line in ipairs(tracked_breakpoints[filePath]) do
		if bp_line == line then
			found_idx = i
			break
		end
	end

	if found_idx then
		-- Remove breakpoint
		table.remove(tracked_breakpoints[filePath], found_idx)
		vim.fn.sign_unplace("mlua_breakpoints", { buffer = bufnr, id = line })
	else
		-- Add breakpoint
		table.insert(tracked_breakpoints[filePath], line)
		vim.fn.sign_place(line, "mlua_breakpoints", "MluaBreakpoint", bufnr, { lnum = line, priority = 10 })
	end

	-- Send updated breakpoints to server if connected
	if adapter.isConnected() then
		adapter.setBreakpoints(filePath, tracked_breakpoints[filePath])
	end
end

---Clear all breakpoints
function M.clearBreakpoints()
	for filePath, _ in pairs(tracked_breakpoints) do
		-- Find buffer for this file
		local bufnr = vim.fn.bufnr(filePath)
		if bufnr ~= -1 then
			vim.fn.sign_unplace("mlua_breakpoints", { buffer = bufnr })
		end

		-- Send empty breakpoints to server if connected
		if adapter.isConnected() then
			adapter.setBreakpoints(filePath, {})
		end
	end
	tracked_breakpoints = {}
end

---Get breakpoints for a file
---@param filePath string
---@return number[]
function M.getBreakpoints(filePath)
	return tracked_breakpoints[filePath] or {}
end

-- Export adapter functions for direct use
M.connect = function(host, port, callback)
	adapter.connect(host or M.config.host, port or M.config.port, callback)
end
M.disconnect = adapter.disconnect
M.isConnected = adapter.isConnected
M.continue = adapter.continue
M.stepOver = adapter.next
M.stepInto = adapter.stepIn
M.stepOut = adapter.stepOut
M.setBreakpoints = adapter.setBreakpoints
M.getStackTrace = adapter.getStackTrace
M.getScopes = adapter.getScopes
M.getVariables = adapter.getVariables
M.evaluate = adapter.evaluate
M.getExecSpace = adapter.getExecSpace

-- Export UI functions
M.ui = ui

return M

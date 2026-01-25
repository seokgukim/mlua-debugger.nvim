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
---@field deprecated_commands boolean Enable deprecated command aliases (default: true)
---@field auto_ui boolean Automatically open/close UI on attach/disconnect (default: true)
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
	deprecated_commands = true,
	auto_ui = true,
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

	-- Setup UI (pass deprecated_commands flag)
	ui.setup(M.config.ui, M.config.deprecated_commands)

	-- Set up sign column for breakpoints
	vim.fn.sign_define("MluaBreakpoint", { text = "●", texthl = "DiagnosticError", linehl = "", numhl = "" })
	vim.fn.sign_define("MluaBreakpointDisabled", { text = "○", texthl = "DiagnosticHint", linehl = "", numhl = "" })

	-- Subcommand handlers for :Mlua debug <command>
	local subcommands = {
		attach = {
			fn = function(args)
				local port = M.config.port
				if args[1] then
					port = tonumber(args[1]) or port
				end
				M.attach(M.config.host, port)
			end,
			desc = "Attach to MSW debugger [port]",
		},
		disconnect = {
			fn = function() M.disconnect() end,
			desc = "Disconnect from debugger",
		},
		continue = {
			fn = function() adapter.continue() end,
			desc = "Continue execution",
		},
		stepover = {
			fn = function() adapter.next() end,
			desc = "Step over",
		},
		stepinto = {
			fn = function() adapter.stepIn() end,
			desc = "Step into",
		},
		stepout = {
			fn = function() adapter.stepOut() end,
			desc = "Step out",
		},
		breakpoint = {
			fn = function() M.toggleBreakpoint() end,
			desc = "Toggle breakpoint at cursor",
		},
		clearbreakpoints = {
			fn = function() M.clearBreakpoints() end,
			desc = "Clear all breakpoints",
		},
		stack = {
			fn = function()
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
			end,
			desc = "Show stack trace",
		},
		eval = {
			fn = function(args)
				local expr = table.concat(args, " ")
				if expr == "" then
					vim.notify("Usage: :Mlua debug eval <expression>", vim.log.levels.WARN)
					return
				end
				adapter.evaluate(expr, nil, "repl", function(result)
					vim.notify(string.format("%s = %s (%s)", expr, result.result, result.type or "unknown"))
				end)
			end,
			desc = "Evaluate expression",
		},
		uiopen = {
			fn = function() ui.open() end,
			desc = "Open debug UI",
		},
		uiclose = {
			fn = function() ui.close() end,
			desc = "Close debug UI",
		},
		uitoggle = {
			fn = function() ui.toggle() end,
			desc = "Toggle debug UI",
		},
		uiclear = {
			fn = function() ui.clear_console() end,
			desc = "Clear debug console",
		},
	}

	-- Main :MluaDebug command handler
	vim.api.nvim_create_user_command("MluaDebug", function(opts)
		local args = vim.split(opts.args, "%s+", { trimempty = true })
		local subcmd = args[1]

		if not subcmd or subcmd == "" then
			-- Show help
			vim.notify("Usage: :MluaDebug <subcommand>", vim.log.levels.INFO)
			vim.notify("Available subcommands:", vim.log.levels.INFO)
			for name, cmd in pairs(subcommands) do
				vim.notify(string.format("  %s - %s", name, cmd.desc), vim.log.levels.INFO)
			end
			return
		end

		local cmd = subcommands[subcmd]
		if cmd then
			-- Pass remaining args to the handler
			local cmd_args = {}
			for i = 2, #args do
				table.insert(cmd_args, args[i])
			end
			cmd.fn(cmd_args)
		else
			vim.notify(string.format("Unknown subcommand: %s", subcmd), vim.log.levels.ERROR)
		end
	end, {
		nargs = "?",
		complete = function(arglead, cmdline, cursorpos)
			local args = vim.split(cmdline, "%s+", { trimempty = true })
			-- args[1] is "MluaDebug"
			if #args == 1 or (#args == 2 and arglead ~= "") then
				-- Complete subcommands
				local names = vim.tbl_keys(subcommands)
				table.sort(names)
				if arglead == "" then
					return names
				end
				return vim.tbl_filter(function(name)
					return name:find("^" .. arglead) ~= nil
				end, names)
			end
			return {}
		end,
		desc = "MluaDebug commands",
	})

	-- Deprecated command aliases (kept for backwards compatibility)
	if M.config.deprecated_commands then
		-- Helper to create deprecated command alias
		local function create_deprecated_alias(old_name, new_subcmd, handler)
			vim.api.nvim_create_user_command(old_name, function(args)
				vim.notify(
					string.format(":%s is deprecated and will be removed in a future version. Use :MluaDebug %s instead.", old_name, new_subcmd),
					vim.log.levels.WARN
				)
				handler(args)
			end, { nargs = "*", desc = string.format("[Deprecated] Use :MluaDebug %s instead", new_subcmd) })
		end

		create_deprecated_alias("MluaDebugAttach", "attach", function(args)
			local port = M.config.port
			if args.args and #args.args > 0 then
				port = tonumber(args.args) or port
			end
			M.attach(M.config.host, port)
		end)
		create_deprecated_alias("MluaDebugDisconnect", "disconnect", function() M.disconnect() end)
		create_deprecated_alias("MluaDebugContinue", "continue", function() adapter.continue() end)
		create_deprecated_alias("MluaDebugStepOver", "stepover", function() adapter.next() end)
		create_deprecated_alias("MluaDebugStepInto", "stepinto", function() adapter.stepIn() end)
		create_deprecated_alias("MluaDebugStepOut", "stepout", function() adapter.stepOut() end)
		create_deprecated_alias("MluaDebugToggleBreakpoint", "breakpoint", function() M.toggleBreakpoint() end)
		create_deprecated_alias("MluaDebugClearBreakpoints", "clearbreakpoints", function() M.clearBreakpoints() end)
		create_deprecated_alias("MluaDebugStackTrace", "stack", function()
			subcommands.stack.fn()
		end)
		create_deprecated_alias("MluaDebugEval", "eval", function(args)
			if args.args and #args.args > 0 then
				local expr_args = vim.split(args.args, "%s+", { trimempty = true })
				subcommands.eval.fn(expr_args)
			else
				vim.notify("Usage: MluaDebugEval <expression>", vim.log.levels.WARN)
			end
		end)
	end

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

				-- Debugging keymaps (only for mlua buffers) - use new :MluaDebug commands
				set_keymap(km.continue, "<cmd>MluaDebug continue<cr>", "Continue")
				set_keymap(km.toggle_breakpoint, "<cmd>MluaDebug breakpoint<cr>", "Toggle breakpoint")
				set_keymap(km.step_over, "<cmd>MluaDebug stepover<cr>", "Step over")
				set_keymap(km.step_into, "<cmd>MluaDebug stepinto<cr>", "Step into")
				set_keymap(km.step_out, "<cmd>MluaDebug stepout<cr>", "Step out")
				set_keymap(km.continue_leader, "<cmd>MluaDebug continue<cr>", "Debug: Continue")
				set_keymap(km.toggle_breakpoint_leader, "<cmd>MluaDebug breakpoint<cr>", "Debug: Toggle breakpoint")
				set_keymap(km.clear_breakpoints, "<cmd>MluaDebug clearbreakpoints<cr>", "Debug: Clear breakpoints")
				set_keymap(km.step_over_leader, "<cmd>MluaDebug stepover<cr>", "Debug: Step over")
				set_keymap(km.step_into_leader, "<cmd>MluaDebug stepinto<cr>", "Debug: Step into")
				set_keymap(km.step_out_leader, "<cmd>MluaDebug stepout<cr>", "Debug: Step out")
				set_keymap(km.stack_trace, "<cmd>MluaDebug stack<cr>", "Debug: Stack trace")
				set_keymap(km.attach, "<cmd>MluaDebug attach<cr>", "Debug: Attach")
				set_keymap(km.disconnect, "<cmd>MluaDebug disconnect<cr>", "Debug: Disconnect")
				set_keymap(km.toggle_ui, "<cmd>MluaDebug uitoggle<cr>", "Debug: Toggle UI")
			end,
		})
	end
end

---Attach to debug server
---@param host string|nil
---@param port number|nil
---@param open_ui boolean|nil Whether to open UI (default: uses config.auto_ui)
function M.attach(host, port, open_ui)
	host = host or M.config.host
	port = port or M.config.port
	if open_ui == nil then
		open_ui = M.config.auto_ui
	end

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

		-- Close existing panels and open fresh UI if requested
		if open_ui then
			ui.close()
			ui.open()
		end
		ui.log("info", string.format("Connected to %s:%d", host, port))
	end)
end

---Disconnect from debug server
---@param close_ui boolean|nil Whether to close UI (default: uses config.auto_ui)
function M.disconnect(close_ui)
	if close_ui == nil then
		close_ui = M.config.auto_ui
	end

	adapter.disconnect()
	ui.log("info", "Disconnected")

	if close_ui then
		ui.close()
	end
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
-- M.disconnect is already defined above with UI handling
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

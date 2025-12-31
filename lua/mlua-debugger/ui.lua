-- mlua-debugger UI module
-- Provides panels for stack trace, variables, and console output

local M = {}

local api = vim.api
local adapter = require("mlua-debugger.adapter")

---@class MluaDebuggerUIConfig
---@field width number Width of side panel (default: 50)
---@field height number Height of bottom panel (default: 8)
---@field position string Position of panels: "left", "right" (default: "right")
local default_config = {
	width = 50,
	height = 8,
	position = "right",
}

---@type MluaDebuggerUIConfig
M.config = vim.deepcopy(default_config)

-- UI state
local state = {
	panels = {
		stack = { win = nil, buf = nil },
		variables = { win = nil, buf = nil },
		console = { win = nil, buf = nil },
	},
	stopped_line = {
		bufnr = nil,
		line = nil,
		ns_id = nil,
		extmark_id = nil,
	},
	console_lines = {},
	-- Variables state
	scopes = nil,
	expanded_references = {}, -- Set of variablesReference -> boolean
	variables_map = {}, -- Map of line number -> variable object
}

-- Highlight groups
local highlights = {
	stopped_line = "MluaDebuggerStoppedLine",
	stack_frame = "MluaDebuggerStackFrame",
	stack_current = "MluaDebuggerStackCurrent",
	variable_name = "MluaDebuggerVariableName",
	variable_type = "MluaDebuggerVariableType",
	variable_value = "MluaDebuggerVariableValue",
	console_info = "MluaDebuggerConsoleInfo",
	console_error = "MluaDebuggerConsoleError",
	panel_title = "MluaDebuggerPanelTitle",
	button_normal = "MluaDebuggerButton",
	button_hover = "MluaDebuggerButtonHover",
}

-- Forward declarations
local render_variables
local render_stack_trace
local render_console

---Setup highlight groups
local function setup_highlights()
	-- Stopped line - background highlight
	api.nvim_set_hl(0, highlights.stopped_line, { bg = "#3a3a00", default = true })
	-- Stack frames
	api.nvim_set_hl(0, highlights.stack_frame, { fg = "#8888ff", default = true })
	api.nvim_set_hl(0, highlights.stack_current, { fg = "#ffff00", bold = true, default = true })
	-- Variables
	api.nvim_set_hl(0, highlights.variable_name, { fg = "#9cdcfe", default = true })
	api.nvim_set_hl(0, highlights.variable_type, { fg = "#4ec9b0", italic = true, default = true })
	api.nvim_set_hl(0, highlights.variable_value, { fg = "#ce9178", default = true })
	-- Console
	api.nvim_set_hl(0, highlights.console_info, { fg = "#aaaaaa", default = true })
	api.nvim_set_hl(0, highlights.console_error, { fg = "#ff8888", default = true })
	-- Panel title
	api.nvim_set_hl(0, highlights.panel_title, { fg = "#ffffff", bold = true, default = true })
	-- Buttons
	api.nvim_set_hl(0, highlights.button_normal, { fg = "#88ff88", bg = "#333333", bold = true, default = true })
	api.nvim_set_hl(0, highlights.button_hover, { fg = "#ffffff", bg = "#555555", bold = true, default = true })

	-- Create namespace for stopped line
	state.stopped_line.ns_id = api.nvim_create_namespace("mlua_debugger_stopped")
end

---Toggle variable expansion
---@param buf number
local function toggle_variable_expand(buf)
	local cursor = api.nvim_win_get_cursor(0)
	local row = cursor[1]
	local var = state.variables_map[row]

	if var and var.variablesReference > 0 then
		local is_expanded = state.expanded_references[var.variablesReference]

		if is_expanded then
			-- Collapse
			state.expanded_references[var.variablesReference] = false
			render_variables()
		else
			-- Expand
			state.expanded_references[var.variablesReference] = true
			
			-- Check if we already have children
			if var.children then
				render_variables()
			else
				-- Fetch children
				adapter.getVariables(var.variablesReference, function(result)
					if result and result.variables then
						var.children = result.variables
						vim.schedule(function()
							render_variables()
						end)
					end
				end)
			end
		end
	end
end

---Setup keymaps for variables panel
---@param buf number
local function setup_variables_keymaps(buf)
	local opts = { buffer = buf, silent = true, nowait = true }
	
	-- Toggle expansion on click or Enter
	vim.keymap.set("n", "<CR>", function() toggle_variable_expand(buf) end, opts)
	vim.keymap.set("n", "<2-LeftMouse>", function() toggle_variable_expand(buf) end, opts)
	vim.keymap.set("n", "o", function() toggle_variable_expand(buf) end, opts)
	
	-- Standard debug keys
	vim.keymap.set("n", "<F5>", function() adapter.continue() end, opts)
	vim.keymap.set("n", "<F10>", function() adapter.next() end, opts)
	vim.keymap.set("n", "<F11>", function() adapter.stepIn() end, opts)
	vim.keymap.set("n", "<S-F11>", function() adapter.stepOut() end, opts)
end

---Setup debug keymaps for other panels
---@param buf number
local function setup_debug_keymaps(buf)
	local opts = { buffer = buf, silent = true, nowait = true }
	
	-- Standard debug keys
	vim.keymap.set("n", "<F5>", function() adapter.continue() end, opts)
	vim.keymap.set("n", "<F10>", function() adapter.next() end, opts)
	vim.keymap.set("n", "<F11>", function() adapter.stepIn() end, opts)
	vim.keymap.set("n", "<S-F11>", function() adapter.stepOut() end, opts)
end

---Create a buffer for a panel
---@param name string
---@return number
local function create_panel_buffer(name)
	local buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_name(buf, "mlua-debugger://" .. name)
	api.nvim_buf_set_option(buf, "buftype", "nofile")
	api.nvim_buf_set_option(buf, "bufhidden", "hide")
	api.nvim_buf_set_option(buf, "swapfile", false)
	api.nvim_buf_set_option(buf, "modifiable", false)
	api.nvim_buf_set_option(buf, "filetype", "mlua-debugger-" .. name)
	
	-- Setup specific keymaps
	if name == "variables" then
		setup_variables_keymaps(buf)
	else
		-- Setup debug keymaps for other panel buffers
		setup_debug_keymaps(buf)
	end
	
	return buf
end

---Set buffer lines
---@param buf number
---@param lines string[]
local function set_buffer_lines(buf, lines)
	api.nvim_buf_set_option(buf, "modifiable", true)
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	api.nvim_buf_set_option(buf, "modifiable", false)
end

---Open a panel window
---@param panel_name string
---@param split_cmd string
---@return number win_id
local function open_panel_window(panel_name, split_cmd)
	local panel = state.panels[panel_name]

	-- Create buffer if needed
	if not panel.buf or not api.nvim_buf_is_valid(panel.buf) then
		panel.buf = create_panel_buffer(panel_name)
	end

	-- Check if window already exists
	if panel.win and api.nvim_win_is_valid(panel.win) then
		return panel.win
	end

	-- Create window
	vim.cmd(split_cmd)
	panel.win = api.nvim_get_current_win()
	api.nvim_win_set_buf(panel.win, panel.buf)

	-- Set window options
	api.nvim_win_set_option(panel.win, "number", false)
	api.nvim_win_set_option(panel.win, "relativenumber", false)
	api.nvim_win_set_option(panel.win, "signcolumn", "no")
	api.nvim_win_set_option(panel.win, "wrap", false)
	api.nvim_win_set_option(panel.win, "cursorline", true)
	api.nvim_win_set_option(panel.win, "winfixwidth", true)
	api.nvim_win_set_option(panel.win, "winfixheight", true)

	return panel.win
end

---Close a panel window
---@param panel_name string
local function close_panel_window(panel_name)
	local panel = state.panels[panel_name]
	if panel.win and api.nvim_win_is_valid(panel.win) then
		api.nvim_win_close(panel.win, true)
	end
	panel.win = nil
end

---Render stack trace panel
render_stack_trace = function()
	local panel = state.panels.stack
	if not panel.buf or not api.nvim_buf_is_valid(panel.buf) then
		return
	end

	local trace = adapter.getStackTrace()
	local title = "╭─ Stack Trace ─╮"
	if trace.execSpace and trace.execSpace ~= "" then
		title = string.format("╭─ Stack Trace (%s) ─╮", trace.execSpace)
	end
	local lines = { title, "" }

	if trace.totalFrames == 0 then
		table.insert(lines, "  (no stack trace)")
	else
		for i, frame in ipairs(trace.stackFrames) do
			local prefix = i == 1 and "→ " or "  "
			local location = string.format("%s:%d", frame.source.name or "?", frame.line)
			local name = frame.name or "(anonymous)"
			table.insert(lines, string.format("%s%d. %s", prefix, i, name))
			table.insert(lines, string.format("     %s", location))
		end
	end

	table.insert(lines, "")
	table.insert(lines, "╰───────────────╯")

	set_buffer_lines(panel.buf, lines)

	-- Apply highlights
	api.nvim_buf_clear_namespace(panel.buf, state.stopped_line.ns_id, 0, -1)
	api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, highlights.panel_title, 0, 0, -1)
	for i = 2, #lines - 2 do
		local line = lines[i]
		if line:match("^→") then
			api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, highlights.stack_current, i - 1, 0, -1)
		elseif line:match("^%s+%d") then
			api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, highlights.stack_frame, i - 1, 0, -1)
		end
	end
end

---Render a single variable recursively
---@param lines string[]
---@param var table
---@param depth number
local function render_variable_recursive(lines, var, depth)
	local indent = string.rep("  ", depth)
	local icon = "  "
	
	if var.variablesReference > 0 then
		if state.expanded_references[var.variablesReference] then
			icon = "▼ "
		else
			icon = "▶ "
		end
	end
	
	local type_str = var.type and string.format(" : %s", var.type) or ""
	local value = var.value or "nil"
	
	-- Better formatting for tables/objects
	if var.variablesReference > 0 and value:match("^table: 0x") then
		-- If it's a table and we have children, maybe show count or just "..."
		-- For now, keep the value but maybe clean it up if needed
	end
	
	if #value > 50 then
		value = value:sub(1, 47) .. "..."
	end
	
	local text = string.format("%s%s%s%s = %s", indent, icon, var.name, type_str, value)
	table.insert(lines, text)
	state.variables_map[#lines] = var
	
	-- Render children if expanded
	if var.variablesReference > 0 and state.expanded_references[var.variablesReference] and var.children then
		for _, child in ipairs(var.children) do
			render_variable_recursive(lines, child, depth + 1)
		end
	end
end

---Render variables panel
render_variables = function()
	local panel = state.panels.variables
	if not panel.buf or not api.nvim_buf_is_valid(panel.buf) then
		return
	end

	-- Reset map
	state.variables_map = {}
	local lines = { "╭─ Variables ─╮", "" }

	local scopes = state.scopes
	if not scopes or #scopes == 0 then
		table.insert(lines, "  (no variables)")
	else
		for _, scope in ipairs(scopes) do
			table.insert(lines, "┌ " .. scope.name)
			if scope.variables then
				for _, var in ipairs(scope.variables) do
					render_variable_recursive(lines, var, 1)
				end
			end
			table.insert(lines, "")
		end
	end

	table.insert(lines, "╰─────────────╯")

	set_buffer_lines(panel.buf, lines)

	-- Apply highlights
	api.nvim_buf_clear_namespace(panel.buf, state.stopped_line.ns_id, 0, -1)
	api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, highlights.panel_title, 0, 0, -1)
	
	-- Highlight variables
	for i, line in ipairs(lines) do
		if state.variables_map[i] then
			-- Find positions for highlighting
			local name_start = line:find("[^%s▶▼]")
			if name_start then
				name_start = name_start - 1
				local eq_pos = line:find(" = ", name_start)
				if eq_pos then
					-- Name
					local type_pos = line:find(" : ", name_start)
					local name_end = type_pos or eq_pos
					api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, highlights.variable_name, i - 1, name_start, name_end - 1)
					
					-- Type
					if type_pos then
						api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, highlights.variable_type, i - 1, type_pos + 3, eq_pos - 1)
					end
					
					-- Value
					api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, highlights.variable_value, i - 1, eq_pos + 3, -1)
				end
			end
		end
	end
end

---Setup keymaps for console panel buttons
---@param buf number
local function setup_console_keymaps(buf)
	local opts = { buffer = buf, silent = true, nowait = true }

	-- Click handler for button line
	vim.keymap.set("n", "<CR>", function()
		local cursor = api.nvim_win_get_cursor(0)
		local row, col = cursor[1], cursor[2]
		if row == 1 then
			-- Button line - determine which button was clicked
			if col >= 1 and col <= 12 then
				-- Continue
				adapter.continue()
			elseif col >= 14 and col <= 22 then
				-- Step Over
				adapter.next()
			elseif col >= 24 and col <= 32 then
				-- Step Into
				adapter.stepIn()
			elseif col >= 34 and col <= 41 then
				-- Step Out
				adapter.stepOut()
			elseif col >= 43 and col <= 50 then
				-- Stop/Disconnect
				adapter.disconnect()
			elseif col >= 52 and col <= 61 then
				-- Clear console
				M.clear_console()
			end
		end
	end, opts)

	-- Also support number keys for quick access
	vim.keymap.set("n", "1", function()
		adapter.continue()
	end, vim.tbl_extend("force", opts, { desc = "Continue" }))
	vim.keymap.set("n", "2", function()
		adapter.next()
	end, vim.tbl_extend("force", opts, { desc = "Step Over" }))
	vim.keymap.set("n", "3", function()
		adapter.stepIn()
	end, vim.tbl_extend("force", opts, { desc = "Step Into" }))
	vim.keymap.set("n", "4", function()
		adapter.stepOut()
	end, vim.tbl_extend("force", opts, { desc = "Step Out" }))
	vim.keymap.set("n", "5", function()
		adapter.disconnect()
	end, vim.tbl_extend("force", opts, { desc = "Stop" }))
	vim.keymap.set("n", "c", function()
		M.clear_console()
	end, vim.tbl_extend("force", opts, { desc = "Clear" }))
end

---Render console panel with clickable buttons
render_console = function()
	local panel = state.panels.console
	if not panel.buf or not api.nvim_buf_is_valid(panel.buf) then
		return
	end

	-- Button bar at top
	local button_line = " [▶ Continue] [≫ Step] [↓ Into] [↑ Out] [■ Stop] [∅ Clear] "
	local lines = { button_line, "─── Console Output ───" }
	for _, entry in ipairs(state.console_lines) do
		table.insert(lines, entry.text)
	end

	if #state.console_lines == 0 then
		table.insert(lines, "(no output)")
	end

	set_buffer_lines(panel.buf, lines)

	-- Apply highlights
	api.nvim_buf_clear_namespace(panel.buf, state.stopped_line.ns_id, 0, -1)
	-- Highlight button bar
	api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, highlights.button_normal, 0, 0, -1)
	-- Highlight title
	api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, highlights.panel_title, 1, 0, -1)
	for i, entry in ipairs(state.console_lines) do
		local hl = entry.level == "error" and highlights.console_error or highlights.console_info
		api.nvim_buf_add_highlight(panel.buf, state.stopped_line.ns_id, hl, i + 1, 0, -1)
	end

	-- Setup clickable button keymaps
	setup_console_keymaps(panel.buf)
end

---Normalize file path (handle Windows paths in WSL)
---@param path string
---@return string
local function normalize_path(path)
	-- Convert backslashes to forward slashes
	path = path:gsub("\\", "/")

	-- Handle Windows drive letters for WSL
	-- C:/Users/... -> /mnt/c/Users/...
	local drive = path:match("^(%a):")
	if drive then
		local drive_lower = drive:lower()
		path = path:gsub("^%a:", "/mnt/" .. drive_lower)
	end

	return path
end

---Highlight stopped line in source buffer
---@param filePath string
---@param line number
local function highlight_stopped_line(filePath, line)
	-- Clear previous highlight
	M.clear_stopped_line()

	-- Normalize path
	filePath = normalize_path(filePath)

	-- Find or open the file buffer
	local bufnr = vim.fn.bufnr(filePath)

	-- If not found, try to find by matching real paths or normalized paths
	if bufnr == -1 then
		local uv = vim.uv or vim.loop
		local target_real = uv.fs_realpath(filePath)

		for _, b in ipairs(api.nvim_list_bufs()) do
			local b_name = api.nvim_buf_get_name(b)
			if b_name ~= "" then
				if normalize_path(b_name) == filePath then
					bufnr = b
					break
				end
				if target_real and uv.fs_realpath(b_name) == target_real then
					bufnr = b
					break
				end
			end
		end
	end

	if bufnr == -1 then
		-- Try to load the file
		bufnr = vim.fn.bufadd(filePath)
		vim.fn.bufload(bufnr)
	end

	if not api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Ensure line is within buffer bounds
	local line_count = api.nvim_buf_line_count(bufnr)
	if line > line_count then
		line = line_count
	elseif line < 1 then
		line = 1
	end

	-- Jump to the file and line
	local wins = api.nvim_list_wins()
	local target_win = nil
	for _, win in ipairs(wins) do
		local win_buf = api.nvim_win_get_buf(win)
		local buf_name = api.nvim_buf_get_name(win_buf)
		-- Skip debugger panels
		if not buf_name:match("^mlua%-debugger://") then
			target_win = win
			break
		end
	end

	if target_win then
		api.nvim_set_current_win(target_win)
		if api.nvim_win_get_buf(target_win) ~= bufnr then
			api.nvim_win_set_buf(target_win, bufnr)
		end
		api.nvim_win_set_cursor(target_win, { line, 0 })
	end

	-- Add highlight with virtual text background
	state.stopped_line.bufnr = bufnr
	state.stopped_line.line = line

	-- Highlight the entire line with background color
	state.stopped_line.extmark_id = api.nvim_buf_set_extmark(bufnr, state.stopped_line.ns_id, line - 1, 0, {
		end_row = line - 1,
		end_col = 0,
		line_hl_group = highlights.stopped_line,
		virt_text = { { " ● STOPPED", highlights.stack_current } },
		virt_text_pos = "eol",
		priority = 1000,
	})
end

---Clear stopped line highlight
function M.clear_stopped_line()
	-- Ensure namespace exists
	if not state.stopped_line.ns_id then
		state.stopped_line.ns_id = api.nvim_create_namespace("mlua_debugger_stopped")
	end

	-- Clear from tracked buffer
	if state.stopped_line.bufnr and api.nvim_buf_is_valid(state.stopped_line.bufnr) then
		api.nvim_buf_clear_namespace(state.stopped_line.bufnr, state.stopped_line.ns_id, 0, -1)
	end

	-- Also clear from all non-panel buffers in case of path mismatch
	for _, buf in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(buf) and api.nvim_buf_is_loaded(buf) then
			local buf_name = api.nvim_buf_get_name(buf)
			-- Skip debugger panel buffers
			if not buf_name:match("^mlua%-debugger://") then
				api.nvim_buf_clear_namespace(buf, state.stopped_line.ns_id, 0, -1)
			end
		end
	end

	state.stopped_line.bufnr = nil
	state.stopped_line.line = nil
	state.stopped_line.extmark_id = nil
end

---Open the debug UI
---Layout:
---  +------------------+------------------+
---  |   Code (main)    |   Variables      |
---  +------------------+------------------+
---  |   Console        |   Stack Trace    |
---  +------------------+------------------+
function M.open()
	local cur_win = api.nvim_get_current_win()
	local total_width = vim.o.columns
	local total_height = vim.o.lines

	-- Calculate dimensions
	local side_width = M.config.width
	local bottom_height = M.config.height

	-- Open Variables panel on the right side of main editor
	vim.cmd("botright " .. side_width .. "vsplit")
	state.panels.variables.win = api.nvim_get_current_win()
	if not state.panels.variables.buf or not api.nvim_buf_is_valid(state.panels.variables.buf) then
		state.panels.variables.buf = create_panel_buffer("variables")
	end
	api.nvim_win_set_buf(state.panels.variables.win, state.panels.variables.buf)
	api.nvim_win_set_option(state.panels.variables.win, "number", false)
	api.nvim_win_set_option(state.panels.variables.win, "relativenumber", false)
	api.nvim_win_set_option(state.panels.variables.win, "signcolumn", "no")
	api.nvim_win_set_option(state.panels.variables.win, "winfixwidth", true)
	api.nvim_win_set_option(state.panels.variables.win, "wrap", false)
	api.nvim_win_set_option(state.panels.variables.win, "cursorline", true)

	-- Split below variables for stack trace (same width as variables)
	vim.cmd("belowright " .. bottom_height .. "split")
	state.panels.stack.win = api.nvim_get_current_win()
	if not state.panels.stack.buf or not api.nvim_buf_is_valid(state.panels.stack.buf) then
		state.panels.stack.buf = create_panel_buffer("stack")
	end
	api.nvim_win_set_buf(state.panels.stack.win, state.panels.stack.buf)
	api.nvim_win_set_option(state.panels.stack.win, "number", false)
	api.nvim_win_set_option(state.panels.stack.win, "relativenumber", false)
	api.nvim_win_set_option(state.panels.stack.win, "signcolumn", "no")
	api.nvim_win_set_option(state.panels.stack.win, "winfixwidth", true)
	api.nvim_win_set_option(state.panels.stack.win, "winfixheight", true)
	api.nvim_win_set_option(state.panels.stack.win, "wrap", false)
	api.nvim_win_set_option(state.panels.stack.win, "cursorline", true)

	-- Go back to main code window and open console at bottom (same width as code)
	api.nvim_set_current_win(cur_win)
	vim.cmd("belowright " .. bottom_height .. "split")
	state.panels.console.win = api.nvim_get_current_win()
	if not state.panels.console.buf or not api.nvim_buf_is_valid(state.panels.console.buf) then
		state.panels.console.buf = create_panel_buffer("console")
	end
	api.nvim_win_set_buf(state.panels.console.win, state.panels.console.buf)
	api.nvim_win_set_option(state.panels.console.win, "number", false)
	api.nvim_win_set_option(state.panels.console.win, "relativenumber", false)
	api.nvim_win_set_option(state.panels.console.win, "signcolumn", "no")
	api.nvim_win_set_option(state.panels.console.win, "winfixheight", true)
	api.nvim_win_set_option(state.panels.console.win, "wrap", false)
	api.nvim_win_set_option(state.panels.console.win, "cursorline", true)

	-- Return to original window
	api.nvim_set_current_win(cur_win)

	-- Initial render
	render_stack_trace()
	render_variables()
	render_console()
end

---Close the debug UI
function M.close()
	M.clear_stopped_line()
	close_panel_window("stack")
	close_panel_window("variables")
	close_panel_window("console")
end

---Toggle the debug UI
function M.toggle()
	if M.is_open() then
		M.close()
	else
		M.open()
	end
end

---Check if UI is open
---@return boolean
function M.is_open()
	for _, panel in pairs(state.panels) do
		if panel.win and api.nvim_win_is_valid(panel.win) then
			return true
		end
	end
	return false
end

---Update UI on debug event
---@param event string
---@param body table|nil
function M.on_event(event, body)
	if event == "continued" then
		-- Clear stopped line when execution continues
		vim.schedule(function()
			M.clear_stopped_line()
		end)
	elseif event == "stopped" then
		-- Get stack trace and update panels
		local trace = adapter.getStackTrace()
		render_stack_trace()

		-- Highlight stopped line
		if trace.totalFrames > 0 then
			local top_frame = trace.stackFrames[1]
			if top_frame.source and top_frame.source.path then
				highlight_stopped_line(top_frame.source.path, top_frame.line)
			end

			-- Fetch and display scopes/variables
			adapter.getScopes(top_frame.id, function(result)
				if result and result.scopes then
					local scopes_with_vars = {}
					local pending = #result.scopes
					
					-- Initialize scopes list
					for i, scope in ipairs(result.scopes) do
						scopes_with_vars[i] = {
							name = scope.name,
							variablesReference = scope.variablesReference,
							variables = {}
						}
					end
					
					if pending == 0 then
						state.scopes = scopes_with_vars
						vim.schedule(function()
							render_variables()
						end)
						return
					end

					for i, scope in ipairs(result.scopes) do
						adapter.getVariables(scope.variablesReference, function(vars_result)
							scopes_with_vars[i].variables = vars_result and vars_result.variables or {}
							pending = pending - 1
							if pending == 0 then
								state.scopes = scopes_with_vars
								vim.schedule(function()
									render_variables()
								end)
							end
						end)
					end
				end
			end)
		end

		M.log("info", "Execution stopped")
	elseif event == "terminated" then
		vim.schedule(function()
			M.clear_stopped_line()
			render_stack_trace()
			state.scopes = nil
			state.expanded_references = {}
			render_variables()
			M.log("info", "Debug session terminated")
		end)
	end
end

---Log message to console
---@param level string "info" | "error"
---@param message string
function M.log(level, message)
	local timestamp = os.date("%H:%M:%S")
	table.insert(state.console_lines, {
		text = string.format("[%s] %s", timestamp, message),
		level = level,
	})

	-- Keep only last 100 lines
	while #state.console_lines > 100 do
		table.remove(state.console_lines, 1)
	end

	render_console()

	-- Auto-scroll to bottom if console is open
	local panel = state.panels.console
	if panel.win and api.nvim_win_is_valid(panel.win) and panel.buf then
		local line_count = api.nvim_buf_line_count(panel.buf)
		pcall(api.nvim_win_set_cursor, panel.win, { line_count, 0 })
	end
end

---Clear console
function M.clear_console()
	state.console_lines = {}
	render_console()
end

---Setup the UI module
---@param opts MluaDebuggerUIConfig|nil
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", default_config, opts or {})
	setup_highlights()

	-- Create commands
	api.nvim_create_user_command("MluaDebugUIOpen", function()
		M.open()
	end, { desc = "Open mLua debug UI" })

	api.nvim_create_user_command("MluaDebugUIClose", function()
		M.close()
	end, { desc = "Close mLua debug UI" })

	api.nvim_create_user_command("MluaDebugUIToggle", function()
		M.toggle()
	end, { desc = "Toggle mLua debug UI" })

	api.nvim_create_user_command("MluaDebugUIClear", function()
		M.clear_console()
	end, { desc = "Clear debug console" })

	api.nvim_create_user_command("MluaDebugEvaluate", function(opts)
		local expr = opts.args
		if expr == "" then
			vim.notify("Usage: MluaDebugEvaluate <expression>", vim.log.levels.ERROR)
			return
		end
		
		adapter.evaluate(expr, nil, nil, function(result)
			vim.schedule(function()
				if result.result then
					M.log("info", string.format("Eval: %s = %s", expr, result.result))
				else
					M.log("error", string.format("Eval failed: %s", expr))
				end
			end)
		end)
	end, { nargs = "+", desc = "Evaluate expression in debug session" })
end

return M

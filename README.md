# mlua-debugger.nvim

Standalone debugger for mLua/MSW in Neovim using MSW's binary protocol.

## Features

- Direct communication with MSW debugger (binary protocol, not DAP JSON-RPC)
- Built-in UI with:
  - Stack trace panel
  - Variables panel
  - Console output panel
  - Stopped line highlighting with virtual text
- No external dependencies (no nvim-dap required)

## Requirements

- Neovim 0.9+

## Installation

### lazy.nvim

```lua
{
  "seokgukim/mlua-debugger.nvim",
  config = function()
    require("mlua-debugger").setup()
  end,
}
```

## Configuration

```lua
require("mlua-debugger").setup({
  port = 51300,       -- Default port to connect to
  host = "localhost", -- Host to connect to
  timeout = 300000,    -- Connection timeout in ms
  ui = {
    width = 40,       -- Width of side panels
    height = 10,      -- Height of console panel
    position = "right", -- Position of side panels: "left" or "right"
  },
  keymaps = {         -- Set to false to disable all keymaps
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
})
```

### Disabling Keymaps

To disable all default keymaps and define your own:

```lua
require("mlua-debugger").setup({
  keymaps = false,  -- Disable all default keymaps
})
```

To disable specific keymaps:

```lua
require("mlua-debugger").setup({
  keymaps = {
    continue = false,  -- Disable <F5>
    step_over = false, -- Disable <F10>
    -- Other keymaps remain default
  },
})
```

## Commands

### Debug Commands

| Command | Description |
|---------|-------------|
| `:MluaDebugAttach [port]` | Attach to MSW debugger |
| `:MluaDebugDisconnect` | Disconnect from debugger |
| `:MluaDebugContinue` | Continue execution |
| `:MluaDebugStepOver` | Step over |
| `:MluaDebugStepInto` | Step into |
| `:MluaDebugStepOut` | Step out |
| `:MluaDebugToggleBreakpoint` | Toggle breakpoint at cursor |
| `:MluaDebugClearBreakpoints` | Clear all breakpoints |
| `:MluaDebugStackTrace` | Show stack trace |
| `:MluaDebugEval <expr>` | Evaluate expression |

### UI Commands

| Command | Description |
|---------|-------------|
| `:MluaDebugUIOpen` | Open debug UI panels |
| `:MluaDebugUIClose` | Close debug UI panels |
| `:MluaDebugUIToggle` | Toggle debug UI panels |
| `:MluaDebugUIClear` | Clear console output |

## Keymaps (mlua filetype)

| Key | Description |
|-----|-------------|
| `<F5>` | Continue |
| `<F9>` | Toggle breakpoint |
| `<F10>` | Step over |
| `<F11>` | Step into |
| `<S-F11>` | Step out |
| `<leader>dc` | Continue |
| `<leader>db` | Toggle breakpoint |
| `<leader>dB` | Clear breakpoints |
| `<leader>ds` | Step over |
| `<leader>di` | Step into |
| `<leader>do` | Step out |
| `<leader>dt` | Stack trace |
| `<leader>da` | Attach |
| `<leader>dd` | Disconnect |
| `<leader>du` | Toggle UI |

## Highlight Groups

| Highlight | Description |
|-----------|-------------|
| `MluaDebuggerStoppedLine` | Background color for stopped line |
| `MluaDebuggerStackFrame` | Stack frame text |
| `MluaDebuggerStackCurrent` | Current stack frame |
| `MluaDebuggerVariableName` | Variable names |
| `MluaDebuggerVariableType` | Variable types |
| `MluaDebuggerVariableValue` | Variable values |
| `MluaDebuggerConsoleInfo` | Console info messages |
| `MluaDebuggerConsoleError` | Console error messages |
| `MluaDebuggerPanelTitle` | Panel titles |

## License

MIT

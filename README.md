# mlua-debugger.nvim

Standalone debugger for mLua/MSW in Neovim using MSW's binary protocol.

<img width="1899" height="1072" alt="mlua-debugger.nvim" src="https://github.com/user-attachments/assets/a8d282c6-b548-4302-bbad-2d10a53b7e0a" />


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
  auto_ui = true,     -- Automatically open/close UI on attach/disconnect
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
  deprecated_commands = true, -- Set to false to hide deprecated command aliases from completion
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

The plugin provides a unified `:MluaDebug <subcommand>` pattern:

### New Command Style

| Command | Description |
|---------|-------------|
| `:MluaDebug attach [port]` | Attach to MSW debugger |
| `:MluaDebug disconnect` | Disconnect from debugger |
| `:MluaDebug continue` | Continue execution |
| `:MluaDebug stepover` | Step over |
| `:MluaDebug stepinto` | Step into |
| `:MluaDebug stepout` | Step out |
| `:MluaDebug breakpoint` | Toggle breakpoint at cursor |
| `:MluaDebug clearbreakpoints` | Clear all breakpoints |
| `:MluaDebug stack` | Show stack trace |
| `:MluaDebug eval <expr>` | Evaluate expression |
| `:MluaDebug uiopen` | Open debug UI panels |
| `:MluaDebug uiclose` | Close debug UI panels |
| `:MluaDebug uitoggle` | Toggle debug UI panels |
| `:MluaDebug uiclear` | Clear console output |

### Legacy Commands (Deprecated)

The old command style is still supported but deprecated. A warning will be shown when using them:

| Old Command | New Command |
|-------------|-------------|
| `:MluaDebugAttach [port]` | `:MluaDebug attach [port]` |
| `:MluaDebugDisconnect` | `:MluaDebug disconnect` |
| `:MluaDebugContinue` | `:MluaDebug continue` |
| `:MluaDebugStepOver` | `:MluaDebug stepover` |
| `:MluaDebugStepInto` | `:MluaDebug stepinto` |
| `:MluaDebugStepOut` | `:MluaDebug stepout` |
| `:MluaDebugToggleBreakpoint` | `:MluaDebug breakpoint` |
| `:MluaDebugClearBreakpoints` | `:MluaDebug clearbreakpoints` |
| `:MluaDebugStackTrace` | `:MluaDebug stack` |
| `:MluaDebugEval <expr>` | `:MluaDebug eval <expr>` |
| `:MluaDebugUIOpen` | `:MluaDebug uiopen` |
| `:MluaDebugUIClose` | `:MluaDebug uiclose` |
| `:MluaDebugUIToggle` | `:MluaDebug uitoggle` |
| `:MluaDebugUIClear` | `:MluaDebug uiclear` |

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

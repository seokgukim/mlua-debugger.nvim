-- Minimal init for testing
vim.opt.runtimepath:append(".")
vim.opt.runtimepath:append("./tests")

-- Disable swap files for tests
vim.opt.swapfile = false

-- Load the plugin
require("mlua-debugger")

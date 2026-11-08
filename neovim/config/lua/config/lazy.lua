-- Kadomo's LazyVim setup: lazy.nvim, LazyVim, the extras for Kadomo's
-- languages, the AI tools turned on in Kadomo's installer, then your plugins.
-- Extras you turn on with :LazyExtras load as well (LazyVim keeps those in
-- lazyvim.json).

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
    }, true, {})
    -- Without a screen (Kadomo's installer runs this headless), there is no key to wait for.
    if #vim.api.nvim_list_uis() > 0 then
      vim.api.nvim_echo({ { "\nPress any key to exit..." } }, true, {})
      vim.fn.getchar()
    end
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

local spec = {
  { "LazyVim/LazyVim", import = "lazyvim.plugins" },

  -- Java: jdtls with debugging and tests (needs a JDK 21 or later to run)
  { import = "lazyvim.plugins.extras.lang.java" },
  -- JavaScript, TypeScript, and Node: vtsls, plus Node debugging
  { import = "lazyvim.plugins.extras.lang.typescript" },
  { import = "lazyvim.plugins.extras.linting.eslint" },
  { import = "lazyvim.plugins.extras.formatting.prettier" },
  -- AWS and config files: JSON and YAML with SchemaStore's schemas,
  -- Dockerfiles; lua/plugins/kadomo-aws.lua adds CloudFormation
  { import = "lazyvim.plugins.extras.lang.json" },
  { import = "lazyvim.plugins.extras.lang.yaml" },
  { import = "lazyvim.plugins.extras.lang.docker" },
  { import = "lazyvim.plugins.extras.lang.markdown" },
  -- Debugging and test running for every language above
  { import = "lazyvim.plugins.extras.dap.core" },
  { import = "lazyvim.plugins.extras.test.core" },
  -- Editing: add, change, and delete surrounding quotes and brackets (gsa, gsd, gsr)
  { import = "lazyvim.plugins.extras.coding.mini-surround" },
}

-- The AI tools picked in Kadomo's installer, from kadomo-ai.lua, which the
-- installer writes and removes: GitHub Copilot and Claude Code.
local ok, ai = pcall(dofile, vim.fn.stdpath("config") .. "/kadomo-ai.lua")
if ok and type(ai) == "table" then
  if ai.copilot then
    table.insert(spec, { import = "lazyvim.plugins.extras.ai.copilot" })
  end
  if ai.claude_code then
    table.insert(spec, { import = "lazyvim.plugins.extras.ai.claudecode" })
  end
end

-- Last: Kadomo's tweaks (lua/plugins/kadomo-*.lua), your plugins, and the
-- theme manager's lua/plugins/theme.lua, which picks the theme's colors.
table.insert(spec, { import = "plugins" })

require("lazy").setup({
  spec = spec,
  defaults = { lazy = false, version = false },
  install = { colorscheme = { "kadomo", "tokyonight", "habamax" } },
  checker = { enabled = true, notify = false },
  performance = {
    rtp = {
      disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" },
    },
  },
})

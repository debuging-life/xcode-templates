---:checkhealth xcode-templates
local M = {}

function M.check()
  local health = vim.health
  health.start("xcode-templates.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim >= 0.10 is required (floating-window title/footer support)")
  end

  if vim.fn.executable("git") == 1 then
    health.ok("git executable found")
    local name = vim.trim(vim.fn.system({ "git", "config", "user.name" }))
    if vim.v.shell_error == 0 and name ~= "" then
      health.ok("header author: " .. name .. " (git config user.name)")
    else
      health.warn("git user.name is not set — header author falls back to $USER", {
        "Run: git config --global user.name 'Your Name'",
        "Or set `author` in setup()",
      })
    end
  else
    health.warn("git not found — header author falls back to $USER")
  end

  local ok, err = pcall(require("xcode-templates.config").validate, require("xcode-templates").config)
  if ok then
    health.ok("configuration is valid")
  else
    health.error("invalid configuration: " .. tostring(err))
  end

  health.info("Template icons need a Nerd Font terminal (LazyVim's default setup)")
end

return M

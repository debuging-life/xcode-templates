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

  -- optional: only needed for old-style (non-synchronized) Xcode projects
  if vim.fn.executable("ruby") == 1 then
    vim.fn.system({ "ruby", "-e", 'require "xcodeproj"' })
    if vim.v.shell_error == 0 then
      health.ok("ruby + xcodeproj gem found (old-style project integration available)")
    else
      health.info("xcodeproj gem not installed — only needed for old-style Xcode projects (`gem install xcodeproj`)")
    end
  else
    health.info("ruby not found — only needed for old-style Xcode projects")
  end

  local ok, err = pcall(require("xcode-templates.config").validate, require("xcode-templates").config)
  if ok then
    health.ok("configuration is valid")
  else
    health.error("invalid configuration: " .. tostring(err))
  end

  if pcall(vim.treesitter.language.inspect, "swift") then
    health.ok("swift tree-sitter parser found (preview pane highlighting)")
  else
    health.info("no swift tree-sitter parser — preview pane falls back to regex syntax")
  end

  health.info("Template icons need a Nerd Font terminal (LazyVim's default setup)")
end

return M

---Header + template context generation (project name, author, date).
local M = {}

---Find the Xcode project/workspace (or Swift package) that owns `path`.
---@param path string absolute path of the file
---@return string project name
function M.project_name(path)
  local dir = vim.fs.dirname(path)
  local found = vim.fs.find(function(name)
    return name:match("%.xcodeproj$") ~= nil or name:match("%.xcworkspace$") ~= nil
  end, { path = dir, upward = true })
  if found[1] then
    return (vim.fn.fnamemodify(found[1], ":t:r"))
  end
  local pkg = vim.fs.find("Package.swift", { path = dir, upward = true })
  if pkg[1] then
    return (vim.fn.fnamemodify(vim.fs.dirname(pkg[1]), ":t"))
  end
  return (vim.fn.fnamemodify(vim.fn.getcwd(), ":t"))
end

---Header author: config override → git config user.name → $USER.
---@param config XcodeTemplates.Config
---@return string
function M.author(config)
  if config.author and config.author ~= "" then
    return config.author
  end
  if vim.fn.executable("git") == 1 then
    local name = vim.trim(vim.fn.system({ "git", "config", "user.name" }))
    if vim.v.shell_error == 0 and name ~= "" then
      return name
    end
  end
  return vim.env.USER or "Unknown"
end

---Sanitize a file basename into a valid Swift type identifier.
---@param name string
---@return string
function M.identifier(name)
  local id = name:gsub("[^%w_]", "")
  if id == "" then
    id = "NewFile"
  end
  if id:match("^%d") then
    id = "_" .. id
  end
  return id
end

---Build the substitution context used by the header and template bodies.
---@param path string file path
---@param config XcodeTemplates.Config
---@return table ctx { filename, name, project, module_name, author, date }
function M.context(path, config)
  local project = M.project_name(vim.fn.fnamemodify(path, ":p"))
  local ok, date = pcall(os.date, config.date_format)
  if not ok or type(date) ~= "string" then
    date = os.date("%Y-%m-%d")
  end
  return {
    filename = vim.fn.fnamemodify(path, ":t"),
    name = M.identifier(vim.fn.fnamemodify(path, ":t:r")),
    project = project,
    -- Xcode module names replace spaces/dashes/dots with underscores
    module_name = (project:gsub("[%s%-%.]", "_")),
    author = M.author(config),
    date = date,
  }
end

---The Xcode-style comment header block (ends with one blank line).
---@param ctx table from M.context
---@return string[]
function M.lines(ctx)
  return {
    "//",
    "//  " .. ctx.filename,
    "//  " .. ctx.project,
    "//",
    "//  Created by " .. ctx.author .. " on " .. ctx.date .. ".",
    "//",
    "",
  }
end

return M

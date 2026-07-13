---xcode-templates.nvim — Xcode-style "New File" templates for Neovim.
local M = {}

local Config = require("xcode-templates.config")
local Header = require("xcode-templates.header")
local Templates = require("xcode-templates.templates")
local Ui = require("xcode-templates.ui")

local uv = vim.uv or vim.loop

---@type XcodeTemplates.Config
M.config = Config.defaults()

local function notify(msg, level)
  vim.notify("xcode-templates: " .. msg, level or vim.log.levels.ERROR)
end

---Builtin sections + user sections from `opts.templates`.
---@return table[]
local function all_sections()
  local out = vim.deepcopy(Templates.sections)
  vim.list_extend(out, M.config.templates or {})
  return out
end

local function buf_is_empty(buf)
  if vim.api.nvim_buf_line_count(buf) > 1 then
    return false
  end
  return (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or "") == ""
end

---Look up a template by id (exact) or display name (case-insensitive).
---@param id_or_name string
---@return table|nil
function M.get(id_or_name)
  local needle = id_or_name:lower()
  for _, sec in ipairs(all_sections()) do
    for _, it in ipairs(sec.items) do
      if it.id == id_or_name or it.name:lower() == needle then
        return it
      end
    end
  end
end

---Insert header + template body into `buf` (does not check emptiness — see M.fill).
---@param buf integer 0 for current
---@param template table
function M.apply(buf, template)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local ctx = Header.context(vim.api.nvim_buf_get_name(buf), M.config)
  local lines, header_len = {}, 0
  if M.config.header then
    lines = Header.lines(ctx)
    header_len = #lines
  end
  local ok, body = pcall(template.body, ctx)
  if not ok then
    notify(("template `%s` failed: %s"):format(template.id or template.name, body))
    return
  end
  vim.list_extend(lines, body)
  if #lines == 0 then
    lines = { "" }
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    local target = #lines
    if template.cursor then
      target = math.min(header_len + template.cursor, #lines)
    end
    pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
  end
end

---Create `path` on disk from a template and open it. Scripting/test entry point.
---@param template string|table template id/name or template table
---@param path string file path; the template's extension is appended if none given
---@return integer|nil buf, string|nil err
function M.create(template, path)
  if type(template) == "string" then
    local t = M.get(template)
    if not t then
      return nil, ("unknown template: %s"):format(template)
    end
    template = t
  end
  if type(path) ~= "string" or vim.trim(path) == "" or path:sub(-1) == "/" then
    return nil, "invalid file name"
  end
  if not path:match("%.%w+$") then
    path = path .. (template.ext or ".swift")
  end
  local full = vim.fn.fnamemodify(path, ":p")
  if uv.fs_stat(full) then
    return nil, ("file already exists: %s"):format(vim.fn.fnamemodify(full, ":~:."))
  end
  local okmk, mkerr = pcall(vim.fn.mkdir, vim.fs.dirname(full), "p")
  if not okmk then
    return nil, ("could not create directory: %s"):format(mkerr)
  end
  local okedit, editerr = pcall(vim.cmd.edit, vim.fn.fnameescape(full))
  if not okedit then
    return nil, ("could not open buffer: %s"):format(editerr)
  end
  local buf = vim.api.nvim_get_current_buf()
  M.apply(buf, template)
  local okw, werr = pcall(vim.cmd.write)
  if not okw then
    return nil, ("could not write %s: %s"):format(vim.fn.fnamemodify(full, ":~:."), werr)
  end
  return buf
end

---Prompt for the new file's path (with file completion) and create it.
---Re-prompts (keeping the input) when the file already exists.
---@param template table
---@param default string|nil prefill; defaults to the current file's directory
local function prompt_filename(template, default)
  if default == nil then
    local bufname = vim.api.nvim_buf_get_name(0)
    default = ""
    if bufname ~= "" and not bufname:match("^%w+://") then
      local dir = vim.fn.fnamemodify(bufname, ":.:h")
      if dir ~= "." then
        default = dir .. "/"
      end
    end
  end
  vim.ui.input({
    prompt = ("New %s: "):format(template.name),
    default = default,
    completion = "file",
  }, function(input)
    if not input or vim.trim(input) == "" or input:sub(-1) == "/" then
      return -- cancelled
    end
    local _, err = M.create(template, input)
    if err then
      notify(err)
      if err:find("already exists", 1, true) then
        vim.schedule(function()
          prompt_filename(template, input)
        end)
      end
    end
  end)
end

---Fill an (empty) buffer from a template, showing the chooser when none is given.
---@param buf integer|nil 0/nil for current
---@param template table|nil skip the chooser by passing a template
function M.fill(buf, template)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not buf_is_empty(buf) then
    notify("buffer is not empty — refusing to overwrite", vim.log.levels.WARN)
    return
  end
  if template then
    return M.apply(buf, template)
  end
  Ui.pick(all_sections(), { columns = M.config.columns }, function(item)
    if item and vim.api.nvim_buf_is_valid(buf) and buf_is_empty(buf) then
      M.apply(buf, item)
    end
  end)
end

---Create a new file: chooser (unless a template is given) → filename prompt → create.
---@param template table|nil
function M.new(template)
  if template then
    return prompt_filename(template)
  end
  Ui.pick(all_sections(), { columns = M.config.columns }, function(item)
    if item then
      prompt_filename(item)
    end
  end)
end

---@param opts XcodeTemplates.Config|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", Config.defaults(), opts or {})
  Config.validate(M.config)

  local group = vim.api.nvim_create_augroup("xcode_templates", { clear = true })
  vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost" }, {
    group = group,
    pattern = "*.swift",
    desc = "Open the template chooser for empty Swift files",
    callback = function(ev)
      if not M.config.auto_pick or #vim.api.nvim_list_uis() == 0 then
        return
      end
      -- scheduled: let the buffer finish loading, and skip if M.create/new
      -- already filled it (or the user moved on) by the time this runs
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(ev.buf) then
          return
        end
        if vim.api.nvim_get_current_buf() ~= ev.buf or vim.bo[ev.buf].buftype ~= "" then
          return
        end
        if buf_is_empty(ev.buf) then
          M.fill(ev.buf)
        end
      end)
    end,
  })

  vim.api.nvim_create_user_command("XcodeTemplate", function(cmd)
    local template
    local arg = vim.trim(cmd.args)
    if arg ~= "" then
      template = M.get(arg)
      if not template then
        notify(("unknown template: %s (see :XcodeTemplate <Tab>)"):format(arg))
        return
      end
    end
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype == "" and vim.bo[buf].filetype == "swift" and buf_is_empty(buf) then
      M.fill(buf, template)
    else
      M.new(template)
    end
  end, {
    nargs = "*",
    desc = "Create a new file from an Xcode-style template",
    complete = function(arglead)
      local out = {}
      for _, sec in ipairs(all_sections()) do
        for _, it in ipairs(sec.items) do
          if it.id:find(arglead:lower(), 1, true) == 1 then
            out[#out + 1] = it.id
          end
        end
      end
      return out
    end,
  })
end

return M

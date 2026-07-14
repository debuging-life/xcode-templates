---xcode-templates.nvim — Xcode-style "New File" templates for Neovim.
local M = {}

local Config = require("xcode-templates.config")
local Header = require("xcode-templates.header")
local Templates = require("xcode-templates.templates")
local Ui = require("xcode-templates.ui")
local Detect = require("xcode-templates.detect")
local Pbxproj = require("xcode-templates.pbxproj")
local Ai = require("xcode-templates.ai")

local uv = vim.uv or vim.loop

---@type XcodeTemplates.Config
M.config = Config.defaults()

local function notify(msg, level)
  vim.notify("xcode-templates: " .. msg, level or vim.log.levels.ERROR)
end

---The Claude-drafted template — shown only when an API key is available.
local AI_ITEM = {
  id = "ai-suggest",
  name = "AI Suggestion",
  icon = "󰚩",
  desc = "Claude drafts this file from its name, project, and sibling files",
  ai = true,
  body = function(ctx)
    return {
      "// ✻ Claude will draft this file based on:",
      ("//   • file name: %s"):format(ctx.filename),
      ("//   • project: %s"):format(ctx.project),
      "//   • the other Swift files in the same folder",
      "",
    }
  end,
}

---Builtin sections + user sections from `opts.templates` (+ AI when configured).
---@return table[]
local function all_sections()
  local out = vim.deepcopy(Templates.sections)
  vim.list_extend(out, M.config.templates or {})
  if Ai.available(M.config) then
    out[#out + 1] = { title = "Intelligence", items = { AI_ITEM } }
  end
  return out
end

local function buf_is_empty(buf)
  if vim.api.nvim_buf_line_count(buf) > 1 then
    return false
  end
  return (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or "") == ""
end

---Make sure the current window can display a file buffer. Invoked from an
---explorer/picker, the current window is 'winfixbuf'-locked (or a prompt),
---so `:edit` there fails and the file is never opened or written. Move to
---an existing normal window in this tab, or split one off.
local function ensure_normal_window()
  local function usable(win)
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      return false -- floating (picker, prompt, our chooser)
    end
    local fixed = false
    pcall(function()
      fixed = vim.wo[win].winfixbuf
    end)
    return not fixed and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
  end
  if usable(vim.api.nvim_get_current_win()) then
    return
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if usable(win) then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
  vim.cmd("botright vsplit")
end

---Restart sourcekit-lsp so it re-reads compiler arguments from fresh build logs.
local function restart_sourcekit()
  vim.defer_fn(function()
    local ok = pcall(vim.cmd, "LspRestart sourcekit")
    if not ok then
      for _, client in ipairs(vim.lsp.get_clients({ name = "sourcekit" })) do
        client:stop()
      end
    end
  end, 300)
end

---Silent background build after creating a file — what Xcode does invisibly.
---On success the LSP restarts, so the new file's types resolve everywhere
---without the user pressing anything.
---@param pbx string path to project.pbxproj
---@return boolean started
local function index_build(pbx)
  if M._index_building then
    return true
  end
  local root = vim.fs.dirname(vim.fs.dirname(pbx))
  local container, scheme, platform
  local sf = io.open(root .. "/.nvim/xcodebuild/settings.json", "r")
  if sf then
    local ok, s = pcall(vim.json.decode, sf:read("*a"))
    sf:close()
    if ok and type(s) == "table" then
      container = s.workspaceFile or s.projectFile or s.xcodeproj
      scheme = s.scheme
      platform = s.platform
    end
  end
  if not scheme then
    local bf = io.open(root .. "/buildServer.json", "r")
    if bf then
      local ok, b = pcall(vim.json.decode, bf:read("*a"))
      bf:close()
      if ok and type(b) == "table" then
        scheme = b.scheme
        container = container or b.workspace
      end
    end
  end
  if not scheme then
    return false -- no scheme known yet (run :XcodebuildSetup once)
  end
  container = container or vim.fs.dirname(pbx)
  M._index_building = true
  local flag = container:match("%.xcworkspace$") and "-workspace" or "-project"
  local dest = "generic/platform=" .. (platform or "iOS Simulator")
  vim.notify("xcode-templates: ⚙ background index build…", vim.log.levels.INFO)
  local ok = pcall(vim.system, { "xcodebuild", flag, container, "-scheme", scheme, "-destination", dest, "build" }, {
    text = true,
  }, function(res)
    vim.schedule(function()
      M._index_building = false
      if res.code == 0 then
        restart_sourcekit()
        vim.notify("xcode-templates: ⚙ index updated — new types resolve everywhere", vim.log.levels.INFO)
      else
        vim.notify(
          "xcode-templates: background index build failed — run a build (<leader>ib) to see the errors",
          vim.log.levels.WARN
        )
      end
    end)
  end)
  if not ok then
    M._index_building = false
    return false
  end
  return true
end

---Explorers don't watch for files created outside their own actions —
---nudge any open one to reload after we write a file to disk.
local function refresh_explorers()
  -- snacks explorer (LazyVim default): re-run the finder
  pcall(function()
    for _, picker in ipairs(require("snacks.picker").get({ source = "explorer" }) or {}) do
      picker:find()
    end
  end)
  pcall(function()
    require("neo-tree.sources.manager").refresh("filesystem")
  end)
  pcall(function()
    require("nvim-tree.api").tree.reload()
  end)
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

-- options (Xcode's second step) ---------------------------------------------

local function option_default(opt, ctx)
  local d = opt.default
  if type(d) == "function" then
    local ok, val = pcall(d, ctx)
    d = ok and val or nil
  end
  if d ~= nil then
    return d
  end
  if opt.choices then
    return opt.choices[1]
  end
  return ""
end

---Resolved default values for every option of a template (no prompting).
local function option_defaults(template, ctx)
  local out = {}
  for _, opt in ipairs(template.options or {}) do
    out[opt.key] = option_default(opt, ctx)
  end
  return out
end

---Prompt for each template option sequentially, like Xcode's "Next" page.
---@param template table
---@param ctx table
---@param cb fun(values: table|nil) nil means the user cancelled
local function resolve_options(template, ctx, cb)
  local opts = template.options or {}
  if #opts == 0 then
    return cb({})
  end
  local values = {}
  local function step(i)
    local opt = opts[i]
    if not opt then
      return cb(values)
    end
    local default = option_default(opt, ctx)
    if opt.choices then
      -- default first so plain <CR> confirms it
      local choices = { default }
      for _, c in ipairs(opt.choices) do
        if c ~= default then
          choices[#choices + 1] = c
        end
      end
      vim.ui.select(choices, { prompt = opt.label }, function(choice)
        if choice == nil then
          return cb(nil)
        end
        values[opt.key] = choice
        step(i + 1)
      end)
    else
      vim.ui.input({ prompt = opt.label .. ": ", default = default }, function(input)
        if input == nil then
          return cb(nil)
        end
        values[opt.key] = vim.trim(input) ~= "" and vim.trim(input) or default
        step(i + 1)
      end)
    end
  end
  step(1)
end

-- applying -------------------------------------------------------------------

---Insert header + template body into `buf` (does not check emptiness — see M.fill).
---@param buf integer 0 for current
---@param template table
---@param options table|nil resolved option values; defaults are used when omitted
function M.apply(buf, template, options)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local ctx = Header.context(vim.api.nvim_buf_get_name(buf), M.config)
  ctx.options = vim.tbl_extend("force", option_defaults(template, ctx), options or {})
  if template.ai then
    return M._apply_ai(buf, ctx)
  end
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

local AI_PLACEHOLDER = "// ✻ Claude is drafting this file…"

---Insert the header + a placeholder, then replace the body when Claude answers.
---@param buf integer
---@param ctx table
function M._apply_ai(buf, ctx)
  local header_lines = M.config.header and Header.lines(ctx) or {}
  local header_len = #header_lines
  local lines = vim.list_extend(vim.list_extend({}, header_lines), { AI_PLACEHOLDER, "" })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local Progress = require("xcode-templates.progress")
  Progress.start({ title = "✻ asking Claude", text = ("drafting %s…"):format(ctx.filename) })

  local hint = Detect.detect(ctx.path).template
  Ai.generate(ctx, M.config, hint, function(body, err)
    Progress.stop()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    -- only touch the buffer if the placeholder is still there (user didn't type)
    local marker = vim.api.nvim_buf_get_lines(buf, header_len, header_len + 1, false)[1] or ""
    if marker ~= AI_PLACEHOLDER then
      return
    end
    if err then
      vim.api.nvim_buf_set_lines(buf, header_len, header_len + 1, false, {
        "// AI generation failed: " .. err,
      })
      notify(err)
      return
    end
    local final = vim.list_extend(M.config.header and Header.lines(ctx) or {}, body)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, final)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and vim.fn.filereadable(name) == 1 then
      vim.api.nvim_buf_call(buf, function()
        pcall(vim.cmd.write)
      end)
    end
    notify(("Claude drafted %s"):format(ctx.filename), vim.log.levels.INFO)
  end)
end

---Create `path` on disk from a template and open it. Scripting/test entry point.
---@param template string|table template id/name or template table
---@param path string file path; the template's extension is appended if none given
---@param options table|nil resolved option values
---@return integer|nil buf, string|nil err
function M.create(template, path, options)
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
  ensure_normal_window()
  local okedit, editerr = pcall(vim.cmd.edit, vim.fn.fnameescape(full))
  if not okedit then
    return nil, ("could not open buffer: %s"):format(editerr)
  end
  local buf = vim.api.nvim_get_current_buf()
  M.apply(buf, template, options)
  local okw, werr = pcall(vim.cmd.write)
  if not okw then
    return nil, ("could not write %s: %s"):format(vim.fn.fnamemodify(full, ":~:."), werr)
  end
  if M.config.add_to_project then
    Pbxproj.add(full, template.target == "test" and "test" or "app")
  end
  refresh_explorers()
  if full:match("%.swift$") then
    local pbx = Pbxproj.find_pbxproj(full)
    if pbx then
      local building = M.config.auto_index_build and index_build(pbx)
      if not building and not M._lsp_hint_shown then
        M._lsp_hint_shown = true
        vim.notify(
          "xcode-templates: sourcekit-lsp indexes new files after a build — run one (<leader>ib) for full completions",
          vim.log.levels.INFO
        )
      end
    end
  end
  return buf
end

-- flows ------------------------------------------------------------------------

---Header + body preview lines for the chooser's preview pane.
local function preview_builder(path)
  return function(item)
    local ctx = Header.context(path, M.config)
    ctx.options = option_defaults(item, ctx)
    local lines = M.config.header and Header.lines(ctx) or {}
    local ok, body = pcall(item.body, ctx)
    if not ok then
      return { "// preview unavailable: " .. tostring(body) }
    end
    return vim.list_extend(vim.list_extend({}, lines), body)
  end
end

local function open_chooser(path, preselect, on_item)
  Ui.pick(all_sections(), {
    columns = M.config.columns,
    preselect = preselect,
    preview = M.config.preview and preview_builder(path) or nil,
  }, on_item)
end

---Turn a path into a directory: itself when it is one, else its parent.
local function dir_of(path)
  if not path or path == "" then
    return nil
  end
  path = vim.fn.fnamemodify(path, ":p")
  if vim.fn.isdirectory(path) == 1 then
    return path
  end
  return vim.fs.dirname(path)
end

---Directory to prefill in the filename prompt. From a regular file buffer:
---that file's folder. From a file explorer (snacks, neo-tree, nvim-tree,
---oil): the folder of the node under the cursor.
---@return string|nil absolute directory
local function base_dir()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local ft = vim.bo[buf].filetype

  -- regular file buffer → its own directory
  if vim.bo[buf].buftype == "" and name ~= "" and not name:match("^%w+://") then
    return vim.fs.dirname(vim.fn.fnamemodify(name, ":p"))
  end

  -- oil.nvim: the buffer *is* the directory
  if name:match("^oil://") then
    local ok, oil = pcall(require, "oil")
    local dir = ok and oil.get_current_dir()
    if dir then
      return vim.fn.fnamemodify(dir, ":p")
    end
  end

  -- snacks explorer (LazyVim default): selected item of the explorer picker
  do
    local ok, picker_mod = pcall(require, "snacks.picker")
    if ok and picker_mod.get then
      local okg, pickers = pcall(picker_mod.get, { source = "explorer" })
      for _, picker in ipairs(okg and pickers or {}) do
        local oki, item = pcall(picker.current, picker)
        local dir = oki and item and dir_of(item.file or item._path)
        if dir then
          return dir
        end
      end
    end
  end

  -- neo-tree: node under the cursor in the filesystem source
  do
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
      local oks, state = pcall(manager.get_state, "filesystem")
      local node = oks and state and state.tree and state.tree:get_node()
      local dir = node and dir_of(node.path or node:get_id())
      if dir then
        return dir
      end
    end
  end

  -- nvim-tree (cursor APIs are only valid inside the tree window)
  if ft == "NvimTree" then
    local ok, api = pcall(require, "nvim-tree.api")
    if ok then
      local okn, node = pcall(api.tree.get_node_under_cursor)
      local dir = okn and node and dir_of(node.absolute_path)
      if dir then
        return dir
      end
    end
  end

  return nil
end

---Prompt for the new file's path (with file completion) and create it.
---Re-prompts (keeping the input) when the file already exists.
---@param template table
---@param default string|nil prefill; defaults to the selected folder (explorer) or current file's directory
local function prompt_filename(template, default)
  if default == nil then
    default = ""
    local dir = base_dir()
    if dir then
      -- relative to cwd when inside it, absolute/home-relative otherwise
      local rel = vim.fn.fnamemodify(dir, ":~:.")
      if rel ~= "" and rel ~= "." then
        default = rel:sub(-1) == "/" and rel or (rel .. "/")
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
    local ctx = Header.context(input, M.config)
    resolve_options(template, ctx, function(values)
      if values == nil then
        return -- cancelled at the options step
      end
      local _, err = M.create(template, input, values)
      if err then
        notify(err)
        if err:find("already exists", 1, true) then
          vim.schedule(function()
            prompt_filename(template, input)
          end)
        end
      end
    end)
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
  local path = vim.api.nvim_buf_get_name(buf)

  local function finish(item)
    if not item then
      return
    end
    local ctx = Header.context(path, M.config)
    resolve_options(item, ctx, function(values)
      if values == nil then
        return
      end
      if vim.api.nvim_buf_is_valid(buf) and buf_is_empty(buf) then
        M.apply(buf, item, values)
      end
    end)
  end

  if template then
    return finish(template)
  end

  local preselect
  if M.config.detect.enabled and path ~= "" then
    local d = Detect.detect(path)
    if d.template and M.get(d.template) then
      if d.confident and M.config.detect.auto_apply then
        return finish(M.get(d.template))
      end
      preselect = d.template
    end
  end
  open_chooser(path, preselect, finish)
end

---Create a new file: chooser (unless a template is given) → filename prompt
---(with path completion) → options → create.
---@param template table|nil
function M.new(template)
  local function with_template(item)
    if item then
      prompt_filename(item)
    end
  end
  if template then
    return with_template(template)
  end
  local placeholder = vim.fs.joinpath(vim.fn.getcwd(), "MyFile.swift")
  open_chooser(placeholder, nil, with_template)
end

---Ask Claude for a ghost-text completion at the cursor (insert or normal mode).
---Implements the comment above the cursor, finishes the current construct, etc.
function M.suggest()
  require("xcode-templates.suggest").trigger(M.config)
end

---Ask Claude about the visual selection (review / implement / refactor / custom).
---@param instruction string|nil prompts when nil
---@param srow integer|nil explicit range (1-indexed) instead of the visual marks
---@param erow integer|nil
function M.ask(instruction, srow, erow)
  require("xcode-templates.suggest").ask(M.config, instruction, srow, erow)
end

---Voice question: toggle microphone capture; the transcript is asked about
---the code around the cursor and answered in a movable float (read-only —
---your file is never touched).
function M.voice()
  local Voice = require("xcode-templates.voice")
  local Progress = require("xcode-templates.progress")
  if Voice.recording() then
    Progress.retitle("✻ transcribing")
    return Voice.stop()
  end
  local win = vim.api.nvim_get_current_win()
  local timer
  local function stop_timer()
    if timer then
      pcall(function()
        timer:stop()
        timer:close()
      end)
      timer = nil
    end
  end
  Voice.toggle(M.config, {
    on_start = function(mode)
      Progress.start({
        title = "🎤 listening",
        text = mode == "record" and "● recording…" or "speak now…",
        hint = "trigger again to stop",
      })
      if mode == "record" then
        -- whisper transcribes on stop, so show elapsed time while recording
        local secs = 0
        timer = (vim.uv or vim.loop).new_timer()
        timer:start(1000, 1000, vim.schedule_wrap(function()
          secs = secs + 1
          Progress.update(("● recording — %d:%02d  (whisper transcribes when you stop)"):format(
            math.floor(secs / 60),
            secs % 60
          ))
        end))
      end
    end,
    on_partial = function(text)
      Progress.update(text) -- live transcription (stream backend)
    end,
    on_phase = function()
      stop_timer()
      Progress.retitle("✻ transcribing (whisper)")
      Progress.update("…")
    end,
    on_error = function()
      stop_timer()
      Progress.stop()
    end,
    on_transcript = function(text)
      stop_timer()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
      end
      require("xcode-templates.suggest").ask_at_cursor(M.config, text, "voice")
    end,
  })
end

---Typed variant of the same: answer in a float, never edits the file.
---@param question string|nil prompts when nil
function M.how(question)
  local function run(q)
    if q and vim.trim(q) ~= "" then
      require("xcode-templates.suggest").ask_at_cursor(M.config, q, "how")
    end
  end
  if question and question ~= "" then
    return run(question)
  end
  vim.ui.input({ prompt = "Ask AI (answer opens in a float): " }, run)
end

---Browse this project's AI history (`clear` wipes it). Selecting an exchange
---reopens its answer in the float, with follow-up available.
---@param arg string|nil "clear"
function M.history(arg)
  local History = require("xcode-templates.history")
  if arg == "clear" then
    return History.clear(M.config)
  end
  History.browse(M.config, function(entry)
    require("xcode-templates.suggest").float({
      title = "✻ " .. (entry.question:len() > 60 and (entry.question:sub(1, 57) .. "…") or entry.question),
      lines = vim.split(entry.answer, "\n", { plain = true }),
      follow_up = function(q)
        require("xcode-templates.suggest").ask_at_cursor(M.config, q, entry.kind)
      end,
    })
  end)
end

---Keep the header's `//  File.swift` line in sync after renames.
---@param buf integer|nil
function M.sync_header(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local l = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
  if l[1] == "//" and l[2] and l[2]:match("^//  %S.*%.swift%s*$") then
    local actual = "//  " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    if l[2] ~= actual then
      vim.api.nvim_buf_set_lines(buf, 1, 2, false, { actual })
    end
  end
end

-- setup --------------------------------------------------------------------------

---@param opts XcodeTemplates.Config|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", Config.defaults(), opts or {})
  -- list-valued options replace the default outright (deep_extend would
  -- merge them element-wise with the default list)
  for _, path in ipairs({
    { "templates" },
    { "ai", "voice", "record" },
    { "ai", "voice", "transcribe" },
    { "ai", "voice", "command" },
  }) do
    local user_value = vim.tbl_get(opts or {}, unpack(path))
    if user_value ~= nil then
      local node = M.config
      for i = 1, #path - 1 do
        node = node[path[i]]
      end
      node[path[#path]] = user_value
    end
  end
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

  if M.config.lsp_restart_on_build then
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "XcodebuildBuildFinished",
      desc = "Restart sourcekit-lsp after a build so new files/types resolve",
      callback = function(ev)
        if type(ev.data) == "table" and ev.data.success == false then
          return -- failed build: stale args would stay stale anyway
        end
        restart_sourcekit()
      end,
    })
  end

  if M.config.sync_header_on_rename then
    vim.api.nvim_create_autocmd({ "BufFilePost", "BufWritePre" }, {
      group = group,
      pattern = "*.swift",
      desc = "Keep the //  File.swift header line in sync with the file name",
      callback = function(ev)
        M.sync_header(ev.buf)
      end,
    })
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "swift",
    desc = "AI keymaps for swift buffers",
    callback = function(ev)
      local function bmap(lhs, fn, desc)
        if lhs then
          vim.keymap.set({ "i", "n" }, lhs, fn, { buffer = ev.buf, desc = desc })
        end
      end
      bmap(M.config.ai.suggest.keymap, M.suggest, "AI: complete at cursor")
      bmap(M.config.ai.keymaps.how, function()
        vim.cmd.stopinsert()
        M.how()
      end, "AI: ask how (answer float)")
      bmap(M.config.ai.keymaps.voice, function()
        vim.cmd.stopinsert()
        M.voice()
      end, "AI: voice question")
    end,
  })

  vim.api.nvim_create_user_command("XcodeSuggest", function()
    M.suggest()
  end, { desc = "AI: complete at the cursor (ghost text)" })

  vim.api.nvim_create_user_command("XcodeHistory", function(cmd)
    M.history(cmd.args ~= "" and cmd.args or nil)
  end, {
    nargs = "?",
    complete = function()
      return { "clear" }
    end,
    desc = "AI: browse this project's Q&A history (`clear` wipes it)",
  })

  vim.api.nvim_create_user_command("XcodeVoice", function()
    M.voice()
  end, { desc = "AI: voice question — answer opens in a movable float" })

  vim.api.nvim_create_user_command("XcodeHow", function(cmd)
    M.how(cmd.args ~= "" and cmd.args or nil)
  end, { nargs = "*", desc = "AI: ask how to do something — answer opens in a movable float" })

  vim.api.nvim_create_user_command("XcodeAI", function(cmd)
    if cmd.range > 0 then
      M.ask(cmd.args ~= "" and cmd.args or nil, cmd.line1, cmd.line2)
    else
      M.suggest()
    end
  end, {
    nargs = "*",
    range = true,
    desc = "AI: ask about the selection (with range) or complete at the cursor",
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

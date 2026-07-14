---Inline AI assistance:
---  trigger()  — ghost-text completion at the cursor (implements the comment
---               above the cursor, finishes the statement you're writing, …)
---  ask()      — act on a visual selection: review, implement, refactor, or
---               any custom instruction; the answer can replace the selection
local M = {}

local Ai = require("xcode-templates.ai")
local Header = require("xcode-templates.header")

local ns = vim.api.nvim_create_namespace("xcode_templates_suggest")

vim.api.nvim_set_hl(0, "XcodeTemplatesGhost", { link = "Comment", default = true })

---@type table|nil the active ghost suggestion { buf, row, col, lines }
local state = nil

local function clear()
  if not state then
    return
  end
  local s = state
  state = nil
  if vim.api.nvim_buf_is_valid(s.buf) then
    vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
    for _, mode in ipairs({ "i", "n" }) do
      pcall(vim.keymap.del, mode, "<Tab>", { buffer = s.buf })
      pcall(vim.keymap.del, mode, "<C-e>", { buffer = s.buf })
    end
  end
  pcall(vim.api.nvim_del_augroup_by_name, "xcode_templates_suggest_active")
end

M.dismiss = clear

---Insert the active suggestion at its anchor and move the cursor after it.
function M.accept()
  if not state then
    return
  end
  local s = state
  clear()
  if not vim.api.nvim_buf_is_valid(s.buf) then
    return
  end
  vim.api.nvim_buf_set_text(s.buf, s.row, s.col, s.row, s.col, s.lines)
  local last_row = s.row + #s.lines - 1
  local last_col = #s.lines == 1 and (s.col + #s.lines[1]) or #s.lines[#s.lines]
  pcall(vim.api.nvim_win_set_cursor, 0, { last_row + 1, last_col })
end

---Render `lines` as ghost text anchored at (row, col), 0-indexed.
---<Tab> accepts, <C-e> dismisses, any edit or cursor move dismisses.
---@return boolean shown
function M.show(buf, row, col, lines)
  clear()
  local virt_lines = {}
  for i = 2, #lines do
    virt_lines[#virt_lines + 1] = { { lines[i], "XcodeTemplatesGhost" } }
  end
  local ok = pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, col, {
    virt_text = { { lines[1], "XcodeTemplatesGhost" } },
    virt_text_pos = "inline",
    virt_lines = #virt_lines > 0 and virt_lines or nil,
  })
  if not ok then
    return false
  end
  state = { buf = buf, row = row, col = col, lines = lines }
  vim.keymap.set({ "i", "n" }, "<Tab>", M.accept, { buffer = buf, nowait = true, desc = "Accept AI suggestion" })
  vim.keymap.set({ "i", "n" }, "<C-e>", M.dismiss, { buffer = buf, nowait = true, desc = "Dismiss AI suggestion" })
  local group = vim.api.nvim_create_augroup("xcode_templates_suggest_active", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged", "CursorMoved", "CursorMovedI", "InsertLeave", "BufLeave" }, {
    group = group,
    buffer = buf,
    callback = function()
      -- accept() clears state before editing, so this only fires for user actions
      clear()
      return true
    end,
  })
  return true
end

---Request a completion at the cursor and show it as ghost text.
---@param config XcodeTemplates.Config
function M.trigger(config)
  if not Ai.available(config) then
    return vim.notify(
      "xcode-templates: no Claude credentials — set $ANTHROPIC_API_KEY or run `ant auth login`",
      vim.log.levels.WARN
    )
  end
  clear()
  local buf = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1] - 1, pos[2]
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  if not vim.api.nvim_get_mode().mode:find("^[iR]") then
    col = #line -- normal mode: complete at the end of the current line
  end

  local scfg = config.ai.suggest
  local total = vim.api.nvim_buf_line_count(buf)
  local before = vim.api.nvim_buf_get_lines(buf, math.max(0, row - scfg.context_before), row, false)
  local after = vim.api.nvim_buf_get_lines(buf, row + 1, math.min(total, row + 1 + scfg.context_after), false)
  local ctx = Header.context(vim.api.nvim_buf_get_name(buf), config)

  local system = table.concat({
    "You are an inline Swift code completion engine.",
    "Output ONLY the code to insert at the ⟨CURSOR⟩ marker — no markdown fences, no commentary,",
    "and never repeat code that already appears before or after the marker.",
    "Match the file's indentation and style. Complete one natural unit",
    "(the current statement, function, or type) and stop.",
    "If the line at or above the marker is a comment describing something to build,",
    "implement exactly that, starting on a new line below the comment.",
  }, " ")
  local user = table.concat({
    ("File: %s — project %s"):format(ctx.filename, ctx.project),
    "Code around the cursor:",
    table.concat(before, "\n"),
    line:sub(1, col) .. "⟨CURSOR⟩" .. line:sub(col + 1),
    table.concat(after, "\n"),
  }, "\n")

  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local Progress = require("xcode-templates.progress")
  Progress.start({ title = "✻ asking Claude", text = ("completing %s:%d…"):format(ctx.filename, row + 1) })
  Ai.complete(system, user, config, scfg.max_tokens, function(lines, err)
    Progress.stop()
    if err then
      return vim.notify("xcode-templates: " .. err, vim.log.levels.WARN)
    end
    while #lines > 0 and vim.trim(lines[#lines]) == "" do
      table.remove(lines)
    end
    if #lines == 0 then
      return vim.notify("xcode-templates: Claude returned nothing to insert", vim.log.levels.WARN)
    end
    if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
      return vim.notify("xcode-templates: buffer changed — suggestion discarded", vim.log.levels.INFO)
    end
    -- a completion triggered at the end of a comment belongs on the next line
    if col == #line and line:match("^%s*//") and lines[1] ~= "" then
      table.insert(lines, 1, "")
    end
    if M.show(buf, row, col, lines) then
      vim.notify(("✻ %d-line suggestion — <Tab> accept · <C-e> dismiss"):format(#lines), vim.log.levels.INFO)
    end
  end)
end

local function looks_like_prose(lines)
  for _, l in ipairs(lines) do
    if vim.trim(l) ~= "" then
      return l:match("^%s*[#>%*%-]") ~= nil or l:match("^%s*%d+%.") ~= nil
    end
  end
  return false
end

---Show an AI answer in a persistent, movable float.
---
---With `question` + `send`, the float is a **conversation thread**: `f`
---prompts for a follow-up and the new Q&A appends into the SAME window
---(with an inline "✻ thinking…" placeholder) instead of opening a new one.
---Keys: arrows move · `f` ask more · `a` apply latest answer (when a source
---range was given; stays open in thread mode for iterating) · `o` pop out to
---a native window · `y` yank latest answer · `q`/<Esc> close.
---@param opts { title: string, lines: string[], question?: string, send?: fun(q: string, cb: fun(lines: string[]|nil, err: string|nil)), src_buf?: integer, srow?: integer, erow?: integer, follow_up?: fun(question: string) }
---@return integer win
function M.float(opts)
  local thread = opts.question ~= nil and opts.send ~= nil
  local turns = { { q = opts.question, lines = opts.lines } }
  local pending = false
  local erow_apply = opts.erow
  local can_apply = opts.src_buf ~= nil

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  pcall(vim.treesitter.start, buf, looks_like_prose(opts.lines) and "markdown" or "swift")

  local ns_t = vim.api.nvim_create_namespace("xcode_templates_thread")
  local width = math.min(100, math.max(46, vim.o.columns - 20))
  local win
  local cfg = {
    relative = "editor",
    width = width,
    height = 3,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = 2,
    style = "minimal",
    border = "rounded",
    title = " " .. opts.title .. " ",
    title_pos = "center",
    footer = "",
    footer_pos = "center",
  }

  local function latest_lines()
    for i = #turns, 1, -1 do
      if turns[i].lines then
        return turns[i].lines
      end
    end
    return {}
  end

  local function footer_text()
    if pending then
      return "  ✻ waiting for Claude…  "
    end
    local parts = { "⇄ move" }
    if thread or opts.follow_up then
      parts[#parts + 1] = "f ask more"
    end
    if can_apply then
      parts[#parts + 1] = "a apply"
    end
    parts[#parts + 1] = "o pop out"
    parts[#parts + 1] = "y yank"
    parts[#parts + 1] = "q close"
    return "  " .. table.concat(parts, " · ") .. "  "
  end

  local function render()
    local out, marks = {}, {}
    local focus_line = 1
    if not thread then
      out = turns[1].lines
    else
      for i, t in ipairs(turns) do
        if i > 1 then
          out[#out + 1] = ""
          out[#out + 1] = string.rep("─", width - 4)
          marks[#marks + 1] = { #out - 1, "XcodeTemplatesSeparator" }
        end
        out[#out + 1] = "❯ " .. t.q
        focus_line = #out
        marks[#marks + 1] = { #out - 1, "XcodeTemplatesSection" }
        out[#out + 1] = ""
        if t.lines then
          vim.list_extend(out, t.lines)
        else
          out[#out + 1] = "✻ thinking…"
          marks[#marks + 1] = { #out - 1, "XcodeTemplatesMuted" }
        end
      end
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns_t, 0, -1)
    for _, m in ipairs(marks) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_t, m[1], 0, {
        end_col = #out[m[1] + 1],
        hl_group = m[2],
        strict = false,
      })
    end
    cfg.height = math.max(3, math.min(#out + 1, vim.o.lines - 8))
    cfg.footer = footer_text()
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_set_config, win, cfg)
      pcall(vim.api.nvim_win_set_cursor, win, { math.min(focus_line, #out), 0 })
    end
  end

  render()
  cfg.row = math.max(0, math.floor((vim.o.lines - cfg.height) / 2) - 1)
  win = vim.api.nvim_open_win(buf, true, cfg)
  vim.wo[win].wrap = true
  render()

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  local function move(dr, dc)
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    cfg.row = math.max(0, math.min((cfg.row or 0) + dr, vim.o.lines - cfg.height - 4))
    cfg.col = math.max(0, math.min((cfg.col or 0) + dc, vim.o.columns - width - 2))
    pcall(vim.api.nvim_win_set_config, win, cfg)
  end

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  map("q", close, "Close")
  map("<esc>", close, "Close")
  map("<up>", function() move(-2, 0) end, "Move up")
  map("<down>", function() move(2, 0) end, "Move down")
  map("<left>", function() move(0, -4) end, "Move left")
  map("<right>", function() move(0, 4) end, "Move right")
  map("y", function()
    vim.fn.setreg('"', table.concat(latest_lines(), "\n") .. "\n")
    vim.notify("xcode-templates: answer yanked")
  end, "Yank the latest answer")
  map("o", function()
    -- pop out into a native window — draggable to any screen
    local tmp = vim.fn.tempname() .. ".md"
    vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmp)
    if vim.fn.executable("open") == 1 then
      vim.system({ "open", "-e", tmp })
      vim.notify("xcode-templates: opened in TextEdit — drag it to any screen")
    else
      vim.notify("xcode-templates: saved to " .. tmp, vim.log.levels.INFO)
    end
  end, "Pop out to a native window")
  if can_apply then
    map("a", function()
      local answer = latest_lines()
      if not vim.api.nvim_buf_is_valid(opts.src_buf) or #answer == 0 then
        return
      end
      vim.api.nvim_buf_set_lines(opts.src_buf, opts.srow - 1, erow_apply, false, answer)
      erow_apply = opts.srow + #answer - 1 -- keep iterative applies aligned
      vim.notify(("xcode-templates: replaced lines %d–%d"):format(opts.srow, erow_apply))
      if not thread then
        close()
      end
    end, "Apply the latest answer as replacement")
  end
  if thread then
    map("f", function()
      if pending then
        return
      end
      vim.ui.input({ prompt = "Follow-up: " }, function(q)
        if not q or vim.trim(q) == "" then
          return
        end
        pending = true
        turns[#turns + 1] = { q = q, lines = nil }
        render()
        opts.send(q, function(answer, err)
          pending = false
          turns[#turns].lines = err and { "⚠ " .. err } or answer
          render()
        end)
      end)
    end, "Ask a follow-up in this window")
  elseif opts.follow_up then
    map("f", function()
      vim.ui.input({ prompt = "Follow-up: " }, function(q)
        if q and vim.trim(q) ~= "" then
          close()
          opts.follow_up(q)
        end
      end)
    end, "Ask a follow-up (with conversation context)")
  end
  return win
end

---Back-compat wrapper: answer float for a selection, with apply enabled.
function M.result_float(src_buf, srow, erow, lines)
  return M.float({
    title = ("✻ Claude — lines %d–%d"):format(srow, erow),
    lines = lines,
    src_buf = src_buf,
    srow = srow,
    erow = erow,
  })
end

---Ask a free-form question about the code around the cursor; the answer opens
---in a float and the source file is never modified. Used by voice input.
---Recent exchanges are replayed as conversation context, so follow-ups work.
---@param config XcodeTemplates.Config
---@param question string
---@param kind string|nil "how" (default) or "voice" — recorded in history
function M.ask_at_cursor(config, question, kind)
  if not Ai.available(config) then
    return vim.notify(
      "xcode-templates: no Claude credentials — set $ANTHROPIC_API_KEY or run `ant auth login`",
      vim.log.levels.WARN
    )
  end
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local scfg = config.ai.suggest
  local total = vim.api.nvim_buf_line_count(buf)
  local around = vim.api.nvim_buf_get_lines(
    buf,
    math.max(0, row - scfg.context_before),
    math.min(total, row + 1 + scfg.context_after),
    false
  )
  local ctx = Header.context(vim.api.nvim_buf_get_name(buf), config)
  local system = table.concat({
    "You are a senior Swift engineer answering a colleague's question inside Neovim.",
    "They want to be SHOWN how to do it — do not assume you can edit their files.",
    "Reply in concise markdown: the code first, then at most a few short bullet points.",
  }, " ")
  local History = require("xcode-templates.history")
  local Progress = require("xcode-templates.progress")

  -- reusable for follow-ups: same code context, fresh question, history replayed
  local function send(q, cb)
    local user = table.concat({
      ("File: %s — project %s"):format(ctx.filename, ctx.project),
      "Code around the cursor:",
      table.concat(around, "\n"),
      "",
      "Question: " .. q,
    }, "\n")
    Ai.complete(system, user, config, scfg.max_tokens, function(lines, err)
      if err then
        return cb(nil, err)
      end
      while #lines > 0 and vim.trim(lines[#lines]) == "" do
        table.remove(lines)
      end
      if #lines == 0 then
        return cb(nil, "empty answer")
      end
      History.add(config, {
        kind = kind or "how",
        file = ctx.filename,
        question = q,
        answer = table.concat(lines, "\n"),
      })
      cb(lines)
    end, History.recent_messages(config))
  end

  Progress.start({ title = "✻ asking Claude", text = '"' .. question .. '"' })
  send(question, function(lines, err)
    Progress.stop()
    if err then
      return vim.notify("xcode-templates: " .. err, vim.log.levels.WARN)
    end
    M.float({
      title = "✻ " .. (question:len() > 60 and (question:sub(1, 57) .. "…") or question),
      question = question,
      lines = lines,
      send = send,
    })
  end)
end

---Ask Claude about a selection: review, implement, refactor, or anything.
---@param config XcodeTemplates.Config
---@param instruction string|nil prompts when nil
---@param srow integer|nil 1-indexed selection start (defaults to the visual selection)
---@param erow integer|nil 1-indexed selection end
function M.ask(config, instruction, srow, erow)
  if not Ai.available(config) then
    return vim.notify(
      "xcode-templates: no Claude credentials — set $ANTHROPIC_API_KEY or run `ant auth login`",
      vim.log.levels.WARN
    )
  end
  local buf = vim.api.nvim_get_current_buf()
  if not (srow and erow) then
    local mode = vim.api.nvim_get_mode().mode
    if mode:find("^[vV\22]") then
      srow, erow = vim.fn.line("v"), vim.fn.line(".")
      vim.cmd("normal! \27") -- leave visual mode so the input prompt behaves
    else
      srow, erow = vim.fn.line("'<"), vim.fn.line("'>")
    end
  end
  if not srow or srow == 0 or not erow or erow == 0 then
    return vim.notify("xcode-templates: select some code first (visual mode)", vim.log.levels.WARN)
  end
  if srow > erow then
    srow, erow = erow, srow
  end
  local code = vim.api.nvim_buf_get_lines(buf, srow - 1, erow, false)

  local function run(instr)
    if not instr or vim.trim(instr) == "" then
      return
    end
    local ctx = Header.context(vim.api.nvim_buf_get_name(buf), config)
    local system = table.concat({
      "You are a senior Swift engineer working inside Neovim on a code selection.",
      "If the instruction asks you to write, implement, refactor, fix, optimize, or otherwise",
      "transform the code, reply with ONLY the replacement Swift code for the selection —",
      "no markdown fences, no commentary.",
      "If the instruction asks a question or requests a review, explanation, or check,",
      "reply in concise markdown: short bullet points, most important finding first.",
    }, " ")
    local History = require("xcode-templates.history")
    local Progress = require("xcode-templates.progress")

    -- reusable for follow-ups: same selection, fresh instruction, history replayed
    local function send(q, cb)
      local user = table.concat({
        ("File: %s — project %s (lines %d–%d selected)"):format(ctx.filename, ctx.project, srow, erow),
        "Selected code:",
        table.concat(code, "\n"),
        "",
        "Instruction: " .. q,
      }, "\n")
      Ai.complete(system, user, config, config.ai.suggest.max_tokens, function(lines, err)
        if err then
          return cb(nil, err)
        end
        while #lines > 0 and vim.trim(lines[#lines]) == "" do
          table.remove(lines)
        end
        if #lines == 0 then
          return cb(nil, "empty answer")
        end
        History.add(config, {
          kind = "ask",
          file = ctx.filename,
          question = q,
          answer = table.concat(lines, "\n"),
          srow = srow,
          erow = erow,
        })
        cb(lines)
      end, History.recent_messages(config))
    end

    Progress.start({ title = "✻ asking Claude", text = ('"%s" on lines %d–%d…'):format(instr, srow, erow) })
    send(instr, function(lines, err)
      Progress.stop()
      if err then
        return vim.notify("xcode-templates: " .. err, vim.log.levels.WARN)
      end
      M.float({
        title = ("✻ Claude — lines %d–%d"):format(srow, erow),
        question = instr,
        lines = lines,
        send = send,
        src_buf = buf,
        srow = srow,
        erow = erow,
      })
    end)
  end

  if instruction and vim.trim(instruction) ~= "" then
    run(instruction)
  else
    vim.ui.input({ prompt = "Ask AI (review / implement / refactor / fix / …): " }, run)
  end
end

return M

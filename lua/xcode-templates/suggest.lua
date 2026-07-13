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
  vim.notify("✻ asking Claude…", vim.log.levels.INFO)
  Ai.complete(system, user, config, scfg.max_tokens, function(lines, err)
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

---Show an AI answer in a float. `a` replaces the original selection with it,
---`y` yanks it, `q`/<Esc> closes. Exposed for tests.
function M.result_float(src_buf, srow, erow, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  pcall(vim.treesitter.start, buf, looks_like_prose(lines) and "markdown" or "swift")

  local width = math.min(100, math.max(46, vim.o.columns - 20))
  local height = math.max(3, math.min(#lines + 1, vim.o.lines - 8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    style = "minimal",
    border = "rounded",
    title = (" ✻ Claude — lines %d–%d "):format(srow, erow),
    title_pos = "center",
    footer = "  a apply as replacement · y yank · q close  ",
    footer_pos = "center",
  })
  vim.wo[win].wrap = true

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<esc>", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "y", function()
    vim.fn.setreg('"', table.concat(lines, "\n") .. "\n")
    vim.notify("xcode-templates: answer yanked")
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "a", function()
    close()
    if vim.api.nvim_buf_is_valid(src_buf) then
      vim.api.nvim_buf_set_lines(src_buf, srow - 1, erow, false, lines)
      vim.notify(("xcode-templates: replaced lines %d–%d"):format(srow, erow))
    end
  end, { buffer = buf, nowait = true })
  return win
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
    local user = table.concat({
      ("File: %s — project %s (lines %d–%d selected)"):format(ctx.filename, ctx.project, srow, erow),
      "Selected code:",
      table.concat(code, "\n"),
      "",
      "Instruction: " .. instr,
    }, "\n")
    vim.notify("✻ asking Claude…", vim.log.levels.INFO)
    Ai.complete(system, user, config, config.ai.suggest.max_tokens, function(lines, err)
      if err then
        return vim.notify("xcode-templates: " .. err, vim.log.levels.WARN)
      end
      while #lines > 0 and vim.trim(lines[#lines]) == "" do
        table.remove(lines)
      end
      if #lines == 0 then
        return vim.notify("xcode-templates: empty answer", vim.log.levels.WARN)
      end
      M.result_float(buf, srow, erow, lines)
    end)
  end

  if instruction and vim.trim(instruction) ~= "" then
    run(instruction)
  else
    vim.ui.input({ prompt = "Ask AI (review / implement / refactor / fix / …): " }, run)
  end
end

return M

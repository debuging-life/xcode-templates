---The Xcode-style floating template chooser.
---
---Keys inside the chooser:
---  type anything   append to the live fuzzy filter (like Xcode's Filter box)
---  <BS> / <C-u>    delete from / clear the filter
---  arrows, <Tab>   move between templates
---  <C-p>           toggle the code preview pane
---  <CR>            choose the selected template
---  <Esc>           clear the filter, or close when the filter is empty
local M = {}

local ns = vim.api.nvim_create_namespace("xcode_templates_ui")

local CELL_W = 20
local GAP = 2
local PREVIEW_W = 54

---@type table|nil the currently open picker controller (single instance)
local active

local function fit(s, w)
  if vim.fn.strdisplaywidth(s) <= w then
    return s
  end
  while vim.fn.strdisplaywidth(s) > w - 1 and s ~= "" do
    s = vim.fn.strcharpart(s, 0, vim.fn.strchars(s) - 1)
  end
  return s .. "…"
end

local function center(s, w)
  s = fit(s, w)
  local len = vim.fn.strdisplaywidth(s)
  local left = math.floor((w - len) / 2)
  return string.rep(" ", left) .. s .. string.rep(" ", math.max(0, w - len - left))
end

---Open the chooser.
---@param sections table[] { title, items }
---@param opts { columns: integer?, preselect: string?, preview: (fun(item: table): string[])? }|nil
---@param on_choose fun(item: table|nil) called (scheduled) with the chosen item, or nil on cancel
---@return table controller { buf, win, state, close(), set_filter(txt), choose(id) } — used by tests/scripts
function M.pick(sections, opts, on_choose)
  if active and vim.api.nvim_win_is_valid(active.win) then
    vim.api.nvim_set_current_win(active.win)
    return active
  end
  opts = opts or {}

  local ncols = opts.columns or 3
  local width = ncols * CELL_W + (ncols + 1) * GAP
  while width > vim.o.columns - 4 and ncols > 1 do
    ncols = ncols - 1
    width = ncols * CELL_W + (ncols + 1) * GAP
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "xcode-templates"

  local function preview_fits()
    return vim.o.columns >= width + PREVIEW_W + 8
  end

  local state = {
    filter = "",
    sel = 1,
    items = {},
    rows = {},
    win = nil,
    height = 0,
    done = false,
    pv_open = opts.preview ~= nil and preview_fits(),
    pv_buf = nil,
    pv_win = nil,
  }

  local function total_width()
    return width + (state.pv_open and (PREVIEW_W + 2) or 0)
  end

  local function grid_col()
    return math.max(0, math.floor((vim.o.columns - total_width()) / 2))
  end

  local function grid_row()
    return math.max(0, math.floor((vim.o.lines - state.height) / 2) - 1)
  end

  local function footer_text()
    if state.filter ~= "" then
      return ("  filter: %s█  ·  ⌫ edit  ·  esc clear  "):format(state.filter)
    end
    local desc = state.items[state.sel] and state.items[state.sel].item.desc
    if desc and desc ~= "" then
      return "  " .. desc .. "  "
    end
    return "  type to filter · ←↑↓→ move · ↵ choose · esc close  "
  end

  local function win_config()
    return {
      relative = "editor",
      width = width,
      height = state.height,
      col = grid_col(),
      row = grid_row(),
      style = "minimal",
      border = "rounded",
      title = " Choose a template for your new file ",
      title_pos = "center",
      footer = footer_text(),
      footer_pos = "center",
    }
  end

  local function pv_config()
    return {
      relative = "editor",
      width = PREVIEW_W,
      height = state.height,
      col = grid_col() + width + 2,
      row = grid_row(),
      style = "minimal",
      border = "rounded",
      title = " Preview ",
      title_pos = "center",
      focusable = false,
    }
  end

  local function update_preview()
    if not state.pv_open or state.done then
      if state.pv_win and vim.api.nvim_win_is_valid(state.pv_win) then
        vim.api.nvim_win_close(state.pv_win, true)
      end
      state.pv_win = nil
      return
    end
    if not (state.pv_buf and vim.api.nvim_buf_is_valid(state.pv_buf)) then
      state.pv_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[state.pv_buf].buftype = "nofile"
      vim.bo[state.pv_buf].bufhidden = "hide"
      if not pcall(vim.treesitter.start, state.pv_buf, "swift") then
        pcall(function()
          vim.bo[state.pv_buf].syntax = "swift"
        end)
      end
    end
    local rec = state.items[state.sel]
    local lines = {}
    if rec and opts.preview then
      local ok, res = pcall(opts.preview, rec.item)
      lines = (ok and type(res) == "table") and res or { "// preview unavailable: " .. tostring(res) }
    end
    vim.api.nvim_buf_set_lines(state.pv_buf, 0, -1, false, lines)
    if state.pv_win and vim.api.nvim_win_is_valid(state.pv_win) then
      pcall(vim.api.nvim_win_set_config, state.pv_win, pv_config())
    else
      state.pv_win = vim.api.nvim_open_win(state.pv_buf, false, pv_config())
      vim.wo[state.pv_win].wrap = false
    end
  end

  local function filtered()
    if state.filter == "" then
      return sections
    end
    local out = {}
    for _, sec in ipairs(sections) do
      local names = {}
      for _, it in ipairs(sec.items) do
        names[#names + 1] = it.name
      end
      local matched = {}
      local ok, res = pcall(vim.fn.matchfuzzy, names, state.filter)
      if ok then
        for _, n in ipairs(res) do
          matched[n] = true
        end
      else
        for _, n in ipairs(names) do
          if n:lower():find(state.filter:lower(), 1, true) then
            matched[n] = true
          end
        end
      end
      local items = {}
      for _, it in ipairs(sec.items) do
        if matched[it.name] then
          items[#items + 1] = it
        end
      end
      if #items > 0 then
        out[#out + 1] = { title = sec.title, items = items }
      end
    end
    return out
  end

  local function render()
    local lines = { "" }
    local static_hl = {}
    state.items, state.rows = {}, {}

    for _, sec in ipairs(filtered()) do
      local title = string.rep(" ", GAP) .. sec.title
      lines[#lines + 1] = title
      static_hl[#static_hl + 1] = { #lines - 1, 0, #title, "Title" }
      local sep = string.rep(" ", GAP) .. string.rep("─", width - 2 * GAP)
      lines[#lines + 1] = sep
      static_hl[#static_hl + 1] = { #lines - 1, 0, #sep, "WinSeparator" }
      lines[#lines + 1] = ""
      for i = 1, #sec.items, ncols do
        local icon_row, name_row = string.rep(" ", GAP), string.rep(" ", GAP)
        local row_ids = {}
        local base = #lines -- icon row will land at line base+1, name row at base+2
        for c = 0, ncols - 1 do
          local it = sec.items[i + c]
          if not it then
            break
          end
          -- byte offsets recorded while building (icons are multibyte)
          local rec = { item = it, l1 = base + 1, l2 = base + 2, s1 = #icon_row, s2 = #name_row }
          icon_row = icon_row .. center(it.icon, CELL_W)
          rec.e1 = #icon_row
          name_row = name_row .. center(it.name, CELL_W)
          rec.e2 = #name_row
          icon_row = icon_row .. string.rep(" ", GAP)
          name_row = name_row .. string.rep(" ", GAP)
          state.items[#state.items + 1] = rec
          row_ids[#row_ids + 1] = #state.items
        end
        lines[#lines + 1] = icon_row
        lines[#lines + 1] = name_row
        lines[#lines + 1] = ""
        state.rows[#state.rows + 1] = row_ids
      end
    end

    if #state.items == 0 then
      lines[#lines + 1] = string.rep(" ", GAP) .. "No matching templates"
      static_hl[#static_hl + 1] = { #lines - 1, 0, -1, "Comment" }
      lines[#lines + 1] = ""
    end
    state.sel = math.max(1, math.min(state.sel, #state.items))

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(static_hl) do
      local end_col = h[3] == -1 and #lines[h[1] + 1] or h[3]
      vim.api.nvim_buf_set_extmark(buf, ns, h[1], h[2], { end_col = end_col, hl_group = h[4], strict = false })
    end
    for idx, rec in ipairs(state.items) do
      if idx == state.sel then
        vim.api.nvim_buf_set_extmark(buf, ns, rec.l1 - 1, rec.s1, { end_col = rec.e1, hl_group = "PmenuSel", strict = false })
        vim.api.nvim_buf_set_extmark(buf, ns, rec.l2 - 1, rec.s2, { end_col = rec.e2, hl_group = "PmenuSel", strict = false })
      else
        vim.api.nvim_buf_set_extmark(buf, ns, rec.l1 - 1, rec.s1, { end_col = rec.e1, hl_group = "Special", strict = false })
      end
    end

    if state.win and vim.api.nvim_win_is_valid(state.win) then
      if #state.items > 0 then
        local rec = state.items[state.sel]
        pcall(vim.api.nvim_win_set_cursor, state.win, { rec.l1, rec.s1 })
      end
      pcall(vim.api.nvim_win_set_config, state.win, win_config())
      update_preview()
    end
  end

  local function close(choice)
    if state.done then
      return
    end
    state.done = true
    active = nil
    if state.pv_win and vim.api.nvim_win_is_valid(state.pv_win) then
      vim.api.nvim_win_close(state.pv_win, true)
    end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
    if on_choose then
      vim.schedule(function()
        on_choose(choice)
      end)
    end
  end

  local function confirm()
    local rec = state.items[state.sel]
    if not rec then
      return -- "No matching templates" — nothing to choose
    end
    close(rec.item)
  end

  local function move(dx, dy)
    if #state.items == 0 then
      return
    end
    if dy == 0 then
      state.sel = ((state.sel - 1 + dx) % #state.items) + 1
    else
      local r, c
      for ri, row in ipairs(state.rows) do
        for ci, idx in ipairs(row) do
          if idx == state.sel then
            r, c = ri, ci
          end
        end
      end
      if r then
        local row = state.rows[math.max(1, math.min(r + dy, #state.rows))]
        state.sel = row[math.min(c, #row)]
      end
    end
    render()
  end

  -- first render (no window yet) to measure content height and build items
  render()
  if opts.preselect then
    for i, rec in ipairs(state.items) do
      if rec.item.id == opts.preselect then
        state.sel = i
        break
      end
    end
  end
  state.height = math.min(vim.api.nvim_buf_line_count(buf), math.max(vim.o.lines - 6, 5))
  state.win = vim.api.nvim_open_win(buf, true, win_config())
  vim.wo[state.win].cursorline = false
  vim.wo[state.win].wrap = false
  vim.wo[state.win].scrolloff = 2
  render()

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end

  map("<cr>", confirm)
  map("<esc>", function()
    if state.filter ~= "" then
      state.filter = ""
      state.sel = 1
      render()
    else
      close(nil)
    end
  end)
  map("<left>", function() move(-1, 0) end)
  map("<right>", function() move(1, 0) end)
  map("<up>", function() move(0, -1) end)
  map("<down>", function() move(0, 1) end)
  map("<tab>", function() move(1, 0) end)
  map("<s-tab>", function() move(-1, 0) end)
  map("<c-p>", function()
    if opts.preview then
      state.pv_open = not state.pv_open and preview_fits()
      render()
    end
  end)
  map("<bs>", function()
    if state.filter ~= "" then
      state.filter = vim.fn.strcharpart(state.filter, 0, vim.fn.strchars(state.filter) - 1)
      state.sel = 1
      render()
    end
  end)
  map("<c-u>", function()
    if state.filter ~= "" then
      state.filter = ""
      state.sel = 1
      render()
    end
  end)
  -- every printable key types into the live filter (Xcode's Filter box)
  for code = 32, 126 do
    local ch = string.char(code)
    local lhs = ch
    if ch == " " then
      lhs = "<space>"
    elseif ch == "<" then
      lhs = "<lt>"
    end
    map(lhs, function()
      state.filter = state.filter .. ch
      state.sel = 1
      render()
    end)
  end

  local group = vim.api.nvim_create_augroup("xcode_templates_ui_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      close(nil)
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if state.done then
        return true -- delete this autocmd
      end
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        state.pv_open = state.pv_open and preview_fits()
        state.height = math.min(vim.api.nvim_buf_line_count(buf), math.max(vim.o.lines - 6, 5))
        render()
      end
    end,
  })

  local ctrl = {
    buf = buf,
    win = state.win,
    state = state,
    close = function()
      close(nil)
    end,
    set_filter = function(txt)
      state.filter = txt or ""
      state.sel = 1
      render()
    end,
    choose = function(id)
      for i, rec in ipairs(state.items) do
        if rec.item.id == id then
          state.sel = i
          break
        end
      end
      confirm()
    end,
  }
  active = ctrl
  return ctrl
end

return M

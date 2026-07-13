---A small top-right status float: live voice transcription while listening,
---then an animated spinner while Claude works. One instance at a time.
local M = {}

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---@type table|nil { buf, win, cfg, timer, frame, title }
local state = nil

local function wrap(text, width)
  local out, line = {}, ""
  for word in text:gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + #word + 1 <= width then
      line = line .. " " .. word
    else
      out[#out + 1] = line
      line = word
    end
  end
  out[#out + 1] = line
  return out
end

---Close the status float and stop the spinner.
function M.stop()
  if not state then
    return
  end
  local s = state
  state = nil
  if s.timer then
    pcall(function()
      s.timer:stop()
      s.timer:close()
    end)
  end
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    pcall(vim.api.nvim_win_close, s.win, true)
  end
end

---Replace the body text (grows the float up to 6 lines, keeps the tail visible).
---@param text string
function M.update(text)
  if not state or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local width = state.cfg.width - 2
  local lines = wrap(text == "" and "…" or text, width)
  while #lines > 6 do
    table.remove(lines, 1) -- keep the most recent speech visible
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  state.cfg.height = math.max(1, #lines)
  pcall(vim.api.nvim_win_set_config, state.win, state.cfg)
end

---Change only the title (e.g. "🎤 listening" → "✻ transcribing").
---@param title string
function M.retitle(title)
  if not state then
    return
  end
  state.title = title
  state.cfg.title = " " .. title .. " "
  if vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_config, state.win, state.cfg)
  end
end

---Open (or replace) the status float.
---@param opts { title: string, text: string?, hint: string?, spin: boolean? }
function M.start(opts)
  M.stop()
  local width = math.min(52, math.max(30, vim.o.columns - 6))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local cfg = {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = vim.o.columns - 1,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " " .. opts.title .. " ",
    title_pos = "left",
    footer = opts.hint and (" " .. opts.hint .. " ") or nil,
    footer_pos = opts.hint and "right" or nil,
    focusable = false,
    zindex = 200,
  }
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, cfg)
  if not ok then
    return
  end
  vim.wo[win].wrap = true
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatTitle:XcodeTemplatesSection"
  state = { buf = buf, win = win, cfg = cfg, title = opts.title, frame = 1 }
  M.update(opts.text or "")

  if opts.spin ~= false then
    local timer = (vim.uv or vim.loop).new_timer()
    state.timer = timer
    timer:start(120, 120, vim.schedule_wrap(function()
      if not state or state.timer ~= timer then
        return
      end
      state.frame = state.frame % #FRAMES + 1
      state.cfg.title = (" %s %s "):format(FRAMES[state.frame], state.title)
      if vim.api.nvim_win_is_valid(state.win) then
        pcall(vim.api.nvim_win_set_config, state.win, state.cfg)
      end
    end))
  end
end

return M

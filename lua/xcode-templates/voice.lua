---Voice capture for AI questions.
---
---Runs a speech-to-text CLI (default: `hear`, macOS on-device speech —
---`brew install hear`) and collects its stdout as the transcript. Any
---command that prints recognized text to stdout works (whisper wrappers,
---etc.) via `ai.voice.command`. Toggle semantics: first call starts
---listening, second call stops and delivers the transcript.
local M = {}

---@type table|nil active recording { handle }
local rec = nil

function M.recording()
  return rec ~= nil
end

---Stop the active recording (the exit callback delivers the transcript).
function M.stop()
  if rec and rec.handle then
    pcall(function()
      rec.handle:kill("sigint")
    end)
  end
end

---Start (or stop, when already listening) voice capture.
---@param config XcodeTemplates.Config
---@param on_transcript fun(text: string) called on the main loop
function M.toggle(config, on_transcript)
  if rec then
    return M.stop()
  end
  local cmd = config.ai.voice.command
  if type(cmd) == "string" then
    cmd = { cmd }
  end
  if vim.fn.executable(cmd[1]) == 0 then
    return vim.notify(
      ("xcode-templates: `%s` not found — install a speech-to-text CLI (macOS: `brew install hear`),"
        .. " or set `ai.voice.command`"):format(cmd[1]),
      vim.log.levels.WARN
    )
  end

  local chunks = {}
  local ok, handle = pcall(vim.system, cmd, {
    text = true,
    stdout = function(_, data)
      if data then
        chunks[#chunks + 1] = data
      end
    end,
  }, function(res)
    vim.schedule(function()
      rec = nil
      local text = vim.trim(table.concat(chunks, ""):gsub("%s+", " "))
      if text == "" then
        local err = vim.trim(res.stderr or "")
        return vim.notify(
          "xcode-templates: heard nothing" .. (err ~= "" and (" (" .. err .. ")") or ""),
          vim.log.levels.WARN
        )
      end
      on_transcript(text)
    end)
  end)
  if not ok then
    return vim.notify("xcode-templates: could not start voice capture: " .. tostring(handle), vim.log.levels.ERROR)
  end
  rec = { handle = handle }
  vim.notify("🎤 listening… trigger again to stop", vim.log.levels.INFO)
end

return M

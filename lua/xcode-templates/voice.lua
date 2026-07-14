---Voice capture for AI questions. Two backends:
---
---  "record" (preferred when available) — record the mic with `sox`, then
---  transcribe with whisper-cpp. Much better accuracy for accented speech;
---  the transcript arrives after you stop. The whisper model is downloaded
---  automatically on first use.
---      brew install sox whisper-cpp
---
---  "stream" — a CLI that prints recognized text to stdout while you speak
---  (default `hear`, macOS on-device). Live text, weaker accuracy.
---
---`ai.voice.mode = "auto"` picks record when sox + whisper are installed.
local M = {}

local uv = vim.uv or vim.loop

---@type table|nil active capture { handle }
local rec = nil

function M.recording()
  return rec ~= nil
end

---Stop the active capture (the pipeline then delivers the transcript).
function M.stop()
  if rec and rec.handle then
    pcall(function()
      rec.handle:kill("sigint")
    end)
  end
end

local function first_arg(cmd)
  return type(cmd) == "table" and cmd[1] or cmd
end

---Effective backend for this machine.
---@param config XcodeTemplates.Config
---@return "record"|"stream"
function M.mode(config)
  local v = config.ai.voice
  if v.mode ~= "auto" then
    return v.mode
  end
  if vim.fn.executable(first_arg(v.record)) == 1 and vim.fn.executable(first_arg(v.transcribe)) == 1 then
    return "record"
  end
  return "stream"
end

---Substitute $FILE / $MODEL / $LANG placeholders in a command list.
local function subst(cmd, vars)
  local out = {}
  for _, a in ipairs(cmd) do
    out[#out + 1] = (a:gsub("%$(%u+)", vars))
  end
  return out
end

function M.model_path(config)
  return vim.fn.stdpath("data") .. "/xcode-templates/ggml-" .. config.ai.voice.model .. ".bin"
end

---Download the whisper model on first use (only when `transcribe` uses $MODEL).
---@param cb fun(ok: boolean, err: string|nil)
function M.ensure_model(config, cb)
  local needs = false
  for _, a in ipairs(config.ai.voice.transcribe) do
    if a:find("$MODEL", 1, true) then
      needs = true
      break
    end
  end
  if not needs then
    return cb(true)
  end
  local path = M.model_path(config)
  if uv.fs_stat(path) then
    return cb(true)
  end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local url = ("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-%s.bin"):format(config.ai.voice.model)
  vim.notify(
    ("xcode-templates: downloading whisper `%s` model (one-time)…"):format(config.ai.voice.model),
    vim.log.levels.INFO
  )
  vim.system({ "curl", "-fsSL", "-o", path .. ".part", url }, { text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        os.rename(path .. ".part", path)
        cb(true)
      else
        pcall(os.remove, path .. ".part")
        cb(false, "whisper model download failed: " .. vim.trim(res.stderr or ("curl exit " .. res.code)))
      end
    end)
  end)
end

local function fail(handlers, msg)
  if handlers.on_error then
    handlers.on_error()
  end
  vim.notify("xcode-templates: " .. msg, vim.log.levels.WARN)
end

---record backend: sox → wav → whisper → transcript
local function start_record(config, handlers)
  local v = config.ai.voice
  local wav = vim.fn.tempname() .. ".wav"
  local ok, handle = pcall(vim.system, subst(v.record, { FILE = wav }), { text = true }, function(res)
    vim.schedule(function()
      rec = nil
      local stat = uv.fs_stat(wav)
      if not stat or stat.size < 2000 then
        return fail(handlers, "no audio captured" .. (res.stderr and res.stderr ~= "" and (" (" .. vim.trim(res.stderr) .. ")") or ""))
      end
      if handlers.on_phase then
        handlers.on_phase("transcribing")
      end
      M.ensure_model(config, function(mok, merr)
        if not mok then
          pcall(os.remove, wav)
          return fail(handlers, merr)
        end
        local tcmd = subst(v.transcribe, { FILE = wav, MODEL = M.model_path(config), LANG = v.language })
        vim.system(tcmd, { text = true }, function(tres)
          vim.schedule(function()
            pcall(os.remove, wav)
            local text = vim.trim((tres.stdout or ""):gsub("%[BLANK_AUDIO%]", ""):gsub("%s+", " "))
            if tres.code ~= 0 or text == "" then
              return fail(handlers, "transcription failed: " .. vim.trim(tres.stderr ~= "" and tres.stderr or "no speech recognized"))
            end
            handlers.on_transcript(text)
          end)
        end)
      end)
    end)
  end)
  if not ok then
    return fail(handlers, "could not start recording: " .. tostring(handle))
  end
  rec = { handle = handle }
  if handlers.on_start then
    handlers.on_start("record")
  end
end

---stream backend: CLI prints text while you speak (live partials)
local function start_stream(config, handlers)
  local cmd = config.ai.voice.command
  if type(cmd) == "string" then
    cmd = { cmd }
  end
  local chunks = {}
  local ok, handle = pcall(vim.system, cmd, {
    text = true,
    stdout = function(_, data)
      if data then
        chunks[#chunks + 1] = data
        if handlers.on_partial then
          vim.schedule(function()
            if rec then
              handlers.on_partial(vim.trim(table.concat(chunks, ""):gsub("%s+", " ")))
            end
          end)
        end
      end
    end,
  }, function(res)
    vim.schedule(function()
      rec = nil
      local text = vim.trim(table.concat(chunks, ""):gsub("%s+", " "))
      if text == "" then
        local err = vim.trim(res.stderr or "")
        return fail(handlers, "heard nothing" .. (err ~= "" and (" (" .. err .. ")") or ""))
      end
      handlers.on_transcript(text)
    end)
  end)
  if not ok then
    return fail(handlers, "could not start voice capture: " .. tostring(handle))
  end
  rec = { handle = handle }
  if handlers.on_start then
    handlers.on_start("stream")
  end
end

---Start (or stop, when already listening) voice capture.
---@param config XcodeTemplates.Config
---@param handlers { on_transcript: fun(text: string), on_partial: (fun(text: string))?, on_start: (fun(mode: string))?, on_phase: (fun(phase: string))?, on_error: (fun())? }
function M.toggle(config, handlers)
  if rec then
    return M.stop()
  end
  local mode = M.mode(config)
  if mode == "record" then
    local v = config.ai.voice
    for _, c in ipairs({ v.record, v.transcribe }) do
      if vim.fn.executable(first_arg(c)) == 0 then
        return vim.notify(
          ("xcode-templates: `%s` not found — voice (whisper) needs: brew install sox whisper-cpp"):format(first_arg(c)),
          vim.log.levels.WARN
        )
      end
    end
    return start_record(config, handlers)
  end
  if vim.fn.executable(first_arg(config.ai.voice.command)) == 0 then
    return vim.notify(
      ("xcode-templates: `%s` not found — install whisper (brew install sox whisper-cpp, recommended)"
        .. " or a streaming STT CLI (github.com/sveinbjornt/hear)"):format(first_arg(config.ai.voice.command)),
      vim.log.levels.WARN
    )
  end
  return start_stream(config, handlers)
end

return M

---Claude-powered file drafting via the Anthropic Messages API.
---
---Raw HTTP through curl (there is no official Lua SDK). The API key is
---resolved from `ai.api_key` (string or function) or $ANTHROPIC_API_KEY,
---and is passed to curl via stdin (`--config -`) so it never appears in
---the process list or logs.
local M = {}

local API_URL = "https://api.anthropic.com/v1/messages"

---Resolve the API key: config override (string or function) → $ANTHROPIC_API_KEY.
---@param config XcodeTemplates.Config
---@return string|nil
function M.api_key(config)
  local k = config.ai and config.ai.api_key
  if type(k) == "function" then
    local ok, v = pcall(k)
    k = ok and v or nil
  end
  if type(k) == "string" and k ~= "" then
    return k
  end
  local env = vim.env.ANTHROPIC_API_KEY
  if env and env ~= "" then
    return env
  end
  return nil
end

local function anthropic_config_dir()
  return vim.env.ANTHROPIC_CONFIG_DIR or (vim.env.HOME .. "/.config/anthropic")
end

---True when the `ant` CLI is installed and `ant auth login` has stored a profile.
---@return boolean
function M.oauth_available()
  if vim.fn.executable("ant") == 0 then
    return false
  end
  return vim.fn.glob(anthropic_config_dir() .. "/credentials/*.json") ~= ""
end

---@param config XcodeTemplates.Config
---@return boolean
function M.available(config)
  return config.ai ~= nil
    and config.ai.enabled
    and vim.fn.executable("curl") == 1
    and (M.api_key(config) ~= nil or M.oauth_available())
end

---Resolve auth headers (async): API key directly, else a fresh OAuth access
---token from `ant auth print-credentials`. Headers are delivered in curl
---`--config` format so secrets go via stdin, never on the argv.
---@param config XcodeTemplates.Config
---@param cb fun(header_config: string|nil, err: string|nil)
local function with_credentials(config, cb)
  local key = M.api_key(config)
  if key then
    return cb(('header = "x-api-key: %s"'):format(key))
  end
  if not M.oauth_available() then
    return cb(nil, "no API key and no `ant auth login` profile — set $ANTHROPIC_API_KEY or run `ant auth login`")
  end
  -- --access-token prints the bare token (refreshing it first if needed)
  vim.system({ "ant", "auth", "print-credentials", "--access-token" }, { text = true }, function(res)
    vim.schedule(function()
      local token = vim.trim(res.stdout or "")
      if res.code ~= 0 or token == "" then
        return cb(nil, "could not get an OAuth token — re-run `ant auth login` (" .. vim.trim(res.stderr or "expired profile?") .. ")")
      end
      -- OAuth tokens use Authorization: Bearer + the oauth beta header, not x-api-key
      cb(table.concat({
        ('header = "authorization: Bearer %s"'):format(token),
        'header = "anthropic-beta: oauth-2025-04-20"',
      }, "\n"))
    end)
  end)
end

---Names of sibling .swift files (context for the model).
---@param path string
---@param limit integer|nil
---@return string[]
function M.siblings(path, limit)
  local dir = vim.fs.dirname(vim.fn.fnamemodify(path, ":p"))
  local out = {}
  local ok, iter = pcall(vim.fs.dir, dir)
  if not ok or type(iter) ~= "function" then
    return out
  end
  for name, t in iter do
    if t == "file" and name:match("%.swift$") then
      out[#out + 1] = name
      if #out >= (limit or 30) then
        break
      end
    end
  end
  table.sort(out)
  return out
end

---Build the system + user prompt for a file-drafting request.
---@param ctx table template context (filename, project, path, ...)
---@param siblings string[]
---@param hint string|nil detected template id, if any
---@return string system, string user
function M.build_prompt(ctx, siblings, hint)
  local system = table.concat({
    "You write a single, complete, idiomatic Swift file for an Xcode project.",
    "Output ONLY Swift code — no markdown fences, no commentary, no explanations.",
    "Do not include the top-of-file // comment header block; the caller prepends it.",
    "Use modern Swift: SwiftUI, Observation, async/await, Swift Testing where appropriate.",
    "Scaffold what the file name implies — compilable as-is, no placeholder pseudo-code.",
  }, " ")
  local parts = {
    ("File to create: %s"):format(ctx.filename),
    ("Xcode project/module: %s"):format(ctx.project),
  }
  if hint then
    parts[#parts + 1] = ("Likely file kind: %s"):format(hint)
  end
  if #siblings > 0 then
    parts[#parts + 1] = ("Other Swift files in the same folder: %s"):format(table.concat(siblings, ", "))
  end
  parts[#parts + 1] = "Generate the most likely intended contents of this file."
  return system, table.concat(parts, "\n")
end

---Parse a Messages API response body into code lines.
---@param body string raw JSON response
---@return string[]|nil lines, string|nil err
function M.parse_response(body)
  local ok, json = pcall(vim.json.decode, body)
  if not ok or type(json) ~= "table" then
    return nil, "could not parse the API response"
  end
  if json.error then
    local e = json.error
    return nil, ("API error (%s): %s"):format(e.type or "unknown", e.message or "no message")
  end
  local text = {}
  for _, block in ipairs(json.content or {}) do
    if block.type == "text" and type(block.text) == "string" then
      text[#text + 1] = block.text
    end
  end
  local out = table.concat(text, "")
  -- strip markdown fences in case the model added them anyway
  out = out:gsub("^%s*```%w*\n", ""):gsub("\n```%s*$", "")
  if vim.trim(out) == "" then
    if json.stop_reason == "refusal" then
      return nil, "the request was declined (stop_reason: refusal)"
    end
    return nil, "the model returned an empty response"
  end
  local lines = vim.split(out, "\n", { plain = true })
  if json.stop_reason == "max_tokens" then
    lines[#lines + 1] = "// NOTE: output truncated (max_tokens reached) — increase ai.max_tokens"
  end
  if lines[#lines] ~= "" then
    lines[#lines + 1] = ""
  end
  return lines
end

---Low-level Messages API call shared by file drafting and inline suggestions.
---cb(lines|nil, err|nil) runs on the main loop.
---@param config XcodeTemplates.Config
---@param system string
---@param user string
---@param max_tokens integer|nil defaults to `ai.max_tokens`
---@param cb fun(lines: string[]|nil, err: string|nil)
local function api_call(config, system, user, max_tokens, cb)
  local request = {
    model = config.ai.model,
    max_tokens = max_tokens or config.ai.max_tokens,
    system = system,
    messages = { { role = "user", content = user } },
  }
  -- adaptive thinking + effort exist on Claude 4.6+/5 models; Haiku rejects both
  if not config.ai.model:find("haiku", 1, true) then
    request.thinking = { type = "adaptive" }
    request.output_config = { effort = config.ai.effort }
  end
  local body = vim.json.encode(request)
  with_credentials(config, function(auth_headers, auth_err)
    if not auth_headers then
      return cb(nil, auth_err)
    end
    local okrun, err = pcall(vim.system, {
      "curl",
      "-sS",
      "--max-time",
      "120",
      "-X",
      "POST",
      API_URL,
      "-H",
      "content-type: application/json",
      "-H",
      "anthropic-version: 2023-06-01",
      "--config",
      "-", -- credentials arrive via stdin, never on the argv
      "--data-binary",
      body,
    }, {
      stdin = auth_headers,
      text = true,
    }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          return cb(nil, "request failed: " .. vim.trim(res.stderr or ("curl exit " .. res.code)))
        end
        cb(M.parse_response(res.stdout or ""))
      end)
    end)
    if not okrun then
      cb(nil, "could not start curl: " .. tostring(err))
    end
  end)
end

---Ask Claude to draft a whole file (async). cb(lines|nil, err|nil) on the main loop.
---@param ctx table template context
---@param config XcodeTemplates.Config
---@param hint string|nil detected template id
---@param cb fun(lines: string[]|nil, err: string|nil)
function M.generate(ctx, config, hint, cb)
  local system, user = M.build_prompt(ctx, M.siblings(ctx.path, config.ai.context_files), hint)
  api_call(config, system, user, config.ai.max_tokens, cb)
end

---Free-form completion request (used by inline suggestions).
---@param system string
---@param user string
---@param config XcodeTemplates.Config
---@param max_tokens integer|nil
---@param cb fun(lines: string[]|nil, err: string|nil)
function M.complete(system, user, config, max_tokens, cb)
  api_call(config, system, user, max_tokens, cb)
end

return M

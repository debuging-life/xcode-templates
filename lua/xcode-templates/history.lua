---Per-project AI conversation history.
---
---Every Q&A (voice, :XcodeHow, selection ask) is appended to a JSON store
---keyed by the project root. The most recent turns are replayed to the API
---as real user/assistant messages, so follow-up questions ("now make it
---generic") have context. Browse with :XcodeHistory, wipe with
---:XcodeHistory clear.
local M = {}

---@type table|nil { key, entries }
local cache = nil

local function project_key()
  local root = vim.fs.root(0, { ".git", "Package.swift", "buildServer.json" }) or vim.fn.getcwd()
  return (vim.fn.fnamemodify(root, ":p"):gsub("/+$", ""))
end

local function store_dir(config)
  return config.ai.history.dir or (vim.fn.stdpath("data") .. "/xcode-templates/history")
end

local function store_path(config, key)
  return store_dir(config) .. "/" .. key:gsub("[/\\: ]", "%%") .. ".json"
end

local function load(config)
  local key = project_key()
  if cache and cache.key == key then
    return cache
  end
  cache = { key = key, entries = {} }
  local f = io.open(store_path(config, key), "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(data) == "table" and type(data.entries) == "table" then
      cache.entries = data.entries
    end
  end
  return cache
end

local function save(config, c)
  local path = store_path(config, c.key)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "w")
  if f then
    f:write(vim.json.encode({ version = 1, entries = c.entries }))
    f:close()
  end
end

---Drop the in-memory cache (tests, or after external edits to the store).
function M._invalidate()
  cache = nil
end

---Record one exchange.
---@param config XcodeTemplates.Config
---@param entry { kind: string, file: string?, question: string, answer: string, srow: integer?, erow: integer? }
function M.add(config, entry)
  if not config.ai.history.enabled then
    return
  end
  local c = load(config)
  entry.ts = os.time()
  c.entries[#c.entries + 1] = entry
  while #c.entries > config.ai.history.max_entries do
    table.remove(c.entries, 1)
  end
  save(config, c)
end

---@param config XcodeTemplates.Config
---@return table[] entries oldest → newest
function M.entries(config)
  return load(config).entries
end

function M.clear(config)
  local c = load(config)
  c.entries = {}
  save(config, c)
  vim.notify("xcode-templates: AI history cleared for this project", vim.log.levels.INFO)
end

---The last `ai.history.turns` exchanges as alternating user/assistant
---messages, ready to prepend to an API request.
---@param config XcodeTemplates.Config
---@return { role: string, content: string }[]
function M.recent_messages(config)
  if not config.ai.history.enabled then
    return {}
  end
  local es = load(config).entries
  local out = {}
  for i = math.max(1, #es - config.ai.history.turns + 1), #es do
    out[#out + 1] = { role = "user", content = es[i].question }
    out[#out + 1] = { role = "assistant", content = es[i].answer }
  end
  return out
end

local KIND_ICONS = { voice = "🎤", how = "✍️ ", ask = "▸ " }

---Browse the project's history (newest first); `open_answer(entry)` is called
---with the chosen exchange.
---@param config XcodeTemplates.Config
---@param open_answer fun(entry: table)
function M.browse(config, open_answer)
  local es = load(config).entries
  if #es == 0 then
    return vim.notify("xcode-templates: no AI history for this project yet", vim.log.levels.INFO)
  end
  local items = {}
  for i = #es, 1, -1 do
    items[#items + 1] = es[i]
  end
  vim.ui.select(items, {
    prompt = ("AI history — %d exchange%s"):format(#items, #items == 1 and "" or "s"),
    format_item = function(e)
      local range = e.srow and (":" .. e.srow .. "-" .. (e.erow or e.srow)) or ""
      return ("%s  %s %s%s — %s"):format(
        os.date("%d %b %H:%M", e.ts or 0),
        KIND_ICONS[e.kind] or "• ",
        e.file or "",
        range,
        e.question:sub(1, 72)
      )
    end,
  }, function(e)
    if e then
      open_answer(e)
    end
  end)
end

return M

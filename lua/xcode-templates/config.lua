---Default options + validation.
local M = {}

---@class XcodeTemplates.Config
---@field auto_pick boolean open the chooser when an empty .swift buffer is opened
---@field header boolean prepend the Xcode-style // comment header
---@field date_format string os.date() format used in the header
---@field author string|nil header author; defaults to `git config user.name`, then $USER
---@field columns integer grid columns in the chooser (1-6)
---@field preview boolean show the live code preview pane (when the terminal is wide enough)
---@field detect { enabled: boolean, auto_apply: boolean } smart template detection from file name/location; auto_apply skips the chooser on confident matches
---@field add_to_project boolean register created files in old-style (non-synchronized) Xcode projects via the `xcodeproj` gem
---@field sync_header_on_rename boolean keep the `//  File.swift` header line in sync after renames
---@field ai { enabled: boolean, api_key: string|fun():string|nil, model: string, max_tokens: integer, effort: string, context_files: integer } Claude-powered "AI Suggestion" template; active when an API key is available
---@field templates table[] extra user sections: { title = string, items = { {id, name, icon, desc?, options?, body} } }

---@return XcodeTemplates.Config
function M.defaults()
  return {
    auto_pick = true,
    header = true,
    date_format = "%Y-%m-%d",
    author = nil,
    columns = 3,
    preview = true,
    detect = { enabled = true, auto_apply = false },
    add_to_project = true,
    sync_header_on_rename = true,
    ai = {
      enabled = true,
      api_key = nil, -- string or function; default: $ANTHROPIC_API_KEY
      model = "claude-opus-4-8",
      max_tokens = 16000,
      effort = "low", -- low | medium | high | xhigh | max
      context_files = 30,
      suggest = {
        keymap = "<C-x><C-a>", -- swift buffers, insert+normal; false to disable
        max_tokens = 4096,
        context_before = 120, -- lines of code sent before the cursor
        context_after = 40, -- lines of code sent after the cursor
      },
      voice = {
        mode = "auto", -- "auto" | "record" (whisper, accurate) | "stream" (live text)
        -- record backend (auto-picked when sox + whisper-cpp are installed):
        record = { "sox", "-q", "-d", "-r", "16000", "-c", "1", "$FILE" },
        transcribe = { "whisper-cli", "-m", "$MODEL", "-f", "$FILE", "-l", "$LANG", "-np", "-nt" },
        model = "small", -- whisper model, auto-downloaded (tiny/base/small/medium)
        language = "en",
        -- stream backend fallback: CLI printing recognized text to stdout
        command = { "hear" },
      },
    },
    templates = {},
  }
end

local function check(name, val, expected, optional)
  if optional and val == nil then
    return
  end
  if type(val) ~= expected then
    error(("xcode-templates: option `%s` must be a %s, got %s"):format(name, expected, type(val)), 0)
  end
end

---Validate a merged config, raising a descriptive error on bad options.
---@param cfg XcodeTemplates.Config
function M.validate(cfg)
  check("auto_pick", cfg.auto_pick, "boolean")
  check("header", cfg.header, "boolean")
  check("date_format", cfg.date_format, "string")
  check("author", cfg.author, "string", true)
  check("columns", cfg.columns, "number")
  check("preview", cfg.preview, "boolean")
  check("detect", cfg.detect, "table")
  check("detect.enabled", cfg.detect.enabled, "boolean")
  check("detect.auto_apply", cfg.detect.auto_apply, "boolean")
  check("add_to_project", cfg.add_to_project, "boolean")
  check("sync_header_on_rename", cfg.sync_header_on_rename, "boolean")
  check("ai", cfg.ai, "table")
  check("ai.enabled", cfg.ai.enabled, "boolean")
  check("ai.model", cfg.ai.model, "string")
  check("ai.max_tokens", cfg.ai.max_tokens, "number")
  check("ai.effort", cfg.ai.effort, "string")
  check("ai.context_files", cfg.ai.context_files, "number")
  if cfg.ai.api_key ~= nil and type(cfg.ai.api_key) ~= "string" and type(cfg.ai.api_key) ~= "function" then
    error("xcode-templates: option `ai.api_key` must be a string or a function returning one", 0)
  end
  if not vim.tbl_contains({ "low", "medium", "high", "xhigh", "max" }, cfg.ai.effort) then
    error("xcode-templates: option `ai.effort` must be one of low/medium/high/xhigh/max", 0)
  end
  check("ai.suggest", cfg.ai.suggest, "table")
  check("ai.suggest.max_tokens", cfg.ai.suggest.max_tokens, "number")
  check("ai.suggest.context_before", cfg.ai.suggest.context_before, "number")
  check("ai.suggest.context_after", cfg.ai.suggest.context_after, "number")
  if cfg.ai.suggest.keymap ~= nil and cfg.ai.suggest.keymap ~= false and type(cfg.ai.suggest.keymap) ~= "string" then
    error("xcode-templates: option `ai.suggest.keymap` must be a string or false", 0)
  end
  check("ai.voice", cfg.ai.voice, "table")
  if type(cfg.ai.voice.command) ~= "string" and type(cfg.ai.voice.command) ~= "table" then
    error("xcode-templates: option `ai.voice.command` must be a string or a list of arguments", 0)
  end
  if not vim.tbl_contains({ "auto", "record", "stream" }, cfg.ai.voice.mode) then
    error("xcode-templates: option `ai.voice.mode` must be auto/record/stream", 0)
  end
  check("ai.voice.record", cfg.ai.voice.record, "table")
  check("ai.voice.transcribe", cfg.ai.voice.transcribe, "table")
  check("ai.voice.model", cfg.ai.voice.model, "string")
  check("ai.voice.language", cfg.ai.voice.language, "string")
  check("templates", cfg.templates, "table")
  if cfg.columns < 1 or cfg.columns > 6 then
    error("xcode-templates: option `columns` must be between 1 and 6", 0)
  end
  for si, sec in ipairs(cfg.templates) do
    if type(sec.title) ~= "string" or type(sec.items) ~= "table" then
      error(("xcode-templates: templates[%d] must have `title` (string) and `items` (table)"):format(si), 0)
    end
    for ii, it in ipairs(sec.items) do
      for _, field in ipairs({ "id", "name", "icon" }) do
        if type(it[field]) ~= "string" then
          error(("xcode-templates: templates[%d].items[%d].%s must be a string"):format(si, ii, field), 0)
        end
      end
      if type(it.body) ~= "function" then
        error(
          ("xcode-templates: templates[%d].items[%d].body must be a function(ctx) -> string[]"):format(si, ii),
          0
        )
      end
      if it.options ~= nil then
        if type(it.options) ~= "table" then
          error(("xcode-templates: templates[%d].items[%d].options must be a list"):format(si, ii), 0)
        end
        for oi, opt in ipairs(it.options) do
          if type(opt.key) ~= "string" or type(opt.label) ~= "string" then
            error(
              ("xcode-templates: templates[%d].items[%d].options[%d] needs `key` and `label` strings"):format(si, ii, oi),
              0
            )
          end
        end
      end
    end
  end
end

return M

---Default options + validation.
local M = {}

---@class XcodeTemplates.Config
---@field auto_pick boolean open the chooser when an empty .swift buffer is opened
---@field header boolean prepend the Xcode-style // comment header
---@field date_format string os.date() format used in the header
---@field author string|nil header author; defaults to `git config user.name`, then $USER
---@field columns integer grid columns in the chooser (1-6)
---@field templates table[] extra user sections: { title = string, items = { {id, name, icon, desc?, body} } }

---@return XcodeTemplates.Config
function M.defaults()
  return {
    auto_pick = true,
    header = true,
    date_format = "%Y-%m-%d",
    author = nil,
    columns = 3,
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
    end
  end
end

return M

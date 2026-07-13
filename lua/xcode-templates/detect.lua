---Smart context detection: guess the right template from the file's
---name and location, like Xcode preselecting a template type.
local M = {}

---Ordered name-suffix rules. First match wins, so more specific
---suffixes (ViewModel, ViewController) come before View.
local RULES = {
  { "UITests$", "ui-test" },
  { "Tests$", "swift-testing" },
  { "ViewModel$", "view-model" },
  { "ViewController$", "cocoa-touch-class" },
  { "View$", "swiftui-view" },
  { "Protocol$", "protocol" },
  { "Coordinator$", "coordinator" },
  { "Repository$", "repository" },
  { "Service$", "api-service" },
  { "Client$", "api-service" },
  { "Endpoint$", "api-endpoint" },
  { "Widget$", "widget" },
  { "%+", "extension-file" }, -- Xcode convention: String+Trimming.swift
  { "Model$", "codable-model" },
}

---@param path string file path
---@return { template: string|nil, confident: boolean }
function M.detect(path)
  local basename = vim.fn.fnamemodify(path, ":t:r")
  local dir = vim.fn.fnamemodify(path, ":p:h"):lower()
  local in_ui_tests = dir:find("uitests", 1, true) ~= nil
  local in_tests = in_ui_tests or dir:find("tests", 1, true) ~= nil

  for _, rule in ipairs(RULES) do
    if basename:find(rule[1]) then
      local id = rule[2]
      -- FooTests.swift inside a UITests folder is a UI test
      if id == "swift-testing" and in_ui_tests then
        id = "ui-test"
      end
      return { template = id, confident = true }
    end
  end

  if in_tests then
    return { template = in_ui_tests and "ui-test" or "swift-testing", confident = false }
  end
  return { template = nil, confident = false }
end

return M

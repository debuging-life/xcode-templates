---Old-style Xcode project integration: add created files to a target via
---the `xcodeproj` Ruby gem. Projects using Xcode 16 synchronized folders
---(PBXFileSystemSynchronizedRootGroup) pick up files automatically, so
---this module no-ops for them.
local M = {}

local uv = vim.uv or vim.loop

local warned_ruby = false

local SCRIPT = [==[
begin
  require "xcodeproj"
rescue LoadError
  abort "xcodeproj gem not installed (gem install xcodeproj)"
end

proj_path, file_path, kind = ARGV
project = Xcodeproj::Project.open(File.dirname(proj_path))
root = Pathname.new(File.expand_path(File.dirname(File.dirname(proj_path))))
abs = Pathname.new(File.expand_path(file_path))
rel = abs.relative_path_from(root)

group = project.main_group
rel.dirname.each_filename do |part|
  next if part == "."
  existing = group.children.find do |c|
    c.is_a?(Xcodeproj::Project::Object::PBXGroup) && (c.path == part || c.name == part)
  end
  group = existing || group.new_group(part, part)
end

if group.files.any? { |f| f.real_path.to_s == abs.to_s }
  puts "file already in project"
  exit 0
end

ref = group.new_reference(abs.to_s)
targets = project.native_targets
target =
  if kind == "test"
    targets.find(&:test_target_type?) || targets.first
  else
    targets.find { |t| t.product_type == "com.apple.product-type.application" } || targets.first
  end
abort "no native targets found" unless target
target.add_file_references([ref])
project.save
puts "added #{rel} to target #{target.name}"
]==]

---@param path string any file path inside the project
---@return string|nil pbxproj absolute path to project.pbxproj
function M.find_pbxproj(path)
  local found = vim.fs.find(function(name)
    return name:match("%.xcodeproj$") ~= nil
  end, { path = vim.fs.dirname(vim.fn.fnamemodify(path, ":p")), upward = true })
  if not found[1] then
    return nil
  end
  local pbx = found[1] .. "/project.pbxproj"
  return uv.fs_stat(pbx) and pbx or nil
end

---@param pbxproj_path string
---@return boolean
function M.uses_synchronized_groups(pbxproj_path)
  local f = io.open(pbxproj_path, "r")
  if not f then
    return false
  end
  local content = f:read("*a")
  f:close()
  return content:find("FileSystemSynchronized", 1, true) ~= nil
end

---Add `file` to the owning Xcode project's build target (async).
---No-ops when there is no project or it uses synchronized folders.
---@param file string absolute file path
---@param kind "app"|"test"
function M.add(file, kind)
  local pbx = M.find_pbxproj(file)
  if not pbx or M.uses_synchronized_groups(pbx) then
    return -- nothing to do: no project, or Xcode 16 synchronized folders
  end
  if vim.fn.executable("ruby") == 0 then
    if not warned_ruby then
      warned_ruby = true
      vim.notify(
        "xcode-templates: this project needs files registered in project.pbxproj, but ruby was not found."
          .. " Install ruby + `gem install xcodeproj`, or add the file in Xcode manually.",
        vim.log.levels.WARN
      )
    end
    return
  end
  vim.system({ "ruby", "-e", SCRIPT, pbx, vim.fn.fnamemodify(file, ":p"), kind or "app" }, { text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        vim.notify("xcode-templates: " .. vim.trim(res.stdout or "added to project"), vim.log.levels.INFO)
      else
        local msg = vim.trim((res.stderr and res.stderr ~= "" and res.stderr) or res.stdout or "unknown error")
        vim.notify("xcode-templates: could not add file to Xcode project: " .. msg, vim.log.levels.WARN)
      end
    end)
  end)
end

---@return string the embedded ruby script (for tests / syntax checking)
function M.script()
  return SCRIPT
end

return M

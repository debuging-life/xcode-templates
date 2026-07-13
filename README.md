# xcode-templates.nvim

Xcode's **"Choose a template for your new file"** dialog, in Neovim — so you never
have to open Xcode just to add a file.

Creating an empty `.swift` file (from snacks explorer, neo-tree, `:e`, anywhere)
pops an Xcode-style chooser with a live code preview — pick *SwiftUI View*,
*XCTest Unit Test*, etc. and the file is filled with the familiar Xcode header
plus the right boilerplate:

```swift
//
//  LoginView.swift
//  AdvanceNetworking
//
//  Created by Pardip Bhatti on 2026-07-13.
//

import SwiftUI

struct LoginView: View {
    var body: some View {
        Text("Hello, World!")
    }
}

#Preview {
    LoginView()
}
```

The header is derived automatically: **file name** from the buffer, **project name**
from the nearest `*.xcodeproj` / `*.xcworkspace` / `Package.swift` looking upward,
**author** from `git config user.name` (fallback `$USER`), **date** from `os.date`.

## Features

- **Xcode-style chooser** — sectioned icon grid (Source / Networking / App / Test / Other)
  with a **live syntax-highlighted preview pane** of the generated code
- **Smart detection** — `FooView.swift` preselects *SwiftUI View*, `FooViewModel.swift`
  *View Model*, `FooTests.swift` in a Tests folder *Swift Testing*, `String+Trimming.swift`
  *Extension*, and so on (optionally skip the chooser entirely with `detect.auto_apply`)
- **Xcode's "options" step** — *Cocoa Touch Class* asks which subclass
  (UIViewController, UITableViewCell, …), test templates ask which module to
  `@testable import`, *Extension* asks which type to extend (pre-derived from the name)
- **Old-project support** — for pre-Xcode-16 projects (no synchronized folders),
  created files are registered in `project.pbxproj` and added to the right target
  (app vs test) via the `xcodeproj` gem. Modern synchronized projects need nothing.
- **Header rename sync** — renaming a file updates the `//  File.swift` header line
- **Completion everywhere** — live fuzzy filter in the chooser, file-path completion
  in the name prompt, `:XcodeTemplate <Tab>` template-id completion

## Requirements

- Neovim ≥ 0.10, a Nerd Font terminal
- Optional: `ruby` + `gem install xcodeproj` (only for old-style Xcode projects)
- Optional: swift tree-sitter parser (preview highlighting; LazyVim: `ensure_installed = { "swift" }`)

## Install (lazy.nvim / LazyVim)

```lua
return {
  {
    name = "xcode-templates.nvim",
    dir = "~/Desktop/xcode-templates.nvim", -- or "pardipbhatti/xcode-templates.nvim" once on GitHub
    event = { "BufReadPre *.swift", "BufNewFile *.swift" },
    cmd = "XcodeTemplate",
    keys = {
      { "<leader>in", function() require("xcode-templates").new() end, desc = "New File from Template" },
    },
    opts = {},
  },
}
```

## Usage

| Trigger | Behavior |
|---|---|
| Open an empty `.swift` file | Chooser opens with the detected template preselected; `Esc` leaves the file empty |
| `<leader>in` / `:XcodeTemplate` | Chooser → filename prompt (path completion) → options → file created & saved |
| `:XcodeTemplate <Tab>` | Complete a template id (`swiftui-view`, `unit-test`, …) and skip the chooser |
| `:XcodeTemplate` in an empty swift buffer | Fills the current buffer instead of creating a new file |

**Inside the chooser:** just **type to filter** (fuzzy, like Xcode's Filter box) ·
arrows / `Tab` / `S-Tab` move · `CR` choose · `C-p` toggle preview ·
`BS` / `C-u` edit/clear the filter · `Esc` clears the filter, then closes.

## Builtin templates

- **Source** — SwiftUI View · Swift File · View Model · Cocoa Touch Class · Protocol · Extension · Enum · Actor
- **Networking** — Codable Model · API Endpoint · API Service · Repository
- **App** — Coordinator · Widget · SwiftData Model
- **Test** — Swift Testing Unit Test · XCTest Unit Test · XCTest UI Test
- **Other** — Empty (header only)

## Options (defaults)

```lua
opts = {
  auto_pick = true,            -- open the chooser for empty .swift buffers
  header = true,               -- prepend the // Xcode header
  date_format = "%Y-%m-%d",    -- os.date() format in the header
  author = nil,                -- override; default: git config user.name → $USER
  columns = 3,                 -- chooser grid columns (1-6)
  preview = true,              -- live code preview pane (when the terminal is wide enough)
  detect = {
    enabled = true,            -- preselect a template from the file name/location
    auto_apply = false,        -- true: skip the chooser on confident matches
  },
  add_to_project = true,       -- register files in old-style (non-synchronized) pbxproj
  sync_header_on_rename = true,-- keep `//  File.swift` in sync after renames
  templates = {},              -- your own sections, appended after the builtins
}
```

### Custom templates

```lua
opts = {
  templates = {
    {
      title = "My Team",
      items = {
        {
          id = "use-case",
          name = "Use Case",
          icon = "󰡱",
          desc = "A single-responsibility use case",
          cursor = 6,          -- optional: 1-based line within the body to land on
          target = "test",     -- optional: route to the test target in old projects
          options = {          -- optional: Xcode-style second-step questions
            { key = "kind", label = "Kind", default = "struct", choices = { "struct", "final class" } },
          },
          body = function(ctx)
            -- ctx: filename, name (sanitized type name), project, module_name,
            --      author, date, options (resolved values by key)
            return {
              "import Foundation",
              "",
              ("%s %s {"):format(ctx.options.kind, ctx.name),
              "",
              "}",
              "",
            }
          end,
        },
      },
    },
  },
}
```

## API

```lua
local xt = require("xcode-templates")
xt.new()                                   -- chooser → filename → options → create
xt.new(xt.get("swiftui-view"))             -- skip the chooser
xt.fill(0)                                 -- fill the current (empty) buffer via the chooser
xt.create("unit-test", "Tests/FooTests",   -- scripting: returns buf|nil, err|nil
          { module = "MyApp" })
xt.sync_header(0)                          -- re-sync the header filename line
```

Run `:checkhealth xcode-templates` to diagnose setup issues.

## License

MIT

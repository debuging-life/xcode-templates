# xcode-templates.nvim

Xcode's **"Choose a template for your new file"** dialog, in Neovim.

Creating an empty `.swift` file (from snacks explorer, neo-tree, `:e`, anywhere)
pops an Xcode-style chooser — pick *SwiftUI View*, *XCTest Unit Test*, etc. and the
file is filled with the familiar Xcode header plus the right boilerplate:

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

## Requirements

- Neovim ≥ 0.10
- A Nerd Font terminal (for the template icons)

## Install (lazy.nvim / LazyVim)

Local checkout:

```lua
return {
  {
    name = "xcode-templates.nvim",
    dir = "~/Desktop/xcode-templates.nvim",
    event = { "BufReadPre *.swift", "BufNewFile *.swift" },
    cmd = "XcodeTemplate",
    keys = {
      { "<leader>in", function() require("xcode-templates").new() end, desc = "New File from Template" },
    },
    opts = {},
  },
}
```

From GitHub (after publishing): replace `name`/`dir` with `"pardipbhatti/xcode-templates.nvim"`.

## Usage

| Trigger | Behavior |
|---|---|
| Open an empty `.swift` file | Chooser opens automatically; pick a template or `Esc` to leave the file empty |
| `<leader>in` / `:XcodeTemplate` | Chooser → filename prompt (with **path completion**) → file created & saved |
| `:XcodeTemplate <Tab>` | Complete a template id (`swiftui-view`, `unit-test`, …) and skip the chooser |
| `:XcodeTemplate` in an empty swift buffer | Fills the current buffer instead of creating a new file |

**Inside the chooser:** just **type to filter** (fuzzy, like Xcode's Filter box) ·
arrows / `Tab` / `S-Tab` move · `CR` choose · `BS` / `C-u` edit/clear the filter ·
`Esc` clears the filter, then closes.

## Builtin templates

- **Source** — SwiftUI View · Swift File · Cocoa Touch Class · Observable Class · Protocol
- **Test** — Swift Testing Unit Test · XCTest Unit Test · XCTest UI Test
  (test templates emit `@testable import <Module>` from the detected project)
- **Other** — Empty (header only)

## Options (defaults)

```lua
opts = {
  auto_pick = true,          -- open the chooser for empty .swift buffers
  header = true,             -- prepend the // Xcode header
  date_format = "%Y-%m-%d",  -- os.date() format in the header
  author = nil,              -- override; default: git config user.name → $USER
  columns = 3,               -- chooser grid columns (1-6)
  templates = {},            -- your own sections, appended after the builtins
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
          id = "view-model",
          name = "View Model",
          icon = "󰙅",
          desc = "MVVM view model",
          cursor = 6, -- optional: 1-based line within the body to land on
          body = function(ctx)
            -- ctx: filename, name (sanitized type name), project, module_name, author, date
            return {
              "import Foundation",
              "import Observation",
              "",
              "@Observable",
              ("final class %s {"):format(ctx.name),
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
xt.new()                            -- chooser → filename prompt → create
xt.new(xt.get("swiftui-view"))      -- skip the chooser
xt.fill(0)                          -- fill the current (empty) buffer via the chooser
xt.create("unit-test", "Tests/FooTests")  -- scripting: returns buf|nil, err|nil
```

Run `:checkhealth xcode-templates` to diagnose setup issues.

## License

MIT

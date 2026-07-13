# 󰀵 xcode-templates.nvim

> Xcode's *"Choose a template for your new file"* dialog, in Neovim — so you never
> have to open Xcode just to add a file.

![Neovim](https://img.shields.io/badge/Neovim-%E2%89%A5%200.10-57A143?logo=neovim&logoColor=white)
![Swift](https://img.shields.io/badge/made%20for-Swift%20%2F%20iOS-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)

Create an empty `.swift` file from your file explorer (snacks, neo-tree, `:e`, anywhere)
and an Xcode-style chooser pops up — sectioned icon grid, live fuzzy filter, and a
syntax-highlighted preview of the code it's about to generate:

```
╭───────────── Choose a template for your new file ─────────────╮  ╭─ Preview ──────────────────────╮
│  Source                                                       │  │ //                             │
│  ────────────────────────────────────────────────────         │  │ //  LoginView.swift            │
│       󰕮              󰛥              󰈈                         │  │ //  AdvanceNetworking          │
│  ▐SwiftUI View▌   Swift File     View Model                   │  │ //                             │
│                                                               │  │ //  Created by Pardip Bhatti…  │
│                                    󰛥                          │  │ //                             │
│  Cocoa Touch     Protocol       Extension                     │  │                                │
│                                                               │  │ import SwiftUI                 │
│  Networking                                                   │  │                                │
│  ────────────────────────────────────────────────────         │  │ struct LoginView: View {       │
│      󰘦              󰌷              󰖟                          │  │     var body: some View {      │
│  Codable Model   API Endpoint   API Service                   │  │         Text("Hello, World!")  │
│  …                                                            │  │ …                              │
╰────────────── A SwiftUI view with a #Preview ─────────────────╯  ╰────────────────────────────────╯
```

Pick a template and the file is filled with the familiar Xcode header and boilerplate —
**file name** from the buffer, **project** from the nearest `*.xcodeproj` / `*.xcworkspace` /
`Package.swift`, **author** from `git config user.name`, **date** from `os.date()`.

## ✨ Features

- **Xcode-style chooser** — sectioned icon grid (*Source · Networking · App · Test · Other*)
  with a live, tree-sitter-highlighted preview pane of the generated code
- **Smart detection** — the file's name and location preselect the right template
  (see the [table below](#-smart-detection)); optionally skip the chooser entirely
- **Xcode's "options" step** — *Cocoa Touch Class* asks which subclass
  (UIViewController, UITableViewCell, …), test templates ask which module to
  `@testable import`, *Extension* derives the type from `Type+Feature.swift`
- **Old-project support** — for pre-Xcode-16 projects, created files are registered
  in `project.pbxproj` and added to the right target (app vs test) via the
  `xcodeproj` gem; Xcode 16 synchronized-folder projects need nothing
- **Header rename sync** — renaming a file updates the `//  File.swift` header line
- **Completion everywhere** — live fuzzy filter in the chooser, file-path completion
  in the name prompt, `:XcodeTemplate <Tab>` template-id completion
- **19 builtin templates**, and your own are first-class citizens via `opts.templates`

## 📦 Requirements

| | |
|---|---|
| Neovim | ≥ 0.10 |
| Terminal | any Nerd Font terminal (for the icons) |
| Optional | swift tree-sitter parser — preview highlighting |
| Optional | `ruby` + `gem install xcodeproj` — only for old-style Xcode projects |

## 🚀 Install

With [lazy.nvim](https://github.com/folke/lazy.nvim) / LazyVim:

```lua
return {
  {
    "pardipbhatti/xcode-templates.nvim",
    event = { "BufReadPre *.swift", "BufNewFile *.swift" },
    cmd = "XcodeTemplate",
    keys = {
      { "<leader>in", function() require("xcode-templates").new() end, desc = "New File from Template" },
    },
    opts = {},
  },
}
```

<details>
<summary>Local checkout instead of GitHub</summary>

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
</details>

## 🕹️ Usage

| Trigger | Behavior |
|---|---|
| Open an empty `.swift` file | Chooser opens with the detected template preselected; `Esc` leaves the file empty |
| `<leader>in` / `:XcodeTemplate` | Chooser → filename prompt (path completion) → options → file created & saved |
| `:XcodeTemplate <Tab>` | Complete a template id (`swiftui-view`, `unit-test`, …) and skip the chooser |
| `:XcodeTemplate` in an empty swift buffer | Fills the current buffer instead of creating a new file |

### Keys inside the chooser

| Key | Action |
|---|---|
| any printable key | live fuzzy filter (like Xcode's Filter box) |
| `←` `↑` `↓` `→` / `Tab` / `S-Tab` | move the selection |
| `CR` | choose the selected template |
| `C-p` | toggle the preview pane |
| `BS` / `C-u` | edit / clear the filter |
| `Esc` | clear the filter, then close |

## 🧠 Smart detection

| File | Preselected template |
|---|---|
| `LoginView.swift` | SwiftUI View |
| `LoginViewModel.swift` | View Model |
| `LoginViewController.swift` | Cocoa Touch Class |
| `AuthService.swift`, `APIClient.swift` | API Service |
| `UserRepository.swift` | Repository |
| `UserModel.swift` | Codable Model |
| `UsersEndpoint.swift` | API Endpoint |
| `AppCoordinator.swift` | Coordinator |
| `String+Trimming.swift` | Extension (extending `String`) |
| `FooProtocol.swift` | Protocol |
| `FooWidget.swift` | Widget |
| `FooTests.swift`, anything in a `…Tests/` folder | Swift Testing Unit Test |
| anything in a `…UITests/` folder | XCTest UI Test |

Set `detect.auto_apply = true` and confident matches skip the chooser entirely —
name the file, get the boilerplate.

## 🗂️ Builtin templates

- **Source** — SwiftUI View · Swift File · View Model · Cocoa Touch Class · Protocol · Extension · Enum · Actor
- **Networking** — Codable Model · API Endpoint · API Service · Repository
- **App** — Coordinator · Widget · SwiftData Model
- **Test** — Swift Testing Unit Test · XCTest Unit Test · XCTest UI Test
- **Other** — Empty (header only)

## ⚙️ Options (defaults)

```lua
opts = {
  auto_pick = true,             -- open the chooser for empty .swift buffers
  header = true,                -- prepend the // Xcode header
  date_format = "%Y-%m-%d",     -- os.date() format in the header
  author = nil,                 -- override; default: git config user.name → $USER
  columns = 3,                  -- chooser grid columns (1-6)
  preview = true,               -- live code preview pane (when the terminal is wide enough)
  detect = {
    enabled = true,             -- preselect a template from the file name/location
    auto_apply = false,         -- true: skip the chooser on confident matches
  },
  add_to_project = true,        -- register files in old-style (non-synchronized) pbxproj
  sync_header_on_rename = true, -- keep `//  File.swift` in sync after renames
  templates = {},               -- your own sections, appended after the builtins
}
```

## 🧩 Custom templates

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

## 🔌 API

```lua
local xt = require("xcode-templates")
xt.new()                                   -- chooser → filename → options → create
xt.new(xt.get("swiftui-view"))             -- skip the chooser
xt.fill(0)                                 -- fill the current (empty) buffer via the chooser
xt.create("unit-test", "Tests/FooTests",   -- scripting: returns buf|nil, err|nil
          { module = "MyApp" })
xt.sync_header(0)                          -- re-sync the header filename line
```

## 🩺 Troubleshooting

- Run `:checkhealth xcode-templates` — it verifies the Neovim version, git author,
  the optional ruby/`xcodeproj` gem, the swift tree-sitter parser, and your config.
- No modal on new files? The chooser only opens for **completely empty** buffers with
  `auto_pick = true`, and never in headless sessions.
- The chooser never overwrites: filling a non-empty buffer is refused with a warning,
  and creating over an existing file re-prompts with your input kept.
- Wrong `@testable import`? The module name comes from the detected project with
  spaces/dashes/dots replaced by `_` — override it at the options prompt, which every
  test template shows.

## 📄 License

[MIT](LICENSE) © Pardip Bhatti

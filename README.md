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
- **✻ AI Suggestion** — with a Claude API key configured, an *Intelligence* section appears:
  pick it and Claude drafts the whole file from its name, project, and the sibling files
  in the same folder (async — a placeholder shows while it thinks)
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
    "debuging-life/xcode-templates",
    name = "xcode-templates.nvim",
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
  ai = {
    enabled = true,             -- show the ✻ AI Suggestion template when a key is available
    api_key = nil,              -- string or function; default: $ANTHROPIC_API_KEY
    model = "claude-opus-4-8",  -- any Claude 4.6+/5-family model
    max_tokens = 16000,
    effort = "low",             -- low | medium | high | xhigh | max (speed vs depth)
    context_files = 30,         -- max sibling file names sent as context
  },
  templates = {},               -- your own sections, appended after the builtins
}
```

## ✻ AI Suggestions

Authenticate any of three ways and an **Intelligence** section appears in the chooser
with an *AI Suggestion* template:

1. **Browser login (no key handling)** — install the [Anthropic CLI](https://platform.claude.com/docs/en/api/sdks/cli)
   (`brew install anthropics/tap/ant`), run `ant auth login`, click *Authorize*.
   The plugin picks up the stored profile and refreshes tokens automatically.
   Note: this authorizes your Anthropic **Platform (API)** account — usage bills
   to API credits, not a claude.ai subscription.
2. **Environment variable** — export `ANTHROPIC_API_KEY` in your shell profile.
3. **`ai.api_key` in setup()** — a string, or a function that reads your password
   manager / Keychain (example below).

Resolution order: `ai.api_key` → `$ANTHROPIC_API_KEY` → `ant auth login` profile.

### Inline suggestions & selection actions

Beyond drafting whole files, the same credentials power in-editor assistance:

| Action | How | Result |
|---|---|---|
| **Implement a comment** | write `// build a two sum function`, press `<C-x><C-a>` (insert or normal mode) or run `:XcodeSuggest` | the function appears as ghost text below the comment — `Tab` accepts, `Ctrl-e` dismisses |
| **Complete at cursor** | trigger the same key mid-statement / mid-function | Claude finishes the current construct as ghost text |
| **Ask about a selection** | visually select code → `:'<,'>XcodeAI` (prompts) or `:'<,'>XcodeAI review this for retain cycles` | answer opens in a float — `a` applies it as a replacement for the selection, `y` yanks, `q` closes |

Suggested extra mappings (LazyVim):

```lua
keys = {
  { "<leader>ia", function() require("xcode-templates").suggest() end, desc = "AI Complete at Cursor" },
  { "<leader>ia", function() require("xcode-templates").ask() end, mode = "x", desc = "AI Ask About Selection" },
},
```

Configure under `ai.suggest`: `keymap` (default `<C-x><C-a>`, `false` to disable),
`max_tokens` (4096), `context_before` (120 lines), `context_after` (40 lines).
Suggestions are manual-trigger by design — no keystroke-by-keystroke API calls.

### 🎤 Voice questions & the answer float

`:XcodeVoice` toggles microphone capture (start → speak → trigger again to stop).
The transcript is asked about the code around your cursor, and the answer opens in
a **movable, persistent float** — your file is never modified. `:XcodeHow [question]`
is the typed equivalent.

In the float: **arrow keys move it** around your editor · **`o` pops it out into a
native TextEdit window you can drag to any screen/monitor** · `y` yanks · `q` closes.
It stays open while you keep coding.

Voice needs a local speech-to-text CLI (the Claude API is text-only). On macOS:

```bash
brew install hear   # Apple's on-device speech recognition as a CLI
```

macOS will ask for microphone + speech-recognition permission for your terminal on
first use. Any other transcriber that prints text to stdout works via
`ai.voice.command` (e.g. a whisper-cpp wrapper).

```lua
keys = {
  { "<leader>iv", function() require("xcode-templates").voice() end, desc = "AI Voice Question" },
  { "<leader>iw", function() require("xcode-templates").how() end, desc = "AI How Do I…" },
},
``` Choosing it inserts the Xcode header plus a placeholder,
then asynchronously asks Claude to draft the file using the file name, the detected
intent (`FooViewModel` → view model, etc.), the project name, and the names of the
sibling Swift files in the folder. `:XcodeTemplate ai-suggest` triggers it directly.

Security notes: the key is read lazily, never stored on disk by the plugin, and is
passed to `curl` via stdin so it never appears in the process list. Only file *names*
(never file contents) are sent as context. Requires `curl`.

```lua
-- example: key from macOS Keychain instead of the environment
ai = {
  api_key = function()
    return vim.fn.system({ "security", "find-generic-password", "-s", "anthropic", "-w" }):gsub("%s+$", "")
  end,
},
```

## 🎨 Highlights

The chooser uses theme-aware groups you can override: `XcodeTemplatesSection`,
`XcodeTemplatesSeparator`, `XcodeTemplatesIcon`, `XcodeTemplatesSelected`,
`XcodeTemplatesSelectedIcon`, `XcodeTemplatesMuted` (default links: Title,
WinSeparator, Special, Visual, Visual, Comment).

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

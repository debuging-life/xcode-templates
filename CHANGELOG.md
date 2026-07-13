# Changelog

All notable changes to xcode-templates.nvim.

## v0.3.0 — 2026-07-13

### Added
- **✻ AI Suggestions** — with a Claude API key (`$ANTHROPIC_API_KEY` or `ai.api_key`),
  an *Intelligence* section appears in the chooser; Claude drafts the whole file from
  its name, detected intent, project, and sibling file names (async, with placeholder)
- Theme-aware highlight groups: `XcodeTemplatesSection`, `XcodeTemplatesSeparator`,
  `XcodeTemplatesIcon`, `XcodeTemplatesSelected`, `XcodeTemplatesSelectedIcon`,
  `XcodeTemplatesMuted`
- `:checkhealth` reports AI availability

### Changed
- Selection highlight now links to `Visual` (was `PmenuSel`)
- Partial grid rows are centered, like Xcode
- Preview pane title shows the selected template's name
- All icons moved to the Material Design Nerd Font range (fixes glyphs that
  rendered blank in fonts without codicon/Font Awesome coverage)

## v0.2.0 — 2026-07-13

### Added
- Smart detection: file name/location preselects the right template
  (`FooView` → SwiftUI View, `Tests` folders → test templates, `Type+Feature` →
  Extension); `detect.auto_apply` can skip the chooser on confident matches
- Xcode-style options step: Cocoa Touch Class subclass picker, `@testable import`
  module input, extension type derivation
- Live tree-sitter-highlighted preview pane (`<C-p>` toggle)
- Template library grown to 19 across Source / Networking / App / Test / Other
- Old-style Xcode project integration: created files registered in
  `project.pbxproj` and added to the app/test target via the `xcodeproj` gem
  (no-op for Xcode 16 synchronized folders)
- Header `//  File.swift` line stays in sync after renames

## v0.1.0 — 2026-07-13

### Added
- Xcode-style "Choose a template for your new file" chooser: sectioned icon grid,
  live fuzzy filter, arrow/Tab navigation
- Auto-opens for empty `.swift` buffers (file-explorer flow)
- `:XcodeTemplate` with template-id completion; `<leader>in` mapping
- Xcode header: project from nearest `xcodeproj`/`xcworkspace`/`Package.swift`,
  author from git config, configurable date format
- 9 builtin templates including SwiftUI View, Swift Testing, XCTest
- Custom templates via `opts.templates`; config validation; `:checkhealth`; vimdoc

---Builtin template sections, modeled on Xcode's "New File" chooser.
---
---Each item: {
---  id      = string   -- stable kebab-case id, used for :XcodeTemplate completion
---  name    = string   -- display name
---  icon    = string   -- nerd-font glyph shown in the chooser
---  desc    = string   -- one-line description
---  ext     = string?  -- default file extension (defaults to ".swift")
---  cursor  = number?  -- 1-based line within the body to place the cursor on
---  target  = string?  -- "test" routes the file to the test target in old projects
---  options = table?   -- Xcode-style second-step questions:
---                     --   { key, label, default (value or fun(ctx)), choices? (list) }
---                     --   without `choices` the option is a free-text input
---  body    = fun(ctx: table): string[]
---     ctx: filename, name (sanitized type name), project, module_name,
---          author, date, options (resolved option values by key)
---}
local M = {}

M.sections = {
  {
    title = "Source",
    items = {
      {
        id = "swiftui-view",
        name = "SwiftUI View",
        icon = "󰕮",
        desc = "A SwiftUI view with a #Preview",
        cursor = 5,
        body = function(ctx)
          return {
            "import SwiftUI",
            "",
            ("struct %s: View {"):format(ctx.name),
            "    var body: some View {",
            '        Text("Hello, World!")',
            "    }",
            "}",
            "",
            "#Preview {",
            ("    %s()"):format(ctx.name),
            "}",
            "",
          }
        end,
      },
      {
        id = "swift-file",
        name = "Swift File",
        icon = "󰛥",
        desc = "An empty Swift file",
        body = function()
          return { "import Foundation", "" }
        end,
      },
      {
        id = "view-model",
        name = "View Model",
        icon = "󰈈",
        desc = "An @Observable view model (MVVM)",
        cursor = 6,
        body = function(ctx)
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
      {
        id = "cocoa-touch-class",
        name = "Cocoa Touch Class",
        icon = "",
        desc = "A UIKit class — asks which subclass, like Xcode",
        cursor = 4,
        options = {
          {
            key = "subclass",
            label = "Subclass of",
            default = "UIViewController",
            choices = {
              "UIViewController",
              "UITableViewController",
              "UICollectionViewController",
              "UIView",
              "UITableViewCell",
              "UICollectionViewCell",
              "NSObject",
            },
          },
        },
        body = function(ctx)
          local sub = ctx.options and ctx.options.subclass or "UIViewController"
          local import = sub:match("^UI") and "UIKit" or "Foundation"
          local lines = { "import " .. import, "", ("class %s: %s {"):format(ctx.name, sub), "" }
          if sub:find("ViewController") then
            vim.list_extend(lines, {
              "    override func viewDidLoad() {",
              "        super.viewDidLoad()",
              "",
              "        // Do any additional setup after loading the view.",
              "    }",
              "",
            })
          elseif sub == "UITableViewCell" or sub == "UICollectionViewCell" then
            vim.list_extend(lines, {
              "    override func awakeFromNib() {",
              "        super.awakeFromNib()",
              "",
              "        // Initialization code",
              "    }",
              "",
            })
          end
          vim.list_extend(lines, { "}", "" })
          return lines
        end,
      },
      {
        id = "protocol",
        name = "Protocol",
        icon = "",
        desc = "A Swift protocol",
        cursor = 4,
        body = function(ctx)
          return {
            "import Foundation",
            "",
            ("protocol %s {"):format(ctx.name),
            "",
            "}",
            "",
          }
        end,
      },
      {
        id = "extension-file",
        name = "Extension",
        icon = "",
        desc = "Extend a type — Type+Feature.swift derives the type",
        cursor = 4,
        options = {
          {
            key = "type",
            label = "Type to extend",
            default = function(ctx)
              -- String+Trimming.swift → String
              return ctx.filename:match("^([%w_]+)%+") or ctx.name
            end,
          },
        },
        body = function(ctx)
          local target = ctx.options and ctx.options.type or ctx.name
          return {
            "import Foundation",
            "",
            ("extension %s {"):format(target),
            "",
            "}",
            "",
          }
        end,
      },
      {
        id = "enum",
        name = "Enum",
        icon = "",
        desc = "A Swift enum",
        cursor = 4,
        body = function(ctx)
          return {
            "import Foundation",
            "",
            ("enum %s {"):format(ctx.name),
            "",
            "}",
            "",
          }
        end,
      },
      {
        id = "actor",
        name = "Actor",
        icon = "󰅶",
        desc = "A Swift actor for isolated mutable state",
        cursor = 4,
        body = function(ctx)
          return {
            "import Foundation",
            "",
            ("actor %s {"):format(ctx.name),
            "",
            "}",
            "",
          }
        end,
      },
    },
  },
  {
    title = "Networking",
    items = {
      {
        id = "codable-model",
        name = "Codable Model",
        icon = "󰘦",
        desc = "A Codable DTO struct",
        cursor = 4,
        body = function(ctx)
          return {
            "import Foundation",
            "",
            ("struct %s: Codable, Equatable {"):format(ctx.name),
            "",
            "}",
            "",
          }
        end,
      },
      {
        id = "api-endpoint",
        name = "API Endpoint",
        icon = "󰌷",
        desc = "An endpoint enum with path + method",
        cursor = 4,
        body = function(ctx)
          return {
            "import Foundation",
            "",
            ("enum %s {"):format(ctx.name),
            "    case example",
            "}",
            "",
            ("extension %s {"):format(ctx.name),
            "    var path: String {",
            "        switch self {",
            '        case .example: "/example"',
            "        }",
            "    }",
            "",
            "    var method: String {",
            "        switch self {",
            '        case .example: "GET"',
            "        }",
            "    }",
            "}",
            "",
          }
        end,
      },
      {
        id = "api-service",
        name = "API Service",
        icon = "󰖟",
        desc = "A URLSession-backed service behind a protocol",
        cursor = 5,
        body = function(ctx)
          return {
            "import Foundation",
            "",
            ("protocol %sProtocol {"):format(ctx.name),
            "",
            "}",
            "",
            ("final class %s: %sProtocol {"):format(ctx.name, ctx.name),
            "    private let session: URLSession",
            "",
            "    init(session: URLSession = .shared) {",
            "        self.session = session",
            "    }",
            "}",
            "",
          }
        end,
      },
      {
        id = "repository",
        name = "Repository",
        icon = "󰆼",
        desc = "A repository behind a protocol for testability",
        cursor = 5,
        body = function(ctx)
          return {
            "import Foundation",
            "",
            ("protocol %sProtocol {"):format(ctx.name),
            "",
            "}",
            "",
            ("final class %s: %sProtocol {"):format(ctx.name, ctx.name),
            "",
            "}",
            "",
          }
        end,
      },
    },
  },
  {
    title = "App",
    items = {
      {
        id = "coordinator",
        name = "Coordinator",
        icon = "󰙅",
        desc = "A navigation coordinator",
        cursor = 10,
        body = function(ctx)
          return {
            "import UIKit",
            "",
            ("final class %s {"):format(ctx.name),
            "    private let navigationController: UINavigationController",
            "",
            "    init(navigationController: UINavigationController) {",
            "        self.navigationController = navigationController",
            "    }",
            "",
            "    func start() {",
            "    }",
            "}",
            "",
          }
        end,
      },
      {
        id = "widget",
        name = "Widget",
        icon = "󰜬",
        desc = "A WidgetKit widget with provider and entry view",
        body = function(ctx)
          local n = ctx.name
          return {
            "import WidgetKit",
            "import SwiftUI",
            "",
            ("struct %sEntry: TimelineEntry {"):format(n),
            "    let date: Date",
            "}",
            "",
            ("struct %sProvider: TimelineProvider {"):format(n),
            ("    func placeholder(in context: Context) -> %sEntry {"):format(n),
            ("        %sEntry(date: .now)"):format(n),
            "    }",
            "",
            ("    func getSnapshot(in context: Context, completion: @escaping (%sEntry) -> Void) {"):format(n),
            ("        completion(%sEntry(date: .now))"):format(n),
            "    }",
            "",
            ("    func getTimeline(in context: Context, completion: @escaping (Timeline<%sEntry>) -> Void) {"):format(n),
            ("        completion(Timeline(entries: [%sEntry(date: .now)], policy: .atEnd))"):format(n),
            "    }",
            "}",
            "",
            ("struct %sEntryView: View {"):format(n),
            ("    var entry: %sEntry"):format(n),
            "",
            "    var body: some View {",
            "        Text(entry.date, style: .time)",
            "    }",
            "}",
            "",
            ("struct %s: Widget {"):format(n),
            ('    let kind: String = "%s"'):format(n),
            "",
            "    var body: some WidgetConfiguration {",
            ("        StaticConfiguration(kind: kind, provider: %sProvider()) { entry in"):format(n),
            ("            %sEntryView(entry: entry)"):format(n),
            "        }",
            "    }",
            "}",
            "",
          }
        end,
      },
      {
        id = "swiftdata-model",
        name = "SwiftData Model",
        icon = "󰆧",
        desc = "A SwiftData @Model class",
        cursor = 6,
        body = function(ctx)
          return {
            "import Foundation",
            "import SwiftData",
            "",
            "@Model",
            ("final class %s {"):format(ctx.name),
            "",
            "    init() {",
            "    }",
            "}",
            "",
          }
        end,
      },
    },
  },
  {
    title = "Test",
    items = {
      {
        id = "swift-testing",
        name = "Swift Testing Unit Test",
        icon = "󰙨",
        desc = "A unit test using the Swift Testing framework",
        cursor = 7,
        target = "test",
        options = {
          {
            key = "module",
            label = "@testable import",
            default = function(ctx)
              return ctx.module_name
            end,
          },
        },
        body = function(ctx)
          local module = ctx.options and ctx.options.module or ctx.module_name
          return {
            "import Testing",
            ("@testable import %s"):format(module),
            "",
            ("struct %s {"):format(ctx.name),
            "",
            "    @Test func example() async throws {",
            "        // Write your test here and use APIs like `#expect(...)` to check expected conditions.",
            "    }",
            "",
            "}",
            "",
          }
        end,
      },
      {
        id = "unit-test",
        name = "XCTest Unit Test",
        icon = "",
        desc = "A unit test using XCTest",
        cursor = 15,
        target = "test",
        options = {
          {
            key = "module",
            label = "@testable import",
            default = function(ctx)
              return ctx.module_name
            end,
          },
        },
        body = function(ctx)
          local module = ctx.options and ctx.options.module or ctx.module_name
          return {
            "import XCTest",
            ("@testable import %s"):format(module),
            "",
            ("final class %s: XCTestCase {"):format(ctx.name),
            "",
            "    override func setUpWithError() throws {",
            "        // Put setup code here. This method is called before the invocation of each test method in the class.",
            "    }",
            "",
            "    override func tearDownWithError() throws {",
            "        // Put teardown code here. This method is called after the invocation of each test method in the class.",
            "    }",
            "",
            "    func testExample() throws {",
            "        // This is an example of a functional test case.",
            "    }",
            "",
            "    func testPerformanceExample() throws {",
            "        // This is an example of a performance test case.",
            "        self.measure {",
            "            // Put the code you want to measure the time of here.",
            "        }",
            "    }",
            "",
            "}",
            "",
          }
        end,
      },
      {
        id = "ui-test",
        name = "XCTest UI Test",
        icon = "󰍹",
        desc = "A UI test driving XCUIApplication",
        cursor = 12,
        target = "test",
        body = function(ctx)
          return {
            "import XCTest",
            "",
            ("final class %s: XCTestCase {"):format(ctx.name),
            "",
            "    override func setUpWithError() throws {",
            "        // In UI tests it is usually best to stop immediately when a failure occurs.",
            "        continueAfterFailure = false",
            "    }",
            "",
            "    @MainActor",
            "    func testExample() throws {",
            "        let app = XCUIApplication()",
            "        app.launch()",
            "    }",
            "",
            "}",
            "",
          }
        end,
      },
    },
  },
  {
    title = "Other",
    items = {
      {
        id = "empty",
        name = "Empty",
        icon = "󰈔",
        desc = "Just the file header",
        body = function()
          return {}
        end,
      },
    },
  },
}

return M

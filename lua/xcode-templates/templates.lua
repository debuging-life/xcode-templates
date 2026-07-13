---Builtin template sections, modeled on Xcode's "New File" chooser.
---
---Each item: {
---  id     = string   -- stable kebab-case id, used for :XcodeTemplate completion
---  name   = string   -- display name
---  icon   = string   -- nerd-font glyph shown in the chooser
---  desc   = string   -- one-line description
---  ext    = string?  -- default file extension (defaults to ".swift")
---  cursor = number?  -- 1-based line within the body to place the cursor on
---  body   = fun(ctx: table): string[]
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
        id = "cocoa-touch-class",
        name = "Cocoa Touch Class",
        icon = "",
        desc = "A UIKit view controller subclass",
        cursor = 7,
        body = function(ctx)
          return {
            "import UIKit",
            "",
            ("class %s: UIViewController {"):format(ctx.name),
            "",
            "    override func viewDidLoad() {",
            "        super.viewDidLoad()",
            "",
            "        // Do any additional setup after loading the view.",
            "    }",
            "",
            "}",
            "",
          }
        end,
      },
      {
        id = "observable-class",
        name = "Observable Class",
        icon = "󰈈",
        desc = "An @Observable model class",
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
        body = function(ctx)
          return {
            "import Testing",
            ("@testable import %s"):format(ctx.module_name),
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
        body = function(ctx)
          return {
            "import XCTest",
            ("@testable import %s"):format(ctx.module_name),
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

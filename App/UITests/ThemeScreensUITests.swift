import XCTest

/// Every theme (Settings > Theme) on the screens people see most, with the
/// rendered contrast of text buttons measured from screenshots: the
/// library's server list and category bar (selected, focused and plain
/// buttons), the category picker, Settings and a series page.
///
/// The check reads the pixels inside a button: the most common color is
/// its ground (platter), and the pixel that differs most from it is the
/// core of its text. Their WCAG contrast must reach 4.5:1. That catches a
/// label drawn in a color close to its platter (dark ink on a dark selected
/// pill), whatever the theme's tokens say.
///
/// Screenshots are kept in the .xcresult (and saved to `DESIGN_AUDIT_DIR`
/// when set) so a person can check that each theme reads as its Theme Lab
/// sample.
final class ThemeScreensUITests: XCTestCase {
    private let remote = XCUIRemote.shared
    private static let themes = ["standard", "celadon", "tenmoku", "newsprint", "blackStock"]

    override func setUp() {
        continueAfterFailure = true
    }

    func testLibraryInEveryTheme() {
        for theme in Self.themes {
            let app = XCUIApplication.launched(tab: "library", extra: ["-demoServers", "-uiTestingTheme", theme])
            let server = app.element("library.server.Demo Kavita")
            guard server.waitForExistence(timeout: 10) else {
                XCTFail("[\(theme)] no server list")
                continue
            }
            focus(server)
            checkContrast(theme, "server-list", app, ids: ["library.server.Demo Kavita", "library.server.Demo Suwayomi"])
            remote.press(.select)

            let categories = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'category.'"))
            guard categories.firstMatch.waitForExistence(timeout: 10) else {
                XCTFail("[\(theme)] no category bar")
                continue
            }
            let ids = categories.allElementsBoundByIndex.prefix(3).map(\.identifier)
            // The first category is open; focus it, then the next one.
            if let first = ids.first { focus(app.element(first), .up) }
            checkContrast(theme, "categories-selected-focused", app, ids: ids + ["library.options"])
            if ids.count > 1 {
                focus(app.element(ids[1]), .right)
                checkContrast(theme, "categories-other-focused", app, ids: ids + ["library.options"])
            }
            // Down into the grid: no category focused, the open one still marked.
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.8)
            checkContrast(theme, "categories-unfocused", app, ids: ids)

            // The picker for which libraries this profile imports.
            let choose = app.element("library.chooseCategories")
            if choose.exists {
                select(choose, .right)
                let item = app.element("categories.item.all")
                if item.waitForExistence(timeout: 5) {
                    focus(item)
                    checkContrast(theme, "choose-libraries", app, ids: ["categories.item.all", "categories.item.short"])
                }
            }
            app.terminate()
        }
    }

    func testSettingsAndSeriesInEveryTheme() {
        for theme in Self.themes {
            let app = XCUIApplication.launched(tab: "settings", extra: ["-demoServers", "-uiTestingTheme", theme])
            let themeRow = app.element("settings.theme")
            guard themeRow.waitForExistence(timeout: 10) else {
                XCTFail("[\(theme)] no Settings")
                continue
            }
            focus(themeRow)
            checkContrast(theme, "settings", app, ids: ["settings.theme", "settings.readerDefaults"])

            app.terminate()
            let home = XCUIApplication.launched(tab: "home", extra: ["-demoServers", "-uiTestingTheme", theme])
            let poster = home.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.'")).firstMatch
            if poster.waitForExistence(timeout: 10) {
                Thread.sleep(forTimeInterval: 1)
                saveScreenshot("\(theme)-home")
                focus(poster)
                remote.press(.select)
                Thread.sleep(forTimeInterval: 2)
                saveScreenshot("\(theme)-series")
            } else {
                XCTFail("[\(theme)] no posters on Home")
            }
            home.terminate()
        }
    }

    // MARK: Rendered contrast

    /// Saves a screenshot and checks each button's text against its platter.
    private func checkContrast(_ theme: String, _ screen: String, _ app: XCUIApplication, ids: [String],
                               file: StaticString = #filePath, line: UInt = #line) {
        Thread.sleep(forTimeInterval: 0.8)
        let shot = XCUIScreen.main.screenshot()
        saveScreenshot("\(theme)-\(screen)", shot)
        guard let pixels = ThemePixels(shot.image) else { return XCTFail("Couldn't read the screenshot") }
        let window = app.windows.firstMatch.frame
        let scale = CGFloat(pixels.width) / max(window.width, 1)
        for id in ids {
            let element = app.element(id)
            guard element.exists, !element.frame.isEmpty else { continue }
            let frame = element.frame
            // Stay inside the platter: away from its rounded corners, its
            // focus shadow and the ground around it.
            let inner = frame.insetBy(dx: min(frame.width * 0.08, 30), dy: frame.height * 0.18)
            guard let ratio = pixels.textContrast(in: inner, scale: scale) else { continue }
            XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                        "[\(theme)] \(screen): \(id) text is \(String(format: "%.2f", ratio)):1 on its platter",
                                        file: file, line: line)
        }
    }

    private func saveScreenshot(_ name: String, _ given: XCUIScreenshot? = nil) {
        let shot = given ?? XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["DESIGN_AUDIT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: url.appendingPathComponent("\(name).png"))
    }
}

/// RGB pixels of a screenshot, for measuring contrast as drawn.
private struct ThemePixels {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(_ image: UIImage) {
        guard let cg = image.cgImage else { return nil }
        width = cg.width
        height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                                          bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        guard drawn else { return nil }
        data = bytes
    }

    /// WCAG relative luminance of the pixel at (x, y), y from the top.
    private func luminance(_ x: Int, _ y: Int) -> Double {
        let i = (y * width + x) * 4
        func channel(_ v: UInt8) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(data[i]) + 0.7152 * channel(data[i + 1]) + 0.0722 * channel(data[i + 2])
    }

    /// Contrast between the most common luminance in `rect` (points) and
    /// the luminance farthest from it, or nil when the rect is off screen.
    func textContrast(in rect: CGRect, scale: CGFloat) -> Double? {
        let x0 = max(Int(rect.minX * scale), 0), x1 = min(Int(rect.maxX * scale), width - 1)
        let y0 = max(Int(rect.minY * scale), 0), y1 = min(Int(rect.maxY * scale), height - 1)
        guard x1 > x0 + 4, y1 > y0 + 4 else { return nil }
        var buckets = [Int](repeating: 0, count: 101)
        var values: [Double] = []
        values.reserveCapacity((x1 - x0) * (y1 - y0) / 4)
        for y in stride(from: y0, to: y1, by: 2) {
            for x in stride(from: x0, to: x1, by: 2) {
                let l = luminance(x, y)
                values.append(l)
                buckets[Int((l * 100).rounded())] += 1
            }
        }
        guard let mode = buckets.indices.max(by: { buckets[$0] < buckets[$1] }) else { return nil }
        let ground = Double(mode) / 100
        // The farthest few pixels, not the single farthest, so one stray
        // pixel doesn't pass a label that is unreadable everywhere else.
        let n = max(1, values.count / 400)
        let far = values.sorted { abs($0 - ground) > abs($1 - ground) }.prefix(n)
        guard let text = far.last else { return nil }
        let (hi, lo) = (max(ground, text), min(ground, text))
        return (hi + 0.05) / (lo + 0.05)
    }
}

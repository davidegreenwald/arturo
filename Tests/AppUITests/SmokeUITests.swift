import CoreGraphics
import ImageIO
import XCTest

/// UI smoke lane — deliberately OUTSIDE the fast gate (ADR-002). It launches the
/// real app, points it at a real folder of real PNGs, and proves the three
/// behaviours that only exist once the app is running: the page is drawn, the
/// key monitor skips, and space pauses.
///
/// Determinism comes from launch arguments: `--folder <path>` opens a folder for
/// that launch only, and `-slideshow.*` values override `UserDefaults` for the
/// launched process, so no test depends on what this machine has stored.
final class SmokeUITests: XCTestCase {
    private func makePhotoFolder(count: Int) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "slideshow-ui-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for index in 1 ... count {
            let url = folder.appending(path: String(format: "photo-%02d.png", index))
            let context = try XCTUnwrap(CGContext(
                data: nil,
                width: 320,
                height: 240,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(
                red: CGFloat(index) / CGFloat(count),
                green: 0.35,
                blue: 0.6,
                alpha: 1
            ))
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))

            let image = try XCTUnwrap(context.makeImage())
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.png" as CFString,
                1,
                nil
            ))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
        return folder
    }

    func testLaunchesToTheEmptyState() {
        let app = XCUIApplication()
        // A restored folder that no longer exists is the realistic way to reach
        // the empty state deterministically — and it must offer the same action.
        // No arguments at all: the app must launch blank by itself, even after
        // a folder was opened in a previous run.
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "viewer window never appeared")
        XCTAssertTrue(
            window.buttons["Open a Folder…"].waitForExistence(timeout: 5),
            "first run should offer the only action that matters"
        )

        app.terminate()
    }

    func testPlaysAPageAndSkipsWithTheArrowKeys() throws {
        let folder = try makePhotoFolder(count: 6)

        let app = XCUIApplication()
        app.launchArguments = [
            "--folder", folder.path,
            "-arturo.columns", "3",
            // Long enough that the timer cannot move the page underneath the
            // assertions; the skip must come from the key monitor.
            "-arturo.holdSeconds", "30",
        ]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "viewer window never appeared")

        // Pause first: the pill auto-hides after ~2.4 s of playing, and a paused
        // viewer keeps its controls (and their accessibility elements) on screen.
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(
            window.buttons["Play"].waitForExistence(timeout: 5),
            "space should pause, exposing the play glyph"
        )

        let position = window.staticTexts["position-label"]
        XCTAssertTrue(position.waitForExistence(timeout: 5), "position readout never appeared")
        XCTAssertEqual(position.value as? String, "1–3 / 6")

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForValue(of: position, toEqual: "4–6 / 6"),
            "right arrow should advance a full page, saw \(String(describing: position.value))"
        )

        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForValue(of: position, toEqual: "1–3 / 6"),
            "left arrow should return to the previous page, saw \(String(describing: position.value))"
        )

        app.terminate()
    }

    func testFillChipTogglesTheFrameStyle() throws {
        let folder = try makePhotoFolder(count: 6)

        let app = XCUIApplication()
        app.launchArguments = [
            "--folder", folder.path,
            "-arturo.columns", "3",
            "-arturo.holdSeconds", "30",
            "-arturo.fillsFrames", "NO",
        ]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "viewer window never appeared")

        // Pausing keeps the pill on screen so the chip can be tapped.
        app.typeKey(" ", modifierFlags: [])

        let fill = window.buttons["Fill frame"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5), "fill chip never appeared")
        XCTAssertEqual(fill.value as? String, "Off", "fit should be the default")

        fill.tap()
        XCTAssertTrue(
            waitForValue(of: fill, toEqual: "On"),
            "the chip should read On after tapping, saw \(String(describing: fill.value))"
        )

        fill.tap()
        XCTAssertTrue(
            waitForValue(of: fill, toEqual: "Off"),
            "the chip should read Off after tapping again, saw \(String(describing: fill.value))"
        )

        app.terminate()
    }

    private func waitForValue(of element: XCUIElement, toEqual expected: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }
}

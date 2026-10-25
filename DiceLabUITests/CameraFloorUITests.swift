import XCTest

/// M11 camera-floor verification driver — a spike tool parked on
/// `spike/camera-floor-uitest`, not part of main. The app is
/// simctl-launched beforehand with its flags (`-engine realityKit
/// -cameraLog -autoroll`) and console output captured; `activate()`
/// foregrounds that running instance so XCTest's real event pipeline
/// drives it and the camera lines land in the simctl capture.
final class CameraFloorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.activate()
        sleep(1)
        // A failed test can leave the settings sheet up — a sheet eats
        // every gesture the roll view is supposed to get.
        var sheetGuard = 0
        while app.navigationBars["Settings"].exists, sheetGuard < 3 {
            app.navigationBars["Settings"].swipeDown()
            sleep(1)
            sheetGuard += 1
        }
    }

    private func dragDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: 400, thenHoldForDuration: 0.1)
    }

    private func dragUp() {
        // Start above the bottom overlay — HistoryPanel + Roll button
        // claim the lower ~280pt and eat the press.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: 400, thenHoldForDuration: 0.1)
    }

    private func dragSideways() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: 400, thenHoldForDuration: 0.1)
    }

    /// Push to the floor, prove the immediate reverse, sideways orbit,
    /// and pinch dolly — read from the [DiceLab] camera lines.
    func testFloorAndResponses() throws {
        sleep(8) // launch fit latches
        for _ in 0..<6 { dragDown(); Thread.sleep(forTimeInterval: 0.25) }
        sleep(1)
        dragUp(); Thread.sleep(forTimeInterval: 0.4)
        dragUp(); Thread.sleep(forTimeInterval: 0.4)
        sleep(1)
        dragSideways()
        sleep(1)
        app.pinch(withScale: 0.5, velocity: -1)
        sleep(1)
        app.pinch(withScale: 2.0, velocity: 1)
        sleep(1)
        // Leave the camera pinned at the floor for the screenshot.
        for _ in 0..<4 { dragDown(); Thread.sleep(forTimeInterval: 0.2) }
        sleep(1)
    }

    /// Roll mid-drag — drags must be ignored while the fit owns the
    /// camera — and orbit must work again after the latch.
    func testRollSuppressesThenReturns() throws {
        sleep(8)
        dragDown()
        // The button relabels "Rolling…" while isRolling — proof the tap
        // landed rather than trusting the gesture was synthesized.
        app.buttons["Roll"].tap()
        XCTAssertTrue(app.buttons["Rolling…"].waitForExistence(timeout: 3),
                      "Roll tap did not start a roll")
        for _ in 0..<3 { dragDown(); Thread.sleep(forTimeInterval: 0.3) }
        sleep(15) // settle + fit latch
        dragDown()
        Thread.sleep(forTimeInterval: 0.4)
        dragDown()
        sleep(1)
    }

    /// Settings → Camera control off: drags ignored. Back on: works.
    /// The sheet opens at medium detent with the Camera section below
    /// the fold — expand it to large, then scroll until the switch is
    /// hittable.
    func testCameraControlToggle() throws {
        sleep(8)
        dragDown()
        sleep(1)
        openSettingsSheet()
        toggleCameraControl()
        closeSettingsSheet()
        dragDown()
        sleep(1)
        dragDown()
        sleep(1)
        openSettingsSheet()
        toggleCameraControl()
        closeSettingsSheet()
        dragDown()
        sleep(1)
    }

    private func openSettingsSheet() {
        app.buttons["Settings"].tap()
        sleep(1)
        app.navigationBars["Settings"].swipeUp() // medium → large detent
        sleep(1)
    }

    private func toggleCameraControl() {
        var tries = 0
        while !app.switches["Camera control"].isHittable, tries < 6 {
            app.collectionViews.firstMatch.swipeUp()
            sleep(1)
            tries += 1
        }
        app.switches["Camera control"].tap()
        sleep(1)
    }

    private func closeSettingsSheet() {
        app.navigationBars["Settings"].swipeDown()
        sleep(1)
    }
}

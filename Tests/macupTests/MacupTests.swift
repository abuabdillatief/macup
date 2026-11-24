import CoreGraphics
import Foundation
import XCTest
@testable import macup

final class MacupTests: XCTestCase {
    func testWindowPlacementCalculations() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)

        XCTAssertNil(WindowPlacement.none.targetFrame(in: screen))

        let leftHalf = WindowPlacement.leftHalf.targetFrame(in: screen)
        XCTAssertEqual(leftHalf, CGRect(x: 0, y: 25, width: 720, height: 875))

        let rightHalf = WindowPlacement.rightHalf.targetFrame(in: screen)
        XCTAssertEqual(rightHalf, CGRect(x: 720, y: 25, width: 720, height: 875))

        let topLeft = WindowPlacement.topLeft.targetFrame(in: screen)
        XCTAssertEqual(topLeft, CGRect(x: 0, y: 25, width: 720, height: 438))

        let bottomRight = WindowPlacement.bottomRight.targetFrame(in: screen)
        XCTAssertEqual(bottomRight, CGRect(x: 720, y: 462, width: 720, height: 438))

        let leftThird = WindowPlacement.leftThird.targetFrame(in: screen)
        XCTAssertEqual(leftThird?.width, 480)
        XCTAssertEqual(leftThird?.origin.x, 0)

        let rightTwoThirds = WindowPlacement.rightTwoThirds.targetFrame(in: screen)
        XCTAssertEqual(rightTwoThirds?.origin.x, 480)
        XCTAssertEqual(rightTwoThirds?.width, 960)
    }

    func testWindowPlacementWithSecondaryDisplayOffset() {
        let secondary = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let rightHalf = WindowPlacement.rightHalf.targetFrame(in: secondary)
        XCTAssertEqual(rightHalf, CGRect(x: 3200, y: 0, width: 1280, height: 1440))
    }

    @MainActor
    func testProfileStorePersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storageURL = tempDir.appendingPathComponent("profiles.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ProfileStore(storageURL: storageURL)
        XCTAssertFalse(store.profiles.isEmpty)

        let added = store.addProfile(name: "Coding", icon: "terminal")
        store.setDefaultProfile(added.id)
        XCTAssertEqual(store.defaultProfile?.id, added.id)

        // Reload from disk
        let reloaded = ProfileStore(storageURL: storageURL)
        XCTAssertEqual(reloaded.profiles.count, store.profiles.count)
        XCTAssertEqual(reloaded.defaultProfile?.name, "Coding")
    }

    func testBrowserDetectionAndURLResolution() {
        let safari = AppLaunchItem(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appPath: "/Applications/Safari.app",
            urls: ["github.com", "https://linear.app", "  "]
        )
        XCTAssertTrue(safari.isBrowser)
        XCTAssertEqual(safari.resolvedURLs.map(\.absoluteString), [
            "https://github.com",
            "https://linear.app"
        ])

        let notes = AppLaunchItem(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            appPath: "/System/Applications/Notes.app"
        )
        XCTAssertFalse(notes.isBrowser)
        XCTAssertTrue(notes.resolvedURLs.isEmpty)
    }
}

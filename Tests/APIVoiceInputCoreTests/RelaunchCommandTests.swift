import Foundation
import XCTest
@testable import APIVoiceInputCore

final class RelaunchCommandTests: XCTestCase {
    func testWaitsForCurrentProcessThenOpensApplicationBundle() {
        let command = RelaunchCommand.afterTerminating(
            processID: 4242,
            applicationURL: URL(fileURLWithPath: "/Applications/API音声ソフト.app")
        )

        XCTAssertEqual(command.executableURL.path, "/bin/sh")
        XCTAssertEqual(command.arguments, [
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open \"$2\"",
            "relaunch",
            "4242",
            "/Applications/API音声ソフト.app"
        ])
    }
}

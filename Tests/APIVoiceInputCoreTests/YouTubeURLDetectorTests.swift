import XCTest
@testable import APIVoiceInputCore

final class YouTubeURLDetectorTests: XCTestCase {
    func testDetectsYouTubeWatchAndShortUrls() {
        XCTAssertTrue(YouTubeURLDetector.isYouTubeURL("https://www.youtube.com/watch?v=abc"))
        XCTAssertTrue(YouTubeURLDetector.isYouTubeURL("https://m.youtube.com/shorts/abc"))
        XCTAssertTrue(YouTubeURLDetector.isYouTubeURL("https://youtu.be/abc"))
    }

    func testRejectsNonYouTubeURLs() {
        XCTAssertFalse(YouTubeURLDetector.isYouTubeURL("https://example.com/youtube.com/watch?v=abc"))
        XCTAssertFalse(YouTubeURLDetector.isYouTubeURL("https://notyoutube.com/watch?v=abc"))
        XCTAssertFalse(YouTubeURLDetector.isYouTubeURL(""))
    }
}

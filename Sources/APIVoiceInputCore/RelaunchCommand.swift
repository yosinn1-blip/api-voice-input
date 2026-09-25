import Foundation

/// A detached command that starts the app only after its current process has exited.
public struct RelaunchCommand: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]

    public static func afterTerminating(processID: Int32, applicationURL: URL) -> Self {
        Self(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open \"$2\"",
                "relaunch",
                String(processID),
                applicationURL.path
            ]
        )
    }
}

import Foundation
import Darwin

struct MediaRemotePauseController {
    struct Snapshot {
        let displayID: String?
        let isPlaying: Bool?
    }

    private final class Library: @unchecked Sendable {
        static let shared = Library()
        let handle: UnsafeMutableRawPointer?

        init() {
            handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        }

        deinit {
            if let handle {
                dlclose(handle)
            }
        }

        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            guard let handle else { return nil }
            return dlsym(handle, name)
        }
    }

    func snapshot(timeoutSeconds: Double = 0.35) -> Snapshot {
        Snapshot(
            displayID: nowPlayingDisplayID(timeoutSeconds: timeoutSeconds),
            isPlaying: nowPlayingIsPlaying(timeoutSeconds: timeoutSeconds)
        )
    }

    func sendPause() -> Bool {
        guard let symbol = Library.shared.symbol("MRMediaRemoteSendCommand") else { return false }
        typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool
        let function = unsafeBitCast(symbol, to: SendCommand.self)
        return function(1, nil) // 1 is the MediaRemote pause command; not play/pause toggle.
    }

    private func nowPlayingDisplayID(timeoutSeconds: Double) -> String? {
        guard let symbol = Library.shared.symbol("MRMediaRemoteGetNowPlayingApplicationDisplayID") else { return nil }
        typealias Completion = @convention(block) (CFString?) -> Void
        typealias Function = @convention(c) (DispatchQueue, @escaping Completion) -> Void
        let function = unsafeBitCast(symbol, to: Function.self)
        let semaphore = DispatchSemaphore(value: 0)
        var value: String?
        let completion: Completion = { displayID in
            value = displayID as String?
            semaphore.signal()
        }
        function(DispatchQueue.global(qos: .utility), completion)
        _ = semaphore.wait(timeout: .now() + timeoutSeconds)
        return value
    }

    private func nowPlayingIsPlaying(timeoutSeconds: Double) -> Bool? {
        guard let symbol = Library.shared.symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying") else { return nil }
        typealias Completion = @convention(block) (Bool) -> Void
        typealias Function = @convention(c) (DispatchQueue, @escaping Completion) -> Void
        let function = unsafeBitCast(symbol, to: Function.self)
        let semaphore = DispatchSemaphore(value: 0)
        var value: Bool?
        let completion: Completion = { isPlaying in
            value = isPlaying
            semaphore.signal()
        }
        function(DispatchQueue.global(qos: .utility), completion)
        _ = semaphore.wait(timeout: .now() + timeoutSeconds)
        return value
    }
}

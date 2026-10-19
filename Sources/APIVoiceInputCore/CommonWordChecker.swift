import CoreServices
import Foundation

/// 「普通の語か」を答える。普通の語は自動登録の対象にしない（カーソル、cloud など）。
public protocol CommonWordChecker: Sendable {
    func isCommonWord(_ word: String) -> Bool
}

/// macOS 内蔵の辞書（大辞林・英和和英など）にその語が載っているかで判断する。
/// 実機で確かめた挙動: 語の一部だけ一致しても返らない（「カーソルバー」は無し）／
/// 英語の語は日本語の見出し（「クラウド」）で返ることがある／崩れた綴り（Glog, Opencode）は無し。
public struct SystemDictionaryWordChecker: CommonWordChecker {
    public init() {}

    public func isCommonWord(_ word: String) -> Bool {
        let range = CFRangeMake(0, (word as NSString).length)
        return DCSCopyTextDefinition(nil, word as CFString, range) != nil
    }
}

import Foundation

/// 語が「1つの語として」現れているか（前後の文字とつながって、別の語の一部になっていないか）の判定。
enum WordBoundary {
    static func isKatakana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x30A1...0x30FA).contains($0.value) || $0.value == 0x30FC }
    }

    static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            (0x30...0x39).contains($0.value) || (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value)
        }
    }

    /// `characters[start..<end]` の前後が、同じ種類の文字（英数字どうし／カタカナどうし）でつながっていないか。
    /// 置き換えのときは英数字だけを見る（カタカナの複合語「コーデックスアプリ」の一部は置き換えたい）。
    /// 学習の根拠を数えるときは、カタカナも見る（「グロースハック」の中の「グロース」を数えない）。
    static func isStandalone(_ characters: [Character], start: Int, end: Int, includingKatakana: Bool) -> Bool {
        guard start < end, start >= 0, end <= characters.count else { return false }
        let first = characters[start]
        let last = characters[end - 1]
        if start > 0 {
            let before = characters[start - 1]
            if isASCIIAlphanumeric(first), isASCIIAlphanumeric(before) { return false }
            if includingKatakana, isKatakana(first), isKatakana(before) { return false }
        }
        if end < characters.count {
            let after = characters[end]
            if isASCIIAlphanumeric(last), isASCIIAlphanumeric(after) { return false }
            if includingKatakana, isKatakana(last), isKatakana(after) { return false }
        }
        return true
    }

    /// 文章の中に、`word` が1つの語として現れる回数。
    static func standaloneCount(of word: String, in text: String) -> Int {
        let characters = Array(text)
        let pattern = Array(word)
        guard pattern.isEmpty == false, pattern.count <= characters.count else { return 0 }
        var count = 0
        var start = 0
        while start + pattern.count <= characters.count {
            let end = start + pattern.count
            if characters[start..<end].elementsEqual(pattern),
               isStandalone(characters, start: start, end: end, includingKatakana: true) {
                count += 1
                start = end
            } else {
                start += 1
            }
        }
        return count
    }
}

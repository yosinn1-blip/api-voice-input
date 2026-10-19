import Foundation

/// 2つの語の「音の近さ」。カタカナでも英字でも、子音の骨組みにして編集距離で測る（0 = 同じ、1 = まるで違う）。
///
/// 自動登録の歯止め用の粗い目安で、正しいことの保証ではない。AIが辞書の語へ無理に当てはめた誤り
/// （セレブラス→Cloudflare など）を、音が違いすぎるという理由で弾くために使う。
public enum PhoneticSimilarity {
    /// これ以下なら「同じ名前の聞き間違い」としてありうる。
    /// 実測: 正しい組は 0.33 以下、AIが無理に当てはめた誤りの組は 0.5 以上（セレブラス→Cloudflare は 0.8）。
    public static let maximumDistanceForSameName = 0.34

    public static func distance(_ first: String, _ second: String) -> Double {
        let left = Array(skeleton(first))
        let right = Array(skeleton(second))
        guard left.isEmpty == false, right.isEmpty == false else { return 1 }
        var previous = Array(0...right.count)
        for i in 1...left.count {
            var current = [i] + [Int](repeating: 0, count: right.count)
            for j in 1...right.count {
                let substitution = previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        return Double(previous[right.count]) / Double(max(left.count, right.count))
    }

    /// 母音を落として、似た子音を同じ仲間にした骨組み。例: グロック・Groq → grk、クラウドフレア・Cloudflare → krdfr
    static func skeleton(_ text: String) -> String {
        var romaji = text.applyingTransform(.toLatin, reverse: false) ?? text
        romaji = romaji.applyingTransform(.stripDiacritics, reverse: false) ?? romaji
        var letters = String(romaji.lowercased().unicodeScalars.filter { (0x61...0x7A).contains($0.value) })
        // 英語の綴りの癖
        for (spelling, sound) in [("ph", "f"), ("ck", "k"), ("sh", "s"), ("ch", "k"), ("x", "ks"), ("q", "k")] {
            letters = letters.replacingOccurrences(of: spelling, with: sound)
        }
        // c は e・i・y の前では s（Vercel）、それ以外は k（Codex）。h は読まれにくいので落とす（GitHub のハブも揃う）。
        letters = letters.replacingOccurrences(of: "c(?=[eiy])", with: "s", options: .regularExpression)
        letters = letters.replacingOccurrences(of: "h", with: "")
        // 母音のあとに続かない r は読まない（Cursor → カーサー）
        letters = letters.replacingOccurrences(of: "r(?![aeiou])", with: "", options: .regularExpression)

        let sameSound: [Character: Character] = ["v": "b", "c": "k", "j": "g", "l": "r", "z": "s"]
        var skeleton = ""
        for character in letters where "aeiouyw".contains(character) == false {
            let sound = sameSound[character] ?? character
            if skeleton.last != sound {
                skeleton.append(sound)
            }
        }
        return skeleton
    }
}

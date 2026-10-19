import XCTest
@testable import APIVoiceInputCore

final class PhoneticSimilarityTests: XCTestCase {
    func testRealMisrecognitionsStayWithinTheThreshold() {
        let pairs: [(String, String)] = [
            ("グロック", "Groq"), ("グロッグ", "Groq"), ("グロックボット", "Grok Bot"), ("ソニオックス", "Soniox"),
            ("ソニョックス", "Soniox"), ("SonyOx", "Soniox"), ("クロードコード", "Claude Code"), ("クロード", "Claude"),
            ("コーデックス", "Codex"), ("ギットハブ", "GitHub"), ("オブシリアン", "Obsidian"), ("オブシディアン", "Obsidian"),
            ("オープンコード", "OpenCode"), ("オープンクロー", "OpenClaw"), ("オープンルーター", "OpenRouter"),
            ("クラウドフレア", "Cloudflare"), ("スパベース", "Supabase"), ("スーパーベース", "Supabase"),
            ("ショーピーファイ", "Shopify"), ("カーサー", "Cursor"), ("ジェミニ", "Gemini"), ("ナノバナナ", "Nano Banana"),
            ("コンピュータユーズ", "Computer Use"), ("オーパス", "Opus"), ("アンリアルエンジン", "Unreal Engine"),
            ("ロブロックス", "Roblox"), ("マックミニ", "Mac mini"), ("グーグルクローム", "Google Chrome"), ("クローム", "Chrome"),
            ("ワンパスワード", "1Password"),
            // 実際の発話の評価で出た本物の崩れ
            ("Glog", "Groq"), ("GlockBot", "Grok Bot"), ("ハギングフェイス", "HuggingFace"), ("ショッピーファイ", "Shopify"),
            ("オブシデアン", "Obsidian"), ("スーパーベイス", "Supabase"), ("クロードコート", "Claude Code"),
            // 例と重ならない語
            ("ドッカー", "Docker"), ("クーバネティス", "Kubernetes"), ("ポストグレスキューエル", "PostgreSQL"),
            ("ストライプ", "Stripe"), ("Dokcer", "Docker"), ("リニア", "Linear"), ("レイキャスト", "Raycast"),
            ("ノーション", "Notion"), ("スラック", "Slack"), ("バーセル", "Vercel"), ("フィグマ", "Figma"),
            ("リアクト", "React"), ("Reakt", "React"), ("タイプスクリプト", "TypeScript"), ("ファイヤーベイス", "Firebase"),
            // th・wh のような h は読まれにくい
            ("パイソン", "Python"), ("ウィスパー", "Whisper")
        ]

        for (wrong, correct) in pairs {
            XCTAssertLessThanOrEqual(
                PhoneticSimilarity.distance(wrong, correct),
                PhoneticSimilarity.maximumDistanceForSameName,
                "\(wrong) → \(correct)"
            )
        }
    }

    func testDifferentNamesAreFarApart() {
        // 前半4組は、実際にAIが辞書の語へ無理に当てはめた誤り
        let pairs: [(String, String)] = [
            ("セレブラス", "Cloudflare"), ("セレブレス", "Cloudflare"), ("フェイブル", "Firebase"), ("Glog", "GitHub"),
            ("ココナラ", "Docker"), ("アカウント", "Slack"), ("プロジェクト", "Obsidian"), ("ログイン", "Codex"),
            ("ハッカソン", "Hugging"), ("トークン", "Notion"), ("カーソル", "Cloudflare"), ("メタルギア", "Claude")
        ]

        for (wrong, correct) in pairs {
            XCTAssertGreaterThan(
                PhoneticSimilarity.distance(wrong, correct),
                PhoneticSimilarity.maximumDistanceForSameName,
                "\(wrong) → \(correct)"
            )
        }
    }

    func testTheSameSoundIsZeroAndTheOrderDoesNotMatter() {
        XCTAssertEqual(PhoneticSimilarity.distance("グロック", "Groq"), 0)
        XCTAssertEqual(
            PhoneticSimilarity.distance("オブシリアン", "Obsidian"),
            PhoneticSimilarity.distance("Obsidian", "オブシリアン")
        )
    }

    func testTextWithoutAnySoundIsNeverSimilar() {
        XCTAssertEqual(PhoneticSimilarity.distance("ー", "Groq"), 1)
        XCTAssertEqual(PhoneticSimilarity.distance("", ""), 1)
        XCTAssertEqual(PhoneticSimilarity.distance("123", "456"), 1)
    }
}

final class WordBoundaryTests: XCTestCase {
    func testCountsOnlyOccurrencesThatAreAWordOnTheirOwn() {
        XCTAssertEqual(WordBoundary.standaloneCount(of: "グロース", in: "グロースハックとグロース"), 1)
        XCTAssertEqual(WordBoundary.standaloneCount(of: "Glog", in: "GlogのAPIとMyGlogとGlog2"), 1)
        XCTAssertEqual(WordBoundary.standaloneCount(of: "コーデックス", in: "コーデックスアプリ"), 0)
        XCTAssertEqual(WordBoundary.standaloneCount(of: "ハック", in: "グロースハック"), 0)
        XCTAssertEqual(WordBoundary.standaloneCount(of: "コーデックス", in: "コーデックスとコーデックスを比べる"), 2)
    }

    func testLatinWordsNextToJapaneseAreStandalone() {
        XCTAssertEqual(WordBoundary.standaloneCount(of: "Glog", in: "Glogの鍵と(Glog)と Glog."), 3)
    }

    func testEmptyWordNeverMatches() {
        XCTAssertEqual(WordBoundary.standaloneCount(of: "", in: "何か"), 0)
        XCTAssertEqual(WordBoundary.standaloneCount(of: "長い語です", in: "短い"), 0)
    }
}

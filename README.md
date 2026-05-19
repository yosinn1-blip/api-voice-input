# API音声ソフト

AIに話しかけるための、Mac向け高速音声入力アプリです。

ChatGPT / Claude / Codex などの入力欄に、`Fn → 話す → Enter` の流れで素早く音声入力します。文章を過度に整えるより、話した意図を速く正確にAIへ渡すことを重視しています。

## 特徴

- AI入力向けのシンプルな音声入力
- Groq Whisper `whisper-large-v3-turbo` による高速な文字起こし
- アプリ独自アカウント不要
- ユーザー自身のGroq APIキーを使用
- APIキーはmacOS Keychainに保存
- 録音中はコンパクトな波形overlayを表示
- 処理後は入力欄へ貼り付け、Enter送信

## ダウンロード

使い方ページ: https://yosinn1-blip.github.io/api-voice-input/

最新版はGitHub Releasesからダウンロードできます。

- https://github.com/yosinn1-blip/api-voice-input/releases

このアプリはメニューバー常駐型です。起動しても通常のウィンドウは開かず、画面上部のメニューバーに `🎙` が表示されます。

## 必要環境

- macOS 14以降
- GroqアカウントとAPIキー
- マイク権限
- アクセシビリティ権限

## 初回セットアップ

1. `API音声ソフト.app` を開きます。
2. macOSに止められる場合は、Finderで右クリックして `開く` を選びます。
3. マイク権限を許可します。
4. アクセシビリティ権限を許可します。
5. メニューバーの `🎙` から `無料のGroq APIキーを取得` を選びます。
6. GroqでAPIキーを作成し、コピーします。
7. `Groq APIキーを設定…` から貼り付けて保存します。

APIキーはMacのKeychainに保存されます。

## 使い方

1. ChatGPT / Claude / Codex などの入力欄をクリックします。
2. `Fn` を押して録音を開始します。
3. 話します。
4. `Enter` を押して録音停止・送信します。

長い文章では、貼り付け完了を待つために自動Enter送信まで少しだけ待ちます。もし送信されない場合は、もう一度 `Enter` を押してください。

## YouTube一時停止オプション

メニューの `録音開始時にYouTubeを一時停止` は、公開向け初期状態ではオフです。

オンにすると、録音開始時にブラウザやmacOSのメディア情報を使ってYouTubeの一時停止を試みます。この機能は追加のmacOS許可ダイアログが出ることがあり、環境によって動作が異なります。

通常の音声入力だけならオフのままで問題ありません。

## 配布について

このMVPは直接配布用です。App Store版やnotarize済み版ではありません。

そのため、初回起動時にmacOSのGatekeeper警告が出る場合があります。公開配布を強める場合は、Apple Developer IDでのnotarizationが次の作業です。

## 開発者向け

```bash
swift test
./scripts/dev-cycle.sh
./scripts/package-release.sh
```

release ZIPは `dist/` に作成されます。

## プライバシー

詳しくは [`PRIVACY.md`](./PRIVACY.md) を参照してください。

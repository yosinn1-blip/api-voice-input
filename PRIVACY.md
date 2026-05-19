# Privacy

API音声ソフトは、AI入力のためのローカルMacアプリです。

## 送信されるデータ

録音した音声ファイルは、文字起こしのためにGroq APIへ送信されます。

- 送信先: Groq API
- 用途: 音声の文字起こし
- モデル: `whisper-large-v3-turbo`

このアプリ独自のサーバーには送信しません。

## APIキー

Groq APIキーはmacOS Keychainに保存されます。

既存の開発環境では `~/Library/Application Support/APIVoiceInput/secrets.env` も読み込めますが、公開向けの通常利用ではKeychain保存を想定しています。

APIキーをログやチャットに貼らないでください。

## 音声ファイル

録音ファイルは処理後に削除される設計です。

無音や短すぎる録音は、Groq APIに送信する前に破棄されます。

## ログ

ログは以下に保存されます。

```text
~/Library/Application Support/APIVoiceInput/debug.log
```

ログには、処理状態、文字数、エラー分類などを記録します。APIキーは記録しません。

## 権限

このアプリは次の権限を使います。

- マイク: 音声入力の録音
- アクセシビリティ: `Fn` / `Enter` 検出、自動貼り付け、自動送信
- Apple Events: オプション機能でブラウザのYouTubeタブを一時停止する場合

## YouTube一時停止オプション

`録音開始時にYouTubeを一時停止` は初期状態ではオフです。

オンにした場合、ブラウザのYouTubeタブやmacOSのメディア情報を使って再生停止を試みます。環境によっては追加のmacOS許可が必要です。

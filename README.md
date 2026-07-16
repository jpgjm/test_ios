# Offline Music Player (iOS)

Flutter で作る iOS 向けオフライン音楽プレイヤー。FLAC / MP3 / AAC / WAV / M4A をサポート。アプリの Documents フォルダを iOS の「ファイル」アプリから読み書き可能にし、そこにあるフォルダを選択して再生する。

## 主な機能

- 音楽ファイル一覧・フォルダ階層をブラウズ
- タップして再生（同じフォルダ内の他ファイルも自動キュー化）
- ミニプレイヤー（再生/停止、前/次、シークバー）
- バックグラウンド再生 + iOS ロック画面コントロール（`just_audio_background`）
- 対応形式: `.flac` `.mp3` `.aac` `.wav` `.m4a`

## ファイル構成

Hello World と同じで、リポジトリにコミットするのは 3 ファイルのみ：

```
music-player-ipa/
├── .github/workflows/build-ipa.yml  # ワークフロー（Info.plistパッチ含む）
├── lib/main.dart                    # 音楽プレイヤー本体
├── pubspec.yaml                     # just_audio, path_provider 等の依存
└── .gitignore
```

`ios/` は CI で毎回生成される。

## Info.plist に自動注入される設定

ワークフローが `flutter create` の後に PlistBuddy で以下を追加：

| キー | 値 | 目的 |
|---|---|---|
| `UIFileSharingEnabled` | `true` | ファイルアプリでアプリのフォルダを表示 |
| `LSSupportsOpeningDocumentsInPlace` | `true` | ファイルアプリからの直接編集を許可 |
| `UIBackgroundModes` | `[audio]` | バックグラウンド再生 + ロック画面制御 |
| `CFBundleDisplayName` | `Music Player` | ホーム画面表示名 |

## 使い方（インストール後）

1. **音楽ファイルの転送**：以下いずれかで iPad の「Music Player」フォルダに音楽ファイルを入れる
   - iPad の「ファイル」アプリ → 「このiPad内」→ 「Music Player」フォルダにドラッグ
   - LocalSend で送信して手動移動
   - AirDrop で受信して「Music Player に保存」
2. **フォルダ構成**（推奨）：
   ```
   Music Player/
   ├── アルバム1/
   │   ├── 01.flac
   │   └── 02.flac
   └── お気に入り/
       ├── song1.mp3
       └── song2.aac
   ```
3. **アプリを開く**：起動するとルート直下のフォルダが表示される
4. **フォルダをタップ**して中に入り、音楽ファイルをタップして再生
5. **右上の更新ボタン**でファイル追加後の再読み込み

## リポジトリへの反映

既存の `jpgjm/ipa` リポジトリにこの中身を反映する場合の GitHub Web UI 手順：

1. `pubspec.yaml` を新しい内容で上書き（`Add file` → `Upload files` → ドラッグ）
2. `lib/main.dart` を新しい内容で上書き
3. `.github/workflows/build-ipa.yml` を新しい内容で編集
4. コミット後、Actions が自動起動 → 完了後 artifact 名は `music-player-ipa`

## 制約 / 既知の問題

- 初回起動時、フォルダにファイルが無ければ空表示。iOS の「ファイル」アプリで先にファイルを配置
- 大量のファイル（数千〜）が同じフォルダにあると `listSync` が遅くなる。実用上は数百までを想定
- 曲順は現状ファイル名昇順のみ。トラック番号順ソート等が欲しければ後で拡張
- カバーアートやタグ情報の読み取りは未実装（ファイル名のみ表示）
- 無料 Apple ID の 7 日制限は Hello World と同じ

## 改善案

- **メタデータ読み取り**：`audiotags` パッケージで ID3/FLAC タグからタイトル・アーティスト・アルバムアートを取得
- **プレイリストの永続化**：`shared_preferences` で最後に再生していた曲を記憶
- **シャッフル/リピート**：`just_audio` の `setShuffleModeEnabled` / `setLoopMode` を UI から操作可能に
- **カバーアート表示**：ミニプレイヤーに album art を表示
- **設定画面**：オーディオ品質、ソート順、テーマ切り替え等
- **Files アプリ連携改善**：`CFBundleDocumentTypes` を設定して「開く」から直接ファイルを受け取り可能に

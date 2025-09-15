# Repository Guidelines

## プロジェクト構成とモジュール
- `i2i.sh` — Ark API を用いた画像→画像生成のメイン Bash スクリプト。
- `uploads/` — タイムスタンプ付きサブフォルダに元画像をコピー（安定 URL 用にコミット）。
- `outputs/` — 生成画像をタイムスタンプ付きサブフォルダに保存。
- `README.md` — プロジェクト概要。必要に応じて使用例を拡張。

例:
```
uploads/20250101-120000/input.png
outputs/20250101-120005/generated_20250101-120005.jpg
```

## ビルド・テスト・開発コマンド
- 生成実行: `ARK_API_KEY=... ./i2i.sh path/to/image.png "Prompt text" [1440x2560]`
  - 画像を `uploads/TS/` にコピー→コミット/プッシュ→Ark 呼び出し→`outputs/TS/` に保存。
- デバッグ: `DEBUG=1 ARK_API_KEY=... ./i2i.sh ...`
  - リクエスト詳細と API キー診断（マスク）を出力。

前提: `git`, `curl`, `jq` が導入済み、`origin` リモートが GitHub を指すこと。

## コーディングスタイルと命名
- 言語: Bash。
- シェルオプション: 新規スクリプトでも `set -euo pipefail` を使用。
- インデント: 2 スペース（タブ不可）。
- 関数: `lower_snake_case`（例: `strip_all_ws`）。
- 変数: 環境/設定は `UPPER_SNAKE_CASE`（例: `ARK_API_KEY`）、ローカルは `lower_snake_case`。
- タイムスタンプ: フォルダ・ファイル名は `YYYYMMDD-HHMMSS`。

## テスト方針
- 手動確認: `DEBUG=1` で小さな画像を用い、以下を確認:
  - `uploads/` に入力画像が作成されること、
  - `outputs/` に生成画像が作成されること、
  - コンソールに RAW URL と生成 URL が表示されること。
- 追加チェック: `bash -n i2i.sh`（構文）、`shellcheck i2i.sh`（Lint、あれば）。

## コミットおよび Pull Request
- コミット: 簡潔で命令形。履歴の体裁に倣い、例: `i2i: add input.png (20250101-120000)`。
- 関連変更をまとめ、`uploads/`/`outputs/` 以外の大きなバイナリや秘匿情報はコミットしない。
- PR には以下を含める:
  - 目的と要約、
  - 再現手順または実行コマンド例、
  - 生成物のパスやスクリーンショット/リンク。

## セキュリティと設定
- `ARK_API_KEY` をコミットしない。環境変数で提供。
- ローカルの環境ファイルは非追跡（例: `.env` を `.gitignore` に）。
- キーはスクリプトで整形/検証される。異常時は `DEBUG=1` で診断。

## アーキテクチャ概要
1) 入力を GitHub バックアップの `uploads/` にコピー → 2) コミット固定 RAW URL を取得 → 3) Ark I2I API を呼び出し → 4) `outputs/` にダウンロード。

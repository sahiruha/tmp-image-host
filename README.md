# tmp-image-host

Ark API を使った画像→画像（I2I）/ テキスト→画像（T2I）スクリプト。

使い方
- 基本: `ARK_API_KEY=... ./i2i.sh path/to/image.png "Prompt text" [1440x2560]`
- 大きい/複雑なプロンプトの入力方法:
  - ファイル指定: `./i2i.sh path/to/image.png @prompt.txt` ・・・ファイル内容をそのまま使用（記号/改行安全）
  - 標準入力: `./i2i.sh path/to/image.png - < prompt.txt`
  - 文字列: `./i2i.sh path/to/image.png "短いプロンプト"`

T2I（テキスト→画像）
- 基本: `ARK_API_KEY=... ./t2i.sh "Prompt text" [1440x2560]`
- 入力方法バリエーション:
  - ファイル指定: `./t2i.sh @prompt.txt`
  - 標準入力: `./t2i.sh - < prompt.txt`
  - 文字列: `./t2i.sh "短いプロンプト"`

デバッグ
- `DEBUG=1` を付けると API キーとプロンプトの診断（長さ、先頭プレビュー、リクエスト JSON）を出力。

出力例
- `uploads/20250101-120000/input.png`
- `outputs/20250101-120005/generated_20250101-120005.jpg`
  - T2I では `uploads/TS/prompt.txt` がコミットされ、生成画像は同様に `outputs/TS/` に保存されます。

#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 目的: 画像をGitHubにコミット→commit固定の直リンクでArk I2Iを実行→生成画像を保存
# 追加: APIキーのフォーマット/空白/改行混入を検出するデバッグログ
# 使い方:
#   ARK_API_KEY=xxxx ./i2i.sh /path/to/image.png "プロンプト" [1440x2560]
# 環境: git, curl, jq
# -----------------------------------------------------------------------------
set -euo pipefail

DEBUG="${DEBUG:-0}"

#--- 小道具 -------------------------------------------------------------------
trim() { awk '{$1=$1; print}' <<<"$1"; }                 # 前後空白除去
strip_all_ws() { tr -d '\r\n\t' <<<"$1"; }               # 改行/タブ除去
head_mask() {                                            # 先頭4文字以外マスク
  local s="$1"; local head="${s:0:4}"; printf "%s****" "$head"
}
show_hex() { hexdump -v -e '/1 "%02X"' <<<"$1"; }        # 16進で可視化(改行混入検出用)

req() {  # curl実行（DEBUGなら -v）
  if [[ "$DEBUG" == "1" ]]; then
    curl -v -sS "$@"
  else
    curl -sS "$@"
  fi
}

#--- 引数処理 -----------------------------------------------------------------
if [[ $# -lt 2 ]]; then
  echo "Usage: ARK_API_KEY=xxxx $0 <image_path> <prompt|@file|- (stdin)> [size:1440x2560]" >&2
  exit 1
fi
IMG_SRC="$1"
PROMPT_SPEC="$2"
SIZE="${3:-1440x2560}"

for cmd in git curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done

: "${ARK_API_KEY:?Error: ARK_API_KEY is not set.}"

#--- APIキー整形 & 検査 --------------------------------------------------------
# 余計なクオート/改行/空白を除去
RAW_KEY="${ARK_API_KEY}"
# 1) 全体トリム
RAW_KEY="$(trim "$RAW_KEY")"
# 2) 先頭と末尾のシングル/ダブルクオートを剥がす
RAW_KEY="${RAW_KEY%\"}"; RAW_KEY="${RAW_KEY#\"}"
RAW_KEY="${RAW_KEY%\'}"; RAW_KEY="${RAW_KEY#\'}"
# 3) 改行/タブなど制御文字除去
CLEAN_KEY="$(strip_all_ws "$RAW_KEY")"

# 最低限チェック（空/短すぎ/空白含む）
if [[ -z "$CLEAN_KEY" ]]; then
  echo "Error: ARK_API_KEY becomes empty after cleaning. Re-set your key." >&2
  exit 1
fi
if [[ "$CLEAN_KEY" != "${CLEAN_KEY// /}" ]]; then
  echo "Error: ARK_API_KEY contains spaces. Remove spaces." >&2
  exit 1
fi

# 参考: 期待フォーマット（例）"ark-..." など。実際のプレフィックスは発行元仕様に依存。
# 下の正規表現はゆるめ: 英数と - _ のみ
if ! [[ "$CLEAN_KEY" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Warning: ARK_API_KEY has unusual characters. Check it." >&2
fi

if [[ "$DEBUG" == "1" ]]; then
  echo "=== API KEY DEBUG ==="
  echo "length: $(printf %s "$CLEAN_KEY" | wc -c | tr -d ' ')"
  echo "mask  : $(head_mask "$CLEAN_KEY")"
  echo "hex   : $(show_hex "$CLEAN_KEY")"
  echo "====================="
fi

#--- GitHub リポジトリ準備 -----------------------------------------------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: run in a git repo root." >&2; exit 1; }

REMOTE_URL="$(git remote get-url origin)"
if [[ "$REMOTE_URL" =~ github.com[:/]+([^/]+)/([^/.]+)(\.git)?$ ]]; then
  GH_USER="${BASH_REMATCH[1]}"
  GH_REPO="${BASH_REMATCH[2]}"
else
  echo "Error: origin is not a GitHub URL: $REMOTE_URL" >&2
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BASENAME="$(basename "$IMG_SRC")"
DEST_DIR="uploads/${TS}"
mkdir -p "$DEST_DIR"
DEST_PATH="${DEST_DIR}/${BASENAME}"
cp -f "$IMG_SRC" "$DEST_PATH"

git add "$DEST_PATH"
git commit -m "i2i: add ${BASENAME} (${TS})" >/dev/null
git push origin HEAD || git push origin HEAD

COMMIT="$(git rev-list -1 HEAD -- "$DEST_PATH")"

RAW_URL="https://raw.githubusercontent.com/${GH_USER}/${GH_REPO}/${COMMIT}/${DEST_PATH}"
CDN_URL="https://cdn.jsdelivr.net/gh/${GH_USER}/${GH_REPO}@${COMMIT}/${DEST_PATH}"

echo ">> Using image URL:"
echo "   $RAW_URL"

#--- Ark API 呼び出し ---------------------------------------------------------
API_URL="https://ark.ap-southeast.bytepluses.com/api/v3/images/generations"
MODEL="seedream-4-0-250828"

# プロンプト入力の取り扱い
# - 文字列そのもの
# - @file: ファイルから読み込み
# - -: 標準入力から読み込み
prompt_tmp=""
prompt_file=""
cleanup_prompt_tmp() { [[ -n "$prompt_tmp" && -f "$prompt_tmp" ]] && rm -f "$prompt_tmp"; }
trap cleanup_prompt_tmp EXIT

if [[ "$PROMPT_SPEC" == "-" ]]; then
  prompt_tmp="$(mktemp)"
  cat - >"$prompt_tmp"
  prompt_file="$prompt_tmp"
elif [[ "$PROMPT_SPEC" == @* ]]; then
  prompt_file="${PROMPT_SPEC#@}"
  [[ -f "$prompt_file" ]] || { echo "Error: prompt file not found: $prompt_file" >&2; exit 1; }
else
  # 単一引数として与えられた文字列を一時ファイル化（記号/改行などの安全性確保）
  prompt_tmp="$(mktemp)"
  printf "%s" "$PROMPT_SPEC" >"$prompt_tmp"
  prompt_file="$prompt_tmp"
fi

if [[ "$DEBUG" == "1" ]]; then
  echo "=== PROMPT DEBUG ==="
  echo "source : ${PROMPT_SPEC:0:1}$( [[ "$PROMPT_SPEC" == @* ]] && echo "(file)" || [[ "$PROMPT_SPEC" == "-" ]] && echo "(stdin)" || echo "(arg)")"
  echo "bytes  : $(wc -c <"$prompt_file" | tr -d ' ')"
  echo "preview: $(head -c 80 "$prompt_file" | tr '\n' ' ' | sed 's/\t/ /g')"  # 先頭80B
  echo "===================="
fi

REQ_JSON=$(jq -n --arg model "$MODEL" \
                --rawfile prompt_file "$prompt_file" \
                --arg image "$RAW_URL" \
                --arg size "$SIZE" \
                '{
                  model: $model,
                  prompt: $prompt_file,
                  image: $image,
                  sequential_image_generation: "disabled",
                  response_format: "url",
                  size: $size,
                  stream: false,
                  watermark: false
                }')

[[ "$DEBUG" == "1" ]] && echo "=== REQUEST JSON ===" && echo "$REQ_JSON" | jq '.' && echo "===================="

echo ">> Requesting Ark I2I ..."
RESP_JSON="$(req -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${CLEAN_KEY}" \
  -d "$REQ_JSON" 2>&1 || true)"

# 成功時 `.data[0].url`
GEN_URL="$(jq -r '.data[0].url // empty' <<<"$RESP_JSON" 2>/dev/null || true)"

if [[ -z "$GEN_URL" ]]; then
  echo "!! First try failed. Retrying with CDN URL ..." >&2
  REQ_JSON=$(jq --arg image "$CDN_URL" '.image = $image' <<<"$REQ_JSON")
  RESP_JSON="$(req -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${CLEAN_KEY}" \
    -d "$REQ_JSON" 2>&1 || true)"
  GEN_URL="$(jq -r '.data[0].url // empty' <<<"$RESP_JSON" 2>/dev/null || true)"
fi

if [[ -z "$GEN_URL" ]]; then
  echo "Error: Generation failed. Raw response/logs below:" >&2
  # curl -v の混在出力をそのまま吐く（DEBUG=1なら詳細ヘッダつき）
  if command -v jq >/dev/null 2>&1; then
    echo "$RESP_JSON" | jq '.' 2>/dev/null || echo "$RESP_JSON"
  else
    echo "$RESP_JSON"
  fi
  exit 1
fi

OUT_DIR="outputs/${TS}"
mkdir -p "$OUT_DIR"
OUT_PATH="${OUT_DIR}/generated_${TS}.jpg"
curl -sSL "$GEN_URL" -o "$OUT_PATH"

echo "✅ Done."
echo " - Source image URL: $RAW_URL"
echo " - Generation URL  : $GEN_URL"
echo " - Saved to        : $OUT_PATH"

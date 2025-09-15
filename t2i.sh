#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 目的: Ark T2I を実行（テキスト→画像）。
# 流れ: プロンプトをファイル化→uploads/TS/ に保存しコミット→Ark を呼び出し→outputs/TS/ に保存
# 追加: APIキーのフォーマット/空白/改行混入を検出するデバッグログ
# 使い方:
#   ARK_API_KEY=xxxx ./t2i.sh "プロンプト" [1440x2560]
#   ARK_API_KEY=xxxx ./t2i.sh @prompt.txt [1440x2560]
#   ARK_API_KEY=xxxx ./t2i.sh - [1440x2560] < prompt.txt
# 前提: git, curl, jq
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
if [[ $# -lt 1 ]]; then
  echo "Usage: ARK_API_KEY=xxxx $0 <prompt|@file|- (stdin)> [size:1440x2560]" >&2
  exit 1
fi
PROMPT_SPEC="$1"
SIZE="${2:-1440x2560}"

for cmd in git curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done

: "${ARK_API_KEY:?Error: ARK_API_KEY is not set.}"

#--- APIキー整形 & 検査 --------------------------------------------------------
RAW_KEY="${ARK_API_KEY}"
RAW_KEY="$(trim "$RAW_KEY")"                         # 1) 全体トリム
RAW_KEY="${RAW_KEY%\"}"; RAW_KEY="${RAW_KEY#\"}"   # 2) 余計なクオート剥がし
RAW_KEY="${RAW_KEY%\'}"; RAW_KEY="${RAW_KEY#\'}"
CLEAN_KEY="$(strip_all_ws "$RAW_KEY")"                # 3) 改行/タブなど除去

if [[ -z "$CLEAN_KEY" ]]; then
  echo "Error: ARK_API_KEY becomes empty after cleaning. Re-set your key." >&2
  exit 1
fi
if [[ "$CLEAN_KEY" != "${CLEAN_KEY// /}" ]]; then
  echo "Error: ARK_API_KEY contains spaces. Remove spaces." >&2
  exit 1
fi
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

#--- プロンプトの取り扱い ------------------------------------------------------
prompt_tmp=""
prompt_file_src=""
cleanup_prompt_tmp() { [[ -n "$prompt_tmp" && -f "$prompt_tmp" ]] && rm -f "$prompt_tmp"; }
trap cleanup_prompt_tmp EXIT

if [[ "$PROMPT_SPEC" == "-" ]]; then
  prompt_tmp="$(mktemp)"
  cat - >"$prompt_tmp"
  prompt_file_src="$prompt_tmp"
elif [[ "$PROMPT_SPEC" == @* ]]; then
  prompt_file_src="${PROMPT_SPEC#@}"
  [[ -f "$prompt_file_src" ]] || { echo "Error: prompt file not found: $prompt_file_src" >&2; exit 1; }
else
  prompt_tmp="$(mktemp)"
  printf "%s" "$PROMPT_SPEC" >"$prompt_tmp"
  prompt_file_src="$prompt_tmp"
fi

if [[ "$DEBUG" == "1" ]]; then
  echo "=== PROMPT DEBUG ==="
  echo "source : ${PROMPT_SPEC:0:1}$( [[ "$PROMPT_SPEC" == @* ]] && echo "(file)" || [[ "$PROMPT_SPEC" == "-" ]] && echo "(stdin)" || echo "(arg)")"
  echo "bytes  : $(wc -c <"$prompt_file_src" | tr -d ' ')"
  echo "preview: $(head -c 80 "$prompt_file_src" | tr '\n' ' ' | sed 's/\t/ /g')"
  echo "===================="
fi

# uploads にバックアップ（再現性/履歴のため）
TS="$(date +%Y%m%d-%H%M%S)"
DEST_DIR="uploads/${TS}"
mkdir -p "$DEST_DIR"
PROMPT_DEST="${DEST_DIR}/prompt.txt"
cp -f "$prompt_file_src" "$PROMPT_DEST"

git add "$PROMPT_DEST"
git commit -m "t2i: add prompt.txt (${TS})" >/dev/null
git push origin HEAD || git push origin HEAD

COMMIT="$(git rev-list -1 HEAD -- "$PROMPT_DEST")"

#--- Ark API 呼び出し（T2I） --------------------------------------------------
API_URL="https://ark.ap-southeast.bytepluses.com/api/v3/images/generations"
MODEL="seedream-4-0-250828"

REQ_JSON=$(jq -n --arg model "$MODEL" \
                --rawfile prompt_file "$PROMPT_DEST" \
                --arg size "$SIZE" \
                '{
                  model: $model,
                  prompt: $prompt_file,
                  response_format: "url",
                  size: $size,
                  stream: false,
                  watermark: false
                }')

[[ "$DEBUG" == "1" ]] && echo "=== REQUEST JSON ===" && echo "$REQ_JSON" | jq '.' && echo "===================="

echo ">> Requesting Ark T2I ..."
RESP_JSON="$(req -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${CLEAN_KEY}" \
  -d "$REQ_JSON" 2>&1 || true)"

GEN_URL="$(jq -r '.data[0].url // empty' <<<"$RESP_JSON" 2>/dev/null || true)"

if [[ -z "$GEN_URL" ]]; then
  echo "Error: Generation failed. Raw response/logs below:" >&2
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
echo " - Prompt file     : $PROMPT_DEST"
echo " - Generation URL  : $GEN_URL"
echo " - Saved to        : $OUT_PATH"


#!/usr/bin/env bash
set -euo pipefail

MODE="t2v"
MODEL="distilled"
PROMPT=""
NUM_FRAMES=240
GUIDANCE=1.0
PYRAMID_STEPS="2 2 2"
STAGE2=1
AMPLIFY=1
COMPILE=1
TF32=1
USE_TRANSFORMER_PATH=0  # default OFF to reduce transformer type mismatch warnings

HELIOS_DIR="/workspace/Helios"
OUTPUT_ROOT="$HELIOS_DIR/output_helios"
MODEL_PATH=""

# NEW:
START_IMAGE=""
END_IMAGE=""
VIDEO_PATH=""

export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"

usage() {
  cat <<'EOF'
Usage: bash run_helios_v21.sh --prompt "..." [options]

Required:
  --prompt "TEXT"

Options:
  --mode t2v|i2v|v2v
  --model base|mid|distilled
  --frames N
  --guidance X
  --steps "a b c"
  --start-image /path/to/start.png
  --end-image /path/to/end.png
  --video /path/to/input.mp4
  --no-stage2
  --no-amplify
  --no-compile
  --no-tf32
  --use-transformer-path
  --no-transformer-path
  --model-path PATH
  --helios-dir PATH
  --output-root PATH
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) PROMPT="${2:-}"; shift 2;;
    --mode) MODE="${2:-}"; shift 2;;
    --model) MODEL="${2:-}"; shift 2;;
    --frames) NUM_FRAMES="${2:-}"; shift 2;;
    --guidance) GUIDANCE="${2:-}"; shift 2;;
    --steps) PYRAMID_STEPS="${2:-}"; shift 2;;
    --start-image) START_IMAGE="${2:-}"; shift 2;;
    --end-image) END_IMAGE="${2:-}"; shift 2;;
    --video) VIDEO_PATH="${2:-}"; shift 2;;
    --no-stage2) STAGE2=0; shift 1;;
    --no-amplify) AMPLIFY=0; shift 1;;
    --no-compile) COMPILE=0; shift 1;;
    --no-tf32) TF32=0; shift 1;;
    --use-transformer-path) USE_TRANSFORMER_PATH=1; shift 1;;
    --no-transformer-path) USE_TRANSFORMER_PATH=0; shift 1;;
    --model-path) MODEL_PATH="${2:-}"; shift 2;;
    --helios-dir) HELIOS_DIR="${2:-}"; shift 2;;
    --output-root) OUTPUT_ROOT="${2:-}"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

[[ -n "$PROMPT" ]] || { echo "ERROR: --prompt required"; exit 2; }

cd "$HELIOS_DIR"
[[ -d "$HELIOS_DIR/.venv" ]] || { echo "ERROR: venv missing. Run bootstrap first."; exit 3; }
source "$HELIOS_DIR/.venv/bin/activate"

if [[ -z "$MODEL_PATH" ]]; then
  if [[ -f "$HELIOS_DIR/.runpod/model_path.txt" ]]; then
    MODEL_PATH="$(cat "$HELIOS_DIR/.runpod/model_path.txt")"
  fi
fi

[[ -n "$MODEL_PATH" ]] || { echo "ERROR: model path not found. Provide --model-path or run bootstrap."; exit 4; }
[[ -f "$MODEL_PATH/model_index.json" ]] || { echo "ERROR: model_index.json missing in $MODEL_PATH"; exit 5; }

# Validate files if provided
if [[ -n "$START_IMAGE" ]]; then [[ -f "$START_IMAGE" ]] || { echo "ERROR: start-image not found: $START_IMAGE"; exit 6; }; fi
if [[ -n "$END_IMAGE" ]]; then [[ -f "$END_IMAGE" ]] || { echo "ERROR: end-image not found: $END_IMAGE"; exit 7; }; fi
if [[ -n "$VIDEO_PATH" ]]; then [[ -f "$VIDEO_PATH" ]] || { echo "ERROR: video not found: $VIDEO_PATH"; exit 8; }; fi

# TF32 speed boost
if [[ "$TF32" -eq 1 ]]; then
  if ! grep -q "set_float32_matmul_precision" "$HELIOS_DIR/infer_helios.py"; then
    sed -i "/^import torch/a torch.set_float32_matmul_precision('high')" "$HELIOS_DIR/infer_helios.py" || true
  fi
fi

TS="$(date +%Y-%m-%d_%H%M%S)"
OUT_DIR="$OUTPUT_ROOT/${MODEL}_${MODE}/${TS}"
mkdir -p "$OUT_DIR"

ARGS=(
  "--base_model_path" "$MODEL_PATH"
  "--sample_type" "$MODE"
  "--prompt" "$PROMPT"
  "--num_frames" "$NUM_FRAMES"
  "--guidance_scale" "$GUIDANCE"
  "--output_folder" "$OUT_DIR"
  "--pyramid_num_inference_steps_list"
)
# shellcheck disable=SC2206
STEPS_ARR=($PYRAMID_STEPS)
ARGS+=("${STEPS_ARR[@]}")

if [[ "$USE_TRANSFORMER_PATH" -eq 1 ]]; then
  ARGS+=("--transformer_path" "$MODEL_PATH")
fi
if [[ "$STAGE2" -eq 1 ]]; then
  ARGS+=("--is_enable_stage2")
fi
if [[ "$AMPLIFY" -eq 1 ]]; then
  ARGS+=("--is_amplify_first_chunk")
fi
if [[ "$COMPILE" -eq 1 ]]; then
  ARGS+=("--enable_compile")
fi

# Helper to find CLI flag in --help output
HELP_TXT=""
if [[ -n "$START_IMAGE" || -n "$END_IMAGE" || -n "$VIDEO_PATH" ]]; then
  HELP_TXT="$(python "$HELIOS_DIR/infer_helios.py" --help 2>/dev/null || true)"
fi
find_flag () {
  local value="$1"; shift
  local -a candidates=("$@")
  local found=""
  for c in "${candidates[@]}"; do
    if echo "$HELP_TXT" | grep -qE "(^|[[:space:]])${c}([[:space:]]|,|$)"; then
      found="$c"
      break
    fi
  done
  if [[ -z "$found" ]]; then
    echo ""
    return 1
  fi
  echo "$found"
  return 0
}

# Attach start image if provided
if [[ -n "$START_IMAGE" ]]; then
  CAND=(--start_image --start_image_path --image_path --input_image --init_image --init_image_path --ref_image)
  FLAG="$(find_flag "$START_IMAGE" "${CAND[@]}" || true)"
  [[ -n "$FLAG" ]] || { echo "ERROR: start-image provided but no known flag found in infer_helios.py --help"; exit 9; }
  echo "[run] start-image flag: $FLAG"
  ARGS+=("$FLAG" "$START_IMAGE")
fi

# Attach end image if provided
if [[ -n "$END_IMAGE" ]]; then
  CAND=(--end_image --end_image_path --target_image --target_image_path --final_image --final_image_path)
  FLAG="$(find_flag "$END_IMAGE" "${CAND[@]}" || true)"
  [[ -n "$FLAG" ]] || { echo "ERROR: end-image provided but no known flag found in infer_helios.py --help"; exit 10; }
  echo "[run] end-image flag: $FLAG"
  ARGS+=("$FLAG" "$END_IMAGE")
fi

# Attach video if provided (for v2v)
if [[ -n "$VIDEO_PATH" ]]; then
  CAND=(--video_path --input_video --input_video_path --video --video_file --source_video --source_video_path)
  FLAG="$(find_flag "$VIDEO_PATH" "${CAND[@]}" || true)"
  [[ -n "$FLAG" ]] || { echo "ERROR: --video provided but no known video flag found in infer_helios.py --help"; exit 11; }
  echo "[run] video flag: $FLAG"
  ARGS+=("$FLAG" "$VIDEO_PATH")
fi

echo "[run] mode=$MODE model=$MODEL frames=$NUM_FRAMES guidance=$GUIDANCE steps=($PYRAMID_STEPS)"
echo "[run] model_path=$MODEL_PATH"
echo "[run] out_dir=$OUT_DIR"
echo "[run] start_image=${START_IMAGE:-<none>}"
echo "[run] end_image=${END_IMAGE:-<none>}"
echo "[run] video=${VIDEO_PATH:-<none>}"
echo "[run] transformer_path=$USE_TRANSFORMER_PATH stage2=$STAGE2 amplify=$AMPLIFY compile=$COMPILE tf32=$TF32"
echo

CUDA_VISIBLE_DEVICES=0 python "$HELIOS_DIR/infer_helios.py" "${ARGS[@]}"

echo
echo "[run] DONE -> $OUT_DIR"


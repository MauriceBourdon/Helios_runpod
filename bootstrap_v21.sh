#!/usr/bin/env bash
set -euo pipefail

MODEL="${MODEL:-distilled}"
DOWNLOAD="auto"     # auto|yes|no
HELIOS_DIR="/workspace/Helios"

HF_REPO_BASE="BestWishYSH/Helios-Base"
HF_REPO_MID="BestWishYSH/Helios-Mid"
HF_REPO_DISTILLED="BestWishYSH/Helios-Distilled"

CUSTOM_REPO=""
CUSTOM_LOCAL_DIR=""

export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"

usage() {
  echo "Usage: bash bootstrap_v21.sh [--model base|mid|distilled] [--download auto|yes|no] [--repo REPO_ID] [--local-dir PATH] [--helios-dir PATH]"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="${2:-}"; shift 2;;
    --download) DOWNLOAD="${2:-}"; shift 2;;
    --repo) CUSTOM_REPO="${2:-}"; shift 2;;
    --local-dir) CUSTOM_LOCAL_DIR="${2:-}"; shift 2;;
    --helios-dir) HELIOS_DIR="${2:-}"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

case "$MODEL" in
  base) HF_REPO="${CUSTOM_REPO:-$HF_REPO_BASE}" ;;
  mid) HF_REPO="${CUSTOM_REPO:-$HF_REPO_MID}" ;;
  distilled) HF_REPO="${CUSTOM_REPO:-$HF_REPO_DISTILLED}" ;;
  *) echo "Invalid --model: $MODEL"; exit 2;;
esac

LOCAL_ROOT="$HELIOS_DIR/BestWishYSH"
LOCAL_DIR_DEFAULT="$LOCAL_ROOT/$(basename "$HF_REPO")"
LOCAL_DIR="${CUSTOM_LOCAL_DIR:-$LOCAL_DIR_DEFAULT}"

echo "[bootstrap] model=$MODEL repo=$HF_REPO local_dir=$LOCAL_DIR download=$DOWNLOAD"
echo "[bootstrap] HELIOS_DIR=$HELIOS_DIR"
echo "[bootstrap] HF_HUB_DISABLE_XET=$HF_HUB_DISABLE_XET"

# Clone Helios if needed
if [[ ! -d "$HELIOS_DIR" ]]; then
  echo "[bootstrap] cloning Helios..."
  git clone --depth=1 https://github.com/PKU-YuanGroup/Helios.git "$HELIOS_DIR"
fi
cd "$HELIOS_DIR"

# Ensure runpod state dir exists
mkdir -p "$HELIOS_DIR/.runpod"

# Create venv if missing
if [[ ! -d "$HELIOS_DIR/.venv" ]]; then
  echo "[bootstrap] creating venv..."
  python3 -m venv "$HELIOS_DIR/.venv"
fi
source "$HELIOS_DIR/.venv/bin/activate"
python -m pip install --upgrade pip setuptools wheel

# Install deps only once (flag file)
if [[ -f "$HELIOS_DIR/.runpod/deps_ok.txt" ]]; then
  echo "[bootstrap] deps already installed (deps_ok.txt). Skipping install.sh"
else
  echo "[bootstrap] installing deps (install.sh)..."
  bash install.sh
  pip install -U "huggingface_hub[cli]"
  echo "ok" > "$HELIOS_DIR/.runpod/deps_ok.txt"
fi

# Patch missing importlib (repo bug seen in practice)
if ! grep -q "^import importlib" "$HELIOS_DIR/infer_helios.py"; then
  echo "[bootstrap] patch infer_helios.py: importlib"
  sed -i '1i import importlib' "$HELIOS_DIR/infer_helios.py"
fi

# record model path for runner
echo "$LOCAL_DIR" > "$HELIOS_DIR/.runpod/model_path.txt"

MODEL_OK=0
if [[ -f "$LOCAL_DIR/model_index.json" ]]; then
  MODEL_OK=1
fi

case "$DOWNLOAD" in
  no)
    [[ $MODEL_OK -eq 1 ]] || { echo "[bootstrap] missing model at $LOCAL_DIR (download=no)"; exit 3; }
    ;;
  yes)
    echo "[bootstrap] downloading $HF_REPO..."
    hf download "$HF_REPO" --local-dir "$LOCAL_DIR"
    ;;
  auto)
    if [[ $MODEL_OK -eq 1 ]]; then
      echo "[bootstrap] model already present."
    else
      echo "[bootstrap] downloading $HF_REPO..."
      hf download "$HF_REPO" --local-dir "$LOCAL_DIR"
    fi
    ;;
  *) echo "Invalid --download: $DOWNLOAD"; exit 2;;
esac

echo "[bootstrap] done."

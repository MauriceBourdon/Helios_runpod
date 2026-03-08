#!/usr/bin/env bash
set -euo pipefail

MODEL="${MODEL:-distilled}"
DOWNLOAD="auto"     # auto|yes|no
HELIOS_DIR="${HELIOS_DIR:-/workspace/Helios}"

HF_REPO_BASE="BestWishYSH/Helios-Base"
HF_REPO_MID="BestWishYSH/Helios-Mid"
HF_REPO_DISTILLED="BestWishYSH/Helios-Distilled"

CUSTOM_REPO=""

export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"

# Force HF caches + temp to /workspace (RunPod-friendly)
mkdir -p /workspace/.cache/huggingface /workspace/tmp
export HF_HOME=/workspace/.cache/huggingface
export HF_HUB_CACHE=/workspace/.cache/huggingface/hub
export TRANSFORMERS_CACHE=/workspace/.cache/huggingface/transformers
export DIFFUSERS_CACHE=/workspace/.cache/huggingface/diffusers
export TMPDIR=/workspace/tmp
export TEMP=/workspace/tmp
export TMP=/workspace/tmp

usage() {
  echo "Usage: bash bootstrap_v21.sh [--model base|mid|distilled] [--download auto|yes|no] [--repo REPO_ID] [--helios-dir PATH]"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="${2:-}"; shift 2;;
    --download) DOWNLOAD="${2:-}"; shift 2;;
    --repo) CUSTOM_REPO="${2:-}"; shift 2;;
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

echo "[bootstrap] model=$MODEL repo=$HF_REPO download=$DOWNLOAD"
echo "[bootstrap] HELIOS_DIR=$HELIOS_DIR"
echo "[bootstrap] HF_HOME=$HF_HOME"
echo "[bootstrap] HF_HUB_CACHE=$HF_HUB_CACHE"
echo "[bootstrap] TMPDIR=$TMPDIR"

# Clone Helios if needed
if [[ ! -f "$HELIOS_DIR/infer_helios.py" ]]; then
echo "[bootstrap] cloning Helios..."
  git clone --depth=1 https://github.com/PKU-YuanGroup/Helios.git "$HELIOS_DIR"
fi
cd "$HELIOS_DIR"

# Ensure runpod state dir exists
mkdir -p "$HELIOS_DIR/.runpod"

# Create venv if missing (reuse torch from system image)
if [[ ! -d "$HELIOS_DIR/.venv" ]]; then
  echo "[bootstrap] creating venv (system-site-packages)..."
  python3 -m venv "$HELIOS_DIR/.venv" --system-site-packages
fi
source "$HELIOS_DIR/.venv/bin/activate"
python -m pip install --upgrade pip setuptools wheel

# Install deps only once (flag file)
if [[ -f "$HELIOS_DIR/.runpod/deps_ok.txt" ]]; then
  echo "[bootstrap] deps already installed (deps_ok.txt). Skipping install.sh"
else
  echo "[bootstrap] installing deps (install.sh)..."
  bash install.sh
  echo "ok" > "$HELIOS_DIR/.runpod/deps_ok.txt"
fi

# Ensure HF CLI + libs available
python -m pip install -U "huggingface_hub[cli]" >/dev/null 2>&1 || true

# Patch missing importlib (repo bug seen in practice)
if ! grep -q "^import importlib" "$HELIOS_DIR/infer_helios.py"; then
  echo "[bootstrap] patch infer_helios.py: importlib"
  sed -i '1i import importlib' "$HELIOS_DIR/infer_helios.py"
fi

# Stage2 scheduler KeyError patch (safe one-liner), apply only if pattern exists
python - <<'PY' || true
import pathlib
p = pathlib.Path("/workspace/Helios/helios/diffusers_version/pipeline_helios_diffusers.py")
if p.exists():
    txt = p.read_text()
    old = "ori_sigma = 1 - self.scheduler.ori_start_sigmas[i_s]  # the original coeff of signal"
    new = "ori_sigma = 1 - self.scheduler.ori_start_sigmas.get(i_s, self.scheduler.ori_start_sigmas.get(0, 0.0))  # the original coeff of signal"
    if old in txt and new not in txt:
        p.write_text(txt.replace(old, new, 1))
        print("[bootstrap] patched Stage2 ori_start_sigmas KeyError")
PY

# Pre-download model into HF cache (diffusers-style), and record snapshot path for runner
MODEL_SNAPSHOT_PATH=""
export HF_REPO="$HF_REPO"

case "$DOWNLOAD" in
  no)
    echo "[bootstrap] download=no -> expecting model already in HF cache."
    ;;
  yes|auto)
    echo "[bootstrap] snapshot_download (cache) for $HF_REPO ..."
    MODEL_SNAPSHOT_PATH="$(python - <<'PY'
from huggingface_hub import snapshot_download
import os
repo = os.environ["HF_REPO"]
cache_dir = os.environ.get("HF_HUB_CACHE")
p = snapshot_download(repo_id=repo, cache_dir=cache_dir)
print(p)
PY
)"
    ;;
  *)
    echo "Invalid --download: $DOWNLOAD"
    exit 2
    ;;
esac

# Record model path for runner (prefer snapshot path)
if [[ -n "$MODEL_SNAPSHOT_PATH" ]]; then
  echo "$MODEL_SNAPSHOT_PATH" > "$HELIOS_DIR/.runpod/model_path.txt"
  echo "[bootstrap] model snapshot: $MODEL_SNAPSHOT_PATH"
else
  # fallback: keep old behavior (runner may use repo_id instead)
  echo "$HF_REPO" > "$HELIOS_DIR/.runpod/model_path.txt"
  echo "[bootstrap] model snapshot not resolved; recorded repo id: $HF_REPO"
fi

echo "[bootstrap] done."

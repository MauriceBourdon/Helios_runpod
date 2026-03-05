#!/usr/bin/env bash
set -euo pipefail

echo "Helios Menu (v2.1)"
read -rp "Mode (t2v/i2v/v2v) [t2v]: " MODE
MODE="${MODE:-t2v}"

read -rp "Model (base/mid/distilled) [distilled]: " MODEL
MODEL="${MODEL:-distilled}"

read -rp "Frames (multiple of 33 recommended) [240]: " FR
FR="${FR:-240}"

read -rp "Guidance [1.0]: " GS
GS="${GS:-1.0}"

read -rp "Disable compile autotune? (y/N): " NC
NO_COMPILE=""
if [[ "${NC,,}" == "y" ]]; then NO_COMPILE="--no-compile"; fi

read -rp "Use transformer_path? (y/N) [recommended: N]: " UT
USE_TP=""
if [[ "${UT,,}" == "y" ]]; then USE_TP="--use-transformer-path"; fi

echo
echo "Enter prompt (end with Ctrl+D):"
PROMPT="$(cat)"

bash /opt/helios/run_helios_v21.sh   --mode "$MODE" --model "$MODEL" --frames "$FR" --guidance "$GS"   $NO_COMPILE $USE_TP   --prompt "$PROMPT"

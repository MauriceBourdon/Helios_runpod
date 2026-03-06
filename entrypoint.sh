#!/usr/bin/env bash
set -euo pipefail

HELIOS_DIR="${HELIOS_DIR:-/workspace/Helios}"
BOOTSTRAP_DOWNLOAD="${BOOTSTRAP_DOWNLOAD:-auto}"
BOOTSTRAP_SESSION="${BOOTSTRAP_SESSION:-helios_boot}"
BOOTSTRAP_LOG_DIR="${HELIOS_DIR}/.runpod"
BOOTSTRAP_LOG="${BOOTSTRAP_LOG_DIR}/bootstrap.log"

echo "[entrypoint] Helios v2.1"
echo "[entrypoint] HF_HUB_DISABLE_XET=${HF_HUB_DISABLE_XET:-1}"
echo "[entrypoint] If you set HF_TOKEN env var, model download will be faster."
echo "[entrypoint] Helios dir: ${HELIOS_DIR}"
echo "[entrypoint] Bootstrap log: ${BOOTSTRAP_LOG}"

mkdir -p "$BOOTSTRAP_LOG_DIR"

RUNPOD_PID=""
JUPYTER_PID=""

if [[ -x /start.sh ]]; then
  echo "[entrypoint] starting RunPod services via /start.sh"
  /start.sh &
  RUNPOD_PID="$!"
else
  echo "[entrypoint] /start.sh not found; falling back to local Jupyter startup"
  if command -v jupyter-lab >/dev/null 2>&1; then
    jupyter-lab --allow-root --no-browser --port=8888 --ip=0.0.0.0 \
      --ServerApp.allow_origin="*" \
      --ServerApp.preferred_dir=/workspace &
    JUPYTER_PID="$!"
  elif command -v jupyter >/dev/null 2>&1; then
    jupyter lab --allow-root --no-browser --port=8888 --ip=0.0.0.0 \
      --ServerApp.allow_origin="*" \
      --ServerApp.preferred_dir=/workspace &
    JUPYTER_PID="$!"
  else
    echo "[entrypoint] jupyter command not found; container will stay alive without UI services"
  fi
fi

if command -v tmux >/dev/null 2>&1; then
  if ! tmux has-session -t "$BOOTSTRAP_SESSION" 2>/dev/null; then
    echo "[entrypoint] starting bootstrap in tmux session: ${BOOTSTRAP_SESSION}"
    tmux new -d -s "$BOOTSTRAP_SESSION" "mkdir -p '$BOOTSTRAP_LOG_DIR'; bash /opt/helios/bootstrap_v21.sh --download '$BOOTSTRAP_DOWNLOAD' 2>&1 | tee -a '$BOOTSTRAP_LOG'; exec bash"
  else
    echo "[entrypoint] bootstrap tmux session already exists: ${BOOTSTRAP_SESSION}"
  fi
else
  echo "[entrypoint] tmux not found, running bootstrap in foreground"
  bash /opt/helios/bootstrap_v21.sh --download "$BOOTSTRAP_DOWNLOAD"
fi

cat <<'EOF'

[entrypoint] Useful commands:

# Watch bootstrap logs:
tmux attach -t helios_boot
tail -f /workspace/Helios/.runpod/bootstrap.log

# Run Helios (after model is present):
bash /opt/helios/run_helios_v21.sh --mode t2v --model distilled --prompt "..."

# Open interactive menu:
bash /opt/helios/menu_helios.sh

EOF

if [[ -n "$RUNPOD_PID" ]]; then
  wait "$RUNPOD_PID"
elif [[ -n "$JUPYTER_PID" ]]; then
  wait "$JUPYTER_PID"
else
  tail -f /dev/null
fi

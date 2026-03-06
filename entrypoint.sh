#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] Helios v2.1"
echo "[entrypoint] HF_HUB_DISABLE_XET=${HF_HUB_DISABLE_XET:-1}"
echo "[entrypoint] If you set HF_TOKEN env var, model download will be faster."

if command -v tmux >/dev/null 2>&1; then
  if ! tmux has-session -t helios_boot 2>/dev/null; then
    echo "[entrypoint] starting bootstrap in tmux session: helios_boot"
    tmux new -d -s helios_boot "bash /opt/helios/bootstrap_v21.sh --download auto || bash"
  else
    echo "[entrypoint] bootstrap tmux session already exists"
  fi
else
  echo "[entrypoint] tmux not found, running bootstrap in foreground"
  bash /opt/helios/bootstrap_v21.sh --download auto
fi

cat <<'EOF'

[entrypoint] Useful commands:

# Watch bootstrap logs:
tmux attach -t helios_boot

# Run Helios (after model is present):
bash /opt/helios/run_helios_v21.sh --mode t2v --model distilled --prompt "..."

# Open interactive menu:
bash /opt/helios/menu_helios.sh

EOF

# Start JupyterLab on 8888 (needed for RunPod proxy)
if command -v jupyter-lab >/dev/null 2>&1; then
  echo "[entrypoint] starting jupyter-lab on :8888"
  jupyter-lab --allow-root --no-browser --port=8888 --ip=0.0.0.0 \
    --ServerApp.allow_origin="*" \
    --ServerApp.preferred_dir=/workspace &
else
  echo "[entrypoint] jupyter-lab not found"
fi

# keep container alive
wait

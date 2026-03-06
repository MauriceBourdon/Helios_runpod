# Helios RunPod Template v2.1 (files to commit)

This folder is meant to be committed to Git as-is.

## What it does
- Builds on an official RunPod PyTorch base image (CUDA 12.8.1 / torch 2.8)
- Keeps model weights OUT of the Docker image (download into /workspace)
- Starts the native RunPod services first (`/start.sh`) so Jupyter/SSH/web terminal keep working
- Auto bootstraps Helios in a tmux session so setup can run without blocking the pod UI
- Provides a runner with prompt args + dated output folders

## Build & push
```bash
docker build -t <your_dockerhub_user>/helios-runpod:v2.1 .
docker push <your_dockerhub_user>/helios-runpod:v2.1
```

## RunPod Template UI
- Container Image: `<your_dockerhub_user>/helios-runpod:v2.1`
- Exposed Ports:
  - 8888 / HTTP (Jupyter)
  - 22 / TCP (SSH)
- Env Vars (recommended):
  - HF_HUB_DISABLE_XET=1
  - HF_TOKEN=<your_hf_token>
  - optional: MODEL=distilled
- Start Command:
  - leave it empty so the Docker `CMD` is used
  - if you override it manually, use `bash /opt/helios/entrypoint.sh`

Important:
- If you replace the start command with a custom command that does not call `/start.sh`, RunPod's Jupyter, SSH, and web terminal services will not come up.

## After start
Bootstrap logs:
```bash
tmux attach -t helios_boot
tail -f /workspace/Helios/.runpod/bootstrap.log
```

Run:
```bash
bash /opt/helios/run_helios_v21.sh --mode t2v --model distilled --prompt "cinematic porsche chase..." --frames 240
```

Menu:
```bash
bash /opt/helios/menu_helios.sh
```

Outputs:
- `/workspace/Helios/output_helios/<model>_<mode>/<timestamp>/`

Tip:
- Add `--no-compile` to reduce time-to-first-frame.
- Default runner does NOT pass `--transformer_path` to reduce transformer type mismatch warnings.

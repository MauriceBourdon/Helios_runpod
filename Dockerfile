FROM runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404

ENV DEBIAN_FRONTEND=noninteractive
ENV HF_HUB_DISABLE_XET=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y \
    git git-lfs ffmpeg nano curl wget tmux \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/helios
WORKDIR /opt/helios

COPY entrypoint.sh /opt/helios/entrypoint.sh
COPY bootstrap_v21.sh /opt/helios/bootstrap_v21.sh
COPY run_helios_v21.sh /opt/helios/run_helios_v21.sh
COPY menu_helios.sh /opt/helios/menu_helios.sh

RUN chmod +x /opt/helios/*.sh

# In RunPod Template UI, set Start Command to:
#   bash /opt/helios/entrypoint.sh

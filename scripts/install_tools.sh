#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/install_tools.sh
# Purpose: Installs Docker, KinD (Kubernetes-in-Docker), and kubectl
# ==============================================================================
set -euo pipefail

echo "=================================================================="
echo " [Step 1/3] Checking and Installing Base Dependencies & Docker"
echo "=================================================================="

# Ensure user is in docker group
sudo usermod -aG docker "$USER" || true
sudo systemctl enable --now docker containerd

# Increase inotify limits required by KinD multi-node clusters
echo "==> Configuring kernel inotify and file limits for multi-node cluster..."
sudo sysctl -w fs.inotify.max_user_watches=524288 >/dev/null
sudo sysctl -w fs.inotify.max_user_instances=8192 >/dev/null
sudo sysctl -w fs.file-max=2097152 >/dev/null

cat << 'EOF' | sudo tee /etc/sysctl.d/99-kubernetes.conf >/dev/null
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
fs.file-max = 2097152
EOF

# Verify Docker
if ! sudo docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running."
    exit 1
fi
echo "==> Docker is active and running."

echo "=================================================================="
echo " [Step 2/3] Installing KinD (Kubernetes in Docker)"
echo "=================================================================="
if ! command -v kind >/dev/null 2>&1; then
    echo "==> Downloading kind binary..."
    KIND_VERSION="v0.27.0"
    ARCH=$(dpkg --print-architecture)
    sudo curl -Lo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}"
    sudo chmod +x /usr/local/bin/kind
    echo "==> KinD installed successfully: $(kind --version)"
else
    echo "==> KinD is already installed: $(kind --version)"
fi

echo "=================================================================="
echo " [Step 3/3] Installing kubectl"
echo "=================================================================="
if ! command -v kubectl >/dev/null 2>&1; then
    echo "==> Downloading kubectl binary..."
    K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    sudo curl -Lo /usr/local/bin/kubectl "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
    sudo chmod +x /usr/local/bin/kubectl
    echo "==> kubectl installed successfully: $(kubectl version --client --output=yaml | grep gitVersion || true)"
else
    echo "==> kubectl is already installed."
fi

echo "=================================================================="
echo " ==> All tools and prerequisites are installed and verified! <== "
echo "=================================================================="

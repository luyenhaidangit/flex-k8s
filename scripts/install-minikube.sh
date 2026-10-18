#!/usr/bin/env bash
# Cài đặt kubectl + minikube trên Ubuntu/WSL2 (amd64) để chạy Kubernetes local.
# Cách dùng: chmod +x install-minikube.sh && ./install-minikube.sh
# Chạy lại nhiều lần an toàn (idempotent). Không tự tạo cluster — chạy create-cluster.sh (hoặc xem docs/infrastructure/k8s-level-1.md Bước 3).

set -euo pipefail

# Nếu không phải root thì dùng sudo
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
if [ "$ARCH" != "amd64" ]; then
  echo "!! Script chỉ hỗ trợ kiến trúc amd64 (phát hiện: ${ARCH:-unknown})." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cd "$TMP_DIR"

echo ">> Cài kubectl..."
KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
$SUDO install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

echo ">> Cài minikube..."
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
$SUDO install minikube-linux-amd64 /usr/local/bin/minikube

echo ">> Kiểm tra cài đặt:"
kubectl version --client
minikube version

echo ">> Hoàn tất."
echo "   Chạy 'minikube start --driver=docker' khi bạn sẵn sàng tạo cluster (cần Docker đã chạy — xem flex-environment/setup/install-docker.sh)."

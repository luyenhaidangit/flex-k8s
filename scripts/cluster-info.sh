#!/usr/bin/env bash
# Xem nhanh thông tin k8s dạng bảng: cluster, node, namespace, deployment, pod, service. Chỉ đọc, không thay đổi gì.
# Cách dùng:
#   bash cluster-info.sh              # workload trong namespace của context hiện tại
#   bash cluster-info.sh <namespace>  # workload trong namespace chỉ định
#   bash cluster-info.sh -A           # workload ở mọi namespace

set -euo pipefail

NS_ARG="${1:-}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "!! Thiếu 'kubectl'. Cài bằng install-minikube.sh." >&2
  exit 1
fi

section() {
  printf '\n== %s ==\n' "$1"
}

section "Cluster (kubectl context, dấu * là đang dùng)"
kubectl config get-contexts

if command -v minikube >/dev/null 2>&1; then
  section "Minikube profile"
  minikube profile list
fi

# Các mục dưới cần kết nối tới cluster đang dùng.
if ! kubectl --request-timeout=5s get nodes >/dev/null 2>&1; then
  echo
  echo "!! Không kết nối được cluster hiện tại ($(kubectl config current-context 2>/dev/null || echo 'chưa chọn context'))." >&2
  echo "   Cluster đã dừng? Thử: minikube start -p <tên>, hoặc đổi: kubectl config use-context <tên>." >&2
  exit 1
fi

section "Phiên bản"
kubectl version

section "Node"
kubectl get nodes -o wide

section "Namespace"
kubectl get namespaces

case "$NS_ARG" in
  "")  NS_FLAG=(); NS_LABEL="namespace $(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)" ;;
  -A)  NS_FLAG=(-A); NS_LABEL="mọi namespace" ;;
  *)   NS_FLAG=(-n "$NS_ARG"); NS_LABEL="namespace $NS_ARG" ;;
esac
[ "$NS_LABEL" = "namespace " ] && NS_LABEL="namespace default"

section "Deployment ($NS_LABEL)"
kubectl get deployments "${NS_FLAG[@]}"

section "Pod ($NS_LABEL)"
kubectl get pods "${NS_FLAG[@]}" -o wide

section "Service ($NS_LABEL)"
kubectl get services "${NS_FLAG[@]}"

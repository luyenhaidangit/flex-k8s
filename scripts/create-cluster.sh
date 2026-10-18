#!/usr/bin/env bash
# Tạo cluster minikube (driver Docker) để học/chạy thử k8s local.
# Cách dùng:
#   bash create-cluster.sh                      # chưa có cluster: tạo "minikube"; đã có: liệt kê rồi hỏi có tạo thêm không
#   CLUSTER_NAME=lab bash create-cluster.sh     # không hỏi, tạo (hoặc start lại) cluster tên "lab"
# Chạy lại an toàn (idempotent): tên cluster đã tồn tại thì chỉ start lại, dữ liệu giữ nguyên.
# Cần minikube + kubectl (install-minikube.sh) và Docker đang chạy.

set -euo pipefail

for cmd in docker minikube kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "!! Thiếu '$cmd'. Cài bằng install-minikube.sh (minikube, kubectl) hoặc flex-environment/setup/install-docker.sh (docker)." >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "!! Docker chưa chạy hoặc user chưa có quyền dùng docker (xem 'docker ps')." >&2
  exit 1
fi

CLUSTER_NAME="${CLUSTER_NAME:-}"
PROFILES_JSON="$(minikube profile list -o json 2>/dev/null || true)"

# Đã có cluster nếu danh sách "valid" khác rỗng.
if [ -n "$PROFILES_JSON" ] && ! grep -q '"valid":\[\]' <<<"$PROFILES_JSON"; then
  echo ">> Đã có cluster minikube:"
  minikube profile list

  if [ -z "$CLUSTER_NAME" ]; then
    if [ ! -t 0 ]; then
      echo ">> Không có terminal tương tác nên không hỏi. Đặt CLUSTER_NAME=<tên> để tạo thêm cluster."
      exit 0
    fi
    echo "   Lưu ý: mỗi cluster chiếm thêm khoảng 2 CPU và 3 GB RAM."
    read -r -p "Tạo thêm cluster mới? [y/N] " answer
    case "$answer" in
      [yY]*) ;;
      *) echo ">> Giữ nguyên các cluster hiện có."; exit 0 ;;
    esac
    read -r -p "Tên cluster mới: " CLUSTER_NAME
  fi
else
  CLUSTER_NAME="${CLUSTER_NAME:-minikube}"
fi

# Tên profile cũng là tên kubectl context nên chỉ nhận chữ thường, số và dấu gạch ngang.
if [[ ! "$CLUSTER_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
  echo "!! Tên cluster '$CLUSTER_NAME' không hợp lệ (chỉ chữ thường, số, dấu '-')." >&2
  exit 1
fi

if grep -q "\"Name\":\"$CLUSTER_NAME\"" <<<"$PROFILES_JSON"; then
  echo ">> Cluster '$CLUSTER_NAME' đã tồn tại, chỉ start lại."
fi

echo ">> Khởi động cluster '$CLUSTER_NAME'..."
minikube start -p "$CLUSTER_NAME" --driver=docker

echo ">> Kiểm tra cluster:"
kubectl config use-context "$CLUSTER_NAME" >/dev/null
kubectl get nodes
kubectl cluster-info

echo ">> Hoàn tất. Đang dùng context '$CLUSTER_NAME'. Thử: kubectl apply -f manifests/nginx.yaml"
echo "   Đổi cluster: kubectl config use-context <tên>. Tắt: minikube stop -p $CLUSTER_NAME. Xóa: minikube delete -p $CLUSTER_NAME."

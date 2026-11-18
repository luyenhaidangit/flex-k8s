#!/usr/bin/env bash
# Sửa file trong manifests/ rồi chạy: apply toàn bộ manifest, service nào đổi thì chạy lại đúng service đó.
# Mỗi app một thư mục manifests/<app>/, file đặt tên <kind>.yaml; apply theo thứ tự chữ cái của tên file (xem AGENTS.md).
# Cách dùng:
#   bash restart.sh                      # apply mọi manifests/<app>/*.yaml
#   bash restart.sh nginx                # chỉ apply manifests/nginx/
#   bash restart.sh flex-api-gateway     # chỉ apply manifests/flex-api-gateway/
# - Deployment (image, env, probe, resources...) đổi: k8s tự rolling update khi apply.
# - ConfigMap đổi: pod không tự nạp lại, script chạy 'rollout restart' deployment cùng label app.
# - Không tự rollback: rollout lỗi thì in log, rollback bằng 'kubectl rollout undo deployment/<tên>'.
# Quy ước: tên Deployment trùng label app của ConfigMap (đúng với nginx, flex-api-gateway).

set -euo pipefail
cd "$(dirname "$0")"

command -v kubectl >/dev/null 2>&1 || { echo "!! Thiếu 'kubectl'." >&2; exit 1; }
kubectl --request-timeout=5s get nodes >/dev/null 2>&1 || { echo "!! Không kết nối được cluster." >&2; exit 1; }

if [ $# -gt 1 ]; then
  echo "!! Chỉ nhận tối đa 1 tên app." >&2
  exit 2
elif [ $# -eq 1 ]; then
  FILES=(manifests/"$1"/*.yaml)
  [ -f "${FILES[0]}" ] || { echo "!! Không có manifest nào trong manifests/$1/." >&2; exit 2; }
else
  # Thứ tự chữ cái: flex-api-gateway trước nginx (nginx phân giải DNS Service gateway lúc khởi động).
  FILES=(manifests/*/*.yaml)
  [ -f "${FILES[0]}" ] || { echo "!! Không có manifest nào trong manifests/<app>/." >&2; exit 2; }
fi

# Mỗi dòng "<app> <hash dữ liệu ConfigMap>" của mọi ConfigMap có label app.
configmap_hashes() {
  kubectl get configmap -l app -o jsonpath='{range .items[*]}{.metadata.labels.app}{" "}{.data}{"\n"}{end}' \
    | while read -r app data; do echo "$app $(printf '%s' "$data" | sha256sum | cut -d' ' -f1)"; done | sort
}

BEFORE="$(configmap_hashes)"

for f in "${FILES[@]}"; do
  echo ">> apply $f"
  kubectl apply -f "$f"
done

# App nào có hash ConfigMap khác trước -> restart deployment cùng tên.
CHANGED="$(comm -13 <(printf '%s\n' "$BEFORE") <(configmap_hashes) | cut -d' ' -f1)"
for app in $CHANGED; do
  if kubectl get "deployment/$app" >/dev/null 2>&1; then
    echo ">> ConfigMap của '$app' đổi -> restart"
    kubectl rollout restart "deployment/$app"
  fi
done

# Chờ rollout của các deployment có trong file đã apply ('-o name' đúng cho cả file một object lẫn nhiều object).
for f in "${FILES[@]}"; do
  for dep in $(kubectl get -f "$f" -o name 2>/dev/null | sed -n 's#^deployment\.apps/##p'); do
    if ! kubectl rollout status "deployment/$dep" --timeout=180s; then
      echo "!! Rollout '$dep' lỗi. Log pod gần nhất:" >&2
      kubectl logs -l "app=$dep" --tail=30 --all-containers >&2 || true
      echo "   Rollback: kubectl rollout undo deployment/$dep" >&2
      exit 1
    fi
  done
done

echo ">> Xong."

#!/usr/bin/env bash
# Cài Argo CD vào cluster hiện tại bằng file khai báo trong argocd/install/ (Kustomize, đã pin version), rồi áp Application 'flex'.
# Cách dùng:
#   bash scripts/install-argocd.sh
# Chạy lại nhiều lần an toàn (kubectl apply): đổi version hoặc patch trong argocd/install/ rồi chạy lại để nâng cấp.
# - Cần kết nối được cluster; thay đổi cluster thật: namespace argocd, CRD, Deployment/StatefulSet của Argo CD, Application 'flex'.
# - Không tạo/đổi mật khẩu admin: Argo CD tự sinh Secret argocd-initial-admin-secret, script chỉ in lệnh để lấy.

set -euo pipefail
cd "$(dirname "$0")/.."

command -v kubectl >/dev/null 2>&1 || { echo "!! Thiếu 'kubectl'." >&2; exit 1; }
kubectl --request-timeout=5s get nodes >/dev/null 2>&1 || { echo "!! Không kết nối được cluster." >&2; exit 1; }

echo ">> Cluster: $(kubectl config current-context)"

echo ">> apply argocd/install (server-side: CRD của Argo CD quá lớn cho client-side apply)"
kubectl apply --server-side -k argocd/install

# Application cần CRD đã sẵn sàng, nếu không lần cài đầu sẽ lỗi 'no matches for kind Application'.
echo ">> Chờ CRD applications.argoproj.io"
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=60s

echo ">> Chờ Argo CD khởi động"
for res in deployment/argocd-server deployment/argocd-repo-server deployment/argocd-redis statefulset/argocd-application-controller; do
  if ! kubectl -n argocd rollout status "$res" --timeout=300s; then
    echo "!! $res chưa sẵn sàng. Xem: kubectl -n argocd get pods; kubectl -n argocd logs $res --tail=30" >&2
    exit 1
  fi
done

echo ">> apply argocd/argocd.yml (Application flex, sync thủ công)"
kubectl apply -f argocd/argocd.yml

cat <<'EOF'
>> Xong. Việc cần làm một lần sau khi cài:
   - Lấy mật khẩu admin ban đầu (không in ra ở đây):
       kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
   - Mở https://flex.luyenhaidangit.pro/argocd (cần location /argocd ở Nginx), đăng nhập 'admin', đổi mật khẩu,
     rồi xóa secret khởi tạo: kubectl -n argocd delete secret argocd-initial-admin-secret
   - Tạm thời chưa qua Nginx: kubectl -n argocd port-forward svc/argocd-server 8080:80 (mở http://localhost:8080/argocd).
EOF

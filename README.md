# flex-k8s

Cấu hình môi trường Kubernetes cho Flex platform. Repo này chỉ chứa manifest YAML thuần (không dùng Kustomize/Helm) và script vận hành; mã nguồn service nằm ở các repo riêng.

> Trạng thái: mới khởi tạo khung dự án. Đã có manifest `manifests/nginx.yaml` (Deployment + Service ClusterIP) để học k8s, chưa apply lên cluster nào.

## Cài công cụ (Ubuntu/WSL2)

```bash
bash scripts/server/bootstrap.sh            # kiểm tra OS, systemd + user mặc định (WSL2; hỏi tên user nếu chưa cấu hình), Docker, kubectl + minikube; thiếu mục nào cài mục đó
bash scripts/server/bootstrap.sh --check    # chỉ kiểm tra, không thay đổi gì (exit 1 nếu còn thiếu)
bash scripts/install-minikube.sh            # cài kubectl + minikube (không tự tạo cluster)
bash scripts/create-cluster.sh              # tạo cluster minikube; nếu đã có cluster thì liệt kê và hỏi có tạo thêm không
CLUSTER_NAME=lab bash scripts/create-cluster.sh   # không hỏi, tạo (hoặc start lại) cluster tên "lab"
```

## Xem nhanh thông tin cluster

```bash
bash scripts/cluster-info.sh                # cluster, node, namespace, deployment/pod/service của namespace hiện tại
bash scripts/cluster-info.sh -A             # workload ở mọi namespace (hoặc truyền tên namespace)
```

Chỉ đọc, không thay đổi cluster.

## Chạy thử nginx (local)

```bash
kubectl apply -f manifests/nginx.yaml
kubectl get pods,svc -l app=nginx
kubectl port-forward svc/nginx 8080:80      # mở http://localhost:8080
```

Rollback: `kubectl rollout undo deployment/nginx`. Dọn dẹp: `kubectl delete -f manifests/nginx.yaml`.

## Cấu trúc

```text
manifests/           # Manifest YAML thuần, áp dụng trực tiếp bằng kubectl apply -f
scripts/             # Script vận hành (non-interactive, fail-fast)
docs/                # Tài liệu setup và vận hành
```

## Quy ước

- Image luôn pin version/digest cụ thể, không dùng `latest`.
- Không commit secret, kubeconfig hay credential thật; dùng `.env.example` làm mẫu.
- Mỗi thay đổi cluster phải có kế hoạch rollback trước khi áp dụng.

## Việc cần quyết định tiếp

- Cluster local: dùng minikube cho khớp tài liệu `../docs/infrastructure/k8s-level-1.md`. Manifest `flex-api-gateway.yaml` đã chuyển từ `flex-environment/k8s/` sang `manifests/`; cần tạo Secret `flex-api-gateway-secret` lúc deploy (không commit).
- Danh sách workload cần đưa lên K8s (xem `../flex-environment/docker-compose.*.yml`).

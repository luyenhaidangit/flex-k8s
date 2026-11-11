# flex-k8s

Cấu hình môi trường Kubernetes cho Flex platform. Repo này chỉ chứa manifest YAML thuần (không dùng Kustomize/Helm) và script vận hành; mã nguồn service nằm ở các repo riêng.

> Trạng thái: mới khởi tạo khung dự án. Đã có manifest `manifests/nginx.yaml` (ConfigMap + Deployment + Service NodePort `30080`): nginx của Flex, giai đoạn phát triển chỉ trả trang "Đang xây dựng". Chưa apply lên cluster nào.

## Cài công cụ (Ubuntu/WSL2)

```bash
bash scripts/server/bootstrap.sh            # kiểm tra và cài phần còn thiếu (systemd, user, Docker)
bash scripts/server/bootstrap.sh --check    # chỉ kiểm tra, không thay đổi
```

Cấu hình mạng WSL2 trên Windows (`networkingMode=mirrored`, `dnsTunneling=true`) do `flex-workstation` quản lý: template ở `scripts/windows/.wslconfig`, áp dụng bởi `scripts\bootstrap.ps1`, kiểm tra bằng `scripts\windows\SYNC_WINDOWS.cmd -Check` (đều ở root workstation). Sau khi áp dụng cần `wsl --shutdown` để có hiệu lực. Các lệnh cài công cụ bên dưới chạy trong WSL.

Cluster là k3s 1 node, cài bằng `flex-environment/setup/04-init-k3s.sh` (kèm `kubectl`), không nằm trong repo này.

## Xem nhanh thông tin cluster

```bash
bash scripts/cluster-info.sh                # cluster, node, namespace, deployment/pod/service của namespace hiện tại
bash scripts/cluster-info.sh -A             # workload ở mọi namespace (hoặc truyền tên namespace)
```

Chỉ đọc, không thay đổi cluster.

## Cập nhật nhanh sau khi sửa manifest

Sửa file trong `manifests/` (ví dụ đổi tag image từ Jenkins `1.0.<BUILD_NUMBER>-dev`, đổi ConfigMap), rồi chạy:

```bash
bash restart.sh                      # apply mọi manifest
bash restart.sh nginx                # chỉ manifests/nginx.yaml
bash restart.sh flex-api-gateway     # chỉ manifests/flex-api-gateway.yaml
```

Deployment đổi thì k8s tự rolling update; ConfigMap đổi thì script `rollout restart` đúng deployment cùng label `app` rồi chờ `rollout status`. Yêu cầu tên Deployment trùng label `app` của ConfigMap. Rollout lỗi thì script in log, rollback bằng `kubectl rollout undo deployment/<tên>`.

## Tạo Secret cho gateway

`flex-api-gateway` đọc `JwtSettings__SecretKey` từ Secret `flex-api-gateway-secret` (nạp qua `secretRef`). Secret không nằm trong repo; tạo trên cluster **trước** khi apply manifest, nếu không Pod kẹt `CreateContainerConfigError`.

```bash
read -rs -p "JwtSettings__SecretKey: " JWT_KEY; echo     # hoặc: JWT_KEY="$(openssl rand -base64 48)"
kubectl create secret generic flex-api-gateway-secret \
  --from-literal=JwtSettings__SecretKey="$JWT_KEY"
unset JWT_KEY
bash restart.sh flex-api-gateway
```

- Khóa phải trùng khóa `flex-auth-service` dùng để ký token, nếu không gateway từ chối mọi token.
- Đổi khóa (xoay): `kubectl delete secret flex-api-gateway-secret`, tạo lại như trên, rồi `kubectl rollout restart deployment/flex-api-gateway`. Secret đổi không tự restart Pod và `restart.sh` chỉ theo dõi ConfigMap.
- Kiểm tra tên key (không in giá trị): `kubectl get secret flex-api-gateway-secret -o jsonpath='{.data}' | jq 'keys'`.
- Không lưu hoặc dán output `kubectl get secret -o yaml`: base64 không phải mã hóa.

## Chạy thử nginx của Flex

```bash
kubectl apply -f manifests/nginx.yaml
kubectl get pods,svc -l app=nginx
curl -i http://localhost:30080/             # NodePort trên host; nginx Docker (flex-environment) proxy tới đây
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

- Cluster: k3s 1 node trên server (`flex-environment/setup/04-init-k3s.sh`). Manifest `flex-api-gateway.yaml` đã chuyển từ `flex-environment/k8s/` sang `manifests/`; JWT key lấy từ Secret `flex-api-gateway-secret` (xem mục "Tạo Secret cho gateway"). `yarp.json` trong image trỏ tới `flex-auth-service`/`host.docker.internal`, chưa có service tương ứng trong cluster nên route `/api/*` sẽ trả 502/503 cho tới khi triển khai các service đó. nginx (`nginx.yaml`) chuyển `/api/` tới gateway.
- Danh sách workload cần đưa lên K8s (xem `../flex-environment/docker-compose.*.yml`).

# flex-k8s

Cấu hình môi trường Kubernetes cho Flex platform. Repo này chứa manifest YAML thuần (không dùng Kustomize/Helm) và script vận hành; ngoại lệ duy nhất là `argocd/install/` dùng Kustomize để cài Argo CD bản đã pin version. Mã nguồn service nằm ở các repo riêng.

> Trạng thái: mới khởi tạo khung dự án. Đã có manifest `manifests/nginx/` (ConfigMap + Deployment + Service NodePort `30080`): nginx của Flex, giai đoạn phát triển chỉ trả trang "Đang xây dựng". Chưa apply lên cluster nào.

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

## Cài Argo CD

Argo CD cài vào namespace `argocd` của cluster k3s 1 node, khai báo hoàn toàn bằng file (không tạo namespace hay sửa cấu hình bằng tay):

```text
argocd/install/          # Kustomize: namespace + install.yaml chính thức v3.5.7 + patch của Flex
argocd/install-argocd.sh # script cài: apply install + chờ sẵn sàng + apply Application
argocd/application.yaml  # Application 'flex' (đồng bộ manifests/, sync thủ công)
```

```bash
kubectl kustomize argocd/install | head        # chỉ render, không đụng cluster (cần mạng để tải install.yaml)
bash argocd/install-argocd.sh                  # apply install + chờ sẵn sàng + apply Application
```

Patch của Flex: bản non-HA; UI chạy HTTP thuần dưới path `/argocd` (`server.insecure`, `server.rootpath`, `server.basehref`); Service `argocd-server` giữ ClusterIP; tắt dex, notifications và applicationset (`replicas: 0`) cho nhẹ node.

Truy cập: `https://flex.luyenhaidangit.pro/argocd`. Đường đi: Nginx Docker (flex-environment, đã chuyển mọi path vào NodePort `30080`, không cần sửa) → Nginx trong k8s (`manifests/nginx/configmap.yaml`, `location /argocd`) → Service `argocd-server.argocd`. **Chỉ host `flex.luyenhaidangit.pro` được vào `/argocd`; `api.luyenhaidangit.pro` cũng đi vào cùng NodePort nhưng nginx k8s trả 404 theo `Host` (map `$argocd_allowed`). **Thứ tự:** cài Argo CD trước (`install-argocd.sh`), rồi mới `bash restart.sh nginx` để áp route; nginx k8s phân giải tên Service lúc khởi động, thiếu `argocd-server` thì pod nginx mới CrashLoop (rolling update giữ pod cũ phục vụ). Chưa qua Nginx thì dùng `kubectl -n argocd port-forward svc/argocd-server 8080:80` rồi mở `http://localhost:8080/argocd`.

Sau khi cài, một lần: lấy mật khẩu admin ban đầu (`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`), đăng nhập, đổi mật khẩu rồi xóa secret khởi tạo. Mật khẩu không nằm trong Git. CLI qua Nginx cần `argocd login flex.luyenhaidangit.pro --grpc-web --grpc-web-root-path /argocd`.

Lưu ý:

- Chính sách truy cập UI (hiện tại, mục đích học): cho phép mọi IP vào `/argocd`, chỉ có đăng nhập admin bảo vệ (Argo CD không có MFA sẵn). Rủi ro còn lại: Argo CD có quyền triển khai lên cluster.
- Kế hoạch: sau này chỉ cấp truy cập `/argocd` cho các IP được phép (allowlist theo IP) ở Nginx Docker của `flex-environment`. Chưa thực hiện, chưa có cấu hình nào cho việc này.
- Không mở thêm NodePort mới; NodePort `30080` hiện có vẫn cần firewall không cho Internet vào.
- Application `flex` sync thủ công: `restart.sh` và Argo CD cùng ghi vào cluster nên chưa bật `automated`/`selfHeal` cho tới khi chốt cách xử lý (ConfigMap đổi không tự restart pod, annotation `restartedAt` của `rollout restart`).
- Nâng version: đổi tag `v3.5.7` trong `argocd/install/kustomization.yaml`, đọc release notes, kiểm tra lại thứ tự `ports[0]` của `argocd-server` rồi chạy lại script.

## Cập nhật nhanh sau khi sửa manifest

Sửa file trong `manifests/` (ví dụ đổi tag image từ Jenkins `1.0.<BUILD_NUMBER>-dev`, đổi ConfigMap), rồi chạy:

```bash
bash restart.sh                      # apply mọi manifests/<app>/*.yaml
bash restart.sh nginx                # chỉ manifests/nginx/
bash restart.sh flex-api-gateway     # chỉ manifests/flex-api-gateway/
```

Deployment đổi thì k8s tự rolling update; ConfigMap đổi thì script `rollout restart` đúng deployment cùng label `app` rồi chờ `rollout status`. Yêu cầu tên Deployment trùng label `app` của ConfigMap. Rollout lỗi thì script in log, rollback bằng `kubectl rollout undo deployment/<tên>`.

## Tạo Secret cho gateway

`flex-api-gateway` đọc `JwtSettings__SecretKey` từ Secret `flex-api-gateway-secret` (nạp qua `secretRef`). Secret không nằm trong repo; tạo trên cluster **trước** khi apply manifest, nếu không Pod kẹt `CreateContainerConfigError`.

```bash
bash set-secret.sh flex-api-gateway-secret JwtSettings__SecretKey   # hỏi giá trị (không hiện ký tự)
bash restart.sh flex-api-gateway                                    # lần đầu: apply Deployment dùng secretRef
```

`set-secret.sh [-n <namespace>] <secret-name> KEY [KEY...]` dùng cho cả thêm mới lẫn cập nhật:

- Giá trị lấy từ biến môi trường cùng tên KEY, không có thì hỏi trên terminal. Giá trị đi qua stdin, không nằm trong tham số lệnh.
- Secret chưa có thì tạo; đã có thì `kubectl patch --type merge` chỉ đổi các KEY được truyền, các key khác giữ nguyên.
- Dữ liệu Secret đổi thì `rollout restart` deployment tên bỏ hậu tố `-secret` (`flex-api-gateway-secret` -> `flex-api-gateway`) và chờ `rollout status`; không đổi thì không restart. Rollout lỗi thì in log, rollback bằng `kubectl rollout undo deployment/<tên>`.
- Từ chối giá trị rỗng, còn là `REPLACE_ME*`, chứa xuống dòng, hoặc `JwtSettings__SecretKey` ngắn hơn 32 ký tự. Cần kubectl hỗ trợ `patch --patch-file` (khoảng 1.22 trở lên).
- Chạy không có terminal (CI): đặt biến môi trường trước, ví dụ `JwtSettings__SecretKey="$KEY" bash set-secret.sh flex-api-gateway-secret JwtSettings__SecretKey`.

Lưu ý:

- Khóa phải trùng khóa `flex-auth-service` dùng để ký token, nếu không gateway từ chối mọi token.
- Lần đầu apply `manifests/flex-api-gateway/` phải có Secret trước, nếu không Pod kẹt `CreateContainerConfigError`: chạy `set-secret.sh` trước `restart.sh`.
- Kiểm tra tên key (không in giá trị): `kubectl get secret flex-api-gateway-secret -o jsonpath='{.data}' | jq 'keys'`.
- Không lưu hoặc dán output `kubectl get secret -o yaml`: base64 không phải mã hóa.

## Giới hạn truy cập gateway

`manifests/flex-api-gateway/networkpolicy.yaml` có NetworkPolicy `flex-api-gateway-allow-nginx`: chỉ pod `app=nginx` trong namespace `default` được vào cổng 8080 của gateway. `kubectl port-forward` và probe vẫn dùng được. NetworkPolicy không lọc được traffic vào NodePort `30080` từ bên ngoài (nguồn bị SNAT thành IP node), phần đó vẫn do firewall host đảm nhiệm.

## Chạy thử nginx của Flex

```bash
kubectl apply -f manifests/nginx/
kubectl get pods,svc -l app=nginx
curl -i http://localhost:30080/             # NodePort trên host; nginx Docker (flex-environment) proxy tới đây
```

Rollback: `kubectl rollout undo deployment/nginx`. Dọn dẹp: `kubectl delete -f manifests/nginx/`.

## Cấu trúc

```text
manifests/           # Manifest YAML thuần, mỗi app một thư mục, áp dụng bằng kubectl apply -f manifests/<app>/
  nginx/             # <kind>.yaml: configmap, service, deployment
  flex-api-gateway/  # configmap, service, deployment, networkpolicy
scripts/             # Script vận hành (non-interactive, fail-fast)
docs/                # Tài liệu setup và vận hành
```

## Quy ước

- Image luôn pin version/digest cụ thể, không dùng `latest`.
- Không commit secret, kubeconfig hay credential thật; dùng `.env.example` làm mẫu.
- Mỗi thay đổi cluster phải có kế hoạch rollback trước khi áp dụng.
- Mọi Deployment khai báo `revisionHistoryLimit` rõ ràng (hiện là `2`), không dùng mặc định 10.

## Bài học kinh nghiệm

### Cây Argo CD hiện quá nhiều ReplicaSet (nginx có 8 `rs`, chỉ 1 cái chạy pod)

- **Hiện tượng:** Deployment `nginx` hiện nhiều ReplicaSet tên `nginx-<hash>`, chỉ 1 cái có pod, các cái còn lại 0 pod.
- **Nguyên nhân:** mỗi lần đổi `spec.template` (image, env, resources, probe, label/annotation trong template, `kubectl rollout restart`) Deployment tạo ReplicaSet mới, giữ ReplicaSet cũ để rollback. Số lượng giữ tối đa là `spec.revisionHistoryLimit`, mặc định 10. Đây là hành vi bình thường, không phải lỗi.
- **Không tạo RS mới:** đổi `replicas`, đổi metadata của chính Deployment, đổi `strategy`/`revisionHistoryLimit`. Đổi ngược về cấu hình cũ thì dùng lại RS cũ (cùng hash).
- **Cách xử lý:** đặt `revisionHistoryLimit` trong manifest rồi sync; K8s tự xoá RS cũ vượt giới hạn. Không xoá RS bằng tay trên Argo CD.
- **Giá trị khuyến nghị:** dev/test `2`, staging `3`, prod `3–5`. Không đặt `0` vì mất `kubectl rollout undo`. Quá cao (≥10) làm rối cây và tốn object trong etcd. Rollback thật sự nên là `git revert` + sync, nên không cần giữ lịch sử dài ở cluster.
- **Kiểm tra:** `kubectl rollout history deployment/nginx` (thêm `--revision=N` để xem chi tiết). Nếu RS tăng dù không sửa gì, tìm annotation tự đổi mỗi lần render (`checksum/config`, timestamp) trong template.

## Việc cần quyết định tiếp

- Cluster: k3s 1 node trên server (`flex-environment/setup/04-init-k3s.sh`). Manifest gateway đã chuyển từ `flex-environment/k8s/` sang `manifests/flex-api-gateway/`; JWT key lấy từ Secret `flex-api-gateway-secret` (xem mục "Tạo Secret cho gateway"). `yarp.json` trong image trỏ tới `flex-auth-service`/`host.docker.internal`, chưa có service tương ứng trong cluster nên route `/api/*` sẽ trả 502/503 cho tới khi triển khai các service đó. nginx (`manifests/nginx/`) chuyển `/api/` tới gateway.
- Danh sách workload cần đưa lên K8s (xem `../flex-environment/docker-compose.*.yml`).

# AGENTS.md

`flex-k8s` là repo cấu hình Kubernetes cho Flex platform. Repo này nằm trong `flex-workstation/` và là Git repo độc lập.

## Ngôn ngữ

- Dùng tiếng Việt có dấu trong trả lời, tài liệu và ghi chú.
- Giữ nguyên định danh kỹ thuật (tên file, resource, command) bằng English.

## Quy tắc làm việc

- Trước khi sửa, đọc `flex-devops-engineering` (skill ở `../.agents/skills/`).
- Manifest là YAML thuần trong `manifests/<app>/`, mỗi resource một file tên theo kind, không số (`configmap.yaml`, `service.yaml`, `deployment.yaml`, `networkpolicy.yaml`, `pvc.yaml`, `ingress.yaml`); chỉ tạo file cho resource thật sự có. Tên app = tên thư mục = tên Deployment (`restart.sh` dựa vào đây); không dùng Kustomize/Helm trừ khi người dùng yêu cầu. Ngoại lệ đã được yêu cầu: `argocd/install/` dùng Kustomize để cài Argo CD bản pin version.
- Image pin version cụ thể; không dùng `latest`.
- Thứ tự apply: tên file không quyết định thứ tự. `kubectl apply -f <thư mục>` đi theo thứ tự chữ cái (`configmap` < `deployment` < `networkpolicy` < `pvc` < `service`), Argo CD tự sắp theo kind, nên Deployment có thể được tạo trước PVC/Service; Kubernetes tự reconcile (Pod chờ `ConfigMap`/`PVC` rồi tự chạy, chỉ báo `CreateContainerConfigError`/`ContainerCreating` thoáng qua). Chỉ `Namespace`/CRD bắt buộc có trước: đặt tên `00-namespace.yaml`. Hiện không có code hay cấu hình nào đọc `<TÊN_SERVICE>_SERVICE_HOST`; nếu sau này app cần biến đó thì apply `service.yaml` trước.
- Không commit secret/kubeconfig; không chạy lệnh làm thay đổi cluster (`kubectl apply/delete`, `helm install`) khi chưa được yêu cầu rõ.
- Validate tĩnh trước (`kubectl apply --dry-run=client -R -f manifests/`); phân biệt rõ "đã viết manifest" với "đã triển khai".
- Khi đổi cấu trúc hoặc lệnh vận hành, cập nhật `README.md`/`docs/`.
- Script shell (`*.sh`): Git trên Windows không lưu quyền thực thi (`core.fileMode=false`), `chmod +x` trên máy dev vô hiệu. Sau khi tạo mới hoặc sửa bất kỳ `*.sh` nào, chạy `git add --chmod=+x <file>` để file vào index với mode `100755`, server `git pull` xong chạy được ngay. Kiểm tra bằng `git ls-files -s <file>` (phải là `100755`).

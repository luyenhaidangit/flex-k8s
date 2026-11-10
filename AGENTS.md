# AGENTS.md

`flex-k8s` là repo cấu hình Kubernetes cho Flex platform. Repo này nằm trong `flex-workstation/` và là Git repo độc lập.

## Ngôn ngữ

- Dùng tiếng Việt có dấu trong trả lời, tài liệu và ghi chú.
- Giữ nguyên định danh kỹ thuật (tên file, resource, command) bằng English.

## Quy tắc làm việc

- Trước khi sửa, đọc `flex-devops-engineering` (skill ở `../.agents/skills/`).
- Manifest là YAML thuần trong `manifests/`; không dùng Kustomize/Helm trừ khi người dùng yêu cầu.
- Image pin version cụ thể; không dùng `latest`.
- Thứ tự resource trong một file YAML (`kubectl apply -f` xử lý tuần tự từ trên xuống): `ConfigMap`/`Secret` → `PersistentVolumeClaim` → `Service` → `Deployment`/`StatefulSet`/`DaemonSet` → `Ingress`. `Deployment` đứng sau `ConfigMap`/`PVC` để Pod không kẹt `CreateContainerConfigError`/`ContainerCreating`; `Service` đứng trước `Deployment` để biến môi trường `<TÊN_SERVICE>_SERVICE_HOST` được bơm vào Pod lúc tạo; `Ingress` đứng cuối vì chỉ trỏ về `Service` đã khai báo.
- Không commit secret/kubeconfig; không chạy lệnh làm thay đổi cluster (`kubectl apply/delete`, `helm install`) khi chưa được yêu cầu rõ.
- Validate tĩnh trước (`kubectl apply --dry-run=client -f manifests/`); phân biệt rõ "đã viết manifest" với "đã triển khai".
- Khi đổi cấu trúc hoặc lệnh vận hành, cập nhật `README.md`/`docs/`.
- Script shell (`*.sh`): Git trên Windows không lưu quyền thực thi (`core.fileMode=false`), `chmod +x` trên máy dev vô hiệu. Sau khi tạo mới hoặc sửa bất kỳ `*.sh` nào, chạy `git add --chmod=+x <file>` để file vào index với mode `100755`, server `git pull` xong chạy được ngay. Kiểm tra bằng `git ls-files -s <file>` (phải là `100755`).

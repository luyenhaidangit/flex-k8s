# AGENTS.md

`flex-k8s` là repo cấu hình Kubernetes cho Flex platform. Repo này nằm trong `flex-workstation/` và là Git repo độc lập.

## Ngôn ngữ

- Dùng tiếng Việt có dấu trong trả lời, tài liệu và ghi chú.
- Giữ nguyên định danh kỹ thuật (tên file, resource, command) bằng English.

## Quy tắc làm việc

- Trước khi sửa, đọc `flex-devops-engineering` (skill ở `../.agents/skills/`).
- Manifest là YAML thuần trong `manifests/`; không dùng Kustomize/Helm trừ khi người dùng yêu cầu.
- Image pin version cụ thể; không dùng `latest`.
- Không commit secret/kubeconfig; không chạy lệnh làm thay đổi cluster (`kubectl apply/delete`, `helm install`) khi chưa được yêu cầu rõ.
- Validate tĩnh trước (`kubectl apply --dry-run=client -f manifests/`); phân biệt rõ "đã viết manifest" với "đã triển khai".
- Khi đổi cấu trúc hoặc lệnh vận hành, cập nhật `README.md`/`docs/`.

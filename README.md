# flex-k8s

Cấu hình môi trường Kubernetes cho Flex platform. Repo này chỉ chứa manifest YAML thuần (không dùng Kustomize/Helm) và script vận hành; mã nguồn service nằm ở các repo riêng.

> Trạng thái: mới khởi tạo khung dự án, chưa triển khai workload nào.

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

- Cluster local: dùng minikube cho khớp tài liệu `../docs/infrastructure/k8s-level-1.md`; chưa chốt có chuyển manifest `../flex-environment/k8s/` sang repo này hay không.
- Danh sách workload cần đưa lên K8s (xem `../flex-environment/docker-compose.*.yml`).

#!/usr/bin/env bash
# Thêm hoặc cập nhật key trong Secret; các key khác trong Secret giữ nguyên. Giá trị không in ra màn hình.
# Cách dùng:
#   bash set-secret.sh [-n <namespace>] <secret-name> KEY [KEY...]
#   bash set-secret.sh flex-api-gateway-secret JwtSettings__SecretKey
# Giá trị mỗi KEY lấy từ biến môi trường cùng tên; không có thì hỏi trên terminal (không hiện ký tự).
# - Secret chưa có: tạo Secret rỗng rồi ghi key. Đã có: 'kubectl patch --type merge' chỉ đổi key được truyền.
# - Giá trị đi qua stdin (base64), không nằm trong tham số lệnh nên không lộ trong 'ps'.
# - Dữ liệu Secret đổi thì 'rollout restart' deployment tên bỏ hậu tố '-secret' rồi chờ rollout (cùng quy ước với restart.sh).
# - Không tự rollback: rollout lỗi thì in log, rollback bằng 'kubectl rollout undo deployment/<tên>'.

set -euo pipefail

command -v kubectl >/dev/null 2>&1 || { echo "!! Thiếu 'kubectl'." >&2; exit 1; }
command -v base64 >/dev/null 2>&1 || { echo "!! Thiếu 'base64'." >&2; exit 1; }
kubectl patch --help 2>/dev/null | grep -q -- '--patch-file' \
  || { echo "!! kubectl quá cũ, thiếu 'patch --patch-file' (cần khoảng 1.22 trở lên)." >&2; exit 1; }
kubectl --request-timeout=5s get nodes >/dev/null 2>&1 || { echo "!! Không kết nối được cluster." >&2; exit 1; }

NS=()
if [ "${1:-}" = "-n" ]; then
  [ -n "${2:-}" ] || { echo "!! Thiếu tên namespace sau -n." >&2; exit 2; }
  NS=(-n "$2")
  shift 2
fi
if [ $# -lt 2 ]; then
  echo "Dùng: bash set-secret.sh [-n <namespace>] <secret-name> KEY [KEY...]" >&2
  exit 2
fi
SECRET="$1"
shift
APP="${SECRET%-secret}"

k() { kubectl "${NS[@]}" "$@"; }

# Hash dữ liệu Secret (không in giá trị); rỗng nếu chưa có Secret.
secret_hash() {
  { k get secret "$SECRET" -o jsonpath='{.data}' 2>/dev/null || true; } | sha256sum | cut -d' ' -f1
}

# Đọc và kiểm tra giá trị của một KEY: biến môi trường trước, không có thì hỏi trên terminal.
read_value() {
  local key="$1" val
  val="$(printenv "$key" 2>/dev/null || true)"
  if [ -z "$val" ]; then
    if { : </dev/tty; } 2>/dev/null; then
      read -rsp "$key: " val </dev/tty
      echo >&2
    else
      echo "!! $key rỗng: đặt biến môi trường $key hoặc chạy trên terminal." >&2
      exit 2
    fi
  fi
  case "$val" in
    "" | REPLACE_ME*) echo "!! $key rỗng hoặc còn là placeholder REPLACE_ME." >&2; exit 2 ;;
    *$'\n'*) echo "!! $key chứa xuống dòng." >&2; exit 2 ;;
  esac
  if [ "$key" = "JwtSettings__SecretKey" ] && [ "${#val}" -lt 32 ]; then
    echo "!! $key phải từ 32 ký tự trở lên." >&2
    exit 2
  fi
  printf '%s' "$val"
}

# Kiểm tra toàn bộ KEY và gom thành chuỗi JSON {"KEY":"<base64>",...}; tên key chỉ gồm A-Z a-z 0-9 . _ -
# nên ghép chuỗi JSON an toàn (base64 không có ký tự cần escape).
PAIRS=""
for key in "$@"; do
  [[ "$key" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "!! Tên key không hợp lệ: $key" >&2; exit 2; }
  val="$(read_value "$key")"
  PAIRS+="${PAIRS:+,}\"$key\":\"$(printf '%s' "$val" | base64 | tr -d '\n')\""
done
unset val

BEFORE="$(secret_hash)"
if ! k get secret "$SECRET" >/dev/null 2>&1; then
  echo ">> Secret '$SECRET' chưa có -> tạo mới"
  k create secret generic "$SECRET" >/dev/null
fi

echo ">> Ghi key: $*"
printf '{"data":{%s}}' "$PAIRS" | k patch secret "$SECRET" --type merge --patch-file /dev/stdin >/dev/null
unset PAIRS

if [ "$BEFORE" = "$(secret_hash)" ]; then
  echo ">> Dữ liệu Secret không đổi, không restart."
  exit 0
fi

if ! k get "deployment/$APP" >/dev/null 2>&1; then
  echo "!! Không thấy deployment '$APP' (tên bỏ hậu tố -secret); Secret đã ghi nhưng chưa restart pod nào." >&2
  exit 0
fi

echo ">> Secret của '$APP' đổi -> restart"
k rollout restart "deployment/$APP"
if ! k rollout status "deployment/$APP" --timeout=180s; then
  echo "!! Rollout '$APP' lỗi. Log pod gần nhất:" >&2
  k logs -l "app=$APP" --tail=30 --all-containers >&2 || true
  echo "   Rollback: kubectl rollout undo deployment/$APP" >&2
  exit 1
fi

echo ">> Xong."

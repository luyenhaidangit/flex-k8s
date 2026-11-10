#!/usr/bin/env bash
# Bootstrap máy Ubuntu/WSL2: kiểm tra từng mục, thiếu mới làm.
# Cách dùng: bash bootstrap.sh            # kiểm tra và cài những gì còn thiếu
#            bash bootstrap.sh --check    # chỉ kiểm tra, không thay đổi gì (exit 1 nếu còn thiếu)
# Chạy lại nhiều lần an toàn (idempotent). Không cài cluster — k3s (kèm kubectl) cài bằng flex-environment/setup/04-init-k3s.sh.
# Các mục: OS hỗ trợ -> systemd + user mặc định (WSL2) -> Docker.
# User mặc định WSL: script hỏi tên khi chưa có [user] default=; chạy không tương tác thì đặt WSL_DEFAULT_USER=<tên>.

set -euo pipefail

SUPPORTED_UBUNTU="22.04 24.04"
WSL_CONF="/etc/wsl.conf"

CHECK_ONLY=""
case "${1:-}" in
  "") ;;
  --check) CHECK_ONLY=1 ;;
  *) echo "!! Tham số không hợp lệ: '$1' (chỉ nhận --check)." >&2; exit 2 ;;
esac

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

MISSING=0
PENDING_WSL_RESTART=""

ok()      { echo "[OK]   $1"; }
todo()    { echo "[THIẾU] $1"; MISSING=1; }
doing()   { echo ">> $1"; }

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

# --- 1. OS ---------------------------------------------------------------
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ] || [[ " $SUPPORTED_UBUNTU " != *" ${VERSION_ID:-} "* ]]; then
  echo "!! Chỉ hỗ trợ Ubuntu $SUPPORTED_UBUNTU (phát hiện: ${ID:-unknown} ${VERSION_ID:-})." >&2
  exit 1
fi
if [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "!! Chỉ hỗ trợ amd64 (phát hiện: $(dpkg --print-architecture))." >&2
  exit 1
fi
ok "Ubuntu ${VERSION_ID} amd64"

# --- 2. systemd (chỉ WSL2) -----------------------------------------------
if is_wsl; then
  if grep -Eq '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$WSL_CONF" 2>/dev/null; then
    ok "systemd=true trong $WSL_CONF"
  elif [ -n "$CHECK_ONLY" ]; then
    todo "systemd=true chưa có trong $WSL_CONF"
  else
    doing "Ghi systemd=true vào $WSL_CONF..."
    if [ -f "$WSL_CONF" ] && grep -q '^\[boot\]' "$WSL_CONF"; then
      $SUDO sed -i '/^\[boot\]/a systemd=true' "$WSL_CONF"
    else
      printf '\n[boot]\nsystemd=true\n' | $SUDO tee -a "$WSL_CONF" >/dev/null
    fi
    PENDING_WSL_RESTART=1
  fi

  if [ -d /run/systemd/system ]; then
    ok "systemd đang chạy (PID 1)"
  else
    echo "[CHỜ]  systemd chưa chạy trong phiên này — cần 'wsl --shutdown' từ Windows rồi mở lại distro"
    PENDING_WSL_RESTART=1
  fi

  # --- 2b. User mặc định ([user] default= trong wsl.conf) ---
  CURRENT_DEFAULT_USER="$(awk '/^\[/{s=$0} s=="[user]" && /^[[:space:]]*default[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/,""); sub(/[[:space:]]+$/,""); print; exit}' "$WSL_CONF" 2>/dev/null || true)"
  if [ -n "$CURRENT_DEFAULT_USER" ]; then
    ok "User mặc định WSL: $CURRENT_DEFAULT_USER"
  elif [ -n "$CHECK_ONLY" ]; then
    todo "[user] default= chưa có trong $WSL_CONF"
  else
    # Tên user lấy từ WSL_DEFAULT_USER (không hỏi) hoặc hỏi người dùng; gợi ý user hiện tại nếu không phải root.
    NEW_USER="${WSL_DEFAULT_USER:-}"
    if [ -z "$NEW_USER" ] && [ -t 0 ]; then
      SUGGESTED_USER="${SUDO_USER:-$(id -un)}"
      [ "$SUGGESTED_USER" = "root" ] && SUGGESTED_USER=""
      read -r -p "User mặc định khi mở WSL${SUGGESTED_USER:+ [$SUGGESTED_USER]}: " NEW_USER
      NEW_USER="${NEW_USER:-$SUGGESTED_USER}"
    fi
    if [ -z "$NEW_USER" ]; then
      echo "[BỎ QUA] Chưa cấu hình user mặc định (không có terminal tương tác). Đặt WSL_DEFAULT_USER=<tên> để cấu hình."
    else
      if [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "!! Tên user '$NEW_USER' không hợp lệ (chữ thường, số, '_' và '-')." >&2
        exit 1
      fi
      if ! id "$NEW_USER" >/dev/null 2>&1; then
        if [ ! -t 0 ]; then
          echo "!! User '$NEW_USER' chưa tồn tại và không có terminal để đặt mật khẩu. Tạo trước bằng 'adduser $NEW_USER'." >&2
          exit 1
        fi
        doing "Tạo user '$NEW_USER' (thêm vào group sudo, docker nếu có)..."
        $SUDO adduser --gecos "" "$NEW_USER"
        $SUDO usermod -aG sudo "$NEW_USER"
        getent group docker >/dev/null && $SUDO usermod -aG docker "$NEW_USER"
      fi
      doing "Ghi default=$NEW_USER vào $WSL_CONF..."
      if [ -f "$WSL_CONF" ] && grep -q '^\[user\]' "$WSL_CONF"; then
        $SUDO sed -i "/^\[user\]/a default=$NEW_USER" "$WSL_CONF"
      else
        printf '\n[user]\ndefault=%s\n' "$NEW_USER" | $SUDO tee -a "$WSL_CONF" >/dev/null
      fi
      PENDING_WSL_RESTART=1
    fi
  fi
fi

# --- 3. Docker -----------------------------------------------------------
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  ok "Docker chạy được ($(docker --version))"
elif [ -n "$CHECK_ONLY" ]; then
  todo "Docker chưa cài hoặc chưa chạy/chưa có quyền (xem 'docker info')"
else
  if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    doing "Cài Docker Engine + Compose..."
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
      $SUDO apt-get remove -y "$pkg" >/dev/null 2>&1 || true
    done
    $SUDO apt-get update -y
    $SUDO apt-get install -y ca-certificates curl
    $SUDO install -m 0755 -d /etc/apt/keyrings
    $SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    $SUDO chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
    $SUDO apt-get update -y
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    doing "Docker đã cài nhưng chưa chạy được — bật service và gán group..."
  fi
  if [ -d /run/systemd/system ]; then
    $SUDO systemctl enable --now docker
  else
    $SUDO service docker start
  fi
  DOCKER_USER="${SUDO_USER:-$(id -un)}"
  if [ "$DOCKER_USER" != "root" ]; then
    $SUDO usermod -aG docker "$DOCKER_USER"
    echo ">> Đăng xuất/đăng nhập lại (hoặc 'newgrp docker') để dùng docker không cần sudo."
  fi
fi

# --- Kết quả -------------------------------------------------------------
echo
if [ -n "$PENDING_WSL_RESTART" ]; then
  echo ">> Cần khởi động lại WSL: chạy 'wsl --shutdown' từ Windows, mở lại distro, rồi chạy lại script này để xác nhận."
fi
if [ -n "$CHECK_ONLY" ] && [ "$MISSING" -ne 0 ]; then
  echo ">> Còn thiếu mục ở trên. Chạy 'bash bootstrap.sh' (không --check) để cài."
  exit 1
fi
[ -n "$PENDING_WSL_RESTART" ] || echo ">> Sẵn sàng."

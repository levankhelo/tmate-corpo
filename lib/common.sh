#!/usr/bin/env bash

LABEL="com.tmate-corpo.agent"
APP_NAME="tmate-corpo"
DEFAULT_USER_COMMAND_PATH="~/bin/tmate-corpo"
DEFAULT_CORPO_SSH_PORT="2222"
INSTALL_ROOT="${TMATE_CORPO_HOME:-$HOME/.tmate-corpo}"
CONFIG_FILE="$INSTALL_ROOT/env"
LOCAL_CONFIG_FILE="${TMATE_CORPO_LOCAL_CONFIG:-}"
PLIST_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$INSTALL_ROOT/logs"
STDOUT_LOG="$LOG_DIR/stdout.log"
STDERR_LOG="$LOG_DIR/stderr.log"
SSHD_ROOT="$INSTALL_ROOT/sshd"
SSHD_CONFIG="$SSHD_ROOT/sshd_config"
SSHD_HOST_KEY="$SSHD_ROOT/ssh_host_ed25519_key"
SSHD_AUTHORIZED_KEYS="$SSHD_ROOT/authorized_keys"
SSHD_PID_FILE="$SSHD_ROOT/sshd.pid"
SSHD_LOG="$LOG_DIR/sshd.log"

ENV_FILE_TARGET_MAC="${FILE_TARGET_MAC-}"
ENV_FILE_TARGET_PATH="${FILE_TARGET_PATH-}"
ENV_USER_MAC="${USER_MAC-}"
ENV_USER_COMMAND_PATH="${USER_COMMAND_PATH-}"
ENV_CORPO_SSH_PORT="${CORPO_SSH_PORT-}"
ENV_CORPO_SSH_HOST="${CORPO_SSH_HOST-}"
ENV_SSHD_BIN="${SSHD_BIN-}"
ENV_SKIP_SSH_COPY_ID="${SKIP_SSH_COPY_ID-}"

FILE_TARGET_PATH="${FILE_TARGET_PATH:-}"
USER_MAC="${USER_MAC:-${FILE_TARGET_MAC:-}}"
USER_COMMAND_PATH="${USER_COMMAND_PATH:-}"
CORPO_SSH_PORT="${CORPO_SSH_PORT:-$DEFAULT_CORPO_SSH_PORT}"
CORPO_SSH_HOST="${CORPO_SSH_HOST:-auto}"
SSHD_BIN="${SSHD_BIN:-/usr/sbin/sshd}"
REMOTE_INSTALL_WITH_SUDO="${REMOTE_INSTALL_WITH_SUDO:-0}"
SKIP_SSH_COPY_ID="${SKIP_SSH_COPY_ID:-0}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "this service uses launchd and must run on macOS"
}

require_sshd() {
  [[ -x "$SSHD_BIN" ]] || die "sshd is not available at $SSHD_BIN"
  have ssh-keygen || die "ssh-keygen is required"
}

shell_quote() {
  printf '%q' "$1"
}

single_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi

  if [[ -n "$LOCAL_CONFIG_FILE" && -f "$LOCAL_CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$LOCAL_CONFIG_FILE"
  fi

  [[ -n "$ENV_FILE_TARGET_MAC" ]] && FILE_TARGET_MAC="$ENV_FILE_TARGET_MAC"
  [[ -n "$ENV_FILE_TARGET_PATH" ]] && FILE_TARGET_PATH="$ENV_FILE_TARGET_PATH"
  [[ -n "$ENV_USER_MAC" ]] && USER_MAC="$ENV_USER_MAC"
  [[ -n "$ENV_USER_COMMAND_PATH" ]] && USER_COMMAND_PATH="$ENV_USER_COMMAND_PATH"
  [[ -n "$ENV_CORPO_SSH_PORT" ]] && CORPO_SSH_PORT="$ENV_CORPO_SSH_PORT"
  [[ -n "$ENV_CORPO_SSH_HOST" ]] && CORPO_SSH_HOST="$ENV_CORPO_SSH_HOST"
  [[ -n "$ENV_SSHD_BIN" ]] && SSHD_BIN="$ENV_SSHD_BIN"
  [[ -n "$ENV_SKIP_SSH_COPY_ID" ]] && SKIP_SSH_COPY_ID="$ENV_SKIP_SSH_COPY_ID"

  USER_MAC="${USER_MAC:-${FILE_TARGET_MAC:-}}"
  USER_COMMAND_PATH="${USER_COMMAND_PATH:-${FILE_TARGET_PATH:-}}"
  FILE_TARGET_MAC="$USER_MAC"
  FILE_TARGET_PATH="${USER_COMMAND_PATH:-$DEFAULT_USER_COMMAND_PATH}"
  USER_COMMAND_PATH="$FILE_TARGET_PATH"
  CORPO_SSH_PORT="${CORPO_SSH_PORT:-$DEFAULT_CORPO_SSH_PORT}"
  CORPO_SSH_HOST="${CORPO_SSH_HOST:-auto}"
  SSHD_BIN="${SSHD_BIN:-/usr/sbin/sshd}"
  REMOTE_INSTALL_WITH_SUDO=0
  SKIP_SSH_COPY_ID="${SKIP_SSH_COPY_ID:-0}"
}

write_config() {
  mkdir -p "$INSTALL_ROOT"
  write_config_file "$CONFIG_FILE"
  chmod 0600 "$CONFIG_FILE"
}

write_local_config() {
  [[ -n "$LOCAL_CONFIG_FILE" ]] || die "TMATE_CORPO_LOCAL_CONFIG is not set"
  mkdir -p "$(dirname "$LOCAL_CONFIG_FILE")"
  write_config_file "$LOCAL_CONFIG_FILE"
  chmod 0600 "$LOCAL_CONFIG_FILE"
}

write_config_file() {
  local path="$1"

  {
    printf 'USER_MAC=%s\n' "$(single_quote "${USER_MAC:-${FILE_TARGET_MAC:-}}")"
    printf 'USER_COMMAND_PATH=%s\n' "$(single_quote "${USER_COMMAND_PATH:-$FILE_TARGET_PATH}")"
    printf 'CORPO_SSH_PORT=%s\n' "$(single_quote "$CORPO_SSH_PORT")"
    printf 'CORPO_SSH_HOST=%s\n' "$(single_quote "$CORPO_SSH_HOST")"
    printf 'SSHD_BIN=%s\n' "$(single_quote "$SSHD_BIN")"
    printf 'REMOTE_INSTALL_WITH_SUDO=%s\n' "$(single_quote "0")"
    printf 'SKIP_SSH_COPY_ID=%s\n' "$(single_quote "$SKIP_SSH_COPY_ID")"
  } >"$path"
}

require_target() {
  [[ -n "${USER_MAC:-${FILE_TARGET_MAC:-}}" ]] || die "USER_MAC is required; run make config or use: USER_MAC=user@user-mac.local make install"
  FILE_TARGET_MAC="${USER_MAC:-$FILE_TARGET_MAC}"
  FILE_TARGET_PATH="${USER_COMMAND_PATH:-$FILE_TARGET_PATH}"
}

launch_domain() {
  printf 'gui/%s\n' "$(id -u)"
}

ensure_ssh_login() {
  require_target

  if ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" true >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$SKIP_SSH_COPY_ID" == "1" ]]; then
    log "SSH key login is not ready for $FILE_TARGET_MAC; skipping ssh-copy-id because SKIP_SSH_COPY_ID=1"
    return 0
  fi

  if have ssh-copy-id; then
    log "SSH key login is not ready for $FILE_TARGET_MAC; running ssh-copy-id"
    ssh-copy-id "$FILE_TARGET_MAC"
    return 0
  fi

  die "SSH key login failed and ssh-copy-id is not installed. Enable Remote Login on the USER Mac, then run from CORPO: ssh-copy-id $FILE_TARGET_MAC"
}

remote_path_expr() {
  local path="$1"

  case "$path" in
    '~')
      printf '"$HOME"'
      ;;
    '~/'*)
      printf '"$HOME"/%s' "$(shell_quote "${path#~/}")"
      ;;
    /*)
      printf '%s' "$(shell_quote "$path")"
      ;;
    *)
      printf '"$HOME"/%s' "$(shell_quote "$path")"
      ;;
  esac
}

preflight_target_path() {
  require_target

  local output

  if ! output="$(remote_check_user_command_path create 2>&1)"; then
    die "cannot write $FILE_TARGET_PATH on USER Mac $FILE_TARGET_MAC.

Remote check output:
$output

Try:
  USER_MAC='$FILE_TARGET_MAC' USER_COMMAND_PATH='~/bin/tmate-corpo' make config
  make install

This path is resolved on the USER Mac under that account's home directory."
  fi
}

preflight_target_path_quiet() {
  require_target

  remote_check_user_command_path create >/dev/null 2>&1
}

target_path_ready_quiet() {
  require_target

  remote_check_user_command_path check >/dev/null 2>&1
}

remote_user_command_exists() {
  require_target

  ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" /bin/bash -s -- "$FILE_TARGET_PATH" <<'REMOTE'
set -euo pipefail

target="$1"

case "$target" in
  '~')
    target="$HOME"
    ;;
  '~/'*)
    target="$HOME/${target#\~/}"
    ;;
  /*)
    ;;
  *)
    target="$HOME/$target"
    ;;
esac

test -x "$target"
REMOTE
}

remote_user_command_info() {
  require_target

  ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" /bin/bash -s -- "$FILE_TARGET_PATH" <<'REMOTE'
set -euo pipefail

target="$1"

case "$target" in
  '~')
    target="$HOME"
    ;;
  '~/'*)
    target="$HOME/${target#\~/}"
    ;;
  /*)
    ;;
  *)
    target="$HOME/$target"
    ;;
esac

dir="$(dirname "$target")"

printf 'resolved target: %s\n' "$target"
printf 'resolved dir: %s\n' "$dir"

if [[ -d "$dir" ]]; then
  printf 'dir exists: yes\n'
  ls -ld "$dir"
else
  printf 'dir exists: no\n'
fi

case ":$PATH:" in
  *":$dir:"*)
    printf 'dir on PATH: yes\n'
    ;;
  *)
    printf 'dir on PATH: no\n'
    ;;
esac

if [[ -e "$target" ]]; then
  printf 'file exists: yes\n'
  ls -l "$target"
else
  printf 'file exists: no\n'
fi
REMOTE
}

remote_ensure_user_command_path_on_path() {
  require_target

  ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" /bin/bash -s -- "$FILE_TARGET_PATH" <<'REMOTE'
set -euo pipefail

target="$1"

case "$target" in
  '~')
    target="$HOME"
    ;;
  '~/'*)
    target="$HOME/${target#\~/}"
    ;;
  /*)
    ;;
  *)
    target="$HOME/$target"
    ;;
esac

dir="$(dirname "$target")"

if [[ "$dir" != "$HOME/bin" ]]; then
  printf 'PATH update skipped: command dir is %s, not %s\n' "$dir" "$HOME/bin"
  exit 0
fi

block_start="# >>> tmate-corpo PATH >>>"
block_end="# <<< tmate-corpo PATH <<<"
path_line='export PATH="$HOME/bin:$PATH"'

ensure_file_has_path_block() {
  local file="$1"

  touch "$file"

  if grep -Fq "$block_start" "$file"; then
    printf 'PATH already managed in %s\n' "$file"
    return 0
  fi

  {
    printf '\n%s\n' "$block_start"
    printf '%s\n' "$path_line"
    printf '%s\n' "$block_end"
  } >>"$file"

  printf 'Added PATH update to %s\n' "$file"
}

ensure_file_has_path_block "$HOME/.zshrc"
ensure_file_has_path_block "$HOME/.zprofile"

case ":$PATH:" in
  *":$dir:"*)
    printf 'Current non-interactive PATH already contains %s\n' "$dir"
    ;;
  *)
    printf 'Future zsh sessions will include %s after opening a new terminal or running: source ~/.zshrc\n' "$dir"
    ;;
esac
REMOTE
}

detect_corpo_ssh_host() {
  if [[ -n "${CORPO_SSH_HOST:-}" && "$CORPO_SSH_HOST" != "auto" ]]; then
    printf '%s\n' "$CORPO_SSH_HOST"
    return 0
  fi

  local iface ip
  iface="$(route get default 2>/dev/null | awk '/interface:/{print $2; exit}' || true)"

  if [[ -n "$iface" ]]; then
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  printf '%s.local\n' "$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
}

fetch_user_public_key() {
  require_target

  ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" /bin/bash -s <<'REMOTE'
set -euo pipefail

for key in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ecdsa.pub" "$HOME/.ssh/id_rsa.pub"; do
  if [[ -r "$key" ]]; then
    cat "$key"
    exit 0
  fi
done

printf 'no public SSH key found in ~/.ssh/id_ed25519.pub, ~/.ssh/id_ecdsa.pub, or ~/.ssh/id_rsa.pub\n' >&2
exit 1
REMOTE
}

write_sshd_config() {
  mkdir -p "$SSHD_ROOT" "$LOG_DIR"

  cat >"$SSHD_CONFIG" <<EOF
Port $CORPO_SSH_PORT
ListenAddress 0.0.0.0
Protocol 2
HostKey $SSHD_HOST_KEY
PidFile $SSHD_PID_FILE
AuthorizedKeysFile $SSHD_AUTHORIZED_KEYS
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
UsePAM no
StrictModes no
X11Forwarding no
AllowTcpForwarding yes
PermitTTY yes
PrintMotd no
PrintLastLog no
Subsystem sftp /usr/libexec/sftp-server
EOF

  chmod 0600 "$SSHD_CONFIG"
}

prepare_userspace_sshd() {
  require_sshd
  require_target

  mkdir -p "$SSHD_ROOT" "$LOG_DIR"
  chmod 0700 "$SSHD_ROOT"

  if [[ ! -f "$SSHD_HOST_KEY" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "$SSHD_HOST_KEY"
  fi

  fetch_user_public_key >"$SSHD_AUTHORIZED_KEYS"
  chmod 0600 "$SSHD_AUTHORIZED_KEYS"
  write_sshd_config
}

sshd_alive() {
  [[ -f "$SSHD_PID_FILE" ]] || return 1

  local pid
  pid="$(cat "$SSHD_PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1
}

stop_userspace_sshd() {
  if sshd_alive; then
    kill "$(cat "$SSHD_PID_FILE")" >/dev/null 2>&1 || true
  fi
  rm -f "$SSHD_PID_FILE"
}

corpo_ssh_command() {
  local host
  host="$(detect_corpo_ssh_host)"

  printf 'ssh -p %s -o StrictHostKeyChecking=accept-new %s@%s' "$CORPO_SSH_PORT" "$(whoami)" "$host"
}

remote_check_user_command_path() {
  local mode="$1"

  require_target

  ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" /bin/bash -s -- "$FILE_TARGET_PATH" "$mode" <<'REMOTE'
set -euo pipefail

target="$1"
mode="$2"

case "$target" in
  '~')
    target="$HOME"
    ;;
  '~/'*)
    target="$HOME/${target#\~/}"
    ;;
  /*)
    ;;
  *)
    target="$HOME/$target"
    ;;
esac

dir="$(dirname "$target")"

printf 'resolved target: %s\n' "$target"
printf 'resolved dir: %s\n' "$dir"
printf 'mode: %s\n' "$mode"
printf 'sudo: disabled\n'

if [[ -e "$target" ]]; then
  test -w "$target" || { printf 'file exists but is not writable: %s\n' "$target" >&2; exit 20; }
  exit 0
fi

if [[ "$mode" == "create" ]]; then
  mkdir -p "$dir"
fi

test -d "$dir" || { printf 'directory does not exist: %s\n' "$dir" >&2; exit 21; }
test -w "$dir" || { printf 'directory is not writable: %s\n' "$dir" >&2; exit 22; }
REMOTE
}

write_connector_script() {
  local path="$1"
  local connect_command="$2"

  cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

CONNECT_COMMAND=$(single_quote "$connect_command")

if [[ "\${1:-}" == "--print" ]]; then
  printf '%s\n' "\$CONNECT_COMMAND"
  exit 0
fi

# The connector stores the current direct LAN SSH command.
# shellcheck disable=SC2206
cmd=( \$CONNECT_COMMAND )
exec "\${cmd[@]}" "\$@"
EOF
  chmod 0755 "$path"
}

publish_connector() {
  require_target

  local connect_command="$1"
  local target_arg
  local tmp
  local status=0

  tmp="$(mktemp "${TMPDIR:-/tmp}/tmate-corpo.XXXXXX")"
  write_connector_script "$tmp" "$connect_command"
  target_arg="$(single_quote "$FILE_TARGET_PATH")"

  ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" "
set -euo pipefail

target=$target_arg

case \"\$target\" in
  '~')
    target=\"\$HOME\"
    ;;
  '~/'*)
    target=\"\$HOME/\${target#\\~/}\"
    ;;
  /*)
    ;;
  *)
    target=\"\$HOME/\$target\"
    ;;
esac

mkdir -p \"\$(dirname \"\$target\")\"
cat > \"\$target\"
chmod 0755 \"\$target\"
test -x \"\$target\"
ls -l \"\$target\"
" <"$tmp" || status=$?

  rm -f "$tmp"
  (( status == 0 )) || return "$status"

  if ! remote_user_command_exists; then
    remote_user_command_info >&2 || true
    return 1
  fi

  remote_ensure_user_command_path_on_path

  log "published $APP_NAME connector to $FILE_TARGET_MAC:$FILE_TARGET_PATH"
}

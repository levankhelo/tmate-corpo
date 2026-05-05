#!/usr/bin/env bash

LABEL="com.tmate-corpo.agent"
APP_NAME="tmate-corpo"
DEFAULT_USER_COMMAND_PATH="/usr/local/bin/tmate-corpo"
INSTALL_ROOT="${TMATE_CORPO_HOME:-$HOME/.tmate-corpo}"
CONFIG_FILE="$INSTALL_ROOT/env"
LOCAL_CONFIG_FILE="${TMATE_CORPO_LOCAL_CONFIG:-}"
PLIST_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$INSTALL_ROOT/logs"
STDOUT_LOG="$LOG_DIR/stdout.log"
STDERR_LOG="$LOG_DIR/stderr.log"

ENV_FILE_TARGET_MAC="${FILE_TARGET_MAC-}"
ENV_FILE_TARGET_PATH="${FILE_TARGET_PATH-}"
ENV_USER_MAC="${USER_MAC-}"
ENV_USER_COMMAND_PATH="${USER_COMMAND_PATH-}"
ENV_TMATE_BIN="${TMATE_BIN-}"
ENV_TMATE_SESSION="${TMATE_SESSION-}"
ENV_TMATE_SOCKET="${TMATE_SOCKET-}"
ENV_TMATE_REFRESH_SECONDS="${TMATE_REFRESH_SECONDS-}"
ENV_TMATE_EMPTY_GRACE_SECONDS="${TMATE_EMPTY_GRACE_SECONDS-}"
ENV_TMATE_RESTART_ON_DISCONNECT="${TMATE_RESTART_ON_DISCONNECT-}"
ENV_REMOTE_INSTALL_WITH_SUDO="${REMOTE_INSTALL_WITH_SUDO-}"
ENV_SKIP_SSH_COPY_ID="${SKIP_SSH_COPY_ID-}"

TMATE_BIN="${TMATE_BIN:-}"
TMATE_SESSION="${TMATE_SESSION:-tmate-corpo}"
TMATE_SOCKET="${TMATE_SOCKET:-$INSTALL_ROOT/tmate.sock}"
FILE_TARGET_PATH="${FILE_TARGET_PATH:-}"
USER_MAC="${USER_MAC:-${FILE_TARGET_MAC:-}}"
USER_COMMAND_PATH="${USER_COMMAND_PATH:-}"
TMATE_REFRESH_SECONDS="${TMATE_REFRESH_SECONDS:-10}"
TMATE_EMPTY_GRACE_SECONDS="${TMATE_EMPTY_GRACE_SECONDS:-5}"
TMATE_RESTART_ON_DISCONNECT="${TMATE_RESTART_ON_DISCONNECT:-1}"
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

require_tmate() {
  if [[ -n "${TMATE_BIN:-}" && -x "$TMATE_BIN" ]]; then
    return 0
  fi

  if have tmate; then
    TMATE_BIN="$(command -v tmate)"
    return 0
  fi

  die "tmate is not installed; install it with: brew install tmate"
}

tmate_available_quiet() {
  if [[ -n "${TMATE_BIN:-}" && -x "$TMATE_BIN" ]]; then
    return 0
  fi

  if have tmate; then
    TMATE_BIN="$(command -v tmate)"
    return 0
  fi

  return 1
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
  [[ -n "$ENV_TMATE_BIN" ]] && TMATE_BIN="$ENV_TMATE_BIN"
  [[ -n "$ENV_TMATE_SESSION" ]] && TMATE_SESSION="$ENV_TMATE_SESSION"
  [[ -n "$ENV_TMATE_SOCKET" ]] && TMATE_SOCKET="$ENV_TMATE_SOCKET"
  [[ -n "$ENV_TMATE_REFRESH_SECONDS" ]] && TMATE_REFRESH_SECONDS="$ENV_TMATE_REFRESH_SECONDS"
  [[ -n "$ENV_TMATE_EMPTY_GRACE_SECONDS" ]] && TMATE_EMPTY_GRACE_SECONDS="$ENV_TMATE_EMPTY_GRACE_SECONDS"
  [[ -n "$ENV_TMATE_RESTART_ON_DISCONNECT" ]] && TMATE_RESTART_ON_DISCONNECT="$ENV_TMATE_RESTART_ON_DISCONNECT"
  [[ -n "$ENV_REMOTE_INSTALL_WITH_SUDO" ]] && REMOTE_INSTALL_WITH_SUDO="$ENV_REMOTE_INSTALL_WITH_SUDO"
  [[ -n "$ENV_SKIP_SSH_COPY_ID" ]] && SKIP_SSH_COPY_ID="$ENV_SKIP_SSH_COPY_ID"

  USER_MAC="${USER_MAC:-${FILE_TARGET_MAC:-}}"
  USER_COMMAND_PATH="${USER_COMMAND_PATH:-${FILE_TARGET_PATH:-}}"
  FILE_TARGET_MAC="$USER_MAC"
  FILE_TARGET_PATH="${USER_COMMAND_PATH:-$DEFAULT_USER_COMMAND_PATH}"
  USER_COMMAND_PATH="$FILE_TARGET_PATH"
  TMATE_BIN="${TMATE_BIN:-}"
  TMATE_SESSION="${TMATE_SESSION:-tmate-corpo}"
  TMATE_SOCKET="${TMATE_SOCKET:-$INSTALL_ROOT/tmate.sock}"
  TMATE_REFRESH_SECONDS="${TMATE_REFRESH_SECONDS:-10}"
  TMATE_EMPTY_GRACE_SECONDS="${TMATE_EMPTY_GRACE_SECONDS:-5}"
  TMATE_RESTART_ON_DISCONNECT="${TMATE_RESTART_ON_DISCONNECT:-1}"
  REMOTE_INSTALL_WITH_SUDO="${REMOTE_INSTALL_WITH_SUDO:-0}"
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
    printf 'TMATE_BIN=%s\n' "$(single_quote "$TMATE_BIN")"
    printf 'TMATE_SESSION=%s\n' "$(single_quote "$TMATE_SESSION")"
    printf 'TMATE_SOCKET=%s\n' "$(single_quote "$TMATE_SOCKET")"
    printf 'TMATE_REFRESH_SECONDS=%s\n' "$(single_quote "$TMATE_REFRESH_SECONDS")"
    printf 'TMATE_EMPTY_GRACE_SECONDS=%s\n' "$(single_quote "$TMATE_EMPTY_GRACE_SECONDS")"
    printf 'TMATE_RESTART_ON_DISCONNECT=%s\n' "$(single_quote "$TMATE_RESTART_ON_DISCONNECT")"
    printf 'REMOTE_INSTALL_WITH_SUDO=%s\n' "$(single_quote "$REMOTE_INSTALL_WITH_SUDO")"
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
  USER_MAC='$FILE_TARGET_MAC' USER_COMMAND_PATH='/usr/local/bin/tmate-corpo' REMOTE_INSTALL_WITH_SUDO=1 make config
  make install

This path usually requires passwordless sudo on the USER Mac."
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

remote_check_user_command_path() {
  local mode="$1"

  require_target

  ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" /bin/bash -s -- "$FILE_TARGET_PATH" "$REMOTE_INSTALL_WITH_SUDO" "$mode" <<'REMOTE'
set -euo pipefail

target="$1"
use_sudo="$2"
mode="$3"

case "$target" in
  '~')
    target="$HOME"
    ;;
  '~/'*)
    target="$HOME/${target#~/}"
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
printf 'sudo: %s\n' "$use_sudo"

if [[ "$use_sudo" == "1" ]]; then
  sudo -n true
  if [[ "$mode" == "create" ]]; then
    sudo -n mkdir -p "$dir"
  fi
  test -d "$dir" || { printf 'directory does not exist: %s\n' "$dir" >&2; exit 10; }
  sudo -n test -w "$dir" || { printf 'sudo cannot write directory: %s\n' "$dir" >&2; exit 11; }
  exit 0
fi

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

tmate_alive() {
  tmate_available_quiet || return 1
  [[ -S "$TMATE_SOCKET" ]] && "$TMATE_BIN" -S "$TMATE_SOCKET" has-session -t "$TMATE_SESSION" >/dev/null 2>&1
}

start_tmate() {
  mkdir -p "$INSTALL_ROOT"

  if [[ -e "$TMATE_SOCKET" ]] && ! "$TMATE_BIN" -S "$TMATE_SOCKET" list-sessions >/dev/null 2>&1; then
    rm -f "$TMATE_SOCKET"
  fi

  if tmate_alive; then
    return 0
  fi

  log "starting tmate session '$TMATE_SESSION'"
  "$TMATE_BIN" -S "$TMATE_SOCKET" new-session -d -s "$TMATE_SESSION"
  "$TMATE_BIN" -S "$TMATE_SOCKET" wait tmate-ready
}

stop_tmate() {
  if ! tmate_available_quiet; then
    rm -f "$TMATE_SOCKET"
    return 0
  fi

  if [[ -S "$TMATE_SOCKET" ]]; then
    "$TMATE_BIN" -S "$TMATE_SOCKET" kill-session -t "$TMATE_SESSION" >/dev/null 2>&1 || true
    "$TMATE_BIN" -S "$TMATE_SOCKET" kill-server >/dev/null 2>&1 || true
  fi

  rm -f "$TMATE_SOCKET"
}

restart_tmate() {
  log "restarting tmate session '$TMATE_SESSION'"
  stop_tmate
  start_tmate
}

tmate_connect_command() {
  "$TMATE_BIN" -S "$TMATE_SOCKET" display-message -p '#{tmate_ssh}' 2>/dev/null | sed '/^[[:space:]]*$/d' | head -n 1
}

tmate_client_count() {
  if ! tmate_alive; then
    printf '0\n'
    return 0
  fi

  "$TMATE_BIN" -S "$TMATE_SOCKET" list-clients 2>/dev/null | wc -l | tr -d '[:space:]'
  printf '\n'
}

write_connector_script() {
  local path="$1"
  local connect_command="$2"

  cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

TMATE_CONNECT_COMMAND=$(single_quote "$connect_command")

if [[ "\${1:-}" == "--print" ]]; then
  printf '%s\n' "\$TMATE_CONNECT_COMMAND"
  exit 0
fi

# tmate prints a shell command such as: ssh abc@nyc1.tmate.io
# shellcheck disable=SC2206
cmd=( \$TMATE_CONNECT_COMMAND )
exec "\${cmd[@]}" "\$@"
EOF
  chmod 0755 "$path"
}

publish_connector() {
  require_target

  local connect_command="$1"
  local target_expr
  local tmp
  local status=0

  tmp="$(mktemp "${TMPDIR:-/tmp}/tmate-corpo.XXXXXX")"
  write_connector_script "$tmp" "$connect_command"
  target_expr="$(remote_path_expr "$FILE_TARGET_PATH")"

  if [[ "$REMOTE_INSTALL_WITH_SUDO" == "1" ]]; then
    local remote_tmp="/tmp/tmate-corpo.$$"
    ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" "target=$target_expr; cat > $(shell_quote "$remote_tmp") && chmod 0755 $(shell_quote "$remote_tmp") && sudo -n mkdir -p \"\$(dirname \"\$target\")\" && sudo -n install -m 0755 $(shell_quote "$remote_tmp") \"\$target\" && rm -f $(shell_quote "$remote_tmp")" <"$tmp" || status=$?
  else
    ssh -o BatchMode=yes -o ConnectTimeout=8 "$FILE_TARGET_MAC" "target=$target_expr; mkdir -p \"\$(dirname \"\$target\")\"; cat > \"\$target\"; chmod 0755 \"\$target\"" <"$tmp" || status=$?
  fi

  rm -f "$tmp"
  (( status == 0 )) || return "$status"

  log "published $APP_NAME connector to $FILE_TARGET_MAC:$FILE_TARGET_PATH"
}

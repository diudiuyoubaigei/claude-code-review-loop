#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF' >&2
Usage: dispatch-claude.sh [OPTIONS]

Options:
  -p, --prompt TEXT          Task prompt to send to Claude Code.
  -f, --prompt-file PATH     Read the task prompt from a file.
  -d, --working-directory DIR
                             Change to DIR before invoking Claude Code.
  -m, --permission-mode MODE Permission mode for Claude Code.
                             (default: bypassPermissions)
  -t, --timeout SECONDS      Maximum seconds to wait per attempt.
                             (default: 7200, minimum: 1800)
  -r, --retry COUNT          Extra attempts after timeout or failure.
                             (default: 1)
  -h, --help                 Show this help message.

Either --prompt or --prompt-file is required. If both are provided,
--prompt takes precedence.
EOF
}

prompt=""
prompt_file=""
working_directory=""
permission_mode="bypassPermissions"
timeout_seconds=7200
retry_count=1

valid_modes=(acceptEdits auto bypassPermissions default dontAsk plan)

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--prompt)
      [ $# -ge 2 ] || { echo "Error: $1 requires a value." >&2; usage; exit 1; }
      prompt="$2"
      shift 2
      ;;
    -f|--prompt-file)
      [ $# -ge 2 ] || { echo "Error: $1 requires a value." >&2; usage; exit 1; }
      prompt_file="$2"
      shift 2
      ;;
    -d|--working-directory)
      [ $# -ge 2 ] || { echo "Error: $1 requires a value." >&2; usage; exit 1; }
      working_directory="$2"
      shift 2
      ;;
    -m|--permission-mode)
      [ $# -ge 2 ] || { echo "Error: $1 requires a value." >&2; usage; exit 1; }
      permission_mode="$2"
      shift 2
      ;;
    -t|--timeout)
      [ $# -ge 2 ] || { echo "Error: $1 requires a value." >&2; usage; exit 1; }
      timeout_seconds="$2"
      shift 2
      ;;
    -r|--retry)
      [ $# -ge 2 ] || { echo "Error: $1 requires a value." >&2; usage; exit 1; }
      retry_count="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -n "$prompt_file" ]; then
  if [ ! -f "$prompt_file" ]; then
    echo "Error: prompt file not found: $prompt_file" >&2
    exit 1
  fi
  prompt=$(cat -- "$prompt_file")
fi

if [ -z "$prompt" ]; then
  echo "Error: provide --prompt or --prompt-file." >&2
  usage
  exit 1
fi

valid_mode_found=false
for mode in "${valid_modes[@]}"; do
  if [ "$mode" = "$permission_mode" ]; then
    valid_mode_found=true
    break
  fi
done
if [ "$valid_mode_found" = false ]; then
  echo "Error: invalid permission mode: $permission_mode" >&2
  echo "Valid modes: ${valid_modes[*]}" >&2
  exit 1
fi

if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]]; then
  echo "Error: TimeoutSeconds must be an integer." >&2
  exit 1
fi
if [ "$timeout_seconds" -lt 1800 ]; then
  echo "Error: TimeoutSeconds must be at least 1800 seconds." >&2
  exit 1
fi

if [[ ! "$retry_count" =~ ^[0-9]+$ ]]; then
  echo "Error: RetryCount must be a non-negative integer." >&2
  exit 1
fi

attempt_limit=$((retry_count + 1))
if [ "$attempt_limit" -lt 1 ]; then
  attempt_limit=1
fi

if [ -n "$working_directory" ]; then
  if [ ! -d "$working_directory" ]; then
    echo "Error: working directory not found: $working_directory" >&2
    exit 1
  fi
  cd -- "$working_directory" || { echo "Error: failed to change directory to $working_directory" >&2; exit 1; }
fi

claude_cmd=$(command -v claude) || {
  echo "Error: 'claude' command not found in PATH." >&2
  exit 1
}

output_file=$(mktemp "${TMPDIR:-/tmp}/dispatch-claude.XXXXXX")
trap 'rm -f "$output_file"' EXIT

run_with_timeout() {
  local limit="$1"
  shift

  "$@" >"$output_file" 2>&1 &
  local pid=$!
  local start
  start=$(date +%s)

  while kill -0 "$pid" 2>/dev/null; do
    local now
    now=$(date +%s)
    if [ $((now - start)) -ge "$limit" ]; then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done

  wait "$pid"
}

last_exit=0
for ((attempt = 1; attempt <= attempt_limit; attempt++)); do
  echo "[dispatch-claude] attempt $attempt/$attempt_limit, timeout=${timeout_seconds}s, permission=$permission_mode" >&2

  run_with_timeout "$timeout_seconds" "$claude_cmd" --permission-mode "$permission_mode" -p "$prompt"
  last_exit=$?

  if [ "$last_exit" -eq 0 ]; then
    cat -- "$output_file"
    exit 0
  fi

  cat -- "$output_file"

  if [ "$last_exit" -eq 124 ]; then
    echo "[dispatch-claude] warning: Claude Code timed out on attempt $attempt." >&2
  else
    echo "[dispatch-claude] warning: Claude Code exited with code $last_exit on attempt $attempt." >&2
  fi
done

echo "[dispatch-claude] error: Claude Code did not finish after $attempt_limit attempt(s)." >&2
exit 1

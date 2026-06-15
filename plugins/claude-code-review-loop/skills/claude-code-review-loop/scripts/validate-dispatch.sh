#!/usr/bin/env bash
# shellcheck disable=SC2329
set -uo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
dispatch="$script_dir/dispatch-claude.sh"
failed=0
passed=0

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/validate-dispatch.XXXXXX")
trap 'rm -rf "$tmp_root"' EXIT

fake_bin="$tmp_root/bin"
mkdir -p "$fake_bin"

run_test() {
  local name="$1"
  shift
  echo "== $name =="
  if "$@"; then
    echo "PASS: $name"
    ((passed++))
  else
    echo "FAIL: $name"
    ((failed++))
  fi
  echo
}

# 1. Syntax check
test_syntax() {
  bash -n "$dispatch"
}

# 2. Missing prompt
test_missing_prompt() {
  if PATH="$fake_bin:$PATH" "$dispatch" &>/dev/null; then
    return 1
  fi
  return 0
}

# 3. Timeout below minimum
test_timeout_too_small() {
  if PATH="$fake_bin:$PATH" "$dispatch" -p "hi" -t 60 &>/dev/null; then
    return 1
  fi
  return 0
}

# 4. Successful dispatch
test_success() {
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/sh
echo "fake claude: $@"
exit 0
EOF
  chmod +x "$fake_bin/claude"
  local out
  if out=$(PATH="$fake_bin:$PATH" "$dispatch" -p "do work" -r 0); then
    [[ "$out" == *"fake claude:"* ]]
  fi
}

# 5. Retry on non-zero exit
test_retry_on_failure() {
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/sh
file="${FAKE_STATE:-/tmp/fake-claude-state}"
count=0
[ -f "$file" ] && count=$(cat "$file")
count=$((count + 1))
echo "$count" > "$file"
echo "attempt $count"
if [ "$count" -eq 1 ]; then
  exit 1
fi
exit 0
EOF
  chmod +x "$fake_bin/claude"
  state_file="$tmp_root/failure-state"
  rm -f "$state_file"
  local out
  out=$(FAKE_STATE="$state_file" PATH="$fake_bin:$PATH" "$dispatch" -p "retry me" -r 1 -t 1800)
  local rc=$?
  local final_count
  final_count=$(cat "$state_file")
  [ "$rc" -eq 0 ] && [ "$final_count" -eq 2 ] && [[ "$out" == *"attempt 1"* ]] && [[ "$out" == *"attempt 2"* ]]
}

# 6. All attempts fail
test_all_fail() {
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/sh
echo "always fails"
exit 1
EOF
  chmod +x "$fake_bin/claude"
  if PATH="$fake_bin:$PATH" "$dispatch" -p "fail" -r 1 -t 1800 &>/dev/null; then
    return 1
  fi
  return 0
}

# 7. Prompt file
test_prompt_file() {
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/sh
echo "args: $@"
exit 0
EOF
  chmod +x "$fake_bin/claude"
  local prompt_file="$tmp_root/prompt.txt"
  printf 'fix the bug in app.js' > "$prompt_file"
  local out
  if out=$(PATH="$fake_bin:$PATH" "$dispatch" -f "$prompt_file" -r 0 -t 1800); then
    [[ "$out" == *"fix the bug in app.js"* ]]
  fi
}

# 8. Working directory
test_working_directory() {
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/sh
echo "cwd=$(pwd)"
exit 0
EOF
  chmod +x "$fake_bin/claude"
  local target_dir="$tmp_root/repo"
  mkdir -p "$target_dir"
  local canonical_target_dir
  canonical_target_dir=$(cd "$target_dir" && pwd)
  local out
  if out=$(PATH="$fake_bin:$PATH" "$dispatch" -d "$target_dir" -p "work here" -r 0 -t 1800); then
    [[ "$out" == *"cwd=$canonical_target_dir"* ]]
  fi
}

run_test "syntax check" test_syntax
run_test "missing prompt" test_missing_prompt
run_test "timeout below minimum" test_timeout_too_small
run_test "successful dispatch" test_success
run_test "retry on failure" test_retry_on_failure
run_test "all attempts fail" test_all_fail
run_test "prompt file" test_prompt_file
run_test "working directory" test_working_directory

echo "Results: $passed passed, $failed failed"
exit $failed

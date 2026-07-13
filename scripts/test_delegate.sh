#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
target="$repo_root/scripts/delegate.sh"

if [[ ! -x "$target" ]]; then
  printf 'expected executable helper at %s\n' "$target" >&2
  exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

test_repo="$tmpdir/repo"
mkdir -p "$test_repo/scripts" "$tmpdir/bin"
git -C "$test_repo" init -q
cp "$target" "$test_repo/scripts/delegate.sh"

cat >"$tmpdir/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

result_path=''
model=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m)
      model=$2
      shift 2
      ;;
    --output-last-message)
      result_path=$2
      shift 2
      ;;
    exec|-)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

printf 'model=%s\n' "$model"

if [[ $model == exit-7 ]]; then
  exit 7
fi

if [[ $model == hold ]]; then
  : >"$DELEGATE_TEST_HOLD_DIR/started"
  while [[ ! -e $DELEGATE_TEST_HOLD_DIR/release ]]; do
    sleep 0.01
  done
fi

if [[ $model == race-hold ]]; then
  : >"$DELEGATE_TEST_STALE_RACE_DIR/codex-started"
  : >"$DELEGATE_TEST_STALE_RACE_DIR/codex-started.$$"
  while [[ ! -e $DELEGATE_TEST_STALE_RACE_DIR/release ]]; do
    sleep 0.01
  done
fi

if [[ $model == orphan-hold ]]; then
  printf '%s\n' "$$" >"$DELEGATE_TEST_HOLD_DIR/codex-pid"
  : >"$DELEGATE_TEST_HOLD_DIR/started"
  while [[ ! -e $DELEGATE_TEST_HOLD_DIR/release ]]; do
    sleep 0.01
  done
fi

if [[ $model == hold-exit-7 ]]; then
  printf '%s\n' "$$" >"$DELEGATE_TEST_HOLD_DIR/codex-pid"
  : >"$DELEGATE_TEST_HOLD_DIR/started"
  while [[ ! -e $DELEGATE_TEST_HOLD_DIR/release ]]; do
    sleep 0.01
  done
  exit 7
fi

cat >"$result_path"
EOF
chmod +x "$tmpdir/bin/codex"

cat >"$tmpdir/bin/rm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n ${DELEGATE_TEST_STALE_RACE_DIR:-} && $# -eq 2 && $1 == -rf && $2 == */.lock ]]; then
  if mkdir "$DELEGATE_TEST_STALE_RACE_DIR/rm-first" 2>/dev/null; then
    : >"$DELEGATE_TEST_STALE_RACE_DIR/rm-first-ready"
    while [[ ! -e $DELEGATE_TEST_STALE_RACE_DIR/rm-second-ready ]]; do
      sleep 0.01
    done
  else
    : >"$DELEGATE_TEST_STALE_RACE_DIR/rm-second-ready"
    while [[ ! -e $DELEGATE_TEST_STALE_RACE_DIR/codex-started ]]; do
      sleep 0.01
    done
  fi
fi

exec /bin/rm "$@"
EOF
chmod +x "$tmpdir/bin/rm"

cat >"$tmpdir/bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args=("$@")
if [[ ${args[0]:-} == -- ]]; then
  args=("${args[@]:1}")
fi

if [[ -n ${DELEGATE_TEST_STALE_RACE_DIR:-} && ${#args[@]} -eq 2 && ${args[0]} == */.lock && ${args[1]} == "${args[0]}.stale."* ]]; then
  if mkdir "$DELEGATE_TEST_STALE_RACE_DIR/mv-first" 2>/dev/null; then
    : >"$DELEGATE_TEST_STALE_RACE_DIR/mv-first-ready"
    while [[ ! -e $DELEGATE_TEST_STALE_RACE_DIR/mv-second-ready ]]; do
      sleep 0.01
    done
    /bin/mv "${args[@]}"
    status=$?
    : >"$DELEGATE_TEST_STALE_RACE_DIR/mv-first-done"
    while [[ ! -e $DELEGATE_TEST_STALE_RACE_DIR/mv-second-done ]]; do
      sleep 0.01
    done
    exit "$status"
  fi

  : >"$DELEGATE_TEST_STALE_RACE_DIR/mv-second-ready"
  while [[ ! -e $DELEGATE_TEST_STALE_RACE_DIR/mv-first-done ]]; do
    sleep 0.01
  done
  set +e
  /bin/mv "${args[@]}"
  status=$?
  set -e
  : >"$DELEGATE_TEST_STALE_RACE_DIR/mv-second-done"
  exit "$status"
fi

exec /bin/mv "$@"
EOF
chmod +x "$tmpdir/bin/mv"

run_helper() {
  (
    cd "$test_repo"
    PATH="$tmpdir/bin:$PATH" "$test_repo/scripts/delegate.sh" "$@"
  )
}

today=$(date +%F)
role='luna-test'
dir="$test_repo/agents/$today-01-delegate-contract/01-$role"

printf 'stdin prompt' | run_helper delegate-contract "$role" gpt-5.6-luna >"$tmpdir/run.out"
[[ $(<"$dir/input.md") == 'stdin prompt' ]]
[[ $(<"$dir/result.md") == 'stdin prompt' ]]
[[ $(<"$dir/output.md") == 'model=gpt-5.6-luna' ]]
rg -F "$dir/input.md" "$tmpdir/run.out" >/dev/null
rg -F "$dir/output.md" "$tmpdir/run.out" >/dev/null
rg -F "$dir/result.md" "$tmpdir/run.out" >/dev/null

if printf 'second prompt' | run_helper delegate-contract "$role" gpt-5.6-luna >"$tmpdir/refuse.out" 2>&1; then
  printf 'expected existing result.md to be refused\n' >&2
  exit 1
fi
rg -F 'refusing to overwrite existing result.md' "$tmpdir/refuse.out" >/dev/null

printf 'forced prompt' | run_helper --force delegate-contract "$role" gpt-5.6-luna >/dev/null
[[ $(<"$dir/result.md") == 'forced prompt' ]]

force_failure_dir="$test_repo/agents/$today-02-delegate-force-failure/01-luna-force-failure"
printf 'successful prompt' | run_helper delegate-force-failure luna-force-failure gpt-5.6-luna >/dev/null
[[ $(<"$force_failure_dir/result.md") == 'successful prompt' ]]
if printf 'failing forced prompt' | run_helper --force delegate-force-failure luna-force-failure exit-7 >/dev/null; then
  printf 'expected forced Codex exit status to be preserved\n' >&2
  exit 1
else
  status=$?
fi
[[ $status -eq 7 ]]
[[ -f "$force_failure_dir/result.md" ]]
[[ ! -s "$force_failure_dir/result.md" ]]

printf 'file prompt' >"$tmpdir/prompt.md"
run_helper delegate-file-input luna-file gpt-5.6-luna "$tmpdir/prompt.md" >/dev/null
[[ $(<"$test_repo/agents/$today-03-delegate-file-input/01-luna-file/input.md") == 'file prompt' ]]

if printf 'failing prompt' | run_helper delegate-exit luna-exit exit-7 >/dev/null; then
  printf 'expected Codex exit status to be preserved\n' >&2
  exit 1
else
  status=$?
fi
[[ $status -eq 7 ]]
[[ -f "$test_repo/agents/$today-04-delegate-exit/01-luna-exit/input.md" ]]
[[ -f "$test_repo/agents/$today-04-delegate-exit/01-luna-exit/output.md" ]]
[[ -f "$test_repo/agents/$today-04-delegate-exit/01-luna-exit/result.md" ]]

hold_dir="$tmpdir/hold"
mkdir "$hold_dir"
DELEGATE_TEST_HOLD_DIR="$hold_dir" \
  run_helper delegate-concurrent luna-concurrent hold >"$tmpdir/first.out" 2>&1 &
first_pid=$!
while [[ ! -e $hold_dir/started ]]; do
  sleep 0.01
done
if run_helper delegate-concurrent luna-concurrent gpt-5.6-luna >"$tmpdir/second.out" 2>&1; then
  printf 'expected concurrent invocation to be refused\n' >&2
  exit 1
else
  status=$?
fi
[[ $status -eq 1 ]]
rg -F 'another invocation is already writing audit files' "$tmpdir/second.out" >/dev/null
: >"$hold_dir/release"
wait "$first_pid"
concurrent_dir="$test_repo/agents/$today-05-delegate-concurrent/01-luna-concurrent"
[[ -f "$concurrent_dir/result.md" ]]

stale_role='luna-stale-lock'
# Pre-created with arbitrary numbers (07/05): the helper must reuse an existing
# numbered dir whose slug/role matches instead of allocating a new number.
stale_dir="$test_repo/agents/$today-07-delegate-stale-lock/05-$stale_role"
stale_lock_path="$stale_dir/.lock"
mkdir -p "$stale_dir"
mkdir "$stale_lock_path"
(exit 0) &
dead_owner_pid=$!
wait "$dead_owner_pid"
printf '%s\n' "$dead_owner_pid" >"$stale_lock_path/pid"
printf 'stale lock prompt' | run_helper delegate-stale-lock "$stale_role" gpt-5.6-luna >/dev/null
[[ $(<"$stale_dir/result.md") == 'stale lock prompt' ]]
[[ ! -e $stale_lock_path ]]

pending_role='luna-pending-codex-lock'
pending_dir="$test_repo/agents/$today-08-delegate-pending-codex-lock/01-$pending_role"
pending_lock_path="$pending_dir/.lock"
mkdir -p "$pending_lock_path"
(exit 0) &
pending_dead_pid=$!
wait "$pending_dead_pid"
printf '%s\n' "$pending_dead_pid" >"$pending_lock_path/pid"
printf 'pending\n' >"$pending_lock_path/codex_pid"
if printf 'must be refused' | run_helper delegate-pending-codex-lock "$pending_role" gpt-5.6-luna >"$tmpdir/pending-codex.out" 2>&1; then
  printf 'expected a dead-wrapper lock with pending codex marker to be refused\n' >&2
  exit 1
else
  status=$?
fi
[[ $status -eq 1 ]]
[[ -d $pending_lock_path ]]
[[ ! -e $pending_dir/result.md ]]
rg -F 'another invocation is already writing audit files' "$tmpdir/pending-codex.out" >/dev/null

missing_pid_role='luna-missing-pid-lock'
missing_pid_dir="$test_repo/agents/$today-09-delegate-missing-pid-lock/01-$missing_pid_role"
missing_pid_lock_path="$missing_pid_dir/.lock"
mkdir -p "$missing_pid_lock_path"
if printf 'must be refused' | run_helper delegate-missing-pid-lock "$missing_pid_role" gpt-5.6-luna >"$tmpdir/missing-pid.out" 2>&1; then
  printf 'expected a lock with no pid file to be refused\n' >&2
  exit 1
else
  status=$?
fi
[[ $status -eq 1 ]]
[[ -d $missing_pid_lock_path ]]
[[ ! -e $missing_pid_dir/result.md ]]
rg -F 'another invocation is already writing audit files' "$tmpdir/missing-pid.out" >/dev/null

race_role='luna-stale-race'
race_dir="$test_repo/agents/$today-10-delegate-stale-race/01-$race_role"
race_lock_path="$race_dir/.lock"
race_control_dir="$tmpdir/stale-race"
mkdir -p "$race_dir" "$race_control_dir"
mkdir "$race_lock_path"
printf '%s\n' "$dead_owner_pid" >"$race_lock_path/pid"
printf 'first contender' >"$tmpdir/race-first.md"
printf 'second contender' >"$tmpdir/race-second.md"
DELEGATE_TEST_STALE_RACE_DIR="$race_control_dir" \
  run_helper --force delegate-stale-race "$race_role" race-hold "$tmpdir/race-first.md" >"$tmpdir/race-first.out" 2>&1 &
race_first_pid=$!
DELEGATE_TEST_STALE_RACE_DIR="$race_control_dir" \
  run_helper --force delegate-stale-race "$race_role" race-hold "$tmpdir/race-second.md" >"$tmpdir/race-second.out" 2>&1 &
race_second_pid=$!
for _ in {1..500}; do
  [[ -e $race_control_dir/codex-started ]] && break
  sleep 0.01
done
[[ -e $race_control_dir/codex-started ]]
for _ in {1..500}; do
  if ! kill -0 "$race_first_pid" 2>/dev/null || ! kill -0 "$race_second_pid" 2>/dev/null; then
    break
  fi
  sleep 0.01
done
[[ -d $race_lock_path ]]
[[ -r $race_lock_path/pid ]]
race_owner_pid=$(<"$race_lock_path/pid")
kill -0 "$race_owner_pid" 2>/dev/null
race_started_count=$(find "$race_control_dir" -name 'codex-started.*' -type f | wc -l | tr -d ' ')
[[ $race_started_count -eq 1 ]]
: >"$race_control_dir/release"
set +e
wait "$race_first_pid"
race_first_status=$?
wait "$race_second_pid"
race_second_status=$?
set -e
if ! { [[ $race_first_status -eq 0 && $race_second_status -eq 1 ]] || [[ $race_first_status -eq 1 && $race_second_status -eq 0 ]]; }; then
  printf 'expected exactly one stale-lock contender to proceed; got %s and %s\n' "$race_first_status" "$race_second_status" >&2
  exit 1
fi
[[ ! -e $race_lock_path ]]
if find "$race_dir" -maxdepth 1 -name '.lock.stale.*' -print -quit | rg . >/dev/null; then
  printf 'expected renamed stale lock directory to be cleaned up\n' >&2
  exit 1
fi

orphan_role='luna-orphan-child'
orphan_dir="$test_repo/agents/$today-11-delegate-orphan-child/01-$orphan_role"
orphan_lock_path="$orphan_dir/.lock"
orphan_hold_dir="$tmpdir/orphan-hold"
mkdir "$orphan_hold_dir"
printf 'orphan prompt' >"$tmpdir/orphan.md"
DELEGATE_TEST_HOLD_DIR="$orphan_hold_dir" \
  run_helper --force delegate-orphan-child "$orphan_role" orphan-hold "$tmpdir/orphan.md" >"$tmpdir/orphan-first.out" 2>&1 &
orphan_job_pid=$!
for _ in {1..500}; do
  [[ -e $orphan_hold_dir/started && -r $orphan_lock_path/pid ]] && break
  sleep 0.01
done
[[ -e $orphan_hold_dir/started ]]
orphan_wrapper_pid=$(<"$orphan_lock_path/pid")
orphan_codex_pid=$(<"$orphan_hold_dir/codex-pid")
kill -KILL "$orphan_wrapper_pid"
wait "$orphan_job_pid" 2>/dev/null || true
kill -0 "$orphan_codex_pid" 2>/dev/null
set +e
printf 'second writer' | run_helper --force delegate-orphan-child "$orphan_role" gpt-5.6-luna >"$tmpdir/orphan-second.out" 2>&1
orphan_second_status=$?
set -e
: >"$orphan_hold_dir/release"
for _ in {1..500}; do
  ! kill -0 "$orphan_codex_pid" 2>/dev/null && break
  sleep 0.01
done
[[ $orphan_second_status -eq 1 ]]
rg -F 'another invocation is already writing audit files' "$tmpdir/orphan-second.out" >/dev/null

wait_status_role='luna-wait-status'
wait_status_dir="$test_repo/agents/$today-12-delegate-wait-status/01-$wait_status_role"
wait_status_hold_dir="$tmpdir/wait-status-hold"
mkdir "$wait_status_hold_dir"
printf 'wait status prompt' >"$tmpdir/wait-status.md"
DELEGATE_TEST_HOLD_DIR="$wait_status_hold_dir" \
  run_helper delegate-wait-status "$wait_status_role" hold-exit-7 "$tmpdir/wait-status.md" >"$tmpdir/wait-status.out" 2>&1 &
wait_status_job_pid=$!
for _ in {1..500}; do
  [[ -e $wait_status_hold_dir/started && -r $wait_status_dir/.lock/codex_pid ]] && break
  sleep 0.01
done
[[ -r $wait_status_dir/.lock/codex_pid ]]
[[ $(<"$wait_status_dir/.lock/codex_pid") == "$(<"$wait_status_hold_dir/codex-pid")" ]]
: >"$wait_status_hold_dir/release"
set +e
wait "$wait_status_job_pid"
wait_status=$?
set -e
[[ $wait_status -eq 7 ]]
[[ ! -e $wait_status_dir/.lock ]]

live_role='luna-live-lock'
live_dir="$test_repo/agents/$today-13-delegate-live-lock/01-$live_role"
live_lock_path="$live_dir/.lock"
mkdir -p "$live_dir"
sleep 30 &
live_owner_pid=$!
mkdir "$live_lock_path"
printf '%s\n' "$live_owner_pid" >"$live_lock_path/pid"
if run_helper delegate-live-lock "$live_role" gpt-5.6-luna >"$tmpdir/live-owner.out" 2>&1; then
  printf 'expected live-owner lock to be refused\n' >&2
  exit 1
else
  status=$?
fi
[[ $status -eq 1 ]]
rg -F 'another invocation is already writing audit files' "$tmpdir/live-owner.out" >/dev/null
kill "$live_owner_pid"
wait "$live_owner_pid" 2>/dev/null || true

if run_helper invalid >/dev/null 2>&1; then
  printf 'expected invalid arguments to fail\n' >&2
  exit 1
fi

printf 'delegate.sh contract tests passed\n'

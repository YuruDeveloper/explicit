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

cat >"$result_path"
EOF
chmod +x "$tmpdir/bin/codex"

run_helper() {
  (
    cd "$test_repo"
    PATH="$tmpdir/bin:$PATH" "$test_repo/scripts/delegate.sh" "$@"
  )
}

today=$(date +%F)
role='luna-test'
dir="$test_repo/agents/$today-delegate-contract/$role"

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

force_failure_dir="$test_repo/agents/$today-delegate-force-failure/luna-force-failure"
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
[[ $(<"$test_repo/agents/$today-delegate-file-input/luna-file/input.md") == 'file prompt' ]]

if printf 'failing prompt' | run_helper delegate-exit luna-exit exit-7 >/dev/null; then
  printf 'expected Codex exit status to be preserved\n' >&2
  exit 1
else
  status=$?
fi
[[ $status -eq 7 ]]
[[ -f "$test_repo/agents/$today-delegate-exit/luna-exit/input.md" ]]
[[ -f "$test_repo/agents/$today-delegate-exit/luna-exit/output.md" ]]
[[ -f "$test_repo/agents/$today-delegate-exit/luna-exit/result.md" ]]

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
concurrent_dir="$test_repo/agents/$today-delegate-concurrent/luna-concurrent"
[[ -f "$concurrent_dir/result.md" ]]

if run_helper invalid >/dev/null 2>&1; then
  printf 'expected invalid arguments to fail\n' >&2
  exit 1
fi

printf 'delegate.sh contract tests passed\n'

#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: scripts/delegate.sh [-f|--force] <task-slug> <role> <model> [input-file]' \
    '       scripts/delegate.sh <task-slug> <role> <model> [input-file] [-f|--force]' >&2
}

usage_error() {
  printf 'error: %s\n' "$1" >&2
  usage
  exit 2
}

is_safe_component() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

force=0
args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      force=1
      ;;
    --)
      shift
      args+=("$@")
      break
      ;;
    -*)
      usage_error "unknown option: $1"
      ;;
    *)
      args+=("$1")
      ;;
  esac
  shift
done

if [[ ${#args[@]} -lt 3 || ${#args[@]} -gt 4 ]]; then
  usage_error 'expected <task-slug> <role> <model> [input-file]'
fi

task_slug=${args[0]}
role=${args[1]}
model=${args[2]}
input_file=${args[3]:-}

if ! is_safe_component "$task_slug"; then
  usage_error 'task-slug must use letters, numbers, dots, underscores, or hyphens'
fi

if ! is_safe_component "$role"; then
  usage_error 'role must use letters, numbers, dots, underscores, or hyphens'
fi

if [[ ! $model =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]; then
  usage_error 'model must use letters, numbers, dots, underscores, hyphens, or colons'
fi

if [[ -n $input_file && (! -f $input_file || ! -r $input_file) ]]; then
  usage_error "input-file is not a readable file: $input_file"
fi

if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  printf 'error: could not determine the Git repository root\n' >&2
  exit 1
fi

agent_dir="$repo_root/agents/$(date +%F)-$task_slug/$role"
input_path="$agent_dir/input.md"
output_path="$agent_dir/output.md"
result_path="$agent_dir/result.md"
lock_path="$agent_dir/.lock"

mkdir -p "$agent_dir"

if ! mkdir "$lock_path" 2>/dev/null; then
  printf 'error: refusing to start; another invocation is already writing audit files: %s\n' "$agent_dir" >&2
  exit 1
fi

cleanup_lock() {
  rmdir "$lock_path" 2>/dev/null || true
}
trap cleanup_lock EXIT

if [[ -e $result_path && $force -ne 1 ]]; then
  printf 'error: refusing to overwrite existing result.md: %s (pass --force to replace it)\n' "$result_path" >&2
  exit 1
fi

: >"$result_path"

if [[ -n $input_file ]]; then
  cp "$input_file" "$input_path"
else
  cat >"$input_path"
fi

set +e
codex exec -m "$model" --output-last-message "$result_path" - \
  <"$input_path" >"$output_path" 2>&1
codex_status=$?
set -e

if [[ ! -e $result_path ]]; then
  : >"$result_path"
fi

printf 'input.md: %s\n' "$input_path"
printf 'output.md: %s\n' "$output_path"
printf 'result.md: %s\n' "$result_path"

exit "$codex_status"

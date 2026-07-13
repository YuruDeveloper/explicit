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

# Directory layout: agents/<YYYY-MM-DD>-<NN>-<task-slug>/<NN>-<role>/
# NN is auto-allocated (per-date for tasks, per-task for roles); an existing
# directory with the same slug/role is reused so reruns and --force keep working.
resolve_numbered_dir() {
  local parent=$1 prefix=$2 slug=$3
  local max=0 found='' path name num rest

  if [[ -d $parent ]]; then
    for path in "$parent"/"$prefix"*; do
      [[ -d $path ]] || continue
      name=${path##*/}
      name=${name#"$prefix"}
      if [[ $name =~ ^([0-9]+)-(.+)$ ]]; then
        num=$((10#${BASH_REMATCH[1]}))
        rest=${BASH_REMATCH[2]}
        (( num > max )) && max=$num
        [[ $rest == "$slug" ]] && found=${path##*/}
      fi
    done
  fi

  if [[ -n $found ]]; then
    printf '%s\n' "$found"
  else
    printf '%s%02d-%s\n' "$prefix" $((max + 1)) "$slug"
  fi
}

agents_root="$repo_root/agents"
date_str=$(date +%F)
task_dir_name=$(resolve_numbered_dir "$agents_root" "$date_str-" "$task_slug")
role_dir_name=$(resolve_numbered_dir "$agents_root/$task_dir_name" '' "$role")
agent_dir="$agents_root/$task_dir_name/$role_dir_name"
input_path="$agent_dir/input.md"
output_path="$agent_dir/output.md"
result_path="$agent_dir/result.md"
lock_path="$agent_dir/.lock"

mkdir -p "$agent_dir"

pid_is_alive() {
  [[ $1 =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null
}

write_lock_owner() {
  if printf '%s\n' "$$" >"$lock_path/pid"; then
    return 0
  fi

  rmdir "$lock_path" 2>/dev/null || true
  return 1
}

acquire_lock() {
  if mkdir "$lock_path" 2>/dev/null; then
    write_lock_owner
    return
  fi

  local owner_pid=''
  local owner_codex_pid=''
  local stale_path=''

  if [[ ! -r $lock_path/pid ]] || ! IFS= read -r owner_pid <"$lock_path/pid"; then
    return 1
  fi

  if [[ ! $owner_pid =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if [[ -e $lock_path/codex_pid ]]; then
    if [[ ! -r $lock_path/codex_pid ]] || ! IFS= read -r owner_codex_pid <"$lock_path/codex_pid"; then
      return 1
    fi
    if [[ ! $owner_codex_pid =~ ^[0-9]+$ ]]; then
      return 1
    fi
  fi

  if pid_is_alive "$owner_pid" || { [[ -n $owner_codex_pid ]] && pid_is_alive "$owner_codex_pid"; }; then
    return 1
  fi

  stale_path="$lock_path.stale.$$.$RANDOM"
  if [[ -e $stale_path ]] || ! mv "$lock_path" "$stale_path" 2>/dev/null; then
    return 1
  fi

  if ! mkdir "$lock_path" 2>/dev/null; then
    rm -rf "$stale_path" || true
    return 1
  fi

  if ! write_lock_owner; then
    rm -rf "$stale_path" || true
    return 1
  fi

  rm -rf "$stale_path" || true
}

if ! acquire_lock; then
  printf 'error: refusing to start; another invocation is already writing audit files: %s\n' "$agent_dir" >&2
  exit 1
fi

cleanup_lock() {
  local owner_pid=''
  if [[ -r $lock_path/pid ]] && IFS= read -r owner_pid <"$lock_path/pid" && [[ $owner_pid == "$$" ]]; then
    rm -f "$lock_path/codex_pid" "$lock_path/pid"
    rmdir "$lock_path" 2>/dev/null || true
  fi
}
trap cleanup_lock EXIT

codex_pid=''
wait_interrupted=0

forward_signal() {
  local signal=$1
  local signal_status=$2

  if [[ -n $codex_pid ]] && kill -0 "$codex_pid" 2>/dev/null; then
    wait_interrupted=1
    kill -s "$signal" "$codex_pid" 2>/dev/null || true
    return
  fi

  exit "$signal_status"
}

trap 'forward_signal TERM 143' TERM
trap 'forward_signal INT 130' INT

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

# Conservative marker: written before the child starts so a wrapper killed in the
# start→pid-write gap leaves a non-numeric codex_pid, which takeover refuses.
if ! printf 'pending\n' >"$lock_path/codex_pid"; then
  printf 'error: could not record pending Codex marker in lock: %s\n' "$lock_path" >&2
  exit 1
fi

set +e
(
  trap - INT TERM
  exec codex exec -m "$model" --output-last-message "$result_path" -
) <"$input_path" >"$output_path" 2>&1 &
codex_pid=$!
if ! printf '%s\n' "$codex_pid" >"$lock_path/codex_pid"; then
  kill -TERM "$codex_pid" 2>/dev/null || true
  wait "$codex_pid" 2>/dev/null || true
  printf 'error: could not record Codex child PID in lock: %s\n' "$lock_path" >&2
  exit 1
fi

while true; do
  wait_interrupted=0
  wait "$codex_pid"
  codex_status=$?
  if [[ $wait_interrupted -eq 0 ]]; then
    break
  fi
done
codex_pid=''
set -e

if [[ ! -e $result_path ]]; then
  : >"$result_path"
fi

printf 'input.md: %s\n' "$input_path"
printf 'output.md: %s\n' "$output_path"
printf 'result.md: %s\n' "$result_path"

exit "$codex_status"

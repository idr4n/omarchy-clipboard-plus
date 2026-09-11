#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob dotglob

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
worker=$repository/ClipboardFiles.sh
scratch=$(mktemp --directory -- /tmp/clipboard-plus-files-test.XXXXXXXXXX)
worker_pids=()
command_fds=()
event_fds=()
editor_paths=()
editor_directories=()
app_ids=()

cleanup() {
  local status=$?
  local fd pid
  trap - EXIT
  # Release every controlled editor before removing any fixture it could use.
  for fd in "${command_fds[@]}"; do
    printf 'succeed\n' >&"$fd" || :
  done
  for pid in "${worker_pids[@]}"; do
    if [[ -n $pid ]]; then wait "$pid" || :; fi
  done
  rm -rf -- "$scratch"
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_success() {
  "$@" > "$scratch/stdout" 2> "$scratch/stderr" || fail "Expected successful file operation: $*"
  cmp -- "$scratch/ok" "$scratch/stdout" || fail 'Success did not produce exactly ok and a newline.'
  [[ ! -s $scratch/stderr ]] || fail 'Unexpected successful-operation diagnostic.'
}

expect_failure() {
  local expected=$1 actual=0
  shift
  "$@" > "$scratch/stdout" 2> "$scratch/stderr" || actual=$?
  (( actual == expected )) || fail "Expected exit $expected, got $actual."
  [[ ! -s $scratch/stdout && -s $scratch/stderr ]] || fail 'Failure must emit only a diagnostic, not success.'
}

expect_only_child() {
  local directory=$1 expected=$2
  local children=("$directory"/*)
  [[ ${#children[@]} == 1 && ${children[0]} == "$expected" ]] || fail "Unexpected leftover or missing file in $directory."
}

expect_original() {
  cmp -- "$source" "$scratch/original" || fail 'The original source image changed.'
}

printf 'ok\n' > "$scratch/ok"
printf 'original image bytes\0\377\n' > "$scratch/original"
source=$scratch/'source ü ;$(not-a-command).png'
cp -- "$scratch/original" "$source"
chmod 400 -- "$source"
expect_success bash "$worker" check "$source"

mkdir -- "$scratch/fresh"
destination=$scratch/'fresh/saved ü ;$(not-a-command).png'
expect_success bash "$worker" copy "$source" "$destination"
cmp -- "$source" "$destination" || fail 'Saved copy differs from the source bytes.'
[[ ! $source -ef $destination ]] || fail 'Saved copy is a hard link to the original.'
[[ $(stat -c '%a' -- "$destination") == 600 ]] || fail 'Saved copy is not private.'
expect_only_child "$scratch/fresh" "$destination"
expect_original

# Existing names are never replaced or followed, even if they contain identical
# bytes or are dangling symlinks. Each directory must retain only its original name.
printf 'protected destination\n' > "$scratch/protected"
printf 'protected destination\n' > "$scratch/protected-expected"
for kind in regular symlink dangling directory hardlink; do
  directory=$scratch/existing-$kind
  mkdir -- "$directory"
  destination=$directory/destination.png
  case $kind in
    regular) cp -- "$scratch/protected" "$destination" ;;
    symlink) ln -s -- "$scratch/protected" "$destination" ;;
    dangling) ln -s -- "$scratch/absent-target" "$destination" ;;
    directory) mkdir -- "$destination"; cp -- "$scratch/protected" "$destination/keep" ;;
    hardlink) ln -- "$source" "$destination" ;;
  esac
  expect_failure 1 bash "$worker" copy "$source" "$destination"
  expect_only_child "$directory" "$destination"
  case $kind in
    regular) cmp -- "$scratch/protected-expected" "$destination" ;;
    symlink) [[ -L $destination && $destination -ef $scratch/protected ]] ;;
    dangling) [[ -L $destination && ! -e $destination ]] ;;
    directory) expect_only_child "$destination" "$destination/keep"; cmp -- "$scratch/protected-expected" "$destination/keep" ;;
    hardlink) [[ $destination -ef $source ]] ;;
  esac || fail "Existing $kind destination was changed."
  expect_original
  cmp -- "$scratch/protected-expected" "$scratch/protected" || fail 'A symlink target was modified.'
done
[[ ! -e $scratch/absent-target ]] || fail 'A dangling symlink target was created.'

# Publication happens inside the copy helper through a held descriptor, so no
# staging pathname or ln invocation exists for the shell to intercept. The atomic
# refusal of a destination created after the preflight, short writes, and a failed
# transfer are covered against the helper itself in tests/clipboard-copy.py.

# A source larger than one transfer chunk must arrive byte-complete.
mkdir -- "$scratch/large"
head -c 3145729 /dev/urandom > "$scratch/large-source.png"
expect_success bash "$worker" copy "$scratch/large-source.png" "$scratch/large/destination.png"
cmp -- "$scratch/large-source.png" "$scratch/large/destination.png" || fail 'A multi-chunk copy did not reproduce the source bytes.'
expect_only_child "$scratch/large" "$scratch/large/destination.png"

# A destination directory that cannot be written must fail visibly, without a
# fallback location, a partial file, or staging leftovers.
mkdir -- "$scratch/unwritable"
chmod 500 -- "$scratch/unwritable"
expect_failure 1 bash "$worker" copy "$source" "$scratch/unwritable/destination.png"
unwritable_children=("$scratch/unwritable"/*)
(( ${#unwritable_children[@]} == 0 )) || fail 'A refused destination directory gained a file.'
chmod 700 -- "$scratch/unwritable"
expect_original

# The worker must find its copy helper next to itself, however it was invoked.
mkdir -- "$scratch/relative"
repository_parent=$(dirname -- "$repository")
repository_name=$(basename -- "$repository")
cd -- "$repository"
expect_success bash ./ClipboardFiles.sh copy "$source" "$scratch/relative/dot-slash.png"
expect_success bash ClipboardFiles.sh copy "$source" "$scratch/relative/bare-name.png"
cd -- "$repository_parent"
expect_success bash "$repository_name/ClipboardFiles.sh" copy "$source" "$scratch/relative/nested.png"
cd -- "$repository"
for invocation in dot-slash bare-name nested; do
  cmp -- "$source" "$scratch/relative/$invocation.png" || fail "A $invocation worker invocation did not save the source bytes."
done
expect_original

# Invalid paths and non-directory parents must fail without allocating output.
expect_failure 1 bash "$worker" copy "$source" "$scratch/missing-parent/copy.png"
[[ ! -e $scratch/missing-parent ]] || fail 'A missing destination parent was created.'
expect_failure 1 bash "$worker" copy "$source" "$source/copy.png"
expect_failure 1 bash "$worker" check "$scratch"
expect_failure 1 bash "$worker" check "$source" extra
expect_failure 1 bash "$worker" copy "$source"
expect_failure 1 bash "$worker" check relative.png
newline_source=$scratch/$'line\nbreak.png'
cp -- "$source" "$newline_source"
expect_failure 1 bash "$worker" check "$newline_source"
expect_failure 1 bash "$worker" copy "$source" "$scratch/"$'line\rbreak.png'
printf -v long_path '/%4096s' ''
expect_failure 1 bash "$worker" check "$long_path"
expect_original

# The fake controls only the editor boundary. All duplication, publication,
# permissions, waiting, signal handling, and cleanup use the real worker/coreutils.
mkdir -- "$scratch/editor-bin"
cat > "$scratch/editor-bin/tensaku" <<'CONTROLLED_EDITOR'
#!/usr/bin/env bash
set -eu
filename= output= app_id=
while (( $# )); do
  case $1 in
    --filename) filename=$2; shift 2 ;;
    --output-filename) output=$2; shift 2 ;;
    --app-id) app_id=$2; shift 2 ;;
    --actions-on-enter|--copy-command) shift 2 ;;
    --save-after-copy) shift ;;
    *) exit 2 ;;
  esac
done
printf '%s\n' "$filename" > "$CLIPBOARD_TEST_CONTROL/image"
printf '%s\n' "$output" > "$CLIPBOARD_TEST_CONTROL/output"
printf '%s\n' "$app_id" > "$CLIPBOARD_TEST_CONTROL/app-id"
printf 'controlled editor diagnostic\n'
if [[ ${CLIPBOARD_TEST_IMMEDIATE:-0} == 1 ]]; then exit 0; fi
exec {commands}<> "$CLIPBOARD_TEST_CONTROL/commands"
exec {events}<> "$CLIPBOARD_TEST_CONTROL/events"
# A real application can delay shutdown. Do not exit until the test releases us.
trap 'printf "signal\n" >&"$events"' HUP INT TERM
printf 'ready\n' >&"$events"
while :; do
  if ! IFS= read -r command <&"$commands"; then continue; fi
  case $command in
    save) printf 'edited duplicate\0\377\n' > "$output"; printf 'saved\n' >&"$events" ;;
    succeed) exit 0 ;;
    fail) exit 37 ;;
    *) exit 2 ;;
  esac
done
CONTROLLED_EDITOR
chmod 700 -- "$scratch/editor-bin/tensaku"

mkdir -- "$scratch/invalid-suffix"
expect_failure 1 env PATH="$scratch/editor-bin:$PATH" CLIPBOARD_TEST_CONTROL="$scratch/invalid-suffix" CLIPBOARD_TEST_IMMEDIATE=1 bash "$worker" edit "$source" 'png/../../outside'
[[ ! -e $scratch/invalid-suffix/image ]] || fail 'An invalid suffix reached the editor.'
mkdir -- "$scratch/no-editor"
expect_failure 127 env PATH="$scratch/no-editor" "$BASH" "$worker" edit "$source" png

# A failed private copy for the editor must never leave an image or its directory.
mkdir -- "$scratch/failed-copy-bin"
cat > "$scratch/failed-copy-bin/cp" <<'FAILED_COPY'
#!/usr/bin/env bash
printf partial > "${@: -1}"
printf '%s\n' "${@: -1}" > "$CLIPBOARD_TEST_COPY_TARGET"
exit 1
FAILED_COPY
chmod 700 -- "$scratch/failed-copy-bin/cp"
expect_failure 1 env PATH="$scratch/failed-copy-bin:$scratch/editor-bin:$PATH" CLIPBOARD_TEST_COPY_TARGET="$scratch/failed-copy-target" CLIPBOARD_TEST_CONTROL="$scratch/invalid-suffix" CLIPBOARD_TEST_IMMEDIATE=1 bash "$worker" edit "$source" png
failed_editor_path=$(< "$scratch/failed-copy-target")
[[ ! -e $failed_editor_path && ! -e ${failed_editor_path%/*} ]] || fail 'A failed private copy leaked its image or directory.'
expect_original

expect_event() {
  local index=$1 expected=$2 event
  IFS= read -r -t 10 event <&"${event_fds[$index]}" || fail "Editor $index did not report $expected."
  [[ $event == "$expected" ]] || fail "Editor $index reported $event instead of $expected."
}

start_editor() {
  local index=$1 commands events image output app_id
  local control=$scratch/editor-$index
  mkdir -- "$control"
  mkfifo -- "$control/commands" "$control/events"
  exec {commands}<> "$control/commands"
  exec {events}<> "$control/events"
  command_fds[$index]=$commands
  event_fds[$index]=$events
  PATH="$scratch/editor-bin:$PATH" CLIPBOARD_TEST_CONTROL="$control" bash "$worker" edit "$source" png > "$control/stdout" 2> "$control/stderr" &
  worker_pids[$index]=$!
  expect_event "$index" ready
  IFS= read -r image < "$control/image"
  IFS= read -r output < "$control/output"
  IFS= read -r app_id < "$control/app-id"
  editor_paths[$index]=$image
  editor_directories[$index]=${image%/*}
  app_ids[$index]=$app_id
  [[ $image == "$output" && $image != "$source" && ! $image -ef $source ]] || fail 'The editor was not isolated from the original.'
  cmp -- "$source" "$image" || fail 'The editor did not receive a complete byte duplicate.'
  [[ $(stat -c '%a' -- "$image") == 600 ]] || fail 'Editor duplicate must be private and writable, even for read-only originals.'
  [[ $(stat -c '%a' -- "${image%/*}") == 700 ]] || fail 'Editor directory is not private.'
  [[ $app_id == dev.tensaku.Tensaku.* && ${#app_id} -le 255 && $app_id =~ ^([A-Za-z_][A-Za-z0-9_-]*[.])+[A-Za-z_][A-Za-z0-9_-]*$ ]] || fail 'Editor identity is not a valid distinct Tensaku application ID.'
  [[ ! -s $control/stdout ]] || fail 'The worker emitted success before the editor exited.'
}

finish_editor() {
  local index=$1 command=$2 expected_status=$3 actual=0
  local control=$scratch/editor-$index
  printf '%s\n' "$command" >&"${command_fds[$index]}"
  wait "${worker_pids[$index]}" || actual=$?
  worker_pids[$index]=
  (( actual == expected_status )) || fail "Editor $index: expected exit $expected_status, got $actual."
  [[ ! -e ${editor_paths[$index]} && ! -e ${editor_directories[$index]} ]] || fail 'Editor files remain after its child exited.'
  if (( expected_status == 0 )); then
    cmp -- "$scratch/ok" "$control/stdout" || fail 'Successful editor session did not emit exactly ok and a newline.'
  else
    [[ ! -s $control/stdout ]] || fail 'Failed editor session emitted success.'
  fi
  [[ $(< "$control/stderr") == *'controlled editor diagnostic'* ]] || fail 'Editor logs did not reach stderr.'
  expect_original
}

start_editor 0
start_editor 1
[[ ${app_ids[0]} != "${app_ids[1]}" && ${editor_paths[0]} != "${editor_paths[1]}" ]] || fail 'Concurrent editor sessions share an identity or file.'
printf 'save\n' >&"${command_fds[0]}"
expect_event 0 saved
printf 'edited duplicate\0\377\n' > "$scratch/edited-expected"
cmp -- "$scratch/edited-expected" "${editor_paths[0]}" || fail 'Saving did not update the private duplicate.'
expect_original

kill -TERM -- "${worker_pids[0]}"
expect_event 0 signal
[[ -f ${editor_paths[0]} ]] || fail 'SIGTERM deleted a live editor image.'
kill -0 -- "${worker_pids[0]}" || fail 'SIGTERM ended the worker before its editor exited.'
kill -HUP -- "${worker_pids[0]}"
expect_event 0 signal
[[ -f ${editor_paths[0]} ]] || fail 'A second signal deleted a live editor image.'
[[ ! -s $scratch/editor-0/stdout ]] || fail 'An interrupted live editor emitted success.'

finish_editor 1 succeed 0
[[ -f ${editor_paths[0]} ]] || fail 'One session cleaned another live editor image.'
finish_editor 0 succeed 143
start_editor 2
finish_editor 2 fail 37

# The worker's own interpreter resolution, so the descriptor-level regressions run
# against exactly the helper a save uses.
interpreter=/usr/bin/python3
[[ -x $interpreter ]] || fail 'The system Python 3 interpreter is unavailable.'
"$interpreter" -I -S -B "$repository/tests/clipboard-copy.py" || fail 'Copy helper regressions failed.'

printf 'Clipboard file safety regressions passed.\n'

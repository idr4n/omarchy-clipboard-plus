#!/usr/bin/env bash

# This worker owns only its private editor duplicate; a saved copy is staged in an
# anonymous inode that needs no cleanup. In particular, an interrupted wait is not
# evidence that Tensaku has stopped using its image.
set -u
umask 077

editor_directory=
editor_file=
editor_pid=
interrupted_status=0
interrupted_signal=
signal_count=0

fail() {
  printf 'Clipboard files: %s\n' "$1" >&2
  exit "${2:-1}"
}

valid_path() {
  [[ $1 == /* && ${#1} -le 4096 && $1 != *$'\r'* && $1 != *$'\n'* ]]
}

on_signal() {
  signal_count=$((signal_count + 1))
  if (( interrupted_status == 0 )); then
    interrupted_signal=$1
    interrupted_status=$2
  fi
  if [[ -n $editor_pid ]]; then
    kill -s "$1" -- "$editor_pid" 2>/dev/null || :
  fi
}

abort_if_interrupted() {
  if (( interrupted_status != 0 )); then
    exit "$interrupted_status"
  fi
}

wait_for_editor() {
  local previous_signal_count status
  while :; do
    previous_signal_count=$signal_count
    wait "$editor_pid"
    status=$?
    # Bash returns early from wait when a trapped signal arrives. Wait again for
    # the same child, including when it delays or ignores the forwarded signal.
    if (( signal_count == previous_signal_count )); then
      editor_pid=
      return "$status"
    fi
  done
}

finish() {
  local status=$?
  local editor_status
  trap - EXIT

  if [[ -n $editor_pid ]]; then
    wait_for_editor
    editor_status=$?
    if (( editor_status != 0 )); then
      printf 'Clipboard files: Tensaku exited with status %s.\n' "$editor_status" >&2
      if (( status == 0 )); then
        status=$editor_status
      fi
    fi
  fi

  # No editor is alive now. Do not let another handled signal interrupt cleanup.
  trap '' HUP INT TERM
  if (( interrupted_status != 0 )); then
    printf 'Clipboard files: Image action interrupted.\n' >&2
    if (( status == 0 )); then
      status=$interrupted_status
    fi
  fi
  if [[ -n $editor_file ]] && ! rm -f -- "$editor_file" 2>/dev/null; then
    printf 'Clipboard files: Unable to remove the private image.\n' >&2
    if (( status == 0 )); then status=1; fi
  fi
  if [[ -n $editor_directory ]] && ! rmdir -- "$editor_directory" 2>/dev/null; then
    printf 'Clipboard files: Unable to remove the private image directory.\n' >&2
    if (( status == 0 )); then status=1; fi
  fi
  if (( status == 0 )); then
    printf 'ok\n'
  fi
  exit "$status"
}

trap 'on_signal HUP 129' HUP
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM
trap finish EXIT

case ${1-} in
  check) (( $# == 2 )) || fail 'Expected check SOURCE.' ;;
  copy) (( $# == 3 )) || fail 'Expected copy SOURCE DESTINATION.' ;;
  edit) (( $# == 3 )) || fail 'Expected edit SOURCE SUFFIX.' ;;
  *) fail 'Unknown file operation.' ;;
esac

source=$2
valid_path "$source" || fail 'Source must be an absolute path of at most 4096 characters without line breaks.'
[[ -f $source && -r $source ]] || fail 'Source is not a readable regular file.'
abort_if_interrupted

case $1 in
  check)
    ;;
  copy)
    destination=$3
    valid_path "$destination" || fail 'Destination must be an absolute path of at most 4096 characters without line breaks.'
    parent=${destination%/*}
    parent=${parent:-/}
    name=${destination##*/}
    [[ -n $name && $name != . && $name != .. ]] || fail 'Destination must name a new file inside a directory.'
    [[ -d $parent ]] || fail 'Destination parent is not an existing directory.'
    # Advisory only: publication refuses every existing name atomically. Reporting a
    # visible conflict here avoids staging a copy that could never be published.
    [[ ! -e $destination && ! -L $destination ]] || fail 'Destination already exists; existing files are never replaced.'
    # The helper is a sibling of this worker, which is invoked by absolute path from
    # the plugin and by either form from the tests; the process cwd is unrelated.
    worker_path=${BASH_SOURCE[0]:-$0}
    copy_helper=${worker_path%/*}
    [[ $copy_helper != "$worker_path" ]] || copy_helper=.
    copy_helper=$copy_helper/ClipboardCopy.py
    [[ -f $copy_helper && -r $copy_helper ]] || fail 'The clipboard copy helper is missing.'
    interpreter=/usr/bin/python3
    [[ -x $interpreter ]] || fail 'The system Python 3 interpreter is unavailable.' 127
    abort_if_interrupted
    # The helper holds the source, the destination directory, and an anonymous
    # O_TMPFILE staging inode open for the whole copy, then publishes the staged
    # inode with one linkat through /proc/self/fd. No staging pathname ever exists,
    # so no other process can substitute the published bytes, an existing
    # destination is never replaced, and a failed copy leaves nothing to remove.
    helper_status=0
    "$interpreter" -I -S -B "$copy_helper" "$source" "$parent" "$name" || helper_status=$?
    if (( helper_status != 0 )); then
      # The helper prints its own diagnostic and exits 1. Any other status means it
      # died before reporting, so this worker still has to explain the failure.
      (( helper_status == 1 )) || fail 'Unable to save the copy safely.' "$helper_status"
      exit 1
    fi
    ;;
  edit)
    case $3 in
      png|jpg|jpeg|webp|gif|bmp|tif|tiff) suffix=$3 ;;
      *) fail 'Unsupported image suffix.' ;;
    esac
    command -v tensaku >/dev/null 2>&1 || fail 'Tensaku is unavailable.' 127
    # A fixed ASCII template avoids Tensaku's output-filename date/tilde expansion
    # interpreting a user-controlled source filename or TMPDIR as a format string.
    editor_directory=$(mktemp --directory -- /tmp/clipboard-plus.XXXXXXXXXX) || fail 'Unable to create a private image directory.'
    editor_file=$editor_directory/image.$suffix
    abort_if_interrupted
    # Precreate with mode 600: even a read-only source must yield a writable copy.
    : > "$editor_file" || fail 'Unable to create a private image.'
    cp --no-target-directory -- "$source" "$editor_file" 2>/dev/null || fail 'Unable to copy the source image.'
    abort_if_interrupted
    tensaku \
      --app-id "dev.tensaku.Tensaku.clipboardplus.p$$.s${editor_directory##*.}" \
      --filename "$editor_file" \
      --output-filename "$editor_file" \
      --actions-on-enter save-to-clipboard \
      --save-after-copy \
      --copy-command wl-copy >&2 &
    editor_pid=$!
    # A signal can arrive between launching the child and recording its PID.
    if (( interrupted_status != 0 )); then
      kill -s "$interrupted_signal" -- "$editor_pid" 2>/dev/null || :
    fi
    ;;
esac

# The exit handler waits for the actual editor, cleans only owned paths, and emits
# the single success line only after both the operation and cleanup have succeeded.
exit 0

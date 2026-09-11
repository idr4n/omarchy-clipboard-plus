#!/usr/bin/env python3

"""Descriptor-level regressions for the copy helper that ClipboardFiles.sh invokes.

These cover the boundaries the shell suite cannot reach now that staging and
publication never touch a pathname: a destination created after the preflight,
short writes, a transfer that fails midway, a filesystem that cannot stage
anonymously, and a source that is not a regular file.
"""

import errno
import importlib.util
import os
import shutil
import signal
import stat
import sys
import tempfile

sys.dont_write_bytecode = True

REPOSITORY = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_specification = importlib.util.spec_from_file_location(
    "clipboard_copy", os.path.join(REPOSITORY, "ClipboardCopy.py"))
helper = importlib.util.module_from_spec(_specification)
_specification.loader.exec_module(helper)

# A payload that is neither empty nor a multiple of the helper's transfer chunk.
PAYLOAD = b"image bytes\0\xff" * 977
COMPETING = b"concurrent destination\n"
SCRATCH = tempfile.mkdtemp(prefix="clipboard-plus-copy-tests.")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def new_source(label):
    path = os.path.join(SCRATCH, "source-%s.png" % label)
    with open(path, "wb") as handle:
        handle.write(PAYLOAD)
    # A read-only original must still produce a private, complete copy.
    os.chmod(path, 0o400)
    return path


def new_directory(label):
    path = os.path.join(SCRATCH, "destination-%s" % label)
    os.mkdir(path)
    return path


def descriptors():
    return set(os.listdir("/proc/self/fd"))


def published_bytes(path):
    with open(path, "rb") as handle:
        return handle.read()


def refuse(source, directory, name):
    """Require a visible refusal rather than a successful publication."""
    try:
        helper.copy_into(source, directory, name)
    except helper.CopyError:
        return
    raise AssertionError("Publication was not refused for %r." % (name,))


def fifo_blocked(number, frame):
    raise AssertionError("A fifo source blocked the copy instead of being rejected.")


try:
    # Baseline: one private file appears, with every byte and no staging name.
    source = new_source("complete")
    directory = new_directory("complete")
    open_descriptors = descriptors()
    helper.copy_into(source, directory, "saved.png")
    require(descriptors() == open_descriptors, "A successful copy leaked a descriptor.")
    require(os.listdir(directory) == ["saved.png"], "A copy left an extra name behind.")
    saved = os.path.join(directory, "saved.png")
    require(published_bytes(saved) == PAYLOAD, "The published copy lost bytes.")
    require(stat.S_IMODE(os.stat(saved).st_mode) == 0o600, "The published copy is not private.")

    # Short writes must be completed instead of silently truncating the image.
    source = new_source("short-writes")
    directory = new_directory("short-writes")
    real_write = os.write
    os.write = lambda fd, data: real_write(fd, data[:7])
    try:
        helper.copy_into(source, directory, "saved.png")
    finally:
        os.write = real_write
    require(published_bytes(os.path.join(directory, "saved.png")) == PAYLOAD,
            "Short writes truncated the published copy.")

    # A destination created after staging keeps its own bytes: publication refuses
    # the name rather than replacing it, which a rename or a preflight-only check
    # would not do.
    source = new_source("race")
    directory = new_directory("race")
    saved = os.path.join(directory, "saved.png")
    real_fsync = os.fsync

    def racing_fsync(fd):
        os.fsync = real_fsync
        require(os.listdir(directory) == [], "An unfinished copy exposed a staging name.")
        with open(saved, "xb") as competitor:
            competitor.write(COMPETING)
        return real_fsync(fd)

    open_descriptors = descriptors()
    os.fsync = racing_fsync
    try:
        refuse(source, directory, "saved.png")
    finally:
        os.fsync = real_fsync
    require(descriptors() == open_descriptors, "A refused publication leaked a descriptor.")
    require(published_bytes(saved) == COMPETING, "Publication replaced a concurrent destination.")
    require(os.listdir(directory) == ["saved.png"], "A refused publication left a staging name.")
    require(published_bytes(source) == PAYLOAD, "A refused publication changed the source.")

    # A directory at the destination name is refused, never published into.
    source = new_source("occupied")
    directory = new_directory("occupied")
    occupied = os.path.join(directory, "saved.png")
    os.mkdir(occupied)
    refuse(source, directory, "saved.png")
    require(os.listdir(occupied) == [], "A copy was published inside a destination directory.")
    require(os.listdir(directory) == ["saved.png"], "A refused copy left a staging name.")

    # A transfer that fails midway publishes nothing and leaves nothing to clean up.
    source = new_source("failed-transfer")
    directory = new_directory("failed-transfer")
    real_write = os.write

    def failing_write(fd, data):
        os.write = real_write
        real_write(fd, data[:64])
        raise OSError(errno.ENOSPC, os.strerror(errno.ENOSPC))

    open_descriptors = descriptors()
    os.write = failing_write
    try:
        refuse(source, directory, "saved.png")
    finally:
        os.write = real_write
    require(descriptors() == open_descriptors, "A failed transfer leaked a descriptor.")
    require(os.listdir(directory) == [], "A failed transfer left a partial or staging file.")

    # A filesystem that cannot stage anonymously fails visibly, with no fallback.
    source = new_source("unsupported")
    directory = new_directory("unsupported")
    real_open = os.open

    def unsupported_open(path, flags, *arguments, **keywords):
        if (flags & os.O_TMPFILE) == os.O_TMPFILE:
            raise OSError(errno.EOPNOTSUPP, os.strerror(errno.EOPNOTSUPP))
        return real_open(path, flags, *arguments, **keywords)

    os.open = unsupported_open
    try:
        refuse(source, directory, "saved.png")
    finally:
        os.open = real_open
    require(os.listdir(directory) == [], "Unsupported staging fell back to a named file.")

    # Publication stays in the selected directory even when its pathname changes.
    source = new_source("directory-moved")
    directory = new_directory("directory-moved")
    moved_directory = directory + "-original"
    replacement = os.path.join(directory, "keep.png")

    def moving_fsync(fd):
        os.fsync = real_fsync
        os.rename(directory, moved_directory)
        os.mkdir(directory)
        with open(replacement, "xb") as handle:
            handle.write(COMPETING)
        return real_fsync(fd)

    os.fsync = moving_fsync
    try:
        helper.copy_into(source, directory, "saved.png")
    finally:
        os.fsync = real_fsync
    require(published_bytes(os.path.join(moved_directory, "saved.png")) == PAYLOAD,
            "Publication did not stay in the originally selected directory.")
    require(os.listdir(directory) == ["keep.png"], "Publication touched the replacement directory.")
    require(published_bytes(replacement) == COMPETING, "Publication modified an unrelated file.")

    # A fifo source is rejected on its descriptor instead of blocking the save.
    directory = new_directory("fifo")
    fifo = os.path.join(SCRATCH, "source-fifo.png")
    os.mkfifo(fifo)
    previous_alarm = signal.signal(signal.SIGALRM, fifo_blocked)
    signal.alarm(5)
    try:
        refuse(fifo, directory, "saved.png")
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous_alarm)
    require(os.listdir(directory) == [], "A rejected source created a destination.")

    # A symlinked source is followed and copied, as symlinked picture trees require.
    source = new_source("symlink")
    alias = os.path.join(SCRATCH, "source-symlink-alias.png")
    os.symlink(source, alias)
    directory = new_directory("symlink")
    helper.copy_into(alias, directory, "saved.png")
    saved = os.path.join(directory, "saved.png")
    require(not os.path.islink(saved), "A symlink was published instead of a copy.")
    require(published_bytes(saved) == PAYLOAD, "A symlinked source was not copied through.")

    # The helper is also a standalone CLI: only a single new component can be linked
    # inside the held directory.
    source = new_source("names")
    directory = new_directory("names")
    for rejected in ("", ".", "..", "nested/saved.png", "saved.png/"):
        refuse(source, directory, rejected)
    require(os.listdir(directory) == [], "A rejected destination name created a file.")
finally:
    shutil.rmtree(SCRATCH, ignore_errors=True)

print("Copy helper descriptor regressions passed.")

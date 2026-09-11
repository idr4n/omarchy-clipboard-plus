#!/usr/bin/env python3

"""Publish a private copy of an image without ever exposing a staging pathname.

`ClipboardFiles.sh copy` invokes this helper. The whole copy is held in
descriptors: the source, the destination directory, and an anonymous O_TMPFILE
staging inode created on the destination's own filesystem. The staged bytes are
published with one linkat through `/proc/self/fd`, so no other process can
substitute the bytes that appear under the destination name, and an existing
destination is never replaced. Linux O_TMPFILE, `/proc`, and filesystem hard-link
support are required; there is deliberately no named-temporary fallback.
"""

import errno
import os
import stat
import sys

# Bound the transfer so an arbitrarily large image is never buffered at once.
CHUNK_SIZE = 1 << 20
PRIVATE_MODE = 0o600
# Filesystems that cannot stage or publish at all, rather than failing transiently.
# Kernels and stacked filesystems reject an unsupported O_TMPFILE with any of these.
STAGING_UNSUPPORTED = frozenset((errno.EOPNOTSUPP, errno.ENOSYS, errno.EISDIR, errno.EPERM))
LINK_UNSUPPORTED = frozenset((errno.EPERM, errno.EOPNOTSUPP, errno.ENOSYS))
# Directory durability is advisory: some filesystems cannot sync a directory.
DIRECTORY_SYNC_UNSUPPORTED = frozenset((errno.EINVAL, errno.EOPNOTSUPP, errno.ENOSYS))


class CopyError(Exception):
    """A failure already described in the worker's own diagnostic wording."""


def _report(message):
    sys.stderr.write("Clipboard files: %s\n" % message)


def _failure(message, error):
    detail = error.strerror or errno.errorcode.get(error.errno, "unknown error")
    return CopyError("%s: %s." % (message, detail))


def _close(fd):
    try:
        os.close(fd)
    except OSError:
        # Published bytes are already synced, so a failing close cannot invalidate
        # the result, and every remaining descriptor must still be released.
        pass


def _open_source(path):
    # O_NONBLOCK and O_NOCTTY keep a fifo or device argument from blocking the save
    # or claiming a controlling terminal. Only regular files are copied, and
    # O_NONBLOCK does not affect regular-file reads. Symlinks are followed, as the
    # worker's own readable-regular-file check already does.
    try:
        return os.open(path, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK | os.O_CLOEXEC)
    except OSError as error:
        raise _failure("Unable to read the source image", error) from None


def _open_directory(path):
    # Holding the directory open pins the one inode that is staged into and
    # published into, whatever happens to its pathname during the copy.
    try:
        return os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    except OSError as error:
        raise _failure("Unable to access the destination directory", error) from None


def _open_staging(directory_fd):
    # An O_TMPFILE inode lives on the destination's filesystem with no pathname to
    # reopen, substitute, or clean up: an interrupted save leaves nothing behind,
    # and only this descriptor can reach the bytes.
    try:
        return os.open(".", os.O_WRONLY | os.O_TMPFILE | os.O_CLOEXEC, PRIVATE_MODE,
                       dir_fd=directory_fd)
    except OSError as error:
        if error.errno in STAGING_UNSUPPORTED:
            raise _failure("Unable to stage the copy privately; this filesystem does not "
                           "support anonymous temporary files", error) from None
        raise _failure("Unable to stage the copy privately", error) from None


def _transfer(source_fd, staging_fd):
    buffer = bytearray(CHUNK_SIZE)
    window = memoryview(buffer)
    while True:
        try:
            filled = os.readv(source_fd, (window,))
        except OSError as error:
            raise _failure("Unable to read the source image", error) from None
        if not filled:
            return
        written = 0
        while written < filled:
            try:
                count = os.write(staging_fd, window[written:filled])
            except OSError as error:
                raise _failure("Unable to copy the source image", error) from None
            if not count:
                raise CopyError("Unable to copy the source image: the filesystem accepted no data.")
            written += count


def _publish(staging_fd, directory_fd, name):
    # linkat(AT_FDCWD, "/proc/self/fd/N", directory_fd, name, AT_SYMLINK_FOLLOW)
    # gives the held inode its first and only name. The kernel refuses an existing
    # name, so a destination created meanwhile keeps its own bytes and no replacing
    # rename is ever attempted. AT_SYMLINK_FOLLOW is required, otherwise the magic
    # /proc symlink itself would be linked.
    try:
        os.link("/proc/self/fd/%d" % staging_fd, name,
                dst_dir_fd=directory_fd, follow_symlinks=True)
    except FileExistsError:
        raise CopyError("Destination already exists; existing files are never replaced.") from None
    except OSError as error:
        if error.errno in LINK_UNSUPPORTED:
            raise _failure("Unable to publish the copy safely; this filesystem does not "
                           "support hard links", error) from None
        raise _failure("Unable to publish the copy safely; check /proc, filesystem hard-link "
                       "support, permissions, and destination conflicts", error) from None


def copy_into(source, directory, name):
    """Copy SOURCE into DIRECTORY as NAME, refusing every name that already exists."""
    if not name or name in (".", "..") or "/" in name:
        raise CopyError("Destination must name a new file inside a directory.")
    descriptors = []
    try:
        source_fd = _open_source(source)
        descriptors.append(source_fd)
        if not stat.S_ISREG(os.fstat(source_fd).st_mode):
            raise CopyError("Source is not a readable regular file.")
        directory_fd = _open_directory(directory)
        descriptors.append(directory_fd)
        staging_fd = _open_staging(directory_fd)
        descriptors.append(staging_fd)
        _transfer(source_fd, staging_fd)
        # Keep the published copy private no matter which umask the worker inherited.
        os.fchmod(staging_fd, PRIVATE_MODE)
        try:
            os.fsync(staging_fd)
        except OSError as error:
            raise _failure("Unable to flush the copy to disk", error) from None
        _publish(staging_fd, directory_fd, name)
        try:
            os.fsync(directory_fd)
        except OSError as error:
            if error.errno not in DIRECTORY_SYNC_UNSUPPORTED:
                raise _failure("Published the copy, but could not flush the destination "
                               "directory", error) from None
    finally:
        for fd in descriptors:
            _close(fd)


def main(arguments):
    if len(arguments) != 3:
        _report("Expected copy SOURCE DIRECTORY NAME.")
        return 1
    try:
        copy_into(arguments[0], arguments[1], arguments[2])
    except CopyError as error:
        _report(str(error))
        return 1
    except OSError as error:
        _report("Unable to save the copy safely: %s." % (error.strerror or error))
        return 1
    except KeyboardInterrupt:
        # The worker reports interruption and owns the resulting exit status.
        return 130
    return 0


if __name__ == "__main__":
    # Status 1 means this helper already wrote its own diagnostic.
    sys.exit(main(sys.argv[1:]))

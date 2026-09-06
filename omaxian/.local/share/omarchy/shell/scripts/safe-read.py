#!/usr/bin/python3 -I
"""Bounded, symlink-safe read of a regular file for Quickshell plugins.

Usage: safe-read.py <max-bytes> <absolute-path>

Opens with O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC, fstats the descriptor
(must be a regular file owned by the caller, nlink==1, size<=max), then reads
at most max+1 bytes and exits 1 on overflow. Prints raw bytes to stdout.
"""
import fcntl
import os
import stat
import sys

def main() -> int:
  if len(sys.argv) != 3:
    print("usage: safe-read.py <max-bytes> <absolute-path>", file=sys.stderr)
    return 2
  try:
    max_bytes = int(sys.argv[1])
  except ValueError:
    return 2
  if max_bytes < 1 or max_bytes > 8 * 1024 * 1024:
    return 2
  path = sys.argv[2]
  if not path.startswith("/") or "\0" in path:
    return 2
  try:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
  except FileNotFoundError:
    return 0
  except OSError:
    return 1
  try:
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode):
      return 1
    if st.st_uid != os.geteuid() or st.st_nlink != 1 or st.st_size > max_bytes:
      return 1
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)
    data = b""
    while len(data) <= max_bytes:
      chunk = os.read(fd, min(65536, max_bytes + 1 - len(data)))
      if not chunk:
        break
      data += chunk
    if len(data) > max_bytes:
      return 1
    sys.stdout.buffer.write(data)
    return 0
  finally:
    os.close(fd)

if __name__ == "__main__":
  sys.exit(main())

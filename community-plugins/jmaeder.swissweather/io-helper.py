#!/usr/bin/python3 -I
"""Bounded state + plugin-asset reads for jmaeder.swissweather."""

import os
import secrets
import sys

MAX_STATE = 64 * 1024
MAX_ASSET = 512 * 1024
STATE_NAME = "state.json"
ASSET_NAMES = frozenset({
    "data/places.csv",
    "data/stations.csv",
    "data/webcams.csv",
    "data/forecast-pages.csv",
})
PLUGIN_ID = "jmaeder.swissweather"


def stat_is_regular(mode):
    return (mode & 0o170000) == 0o100000


def stat_is_directory(mode):
    return (mode & 0o170000) == 0o040000


def _check_directory(fd, label, owner_required=True):
    info = os.fstat(fd)
    if not stat_is_directory(info.st_mode):
        raise OSError("unsafe " + label)
    if owner_required and info.st_uid != os.getuid():
        raise OSError("unsafe " + label)
    if info.st_mode & 0o022:
        raise OSError("unsafe " + label)
    return fd


def _open_directory(parent_fd, name, create, private=False, owner_required=True):
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        fd = os.open(name, flags, dir_fd=parent_fd)
    except FileNotFoundError:
        if not create:
            raise
        try:
            os.mkdir(name, 0o700, dir_fd=parent_fd)
        except FileExistsError:
            pass
        fd = os.open(name, flags, dir_fd=parent_fd)
    try:
        _check_directory(fd, "directory", owner_required=owner_required)
        if private:
            os.fchmod(fd, 0o700)
        return fd
    except BaseException:
        os.close(fd)
        raise


def open_home_chain(parts, create_tail=False, private_tail=False):
    home_value = os.environ.get("HOME", "")
    if not home_value or not home_value.startswith("/"):
        raise OSError("HOME is not set")
    root_fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    current_fd = root_fd
    try:
        home_parts = [p for p in home_value.split("/") if p]
        if any(p in (".", "..") for p in home_parts):
            raise OSError("unsafe home")
        for index, part in enumerate(home_parts):
            next_fd = _open_directory(
                current_fd, part, create=False,
                owner_required=index == len(home_parts) - 1,
            )
            os.close(current_fd)
            current_fd = next_fd
        for i, part in enumerate(parts):
            is_tail = i == len(parts) - 1
            next_fd = _open_directory(
                current_fd, part,
                create=create_tail,
                private=private_tail and is_tail,
            )
            os.close(current_fd)
            current_fd = next_fd
        out = current_fd
        current_fd = -1
        return out
    except BaseException:
        if current_fd != -1:
            os.close(current_fd)
        raise


def state_dir_fd():
    return open_home_chain(
        [".local", "state", "omarchy", "plugins", PLUGIN_ID],
        create_tail=True,
        private_tail=True,
    )


def read_state():
    directory_fd = state_dir_fd()
    try:
        try:
            fd = os.open(
                STATE_NAME,
                os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC,
                dir_fd=directory_fd,
            )
        except FileNotFoundError:
            return
        try:
            info = os.fstat(fd)
            if not stat_is_regular(info.st_mode) or info.st_uid != os.getuid():
                raise OSError("unsafe state file")
            if info.st_size > MAX_STATE:
                raise OSError("state too large")
            os.fchmod(fd, 0o600)
            data = os.read(fd, MAX_STATE + 1)
        finally:
            os.close(fd)
    finally:
        os.close(directory_fd)
    if len(data) > MAX_STATE:
        raise OSError("state too large")
    sys.stdout.buffer.write(data)


def write_state(data):
    if len(data) > MAX_STATE:
        raise OSError("state too large")
    directory_fd = state_dir_fd()
    fd = -1
    temporary = None
    try:
        for _ in range(100):
            temporary = "." + STATE_NAME + "." + secrets.token_hex(16)
            try:
                fd = os.open(
                    temporary,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                    0o600,
                    dir_fd=directory_fd,
                )
                break
            except FileExistsError:
                temporary = None
        else:
            raise OSError("temp create failed")
        os.fchmod(fd, 0o600)
        offset = 0
        while offset < len(data):
            offset += os.write(fd, data[offset:])
        os.fsync(fd)
        os.replace(temporary, STATE_NAME, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        temporary = None
        os.close(fd)
        fd = -1
        os.fsync(directory_fd)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        if temporary:
            try:
                os.unlink(temporary, dir_fd=directory_fd)
            except FileNotFoundError:
                pass
        os.close(directory_fd)


def read_asset(plugin_root, relative):
    if relative not in ASSET_NAMES:
        raise ValueError("invalid asset")
    root = os.path.realpath(plugin_root)
    if not root.startswith("/") or ".." in relative.split("/"):
        raise ValueError("unsafe asset path")
    # Open plugin root without following a final symlink replace mid-flight:
    # walk from / using the realpath components (install tree is user-owned).
    parts = [p for p in root.split("/") if p]
    directory_fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    current = directory_fd
    try:
        for index, part in enumerate(parts):
            nxt = _open_directory(
                current, part, create=False,
                owner_required=index == len(parts) - 1,
            )
            os.close(current)
            current = nxt
        # relative may contain one slash (data/foo.csv)
        rel_parts = relative.split("/")
        for part in rel_parts[:-1]:
            nxt = _open_directory(current, part, create=False)
            os.close(current)
            current = nxt
        name = rel_parts[-1]
        fd = os.open(
            name,
            os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC,
            dir_fd=current,
        )
        try:
            info = os.fstat(fd)
            if not stat_is_regular(info.st_mode):
                raise OSError("asset not regular")
            if info.st_size > MAX_ASSET:
                raise OSError("asset too large")
            data = os.read(fd, MAX_ASSET + 1)
        finally:
            os.close(fd)
    finally:
        os.close(current)
    if len(data) > MAX_ASSET:
        raise OSError("asset too large")
    sys.stdout.buffer.write(data)


def main():
    try:
        if len(sys.argv) < 2:
            return 1
        if sys.argv[1] == "read-state" and len(sys.argv) == 2:
            read_state()
            return 0
        if sys.argv[1] == "write-state" and len(sys.argv) == 3:
            write_state(sys.argv[2].encode())
            return 0
        if sys.argv[1] == "read-asset" and len(sys.argv) == 4:
            read_asset(sys.argv[2], sys.argv[3])
            return 0
    except (OSError, ValueError, IndexError):
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

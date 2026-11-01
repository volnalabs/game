"""Downloads the Godot export templates TerraFront needs (Windows x86-64 and Linux x86-64 release)
without fetching the whole 1.3 GB archive: the official .tpz is a zip, so only its directory and the
two members are read with HTTP range requests (curl). Templates are the official Godot binaries (MIT).

Usage: python3 tools/get_templates.py [version]       (default 4.7.2; needs curl)
Writes ~/.local/share/godot/export_templates/<version>.stable/ (Windows: %APPDATA%/Godot/...)."""
import io
import os
import subprocess
import sys
import zipfile

VERSION = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT_VERSION", "4.7.2")
URL = f"https://github.com/godotengine/godot/releases/download/{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"
WANT = ["windows_release_x86_64.exe", "linux_release.x86_64", "version.txt"]


def templates_dir() -> str:
    if os.name == "nt":
        base = os.path.join(os.environ["APPDATA"], "Godot")
    else:
        base = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "godot")
    return os.path.join(base, "export_templates", f"{VERSION}.stable")


def remote_size() -> int:
    head = subprocess.run(["curl", "-sIL", URL], capture_output=True, text=True, check=True).stdout
    lengths = [l for l in head.splitlines() if l.lower().startswith("content-length")]
    return int(lengths[-1].split(":")[1])


class RangeFile(io.RawIOBase):
    """A read-only, seekable view of the remote file; every read is one HTTP range request."""

    def __init__(self, size: int):
        self.size = size
        self.pos = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def readinto(self, b):
        if self.pos >= self.size:
            return 0
        end = min(self.size, self.pos + len(b)) - 1
        data = subprocess.run(["curl", "-sSL", "--retry", "4", "-r", f"{self.pos}-{end}", URL],
                              capture_output=True, check=True).stdout
        b[:len(data)] = data
        self.pos += len(data)
        return len(data)


def main() -> None:
    out = templates_dir()
    os.makedirs(out, exist_ok=True)
    missing = [n for n in WANT if not os.path.exists(os.path.join(out, n))]
    if not missing:
        print(out)
        return
    archive = zipfile.ZipFile(io.BufferedReader(RangeFile(remote_size()), buffer_size=8 * 1024 * 1024))
    for name in missing:
        member = "templates/" + name
        with archive.open(member) as src, open(os.path.join(out, name), "wb") as dst:
            while True:
                chunk = src.read(16 * 1024 * 1024)
                if not chunk:
                    break
                dst.write(chunk)
        if name.endswith(".x86_64"):
            os.chmod(os.path.join(out, name), 0o755)
    print(out)


if __name__ == "__main__":
    main()

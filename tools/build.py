"""Build the device payload from pinned upstream Frida releases."""

import hashlib
import io
import lzma
from pathlib import Path
from urllib.request import urlopen
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
INJECT_URL = (
    "https://github.com/frida/frida/releases/download/17.26.2/"
    "frida-inject-17.26.2-android-arm64.xz"
)
INJECT_SHA256 = "97aac7e5bbf4a90156b9c89bb3bc9cefb7e837676f1047270cce34d9e4c97b0f"
BRIDGE_URL = (
    "https://files.pythonhosted.org/packages/e9/1b/"
    "c6c470aa1b1dbb3b55b184d0025bb7b75e409a2ce6175a8850ba35df1565/"
    "frida_tools-14.13.0-py3-none-any.whl"
)
BRIDGE_SHA256 = "7dbf25e52b5308e0c3e10f922a61207a35a74a92555b84c08e1b537604d0ce77"


def verified_download(url: str, expected_sha256: str) -> bytes:
    with urlopen(url, timeout=90) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != expected_sha256:
        raise ValueError(f"SHA-256 mismatch: {url}")
    return data


def source(name: str) -> bytes:
    return (ROOT / "device" / name).read_bytes().replace(b"\r\n", b"\n")


def main() -> None:
    archive = verified_download(INJECT_URL, INJECT_SHA256)
    wheel = verified_download(BRIDGE_URL, BRIDGE_SHA256)
    with ZipFile(io.BytesIO(wheel)) as package:
        bridge = package.read("frida_tools/bridges/java.js")

    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    (output / "inject").write_bytes(lzma.decompress(archive))
    (output / "rotate.bundle.js").write_bytes(bridge + b"\n" + source("rotate.js"))
    for name in ("start.sh", "ryuo180.rc", "control.sh"):
        (output / name).write_bytes(source(name))
    print(f"Device payload: {output}")


if __name__ == "__main__":
    main()

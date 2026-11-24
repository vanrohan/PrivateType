"""Download the pinned iOS inference libraries. Verify each published checksum."""

import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

root = Path(__file__).resolve().parent.parent
lock = json.loads((root / "scripts/runtime-lock.json").read_text())
output = root / "Vendor/ExecuTorch"
cache = root / "build/runtime-downloads"
output.mkdir(parents=True, exist_ok=True)
cache.mkdir(parents=True, exist_ok=True)
for name, expected in lock["checksums"].items():
    path = cache / (name + ".zip")
    if not path.exists():
        url = f'https://ossci-ios.s3.amazonaws.com/executorch/{name}-{lock["version"]}.zip'
        urllib.request.urlretrieve(url, path)
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise RuntimeError(f"Checksum mismatch: {name}")
    with zipfile.ZipFile(path) as archive:
        archive.extractall(output)
    print(f"Verified {name}")

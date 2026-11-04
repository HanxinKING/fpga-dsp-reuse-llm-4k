"""Read-only verification of the submission material file manifest."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def verify(root):
    root = root.resolve(strict=True)
    manifest_path = root / "files.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    if manifest.get("schema") != "submission-files-v1":
        raise ValueError("Unsupported manifest schema")
    entries = manifest.get("files")
    if not isinstance(entries, list) or not entries:
        raise ValueError("Manifest must contain a nonempty file list")
    seen = set()
    errors = []
    for entry in entries:
        name = entry.get("path", "")
        relative = PurePosixPath(name)
        if (not name or "\\" in name or ":" in name
                or relative.is_absolute() or ".." in relative.parts
                or relative.as_posix() != name or name == "files.json"):
            raise ValueError("Unsafe or invalid manifest path")
        key = name.casefold()
        if key in seen:
            raise ValueError("Duplicate manifest path: " + name)
        seen.add(key)
        path = (root / name).resolve()
        if not path.is_relative_to(root):
            raise ValueError("Path escapes package: " + name)
        if not path.is_file():
            errors.append({"path": name, "reason": "missing"})
            continue
        if path.stat().st_size != entry.get("bytes"):
            errors.append({"path": name, "reason": "size mismatch"})
        if digest(path) != entry.get("sha256"):
            errors.append({"path": name, "reason": "SHA-256 mismatch"})
    actual = {
        path.relative_to(root).as_posix().casefold()
        for path in root.rglob("*") if path.is_file()
        and path != manifest_path and not any(part in {".git", "__pycache__"} for part in path.parts)
    }
    for name in sorted(actual - seen):
        errors.append({"path": name, "reason": "not listed"})
    return {
        "status": "PACKAGE_FILE_HASH_FAIL" if errors else "PACKAGE_FILE_HASH_PASS",
        "checked_files": len(entries),
        "errors": errors,
        "hardware_verified": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path,
                        default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        result = verify(args.root)
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        result = {"status": "PACKAGE_FILE_HASH_FAIL", "error": str(error),
                  "hardware_verified": False}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "PACKAGE_FILE_HASH_PASS" else 1


if __name__ == "__main__":
    sys.exit(main())

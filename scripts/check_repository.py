"""Check tracked text files without third-party dependencies."""

import pathlib
import subprocess
import sys


def main():
    paths = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
    errors = []
    for name in filter(None, paths):
        path = pathlib.Path(name)
        if not path.is_file():
            continue
        data = path.read_bytes()
        if b"\0" in data:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if text and not text.endswith("\n"):
            errors.append(f"{name}: missing final newline")
        for number, line in enumerate(text.splitlines(), 1):
            if line.rstrip() != line:
                errors.append(f"{name}:{number}: trailing whitespace")
            if line.startswith(("<<<<<<< ", "=======", ">>>>>>> ")):
                errors.append(f"{name}:{number}: possible merge conflict marker")
    print("\n".join(errors) if errors else "Repository checks passed.")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())

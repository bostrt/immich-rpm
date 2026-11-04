"""Use Fedora's ExifTool for all instances, including the exported singleton."""
from pathlib import Path

root = Path("server-pruned/node_modules")
matches = list(root.glob(".pnpm/exiftool-vendored@*/node_modules/exiftool-vendored/dist/DefaultExifToolOptions.js"))
if len(matches) != 1:
    raise SystemExit(f"Expected one ExifTool default-options module, got {matches}")
path = matches[0]
text = path.read_text()
import re
text, count = re.subn(r"exiftoolPath: [^\n]+", 'exiftoolPath: "/usr/bin/exiftool",', text)
if count != 1:
    raise SystemExit("ExifTool default-options layout changed")
path.write_text(text)
for vendored in root.glob(".pnpm/exiftool-vendored.pl@*/node_modules/exiftool-vendored.pl"):
    # Leave package metadata for the dependency resolver but remove its Perl copy.
    import shutil
    for item in vendored.iterdir():
        if item.name not in {"package.json", "index.js", "LICENSE", "README.md"}:
            if item.is_dir():
                shutil.rmtree(item)
            else:
                item.unlink()

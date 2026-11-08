"""Ставит ограничение размера для всех 2D-текстур проекта (process/size_limit)."""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
limit = int(sys.argv[2])
changed = 0
for imp in root.rglob("*.import"):
    if ".godot" in imp.parts:
        continue
    text = imp.read_text(encoding="utf-8")
    if 'importer="texture"' not in text:
        continue
    if re.search(r"^process/size_limit=", text, re.M):
        new = re.sub(r"^process/size_limit=\d+", f"process/size_limit={limit}", text, flags=re.M)
    else:
        new = text.replace("[params]\n", f"[params]\n\nprocess/size_limit={limit}\n", 1)
    if new != text:
        imp.write_text(new, encoding="utf-8")
        changed += 1
print(f"size_limit={limit}: изменено {changed} файлов")

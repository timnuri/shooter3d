"""Убирает из уровня тяжёлые данные, которые на телефоне не используются:
VoxelGI (40 МБ) и SDF для столкновения частиц (10 МБ)."""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
tscn = root / "level" / "level.tscn"
s = tscn.read_text(encoding="utf-8")
ids = []
for path in ("res://level/geometry/giprobe_data.res", "res://level/level.GPUParticlesCollisionSDF3D_data.exr"):
    m = re.search(r'^\[ext_resource [^\n]*path="' + re.escape(path) + r'" id="([^"]+)"\]\n', s, re.M)
    if m:
        ids.append(m.group(1))
        s = s.replace(m.group(0), "")
for i in ids:
    s = re.sub(r'^\w+ = ExtResource\("' + re.escape(i) + r'"\)\n', "", s, flags=re.M)
tscn.write_text(s, encoding="utf-8")
for f in ("level/geometry/giprobe_data.res", "level/level.GPUParticlesCollisionSDF3D_data.exr",
          "level/level.GPUParticlesCollisionSDF3D_data.exr.import"):
    p = root / f
    if p.exists():
        p.unlink()
print("Уровень облегчён, убрано ссылок:", len(ids))

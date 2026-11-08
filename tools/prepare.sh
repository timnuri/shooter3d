#!/usr/bin/env bash
# Собирает проект игры: берёт Godot TPS Demo (уровень, модели, звуки)
# и накладывает поверх файлы из папки game/.
# Использование: tools/prepare.sh [папка_проекта]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/project}"
TPS_REPO="${TPS_REPO:-https://github.com/godotengine/tps-demo}"
TPS_SHA="a82f15448e9b015440d3bbdf5e10801b260c4e9f"

if [ ! -d "$OUT/.git" ]; then
  rm -rf "$OUT"
  git init -q "$OUT"
  git -C "$OUT" remote add origin "$TPS_REPO"
fi
if ! git -C "$OUT" cat-file -e "$TPS_SHA^{commit}" 2>/dev/null; then
  git -C "$OUT" fetch -q --depth 1 origin "$TPS_SHA"
fi
# Возвращаем исходное состояние демо (папку .godot с кэшем импорта не трогаем).
git -C "$OUT" checkout -q -f "$TPS_SHA"
git -C "$OUT" clean -q -fd -e .godot

# Убираем то, что не нужно в игре.
rm -rf "$OUT/screenshots" "$OUT/.github" "$OUT/menu/menu.tscn" "$OUT/menu/menu.gd" "$OUT/menu/menu.gd.uid"
find "$OUT" -name "*.blend" -delete
find "$OUT" -name "*.blend1" -delete

# Наши файлы поверх.
cp -r "$ROOT/game/." "$OUT/"

# Для телефона (APK и браузер на телефоне) нужны только мобильные форматы текстур ETC2/ASTC.
if [ "${MOBILE_ONLY_TEXTURES:-1}" = "1" ]; then
  sed -i 's|^textures/vram_compression/import_etc2_astc=true|textures/vram_compression/import_etc2_astc=true\ntextures/vram_compression/import_s3tc_bptc=false|' "$OUT/project.godot"
fi

# Уменьшаем огромные текстуры (до 4K) — для телефона хватает 1024.
python3 "$ROOT/tools/slim_level.py" "$OUT"
python3 "$ROOT/tools/limit_textures.py" "$OUT" "${TEXTURE_LIMIT:-1024}"
echo "Проект готов: $OUT"

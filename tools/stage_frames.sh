#!/bin/bash
# 把 Resources/<role>/ 里的原始白底图按 <role>_<动作>_<序号>.png 规范复制到 Resources/frames/
# AI 出图时的文件名比较随意(idel2 / 缺 idle1),这里统一收口,避免手工改名出错。
set -e
cd "$(dirname "$0")/.."
DST=Resources/frames
mkdir -p "$DST"

copy() {  # copy <源文件> <目标文件名>
  if [ -f "$1" ]; then
    cp "$1" "$DST/$2"
    echo "  → $2"
  else
    echo "  ⚠️  缺 $1"
  fi
}

echo "== boy (立绘顶替 idle_1,原图缺一张静止帧)"
copy Resources/boy/body.png   boy_idle_1.png
copy Resources/boy/idle2.png  boy_idle_2.png
for i in 1 2 3 4; do copy "Resources/boy/walk$i.png" "boy_walk_$i.png"; done
for i in 1 2 3;   do copy "Resources/boy/happy$i.png" "boy_happy_$i.png"; done
for i in 1 2;     do copy "Resources/boy/sleep$i.png" "boy_sleep_$i.png"; done
copy Resources/boy/poke1.png  boy_poke_1.png
copy Resources/boy/cake1.png  boy_cake_1.png

echo "== cat"
for i in 1 2;     do copy "Resources/cat/idle$i.png"  "cat_idle_$i.png"; done
for i in 1 2 3 4; do copy "Resources/cat/walk$i.png"  "cat_walk_$i.png"; done
for i in 1 2;     do copy "Resources/cat/happy$i.png" "cat_happy_$i.png"; done
for i in 1 2;     do copy "Resources/cat/sleep$i.png" "cat_sleep_$i.png"; done
copy Resources/cat/poke1.png  cat_poke_1.png

echo "== dog (原图 idel2 拼写笔误,按 idle_2 收口)"
copy Resources/dog/idle1.png  dog_idle_1.png
copy Resources/dog/idel2.png  dog_idle_2.png
for i in 1 2 3 4; do copy "Resources/dog/walk$i.png"  "dog_walk_$i.png"; done
for i in 1 2;     do copy "Resources/dog/happy$i.png" "dog_happy_$i.png"; done
for i in 1 2;     do copy "Resources/dog/sleep$i.png" "dog_sleep_$i.png"; done
copy Resources/dog/poke1.png  dog_poke_1.png
copy Resources/dog/drag1.png  dog_drag_1.png

echo "✅ 已归入 $DST"
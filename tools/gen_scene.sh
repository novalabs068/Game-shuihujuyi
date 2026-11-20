#!/usr/bin/env bash
# 用 Cursor 的出图工具生成一张图：提示词全部写在 art/prompts/<名字>.txt 里（内容和画风都写在里面）。
#   tools/gen_scene.sh <名字> <画面比例，如 16:9>
# 原图存到 art/inbox/<名字>.png（这个文件夹不进 git）。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
name="$1"
aspect="$2"
inbox="$root/art/inbox"
content="$(cat "$root/art/prompts/$name.txt")"

cd "$inbox"
cursor-agent -p --trust --sandbox enabled --output-format text "请使用你的图像生成工具（GenerateImage）生成一张图片，并保存为这个绝对路径：${inbox}/${name}.png
不要修改或创建任何其他文件，不要运行其他命令。完成后只回复保存的文件路径和图片尺寸。

图片要求（画面比例 ${aspect}）：
${content}"

# Cursor 有时把图存进它自己的素材目录，找回来
if ! ls "$inbox/$name".* >/dev/null 2>&1; then
	found="$(ls -t "$HOME"/.cursor/projects/*/assets/"$name".* 2>/dev/null | head -1 || true)"
	if [[ -n "$found" ]]; then
		cp "$found" "$inbox/$name.${found##*.}"
	fi
fi
ls "$inbox/$name".* >/dev/null 2>&1 || { echo "没有拿到 ${name} 的图" >&2; exit 1; }

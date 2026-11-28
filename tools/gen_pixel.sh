#!/usr/bin/env bash
# 用 Cursor 的出图工具，按像素场景风格生成一张素材图。
#   tools/gen_pixel.sh <名字> <画面比例，如 16:9>
# 内容描述在 art/prompts/<名字>.txt，风格固定段在 art/STYLE.md（pixel:begin/end），原图存到 art/inbox/<名字>.png。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
name="$1"
aspect="$2"
inbox="$root/art/inbox"
content="$(cat "$root/art/prompts/$name.txt")"
style="$(sed -n '/<!-- pixel:begin -->/,/<!-- pixel:end -->/p' "$root/art/STYLE.md" | sed '1d;$d')"

cd "$inbox"
cursor-agent -p --trust --sandbox enabled --output-format text "请使用你的图像生成工具（GenerateImage）生成一张图片，并保存为这个绝对路径：${inbox}/${name}.png
不要修改或创建任何其他文件，不要运行其他命令。完成后只回复保存的文件路径和图片尺寸。

图片要求（画面比例 ${aspect}）：
${content}
${style}"

# Cursor 有时把图存进它自己的素材目录，找回来（同名的会存成 <名字>-2、<名字>-3……，取最新的那张）
if ! ls "$inbox/$name".* >/dev/null 2>&1; then
	found="$(ls -t "$HOME"/.cursor/projects/*/assets/"$name".* "$HOME"/.cursor/projects/*/assets/"$name"-*.* 2>/dev/null | head -1 || true)"
	if [[ -n "$found" ]]; then
		cp "$found" "$inbox/$name.${found##*.}"
	fi
fi
ls "$inbox/$name".* >/dev/null 2>&1 || { echo "没有拿到 ${name} 的图" >&2; exit 1; }

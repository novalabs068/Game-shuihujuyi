#!/usr/bin/env bash
# 用 Cursor 的出图工具，按版画风格样板生成一张人物立绘。
#   tools/gen_portrait.sh <id>
# 人物描述在 art/prompts/<id>.txt，风格固定段在 art/STYLE.md，原图存到 art/inbox/<id>.png 或 .jpg。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
id="$1"
inbox="$root/art/inbox"
seed="$inbox/lin_chong.jpg"
character="$(cat "$root/art/prompts/$id.txt")"
style="$(sed -n '/<!-- prompt:begin -->/,/<!-- prompt:end -->/p' "$root/art/STYLE.md" | sed '1d;$d')"

cd "$inbox"
cursor-agent -p --trust --sandbox enabled --output-format text "请使用你的图像生成工具（GenerateImage）生成一张图片，并保存为这个绝对路径：${inbox}/${id}.png
参考图：${seed}（如果图像工具支持传入参考图就传入它；只参考画风，不要参考人物长相）。
不要修改或创建任何其他文件，不要运行其他命令。完成后只回复保存的文件路径。

图片要求：
${character}
${style}"

# Cursor 有时把图存进它自己的素材目录，找回来（同名的会存成 <名字>-2、<名字>-3……，取最新的那张）
if ! ls "$inbox/$id".* >/dev/null 2>&1; then
	found="$(ls -t "$HOME"/.cursor/projects/*/assets/"$id".* "$HOME"/.cursor/projects/*/assets/"$id"-*.* 2>/dev/null | head -1 || true)"
	if [[ -n "$found" ]]; then
		cp "$found" "$inbox/$id.${found##*.}"
	fi
fi
ls "$inbox/$id".* >/dev/null 2>&1 || { echo "没有拿到 ${id} 的图" >&2; exit 1; }

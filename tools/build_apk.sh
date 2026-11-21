#!/usr/bin/env bash
# 打一个新的调试版 APK，版本号自动加一。
#   tools/build_apk.sh
# 版本号是「大.小.编号」：编号（安卓的 version/code）每打一次加一，大、小两段手动改
# export_presets.cfg 里的 version/name 前两段。新版本号同时写进 project.godot（游戏里显示）。
# 需要 JDK 17 和 Android SDK（路径见下面两个环境变量，可在外面覆盖）。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export JAVA_HOME="${JAVA_HOME:-$HOME/Library/Java/jdk-17.0.21.1+2/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

version="$(python3 - "$root" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
presets = root / "export_presets.cfg"
text = presets.read_text()
code = int(re.search(r"^version/code=(\d+)", text, re.M).group(1)) + 1
name = re.search(r'^version/name="([^"]*)"', text, re.M).group(1)
major_minor = ".".join((name.split(".") + ["0"])[:2])
name = f"{major_minor}.{code}"
text = re.sub(r"^version/code=\d+", f"version/code={code}", text, flags=re.M)
text = re.sub(r'^version/name="[^"]*"', f'version/name="{name}"', text, flags=re.M)
presets.write_text(text)
project = root / "project.godot"
p = project.read_text()
if re.search(r'^config/version=', p, re.M):
    p = re.sub(r'^config/version="[^"]*"', f'config/version="{name}"', p, flags=re.M)
else:
    p = p.replace('config/name="水浒聚义"\n', f'config/name="水浒聚义"\nconfig/version="{name}"\n', 1)
project.write_text(p)
print(name)
PY
)"
echo "版本 $version"
cd "$root"
godot --headless --path . --export-debug "Android" build/shuihu.apk > build/export.log 2>&1 || { tail -20 build/export.log; exit 1; }
ls -lh build/shuihu.apk | awk -v v="$version" '{print "build/shuihu.apk  " $5 "  版本 " v}'

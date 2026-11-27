# 水浒聚义

离线单机手游（先安卓，后 iOS），Godot 4.7.2 + GDScript，2D，**横屏 1280×720**（stretch canvas_items / expand）。
玩法：江湖沙盒（没有主线），原创侠客当统领，在俯视像素场景里走动；聚义令招募水浒好汉（抽卡，**没有任何付费、广告、每日签到**）；
回合制战斗，主角 + 最多 3 位好汉；好汉列传是视觉小说式的剧情。设计文档：https://claude.ai/artifact/P6c5QdXoUPhMfi3hzhwkxa

## 和用户合作

- 用户是游戏开发新手，用中文沟通。界面文字、代码注释、提交说明都写中文。
- 涉及画面、手感的选择，先给图（截图、参考图、示意）再动手，别只写术语。
- 好汉名单、品级、兵器、绝招、名器这类内容要用户确认后才算定稿，先当草稿给他看。
- 兵器和绝招名不能照搬别家产品（如小浣熊水浒卡，docs/reference 里的只作结构参考）；不用「佩剑」「朴刀」这类泛称。

## 常用命令

```bash
godot --path .                    # 直接玩（开始界面）
godot -e --path .                 # 打开编辑器，F5 运行
godot --headless --path . --script res://tests/test_runner.gd   # 全部测试 + 数值模拟，结尾打印 Results: N passed, M failed
godot --headless --path . --import  # 新增 class_name 后刷新全局类缓存（否则别的脚本报 "not declared"）
tools/build_apk.sh                # 打调试 APK 到 build/，版本号自动加一（写进 export_presets.cfg 和 project.godot）
```

改完代码一定跑测试。测试在 `tests/test_runner.gd`，新测试函数要加进 `_initialize()` 里的列表。

## 目录

- `scripts/autoload/`：GameDB（读 data/ 下所有 .tres）、GameState（存档、队伍、聚义令、招募等全部玩家状态）、Music、Sfx
- `scripts/battle/`：纯规则（战斗模型、抽卡 Gacha、升星 Stars、装备、武学、羁绊、阵法……），不依赖界面，方便测试
- `scripts/data/`：Resource 类（UnitData、SkillData、StageData……），数据本身在 `data/<种类>/*.tres`
- `scripts/ui/`：每个画面一个脚本，全部用代码搭 UI（基本不用 .tscn）。`main.gd` 负责切换画面；`ui_kit.gd` 放颜色、字体、按钮、面板等公共样式；`hero_card.gd` 是竖长好汉卡
- `scripts/story/` + `data/stories/<好汉>/*.txt`：列传剧本（@bg/@show/@battle/?选项/*标签/@goto）
- `art/`：立绘是木刻版画风（规则见 `art/STYLE.md`），场景是像素风；`tools/` 里是出图和处理脚本、世界生成器 `world_gen.gd`

## 写代码的约定

- GDScript 2.0，静态类型（`var x := ...`、`-> void`）；类和函数上面用 `##` 中文注释说明「做什么、为什么」。
- 数值和规则放常量，写在用到的类最上面，注释说明含义。
- 存档：`user://save.json`（macOS 在 `~/Library/Application Support/Godot/app_userdata/水浒聚义/`）。加新字段要兼容旧存档（读档时给默认值、做换算）；存档里的旗子名不要改（例：`first_ten_pull` 现在指第一次五连）。
- 提交说明：一段中文，写清改了什么、数值怎么变；打包后另有「版本 x.y.z」提交。只在用户要求时提交、推送。

## 坑

- **用户在两次对话之间会玩游戏，临时脚本和用户共用真存档**：跑任何会存档的脚本前先备份 save.json，跑完恢复；不要删除存档。游戏开着时改存档会被游戏覆盖，要先关游戏。
- `--script` 跑的 SceneTree 脚本在编译时拿不到 autoload（GameDB、GameState），引用了它们的项目类也会编译失败，而且失败后会卡住不退出。临时脚本里用 `load("res://...").new()` 和 `root.get_node("GameDB")`，并加超时退出。
- 用 `--script` 截图时画面没有套 `UiKit.make_theme()`，缺字是截图问题，不是游戏问题（游戏用 Hiragino Sans GB，测试 `test_font_covers_text` 会查缺字）。
- macOS 没有 `timeout` 命令；zsh 不会把 `$var` 按空格拆开，要用 `${=var}`；bash 里 `$var` 紧跟中文要写成 `${var}`。
- 推送到 GitHub（origin = novalabs068/Game-shuihujuyi）大文件容易断，失败就重试。

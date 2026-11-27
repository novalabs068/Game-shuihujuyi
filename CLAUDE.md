# 水浒聚义

离线单机手游（先安卓，后 iOS），Godot 4.7.2 + GDScript，2D，**横屏 1280×720**（stretch canvas_items / expand）。
玩法：江湖沙盒（没有主线），原创侠客当统领，在俯视像素场景里走动；聚义令招募水浒好汉（抽卡，**没有任何付费、广告、每日签到**）；
回合制战斗，统领 + 最多 3 位好汉；好汉列传是视觉小说式的剧情。设计文档：https://claude.ai/artifact/P6c5QdXoUPhMfi3hzhwkxa

## 和用户合作

- 用户是游戏开发新手，用中文沟通。界面文字、代码注释、提交说明都写中文。
- 涉及画面、手感的选择，先给图（截图、参考图、示意）再动手，别只写术语。
- 好汉名单、品级、兵器、绝招、名器这类内容要用户确认后才算定稿，先当草稿给用户看。
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
- 改完代码先跑测试，全部通过再提交；不要提交 `.godot/`、`build/`、APK、`art/inbox/`（已在 .gitignore）。

## 分支规范

- **默认分支是 `master`**（远端 origin/master），它始终要能直接运行、测试全过；不要直接在 master 上改代码或提交。
- 每件事开一个分支，一个分支只做一件事。按类型用下面的前缀，后面跟几个字的中文简述：

  | 前缀 | 用途 | 从哪拉出 | 合回 | 例子 |
  |---|---|---|---|---|
  | `feat/` | 新功能、新内容、玩法或数值调整、界面优化 | `origin/master` | `master` | `feat/公孙胜列传`、`feat/优化战斗界面` |
  | `bugfix/` | 修开发中发现的、还没打包发出去的问题 | `origin/master` | `master` | `bugfix/布阵板点不动` |
  | `hotfix/` | 已经打包给人玩的版本出了要紧的问题，马上修 | 出问题的那个版本提交（通常是 `origin/master`） | `master`，修完立刻打补丁版本 | `hotfix/0.3.19读档闪退` |
  | `prerelease/` | 准备打包：只改版本号、发版前的小修，不加新功能 | `origin/master` | `master` | `prerelease/0.3.20` |

  - 开分支：`git fetch origin && git switch -c feat/<简述> origin/master`。
  - 只做研究、试验不打算合并的，也用 `feat/`，用完告诉用户可以删。
  - 拿不准算哪类时，按「有没有发出去」分：没发出去的问题用 `bugfix/`，已发出去的用 `hotfix/`；其余都是 `feat/`。
- 版本号：`tools/build_apk.sh` 会改 `project.godot` 和 `export_presets.cfg` 里的版本号，只在 `prerelease/` 或 `hotfix/` 分支上打包，`feat/`、`bugfix/` 分支不要打包，免得几个分支同时改版本号冲突。补丁版本（hotfix）加末位，例 0.3.19 → 0.3.20。
- 合并：推送分支 → 在 GitHub 开 PR 到 `master` → 用户确认后合并（不要自己合并 PR，也不要 force push master）。分支落后 master 时用 `git merge origin/master` 跟上，有冲突先告诉用户。合并后的分支可以删掉（本地和远端），删之前确认已经进了 master。
- 用户常用 worktree 同时开好几个分支（`~/orca/workspaces/shuihu/<名字>/`，主仓库在 `~/Projects/shuihu`）。只在当前 worktree 里干活，不要 `cd` 到别的 worktree 或主仓库改东西；共享的 stash 不要用裸 `git stash`。
- 新 worktree 没有 `.godot/` 缓存，第一次先跑 `godot --headless --path . --import` 再跑测试。

## 坑

- **用户在两次对话之间会玩游戏，临时脚本和用户共用真存档**（所有 worktree 也共用同一份存档）：跑任何会存档的脚本前先备份 save.json，跑完恢复；不要删除存档。游戏开着时改存档会被游戏覆盖，要先关游戏。
- `--script` 跑的 SceneTree 脚本在编译时拿不到 autoload（GameDB、GameState），引用了它们的项目类也会编译失败，而且失败后会卡住不退出。临时脚本里用 `load("res://...").new()` 和 `root.get_node("GameDB")`，并加超时退出。
- 用 `--script` 截图时画面没有套 `UiKit.make_theme()`，缺字是截图问题，不是游戏问题（游戏用 Hiragino Sans GB，测试 `test_font_covers_text` 会查缺字）。
- macOS 没有 `timeout` 命令；zsh 不会把 `$var` 按空格拆开，要用 `${=var}`；bash 里 `$var` 紧跟中文要写成 `${var}`。
- 推送到 GitHub（origin = novalabs068/Game-shuihujuyi）大文件容易断，失败就重试。

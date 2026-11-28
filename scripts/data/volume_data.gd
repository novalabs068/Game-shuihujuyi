class_name VolumeData
extends Resource
## 江湖大事的一卷（见方案页「江湖年表」）：没有主线，但江湖上的大事按原著年代一卷一卷发生。
## 境界够了这一卷才「开启」；还没开发的卷也先放进来，年表上露个传闻，让玩家知道后面还有事。
## 加一卷只要在 data/volumes/ 加一个 .tres，不用改代码。

## 开发进度：已经能玩 / 已经规划（原著里的大事） / 远期（虚构的外传）
enum Status { OPEN, PLANNED, FAR }

## 唯一编号，存档旗子会用到（以后的 volume_<id>_done），定了就别改
@export var id: StringName
## 年表里的先后
@export var order: int
## 卷名，如「卷一　落草」
@export var title: String
## 一句话说这一卷是什么年代
@export var era: String
## 这一卷讲什么（开启后显示）
@export_multiline var summary: String
## 还没开启时显示的江湖传闻
@export_multiline var rumor: String
## 外传（虚构的故事，不在原著里）
@export var side_story: bool = false
@export var status: Status = Status.PLANNED
## 统领境界到第几阶才开启（见 Renown.NAMES）
@export var realm_gate: int = 0
## 这一卷敌人大约的等级
@export var level_min: int = 1
@export var level_max: int = 99
## 原著里的经典场面（开启前也列出来，当作目录）
@export var affairs: PackedStringArray = []
## 这一卷新开的玩法，一句一条
@export var new_play: PackedStringArray = []

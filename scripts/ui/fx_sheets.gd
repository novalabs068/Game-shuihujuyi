class_name FxSheets
## 由 pixelfx 导出的战斗特效序列帧（art/fx/<名字>.png）的参数。重新导出见 tools/pixelfx/README.md。
## 名字: [每帧宽, 每帧高, 每行几帧, 总帧数, 每秒帧数, 是否循环, 锚点 x, 锚点 y]
const SHEETS := {
	"blessing": [80, 128, 12, 90, 30, true, 40, 108],
	"heal": [80, 104, 9, 58, 30, false, 40, 92],
	"crit_hit": [216, 136, 5, 28, 30, false, 84, 106],
	"hit_spark": [136, 80, 4, 16, 30, false, 44, 64],
	"sword_slash": [136, 104, 5, 24, 30, false, 44, 92],
	"poof": [112, 92, 7, 49, 30, false, 56, 80],
	"cursed": [64, 84, 10, 72, 30, true, 32, 76],
	"stunned": [60, 64, 8, 60, 30, true, 30, 56],
	"explosion": [300, 240, 12, 66, 30, false, 150, 196],
	"ground_slam": [288, 208, 9, 64, 30, false, 144, 164],
	"heavy_cleave": [208, 116, 6, 58, 30, false, 68, 96],
	"burning": [80, 124, 12, 90, 30, true, 40, 94],
}

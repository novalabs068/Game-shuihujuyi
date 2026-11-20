class_name Bonds
## 羁绊：主角和每位好汉的交情。带他打赢一场、打完他的一段列传都会涨；
## 每升一级，这位好汉生命、攻击、防御 +3%。到「知己」后可以结义（结义另做）。纯规则，数值是初稿。

const NAMES: Array[String] = ["相识", "相熟", "相知", "知己"]
## 到这一级需要的羁绊点数
const THRESHOLDS: Array[int] = [0, 30, 80, 150]
const STAT_BONUS := 0.03
const BATTLE_POINTS := 2
const STORY_POINTS := 20


static func level(points: int) -> int:
	var lv := 0
	for i in THRESHOLDS.size():
		if points >= THRESHOLDS[i]:
			lv = i
	return lv


static func level_name(points: int) -> String:
	return NAMES[level(points)]


## 「相熟（45 / 80）」；到顶了只写名字。
static func progress_text(points: int) -> String:
	var lv := level(points)
	if lv >= THRESHOLDS.size() - 1:
		return NAMES[lv]
	return "%s（%d / %d）" % [NAMES[lv], points, THRESHOLDS[lv + 1]]


## 带上羁绊加成的战斗数据：相识时原样返回，否则返回一份复制。
static func apply(hero: UnitData, points: int) -> UnitData:
	var lv := level(points)
	if lv == 0:
		return hero
	var out: UnitData = hero.duplicate(true)
	var k := 1.0 + STAT_BONUS * lv
	out.base_hp = roundi(hero.base_hp * k)
	out.base_atk = roundi(hero.base_atk * k)
	out.base_def = roundi(hero.base_def * k)
	return out

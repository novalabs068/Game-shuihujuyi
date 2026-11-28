class_name Bonds
## 羁绊：主角和每位好汉的交情。带他打赢一场、打完他的一段列传都会涨；
## 每升一级，这位好汉生命、攻击、防御、法抗 +3%。到「知己」后可以结义，解锁主角和他的组合技「结义同心」。纯规则，数值是初稿。

const NAMES: Array[String] = ["相识", "相熟", "相知", "知己"]
## 到这一级需要的羁绊点数
const THRESHOLDS: Array[int] = [0, 30, 80, 150]
const STAT_BONUS := 0.03
const BATTLE_POINTS := 2
const STORY_POINTS := 20
## 结义要到的羁绊等级（知己）
const SWEAR_LEVEL := 3
## 结义同心：主角先打单体这么多倍
const SWORN_POWER := 1.5


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
	if hero.base_res >= 0:
		out.base_res = roundi(hero.base_res * k)
	return out


## 主角和这位好汉的组合技「结义同心」：主角先出手，好汉紧接着放一次强化过的绝招。
static func sworn_combo(hero: UnitData, protagonist_id: StringName) -> ComboData:
	var c := ComboData.new()
	c.id = StringName("sworn_" + String(hero.id))
	c.display_name = "结义同心"
	c.hero_a = protagonist_id
	c.hero_b = hero.id
	c.effect = ComboData.Effect.SWORN
	c.power = SWORN_POWER
	var move := hero.skill.display_name if hero.skill != null else "绝招"
	c.description = "统领一声号令，%s先对单体造成 %d%% 伤害，紧接着放出强化过的「%s」（不占冷却）。%s怒气满就能放。" % [hero.display_name, roundi(SWORN_POWER * 100), move, hero.display_name]
	return c

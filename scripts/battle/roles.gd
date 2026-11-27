class_name Roles
## 五个职业的规则：近战还是远程、物理还是法术、暴击、闪避、谁克谁。纯规则，不碰画面。
##
## 相克不再是一圈，而是「打对方弱的那一面」：战士防御高法抗低，道士法抗高防御很低，
## 治疗两样都低；再加上近身时战士压制所有职业。见设计方案「相克」一节。

## 近战职业：只能打到每一路最前面的人（刺客例外，能越过前排）
const MELEE: Array[UnitData.Role] = [UnitData.Role.WARRIOR, UnitData.Role.ASSASSIN]
## 打法术伤害的职业：看对方法抗，不能被闪避
const MAGIC: Array[UnitData.Role] = [UnitData.Role.TAOIST]

## 法抗没填时按防御折算的比例（战士防御高法抗低，道士反过来）
const RES_RATIO: Array[float] = [0.35, 1.2, 1.0, 3.0, 1.0]
## 敏捷没填时的默认值
const DEFAULT_AGI: Array[int] = [22, 125, 50, 38, 38]
## 暴击率、暴击伤害倍数（按职业）
const CRIT_CHANCE: Array[float] = [0.05, 0.25, 0.10, 0.05, 0.05]
const CRIT_MULT: Array[float] = [1.5, 2.2, 1.5, 1.5, 1.5]

## 闪避率 =（敏捷 - DODGE_FLOOR）÷（敏捷 + DODGE_SOFT），最少 0，最多 DODGE_MAX
const DODGE_FLOOR := 30.0
const DODGE_SOFT := 250.0
const DODGE_MAX := 0.4
## 射手「百步穿杨」：对方的闪避对射手只剩这么多
const ARCHER_DODGE_FACTOR := 0.5
## 刺客普攻轻：普攻伤害倍数
const ASSASSIN_BASIC_MULT := 0.75
## 近身战士压制：战士近战打别的职业 +20%；别的职业近身打战士 -15%
const WARRIOR_MELEE_BONUS := 0.2
const VS_WARRIOR_MELEE_PENALTY := 0.15
## 站错排（近战站后排够不着、远程站前排手忙脚乱）：伤害 -20%
const MISPLACED_PENALTY := 0.2


## 各职业丁品 1 级的属性范围：[气血, 攻击, 防御, 法抗, 速度, 敏捷]，每项 [最低, 最高]。
## 品级越高：气血、攻击、防御、法抗 ×TIER_MULT；速度、敏捷 +TIER_ADD。见设计方案「按品级的初始属性」
const BASE_RANGES := [
	[[430, 480], [40, 52], [32, 38], [10, 16], [85, 100], [15, 30]],
	[[300, 350], [52, 60], [16, 22], [20, 26], [115, 130], [110, 140]],
	[[290, 330], [50, 58], [20, 26], [20, 26], [95, 110], [40, 60]],
	[[280, 320], [50, 58], [10, 14], [34, 40], [95, 110], [30, 45]],
	[[320, 360], [36, 44], [16, 22], [16, 22], [95, 115], [30, 45]],
]
const STAT_NAMES: Array[String] = ["气血", "攻击", "防御", "法抗", "速度", "敏捷"]
## 甲乙丙丁（UnitData.Tier 的顺序）
const TIER_MULT: Array[float] = [1.3, 1.2, 1.1, 1.0]
const TIER_ADD: Array[int] = [12, 8, 4, 0]
## 好汉每升一级气血、攻击、防御、法抗乘这么多（按品级）；敌人和统领用 BattleUnit.LEVEL_GROWTH
const TIER_GROWTH: Array[float] = [1.031, 1.030, 1.029, 1.028]


## 某职业某品级某项属性的范围 [最低, 最高]。
static func stat_range(role: UnitData.Role, tier: UnitData.Tier, stat: int) -> Vector2i:
	var r: Array = BASE_RANGES[role][stat]
	if stat >= 4:
		return Vector2i(r[0] + TIER_ADD[tier], r[1] + TIER_ADD[tier])
	return Vector2i(roundi(r[0] * TIER_MULT[tier]), roundi(r[1] * TIER_MULT[tier]))


## 统领的属性：当前职业甲品范围的中间值 [气血, 攻击, 防御, 法抗, 速度, 敏捷]。
static func protagonist_stats(role: UnitData.Role) -> Array[int]:
	var out: Array[int] = []
	for i in STAT_NAMES.size():
		var r := stat_range(role, UnitData.Tier.JIA, i)
		out.append((r.x + r.y) / 2)
	return out


## 这个人每升一级的成长倍数：好汉按品级，其余（敌人、统领）用 BattleUnit.LEVEL_GROWTH。
static func level_growth(u: UnitData) -> float:
	if u.rarity in [UnitData.Rarity.DISHA, UnitData.Rarity.TIANGANG]:
		return TIER_GROWTH[u.tier]
	return BattleUnit.LEVEL_GROWTH


static func is_melee(role: UnitData.Role) -> bool:
	return role in MELEE


static func is_magic(role: UnitData.Role) -> bool:
	return role in MAGIC


## 能不能越过前排打后排（刺客）。
static func ignores_block(role: UnitData.Role) -> bool:
	return role == UnitData.Role.ASSASSIN


## 这个职业宜站哪排：0 前排、1 后排。
static func home_row(role: UnitData.Role) -> int:
	return 0 if is_melee(role) else 1


static func dodge_chance(agi: float) -> float:
	return clampf((agi - DODGE_FLOOR) / (agi + DODGE_SOFT), 0.0, DODGE_MAX)


## 近身压制的伤害倍数：战士近战打别人 ×1.2，别的近战打战士 ×0.85，其余 ×1。
static func melee_multiplier(attacker: UnitData.Role, defender: UnitData.Role) -> float:
	if not is_melee(attacker):
		return 1.0
	if attacker == UnitData.Role.WARRIOR and defender != UnitData.Role.WARRIOR:
		return 1.0 + WARRIOR_MELEE_BONUS
	if attacker != UnitData.Role.WARRIOR and defender == UnitData.Role.WARRIOR:
		return 1.0 - VS_WARRIOR_MELEE_PENALTY
	return 1.0


## 这一下打在对方弱的那一面（头上跳「克」）：战士近身打别的职业；法术打法抗低的（战士、治疗）；
## 物理打防御低的（刺客、道士、治疗）。
static func exploits(attacker: UnitData.Role, defender: UnitData.Role) -> bool:
	if attacker == UnitData.Role.WARRIOR and defender != UnitData.Role.WARRIOR:
		return true
	if is_magic(attacker):
		return defender in [UnitData.Role.WARRIOR, UnitData.Role.HEALER]
	return defender in [UnitData.Role.ASSASSIN, UnitData.Role.TAOIST, UnitData.Role.HEALER]


## 出手前给玩家看的提示：「（克：法术破铁甲）」或空。
static func matchup_text(attacker: UnitData.Role, defender: UnitData.Role) -> String:
	if not exploits(attacker, defender):
		return ""
	if attacker == UnitData.Role.WARRIOR:
		return "（克：近身压制）"
	if is_magic(attacker):
		return "（克：法术打法抗低的）"
	return "（克：物理打防御低的）"


## 「近战 · 物理 · 宜站前排」
static func summary(role: UnitData.Role) -> String:
	return "%s · %s · 宜站%s" % ["近战" if is_melee(role) else "远程", "法术" if is_magic(role) else "物理", "前排" if home_row(role) == 0 else "后排"]


## 一批关卡里敌人最多的几种职业（多的在前，最多 count 种）。
static func common_roles(stages: Array[StageData], count := 2) -> Array[UnitData.Role]:
	var tally := {}
	for st in stages:
		for e in st.enemies:
			tally[e.role] = int(tally.get(e.role, 0)) + 1
	var roles: Array = tally.keys()
	roles.sort_custom(func(a: int, b: int) -> bool: return tally[a] > tally[b] or (tally[a] == tally[b] and a < b))
	var out: Array[UnitData.Role] = []
	for r: UnitData.Role in roles.slice(0, count):
		out.append(r)
	return out


## 对付这种职业带什么：战士带道士，刺客、射手带战士，道士带射手和刺客，治疗谁都行（带刺客切后排）。
const COUNTER_OF: Array[String] = ["道士", "战士", "战士", "射手、刺客", "刺客"]


## 编队页的提示：「这一带的敌人多是战士、射手；带道士、战士对付它们」。
static func region_hint(stages: Array[StageData]) -> String:
	var common := common_roles(stages)
	if common.is_empty():
		return ""
	var foes := PackedStringArray()
	var counters := PackedStringArray()
	for r in common:
		foes.append(UnitData.ROLE_NAMES[r])
		for c in COUNTER_OF[r].split("、"):
			if not c in counters:
				counters.append(c)
	return "敌人多是%s；带%s对付它们" % ["、".join(foes), "、".join(counters)]

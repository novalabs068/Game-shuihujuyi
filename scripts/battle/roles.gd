class_name Roles
## 五种职业的相克：武 → 射 → 谋 → 猛 → 奇 → 武，每种克一种、被一种克。纯规则，不碰画面。

## 克制方打被克方的伤害加成；被克方打克制方的伤害减成
const ADVANTAGE_BONUS := 0.2
const DISADVANTAGE_PENALTY := 0.15
## 克制方的控制（眩晕、缴械、计穷）多持续的回合
const ADVANTAGE_CONTROL_TURNS := 1

## 职业 → 它克的职业
const BEATS := {
	UnitData.Role.WARRIOR: UnitData.Role.ARCHER,
	UnitData.Role.ARCHER: UnitData.Role.STRATEGIST,
	UnitData.Role.STRATEGIST: UnitData.Role.TANK,
	UnitData.Role.TANK: UnitData.Role.MYSTIC,
	UnitData.Role.MYSTIC: UnitData.Role.WARRIOR,
}


static func beats(attacker: UnitData.Role, defender: UnitData.Role) -> bool:
	return BEATS[attacker] == defender


## 这种职业被谁克。
static func beaten_by(role: UnitData.Role) -> UnitData.Role:
	for r: UnitData.Role in BEATS:
		if BEATS[r] == role:
			return r
	return role


## 伤害倍率：克制 1.2、被克 0.85、不相干 1。
static func damage_multiplier(attacker: UnitData.Role, defender: UnitData.Role) -> float:
	if beats(attacker, defender):
		return 1.0 + ADVANTAGE_BONUS
	if beats(defender, attacker):
		return 1.0 - DISADVANTAGE_PENALTY
	return 1.0


## 控制的持续回合：克制方多 1 回合。
static func control_turns(attacker: UnitData.Role, defender: UnitData.Role, turns: int) -> int:
	return turns + (ADVANTAGE_CONTROL_TURNS if beats(attacker, defender) else 0)


## 出手前给玩家看的相克提示：「（克制）」「（被克）」或空。
static func matchup_text(attacker: UnitData.Role, defender: UnitData.Role) -> String:
	if beats(attacker, defender):
		return "（%s克%s，伤害 +%d%%）" % [UnitData.ROLE_TAGS[attacker], UnitData.ROLE_TAGS[defender], roundi(ADVANTAGE_BONUS * 100)]
	if beats(defender, attacker):
		return "（被%s克，伤害 -%d%%）" % [UnitData.ROLE_TAGS[defender], roundi(DISADVANTAGE_PENALTY * 100)]
	return ""


## 「克射，被奇克」
static func summary(role: UnitData.Role) -> String:
	return "克%s，被%s克" % [UnitData.ROLE_TAGS[BEATS[role]], UnitData.ROLE_TAGS[beaten_by(role)]]


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


## 编队页的提示：「这一带的敌人多是猛、射；带谋、武克制它们」。
static func region_hint(stages: Array[StageData]) -> String:
	var common := common_roles(stages)
	if common.is_empty():
		return ""
	var foes := PackedStringArray()
	var counters := PackedStringArray()
	for r in common:
		foes.append(UnitData.ROLE_TAGS[r])
		var c := UnitData.ROLE_TAGS[beaten_by(r)]
		if not c in counters:
			counters.append(c)
	return "敌人多是%s；带%s克制它们" % ["、".join(foes), "、".join(counters)]

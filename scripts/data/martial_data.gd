class_name MartialData
extends Resource
## 统领的一门武学。主修的那门就是统领在战斗里放的绝招；统领的职业由出身定死，
## 主修别的职业的武学也行，但威力打 FOREIGN_POWER 折（不是本门功夫）。
## 从出身、奇遇、列传（好汉传授）、技能书中学到，可以随时换。（「副修加成」那组字段是旧设计，已不再使用）

@export var id: StringName
@export var display_name: String
@export_multiline var flavor: String
## 从哪学来的（显示给玩家看）
@export var source: String
## 主修时的技能
@export var skill: SkillData
## 主修这门武学时主角算哪一种职业（相克按它算）
@export var role: UnitData.Role = UnitData.Role.WARRIOR

@export_group("副修加成")
@export var side_hp_pct := 0.0
@export var side_atk_pct := 0.0
@export var side_def_pct := 0.0
@export var side_spd_pct := 0.0
## 装备特效（EquipData.EFFECTS 的键）
@export var side_effects: Array[StringName] = []


## 修炼：每门武学分十重（见设计方案「统领和技能书」）。
const MAX_LEVEL := 10
## 每重绝招伤害（或治疗量、加成数值）+6%（第 5、10 重另有效果，不加这一条）
const POWER_PER_LEVEL := 0.06
## 第 5 重：伤害招多一个附带效果（打中露出破绽），辅助招持续多 1 回合
const EXTRA_LEVEL := 5
## 第 7 重：冷却少 1 回合
const COOLDOWN_LEVEL := 7
## 第 10 重大成：范围升一级；已经是全范围的伤害再 +15%
const MASTER_LEVEL := 10
const MASTER_ALL_BONUS := 0.15
## 修炼一重要多少银两：从 level 重修到下一重 = LEVEL_COST × level × level
const LEVEL_COST := 150


## 主修别的职业的武学：伤害（或治疗量、加成数值）打七折
const FOREIGN_POWER := 0.7


## 别的职业的武学：返回打过折的复制（description 末尾注明）。
static func foreign(s: SkillData) -> SkillData:
	if s == null:
		return null
	var out: SkillData = s.duplicate()
	out.power *= FOREIGN_POWER
	out.amount *= FOREIGN_POWER
	out.description += "（外门武学，威力七成）"
	return out


## 修到第 level 重时的绝招（复制一份，不改原数据）。
func skill_at(level: int) -> SkillData:
	if skill == null:
		return null
	var s: SkillData = skill.duplicate()
	var boosts := 0
	for l in range(2, level + 1):
		if l != EXTRA_LEVEL and l != MASTER_LEVEL:
			boosts += 1
	var k := 1.0 + POWER_PER_LEVEL * boosts
	s.power *= k
	s.amount *= k
	if level >= EXTRA_LEVEL:
		if s.needs_enemy_target() or s.effect in SkillData.ALL_EFFECTS:
			s.exposes = true
		elif s.turns > 0:
			s.turns += 1
	if level >= COOLDOWN_LEVEL:
		s.cooldown = maxi(s.cooldown - 1, 1)
	if level >= MASTER_LEVEL:
		s.area = upgraded_area(s)
		if s.effect in SkillData.ALL_EFFECTS:
			s.power *= 1.0 + MASTER_ALL_BONUS
	return s


## 大成时范围升一级：单人 → 穿透，穿透 → 多人，多人、连锁 → 全范围。
static func upgraded_area(s: SkillData) -> SkillData.Area:
	match s.area:
		SkillData.Area.SINGLE:
			return SkillData.Area.LANE
		SkillData.Area.LANE:
			return SkillData.Area.ROW
		SkillData.Area.ROW, SkillData.Area.CHAIN:
			return SkillData.Area.ALL
	return s.area


## 第 level 重得到什么（修炼面板上看）。
static func level_text(level: int) -> String:
	match level:
		EXTRA_LEVEL:
			return "绝招多一个附带效果：伤害招打中露出破绽，辅助招多持续 1 回合"
		COOLDOWN_LEVEL:
			return "绝招 +%d%%，冷却少 1 回合" % roundi(POWER_PER_LEVEL * 100)
		MASTER_LEVEL:
			return "大成：绝招范围升一级（单人→穿透→多人→全范围）"
	return "绝招 +%d%%" % roundi(POWER_PER_LEVEL * 100)


static func level_cost(level: int) -> int:
	return LEVEL_COST * level * level


## 副修加成折算成一件「装备」，和身上的装备一起交给 Equipment.apply。
func side_as_gear() -> EquipData:
	var g := EquipData.new()
	g.display_name = display_name
	g.hp_pct = side_hp_pct
	g.atk_pct = side_atk_pct
	g.def_pct = side_def_pct
	g.spd_pct = side_spd_pct
	g.effects = side_effects.duplicate()
	return g


## 「攻击 +8%　会心」这样的副修说明。
func side_summary() -> String:
	return side_as_gear().summary()

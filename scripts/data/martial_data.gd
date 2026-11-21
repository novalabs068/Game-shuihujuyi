class_name MartialData
extends Resource
## 主角的一门武学。主角同时带两门：主修的那门就是他在战斗里放的技能，副修的那门只给被动加成。
## 从出身、奇遇、列传（好汉传授）中学到，可以随时换。

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

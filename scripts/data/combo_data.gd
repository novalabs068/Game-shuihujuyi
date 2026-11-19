class_name ComboData
extends Resource
## 两个好汉的组合技。hero_b 是负责出手打伤害的一方。

enum Effect {
	SHIELD_STRIKE,   ## 全队获得 amount 比例生命的护盾，hero_b 对单体造成 power 倍伤害
	STUN_ALL_COMBO,  ## 全体敌人眩晕 1 回合，hero_b 对单体连击 hits 次，每次 power 倍
	STEAL_ALL_RAGE,  ## 偷取敌方全部增益，全队怒气 +rage_gain
}

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var hero_a: StringName
@export var hero_b: StringName
@export var effect: Effect
@export var power := 1.0
@export var hits := 1
@export var amount := 0.0
@export var rage_gain := 0


## hero_id 在这个组合里时返回搭档的 id，否则返回空。
func partner_of(hero_id: StringName) -> StringName:
	if hero_id == hero_a:
		return hero_b
	if hero_id == hero_b:
		return hero_a
	return &""


func needs_enemy_target() -> bool:
	return effect != Effect.STEAL_ALL_RAGE

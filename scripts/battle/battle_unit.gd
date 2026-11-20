class_name BattleUnit
extends RefCounted
## 战斗中的一个单位：当前属性、怒气和状态。纯数据，不碰画面。
##
## 带「剩余回合」的状态（嘲讽、减伤、增益）为 -1 表示没有；每次轮到自己时减 1，
## 所以持续 N 回合 = 一直生效到自己之后的第 N 次行动结束。

enum Side { PLAYER, ENEMY }

## 每升一级属性乘这个倍数（复利成长：每差 7 级约差 2 倍，前期后期一样明显）
const LEVEL_GROWTH := 1.1
const RAGE_MAX := 100
const BERSERK_THRESHOLD := 0.3
const BERSERK_BONUS := 1.0
## 减益叠得再多，攻击和速度也不低于原来的这么多
const MIN_STAT_RATIO := 0.3


class Buff:
	var name: String
	var atk_bonus: float
	var spd_bonus: float
	var turns_left: int

	func _init(p_name: String, p_atk_bonus: float, p_spd_bonus: float, p_turns: int) -> void:
		name = p_name
		atk_bonus = p_atk_bonus
		spd_bonus = p_spd_bonus
		turns_left = p_turns


var data: UnitData
var side: BattleUnit.Side
var slot: int
var level: int
var max_hp: int
var hp: int
var rage := 0
var skill_cooldown := 0
var shield := 0
var guarding := false
var stun_turns := 0
var taunt_turns := -1
var reduction := 0.0
var reduction_turns := -1
var buffs: Array[Buff] = []
var next_time := 0.0
var enraged := false
## 灼烧：每次轮到自己时掉 burn_damage 血，还剩 burn_turns 次
var burn_damage := 0
var burn_turns := 0
## 敌人预告的下一步：用技能还是普攻、打谁。只有敌人有，见 BattleModel.intent_target_of()
var intent_skill := false
var intent_target: BattleUnit

var _atk: int
var _def: int
var _spd: int


func _init(p_data: UnitData, p_side: BattleUnit.Side, p_slot: int, p_level: int) -> void:
	data = p_data
	side = p_side
	slot = p_slot
	level = p_level
	max_hp = _scaled(data.base_hp)
	hp = max_hp
	_atk = _scaled(data.base_atk)
	_def = _scaled(data.base_def)
	_spd = data.base_spd  # 速度不随等级成长，出手顺序只由好汉本身决定


func _scaled(base: int) -> int:
	return roundi(base * pow(LEVEL_GROWTH, level - 1))


func display_name() -> String:
	return data.display_name


func is_alive() -> bool:
	return hp > 0


func hp_ratio() -> float:
	return float(hp) / max_hp


func atk() -> float:
	var bonus := 0.0
	for b in buffs:
		bonus += b.atk_bonus
	if data.elite_trait == &"berserk" and hp_ratio() < BERSERK_THRESHOLD:
		bonus += BERSERK_BONUS
	return _atk * maxf(1.0 + bonus, MIN_STAT_RATIO)


func def() -> float:
	return float(_def)


func spd() -> float:
	var bonus := 0.0
	for b in buffs:
		bonus += b.spd_bonus
	return _spd * maxf(1.0 + bonus, MIN_STAT_RATIO)


func has_gear(effect: StringName) -> bool:
	return effect in data.gear_effects


func is_taunting() -> bool:
	return taunt_turns >= 0


func has_full_rage() -> bool:
	return rage >= RAGE_MAX


func add_rage(amount: int) -> void:
	rage = clampi(rage + amount, 0, RAGE_MAX)


func skill_ready() -> bool:
	return data.skill != null and skill_cooldown == 0


## 轮到自己时调用：清掉上回合的防御，冷却和各状态减 1。
func tick_turn_start() -> void:
	guarding = false
	skill_cooldown = maxi(skill_cooldown - 1, 0)
	if taunt_turns >= 0:
		taunt_turns -= 1
	if reduction_turns >= 0:
		reduction_turns -= 1
		if reduction_turns < 0:
			reduction = 0.0
	for b in buffs:
		b.turns_left -= 1
	buffs.assign(buffs.filter(func(b: Buff) -> bool: return b.turns_left >= 0))


func status_tags() -> PackedStringArray:
	var tags := PackedStringArray()
	if data.elite_trait == &"iron":
		tags.append("铁甲")
	elif data.elite_trait == &"berserk":
		tags.append("狂暴！" if hp_ratio() < BERSERK_THRESHOLD else "狂暴")
	if is_taunting():
		tags.append("嘲讽")
	if reduction_turns >= 0:
		tags.append("减伤")
	if guarding:
		tags.append("防御")
	if stun_turns > 0:
		tags.append("眩晕")
	if burn_turns > 0:
		tags.append("灼烧")
	if shield > 0:
		tags.append("盾%d" % shield)
	for b in buffs:
		tags.append(b.name)
	return tags

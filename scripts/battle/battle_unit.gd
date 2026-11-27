class_name BattleUnit
extends RefCounted
## 战斗中的一个单位：当前属性、怒气和状态。纯数据，不碰画面。
##
## 带「剩余回合」的状态（嘲讽、减伤、增益）为 -1 表示没有；每次轮到自己时减 1，
## 所以持续 N 回合 = 一直生效到自己之后的第 N 次行动结束。

enum Side { PLAYER, ENEMY }

## 每升一级属性乘这个倍数（复利成长：每差 23 级约差 2 倍；1 级到 99 级一共约 18 倍）
const LEVEL_GROWTH := 1.03
const RAGE_MAX := 100
const BERSERK_THRESHOLD := 0.3
const BERSERK_BONUS := 1.0
## 减益叠得再多，攻击和速度也不低于原来的这么多
const MIN_STAT_RATIO := 0.3
## 持续这么多回合以上的增益算「整场有效」（天赋、越打越快），各算各的，不和同类合并
const PERMANENT_TURNS := 900
## 头目的韧性条：满值；打空就「破绽」跪地一回合
const TOUGHNESS_MAX := 100


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
## 站在哪一格：row 0 前排、1 后排；lane 0 上路、1 中路、2 下路。大体型的头目占这一路的前后两格（row 记 0）
var row := -1
var lane := 0
var level: int
var max_hp: int
var hp: int
var rage := 0
var skill_cooldown := 0
## 这一轮冷却一共几回合（放绝招时记下，界面画冷却弧用）
var skill_cooldown_total := 0
var shield := 0
var guarding := false
var stun_turns := 0
## 缴械：不能普攻；计穷：不能放绝招和组合技；破绽：下一次挨打伤害 +20%。都在自己行动结束时减 1
var disarm_turns := 0
var silence_turns := 0
var expose_turns := 0
## 头目的韧性：控制和打中弱点削得多，打空就破绽（跪地一回合、受到伤害 +30%、蓄的大招作废）
var toughness := TOUGHNESS_MAX
## 破绽还剩几回合（>0 时受到的伤害加成）
var broken_turns := 0
## 头目第几阶段（1～3），血量 60%、30% 时换阶段
var phase := 1
## 头目蓄的大招要砸的格子（Vector2i(row, lane)，对方那一边的格子）；放的时候打这些格子里的人
var charge_cells: Array[Vector2i] = []
## 阵法给的加成（Formations 写入，破阵时清空）：atk、def、spd、taken、heal、control、tail、horn
var formation_mods: Dictionary = {}
## 站在阵眼上：倒下就破阵
var formation_eye := false
## 召唤物：谁召出来的、还剩几回合（0 = 打死为止）。召唤者倒下就一起消散
var summoner: BattleUnit
var summon_turns := 0
## 我方满四人时敌人扩编来的增援（不给经验银两）
var reinforcement := false
## 头目蓄力中：下一次行动放出蓄满的绝招（伤害 ×BattleModel.CHARGE_BONUS）；这期间被控制就打断
var charging := false
## 阵法、山头给的：受到的伤害倍数、额外暴击率
var taken_mult := 1.0
var crit_bonus := 0.0
var taunt_turns := -1
var reduction := 0.0
var reduction_turns := -1
var buffs: Array[Buff] = []
var next_time := 0.0
var enraged := false
## 灼烧：每次轮到自己时掉 burn_damage 血，还剩 burn_turns 次
var burn_damage := 0
var burn_turns := 0
## 是谁放的火：他在 BattleModel.units 里的序号（统计时灼烧伤害记在他头上；不直接存人，免得互相引用）
var burn_source := -1
## 别人的天赋给的特效（比如安道全让全队回春），和 data.gear_effects 一起算
var extra_effects: Array[StringName] = []
## 「首击必暴」天赋：还没出过手
var first_crit_ready := false
## 敌人预告的下一步：用技能还是普攻、打谁。只有敌人有，见 BattleModel.intent_target_of()
var intent_skill := false
var intent_target: BattleUnit

var _atk: int
var _def: int
var _res: int
var _spd: int
var _agi: int


func _init(p_data: UnitData, p_side: BattleUnit.Side, p_slot: int, p_level: int) -> void:
	data = p_data
	side = p_side
	slot = p_slot
	level = p_level
	max_hp = _scaled(data.base_hp)
	hp = max_hp
	_atk = _scaled(data.base_atk)
	_def = _scaled(data.base_def)
	_res = _scaled(data.res())
	_spd = data.base_spd  # 速度不随等级成长，出手顺序只由好汉本身决定
	_agi = data.agi()  # 敏捷也不随等级涨：闪避手感前期后期一样
	first_crit_ready = has_talent(&"first_crit")


## 召唤物的属性：按召唤者折算（开战后召出来，血是满的）。
func set_summon_stats(p_hp: int, p_atk: float) -> void:
	max_hp = maxi(1, p_hp)
	hp = max_hp
	_atk = maxi(1, roundi(p_atk))


## 敌人加强：生命、攻击按 k 放大，防御按 k_def 放大（开战前调用，血是满的）。
func strengthen(k: float, k_def := 1.0) -> void:
	max_hp = roundi(max_hp * k)
	hp = max_hp
	_atk = roundi(_atk * k)
	_def = roundi(_def * k_def)
	_res = roundi(_res * k_def)


## 敌人按我方人数加强：生命、攻击各乘一个数（开战前调用，血是满的）。
func scale_squad(k_hp: float, k_atk: float) -> void:
	max_hp = roundi(max_hp * k_hp)
	hp = max_hp
	_atk = roundi(_atk * k_atk)


## 开战时按倍数加防御、加生命（阵法、山头用）。
func scale_def(k: float) -> void:
	_def = roundi(_def * k)
	_res = roundi(_res * k)


func scale_hp(k: float) -> void:
	max_hp = roundi(max_hp * k)
	hp = max_hp


func _scaled(base: int) -> int:
	return roundi(base * pow(Roles.level_growth(data), level - 1))


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
	if hp_ratio() < 0.5:
		bonus += talent(&"bloodlust")
	bonus += float(formation_mods.get("atk", 0.0))
	return _atk * maxf(1.0 + bonus, MIN_STAT_RATIO)


func def() -> float:
	return _def * (1.0 + float(formation_mods.get("def", 0.0)))


## 法抗：挡法术伤害。
func res() -> float:
	return _res * (1.0 + float(formation_mods.get("def", 0.0)))


func agi() -> float:
	return float(_agi)


func spd() -> float:
	var bonus := 0.0
	for b in buffs:
		bonus += b.spd_bonus
	bonus += float(formation_mods.get("spd", 0.0))
	return _spd * maxf(1.0 + bonus, MIN_STAT_RATIO)


func role() -> UnitData.Role:
	return data.role


func is_melee() -> bool:
	return Roles.is_melee(data.role)


func is_summon() -> bool:
	return summoner != null


## 站的格子（大体型的头目返回它的前排格）。
func cell() -> Vector2i:
	return Vector2i(row, lane)


## 占着的格子：一般一格，大体型占一路前后两格。
func cells() -> Array[Vector2i]:
	if data.big:
		return [Vector2i(0, lane), Vector2i(1, lane)]
	return [Vector2i(row, lane)]


func occupies(c: Vector2i) -> bool:
	return c in cells()


## 站错排（近战在后排、远程在前排）。大体型和召唤物不算。
func misplaced() -> bool:
	return not data.big and not is_summon() and row != Roles.home_row(data.role)


func has_gear(effect: StringName) -> bool:
	return effect in data.gear_effects or effect in extra_effects


## 身上起作用的被动：天赋（按档次）和秘籍（按 1 档），每项是 [TalentData, 档次]。
func passives() -> Array:
	var out := []
	if data.talent != null and data.talent_rank > 0:
		out.append([data.talent, data.talent_rank])
	if data.miji_effect != null:
		out.append([data.miji_effect, 1])
	return out


## 某种被动（天赋或秘籍）里的第一条，没有返回 null。
func passive(kind: StringName) -> TalentData:
	for p in passives():
		if p[0].kind == kind:
			return p[0]
	return null


func has_talent(kind: StringName) -> bool:
	return passive(kind) != null


## 这种被动的当前数值（天赋和秘籍都有就相加）；没有时为 0。
func talent(kind: StringName) -> float:
	var total := 0.0
	for p in passives():
		if p[0].kind == kind:
			total += p[0].value(p[1])
	return total


func is_taunting() -> bool:
	return taunt_turns >= 0


func has_full_rage() -> bool:
	return rage >= RAGE_MAX


func add_rage(amount: int) -> void:
	rage = clampi(rage + amount, 0, RAGE_MAX)


func skill_ready() -> bool:
	return data.skill != null and skill_cooldown == 0 and silence_turns == 0


func can_attack() -> bool:
	return disarm_turns == 0


## 头目不吃控制：控制改成削韧性（见 BattleModel._control）。
func resists(_kind: StringName) -> bool:
	return data.is_boss


## 加一个增益或减益。同一类（加攻、减攻、加速、减速）不叠加：数值取大的，回合取长的。
## 整场有效的（天赋给的）各算各的。
func add_buff(b: Buff) -> void:
	if b.turns_left < PERMANENT_TURNS:
		var key := _buff_kind(b)
		for old in buffs:
			if old.turns_left < PERMANENT_TURNS and _buff_kind(old) == key:
				if absf(b.atk_bonus) + absf(b.spd_bonus) > absf(old.atk_bonus) + absf(old.spd_bonus):
					old.name = b.name
					old.atk_bonus = b.atk_bonus
					old.spd_bonus = b.spd_bonus
				old.turns_left = maxi(old.turns_left, b.turns_left)
				return
	buffs.append(b)


static func _buff_kind(b: Buff) -> String:
	if not is_zero_approx(b.atk_bonus):
		return "atk+" if b.atk_bonus > 0 else "atk-"
	return "spd+" if b.spd_bonus > 0 else "spd-"


## 自己行动结束时：缴械、计穷、破绽各减 1；头目的控制刚结束就起定力。
func tick_turn_end() -> void:
	if disarm_turns > 0:
		disarm_turns -= 1
	if silence_turns > 0:
		silence_turns -= 1
	expose_turns = maxi(expose_turns - 1, 0)


## 眩晕的这一回合被跳过时调用。破绽（跪地）也是这样跳过的，跪完韧性回满。
func consume_stun() -> void:
	stun_turns -= 1
	if broken_turns > 0:
		broken_turns -= 1
		if broken_turns == 0:
			toughness = TOUGHNESS_MAX


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
	if disarm_turns > 0:
		tags.append("缴械")
	if silence_turns > 0:
		tags.append("计穷")
	if expose_turns > 0 and broken_turns == 0:
		tags.append("破绽")
	if formation_eye and not formation_mods.is_empty():
		tags.append("阵眼")
	if is_summon() and summon_turns > 0:
		tags.append("余%d回合" % summon_turns)
	if broken_turns > 0:
		tags.append("破绽")
	if charging:
		tags.append("蓄力")
	if burn_turns > 0:
		tags.append("灼烧")
	if shield > 0:
		tags.append("盾%d" % shield)
	for b in buffs:
		tags.append(b.name)
	return tags

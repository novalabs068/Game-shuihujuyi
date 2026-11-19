class_name BattleModel
extends RefCounted
## 战斗规则（见设计文档「战斗系统」）。不碰任何画面：每一步返回一串事件，由 BattleView 播放，
## 也可以在无界面模式下整场模拟来调数值。
##
## 用法：start_next_turn() 选出下一个行动者 current；current 为 null 说明这回合被跳过（眩晕），
## 否则调用 act()（玩家选择）或 act_ai()（敌人、自动战斗）。直到 result 不再是 ONGOING。
##
## 出手顺序：每个单位的「下次行动时间」= 上次 + 1000 / 速度，时间最小的先动，
## 速度 100 的单位每回合（ROUND_TIME）正好动一次。

enum Action { ATTACK, SKILL, GUARD, COMBO }
enum Result { ONGOING, WIN, LOSE }

const TIME_PER_ACTION := 1000.0
const ROUND_TIME := 10.0
const CRIT_CHANCE := 0.05
const CRIT_MULTIPLIER := 1.5
const RAGE_ON_ATTACK := 20
const RAGE_ON_SKILL := 10
const RAGE_ON_GUARD := 25
const GUARD_REDUCTION := 0.5
const EXECUTE_THRESHOLD := 0.3
const ENRAGE_THRESHOLD := 0.5
const TURN_PREVIEW_COUNT := 6
## 自动战斗时，有队友血量低于这个比例才用治疗技能
const AI_HEAL_THRESHOLD := 0.6

var stage: StageData
var units: Array[BattleUnit] = []
var combos: Array[ComboData] = []
var current: BattleUnit
var result := Result.ONGOING
var time := 0.0
var player_deaths := 0
var rng := RandomNumberGenerator.new()

var _events: Array[Dictionary] = []
var _extra_action := false


func _init(p_stage: StageData, team: Array[UnitData], hero_level: int, p_combos: Array[ComboData], seed_value: int = -1) -> void:
	stage = p_stage
	combos = p_combos
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	for i in team.size():
		units.append(BattleUnit.new(team[i], BattleUnit.Side.PLAYER, i, hero_level))
	for i in stage.enemies.size():
		units.append(BattleUnit.new(stage.enemies[i], BattleUnit.Side.ENEMY, i, stage.enemy_level))
	for u in units:
		u.next_time = TIME_PER_ACTION / u.spd()
	for e in alive(BattleUnit.Side.ENEMY):
		_plan_intent(e)


# --- 查询 ---

func round_number() -> int:
	return maxi(1, ceili(time / ROUND_TIME))


func alive(side: BattleUnit.Side) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	out.assign(units.filter(func(u: BattleUnit) -> bool: return u.side == side and u.is_alive()))
	return out


func allies_of(unit: BattleUnit) -> Array[BattleUnit]:
	return alive(unit.side)


func foes_of(unit: BattleUnit) -> Array[BattleUnit]:
	return alive(BattleUnit.Side.ENEMY if unit.side == BattleUnit.Side.PLAYER else BattleUnit.Side.PLAYER)


## 接下来行动的 TURN_PREVIEW_COUNT 个单位（假设期间速度不变），第一个就是下一个行动者。
func turn_order_preview() -> Array[BattleUnit]:
	var pending: Array[BattleUnit] = []
	pending.assign(units.filter(func(u: BattleUnit) -> bool: return u.is_alive()))
	var order: Array[BattleUnit] = []
	if pending.is_empty():
		return order
	var times: Array[float] = []
	for u in pending:
		times.append(u.next_time)
	for n in TURN_PREVIEW_COUNT:
		var best := 0
		for i in range(1, pending.size()):
			if _acts_before(pending[i], times[i], pending[best], times[best]):
				best = i
		order.append(pending[best])
		times[best] += TIME_PER_ACTION / pending[best].spd()
	return order


## 当前行动者能发动的组合技（搭档在场、双方怒气都满），没有则返回 null。
func available_combo(actor: BattleUnit) -> ComboData:
	if actor == null or not actor.has_full_rage():
		return null
	for c in combos:
		var partner := _find_ally(actor, c.partner_of(actor.data.id))
		if partner != null and partner != actor and partner.has_full_rage():
			return c
	return null


## 胜利后的三颗星：获胜、无人倒下、在限定回合内获胜。
func star_conditions() -> Array[bool]:
	var won := result == Result.WIN
	return [won, won and player_deaths == 0, won and round_number() <= stage.star_round_limit]


func stars() -> int:
	return star_conditions().count(true)


# --- 推进 ---

func start_next_turn() -> Array[Dictionary]:
	_events = []
	current = null
	if result != Result.ONGOING:
		return _events
	var actor: BattleUnit = turn_order_preview()[0]
	time = actor.next_time
	actor.tick_turn_start()
	if actor.stun_turns > 0:
		actor.stun_turns -= 1
		_emit("info", actor, "眩晕", "%s 被眩晕，跳过本回合" % actor.display_name())
		_finish_turn(actor)
		return _events
	current = actor
	_emit("turn", actor, "", "")
	return _events


func act(action: Action, target: BattleUnit = null) -> Array[Dictionary]:
	_events = []
	var actor := current
	if actor == null:
		return _events
	current = null
	_extra_action = false
	match action:
		Action.SKILL when actor.skill_ready():
			_do_skill(actor, target)
		Action.GUARD:
			actor.guarding = true
			actor.add_rage(RAGE_ON_GUARD)
			_emit("action", actor, "防御", "%s 摆出防御架势" % actor.display_name())
		Action.COMBO when available_combo(actor) != null:
			_do_combo(actor, available_combo(actor), target)
		_:
			_do_attack(actor, target)
	_finish_turn(actor)
	return _events


## 敌人照预告的意图出手。自动战斗：能放组合技就放；被敌人的技能瞄准就防御；
## 技能值得用就用；否则普攻最弱的目标。
func act_ai() -> Array[Dictionary]:
	var actor := current
	if actor == null:
		return []
	if actor.side == BattleUnit.Side.ENEMY:
		var use_skill := actor.intent_skill and actor.skill_ready()
		return act(Action.SKILL if use_skill else Action.ATTACK, intent_target_of(actor))
	var foes := foes_of(actor)
	var weakest := _weakest(foes)
	if available_combo(actor) != null:
		return act(Action.COMBO, weakest)
	if is_threatened(actor) and not (actor.skill_ready() and actor.data.skill.effect in [SkillData.Effect.STUN, SkillData.Effect.HEAL]):
		return act(Action.GUARD)
	if actor.skill_ready() and _skill_worth_using(actor, foes):
		return act(Action.SKILL, _skill_target(actor, foes, weakest))
	return act(Action.ATTACK, weakest)


## 敌人这一步实际会打谁：普攻会被嘲讽拉走，技能（背后捅刀）不会；原目标倒下就改打最弱的。
func intent_target_of(enemy: BattleUnit) -> BattleUnit:
	var foes := foes_of(enemy)
	if foes.is_empty():
		return null
	if not enemy.intent_skill:
		for f in foes:
			if f.is_taunting():
				return f
	if enemy.intent_target != null and enemy.intent_target.is_alive():
		return enemy.intent_target
	return _weakest(foes)


## 有没有敌人预告要用技能打这个好汉。
func is_threatened(hero: BattleUnit) -> bool:
	for e in alive(BattleUnit.Side.ENEMY):
		if e.intent_skill and e.stun_turns == 0 and intent_target_of(e) == hero:
			return true
	return false


# --- 行动结算 ---

func _do_attack(actor: BattleUnit, wanted: BattleUnit) -> void:
	var target := _pick_foe(actor, wanted)
	if target == null:
		return
	_emit("action", actor, "普攻", "%s 普攻 %s" % [actor.display_name(), target.display_name()])
	_deal(actor, target, 1.0)
	actor.add_rage(RAGE_ON_ATTACK)


func _do_skill(actor: BattleUnit, wanted: BattleUnit) -> void:
	var s := actor.data.skill
	actor.skill_cooldown = s.cooldown
	_emit("skill", actor, s.display_name, "%s 使用「%s」" % [actor.display_name(), s.display_name])
	match s.effect:
		SkillData.Effect.DAMAGE:
			_deal(actor, _pick_foe(actor, wanted), s.power)
		SkillData.Effect.EXECUTE:
			var target := _pick_foe(actor, wanted)
			var low := target.hp_ratio() < EXECUTE_THRESHOLD
			if low:
				_emit("info", target, "破绽", "%s 露出破绽，伤害翻倍" % target.display_name())
			_deal(actor, target, s.power * (2.0 if low else 1.0))
		SkillData.Effect.MULTI_HIT:
			var target := _pick_foe(actor, wanted)
			for i in s.hits:
				if not target.is_alive():
					target = _pick_foe(actor, null)
					if target == null:
						break
				_deal(actor, target, s.power)
		SkillData.Effect.SURE_CRIT:
			_deal(actor, _pick_foe(actor, wanted), s.power, true)
		SkillData.Effect.TAUNT:
			actor.taunt_turns = s.turns
			actor.reduction = s.amount
			actor.reduction_turns = s.turns
			_emit("info", actor, "嘲讽", "%s 吸引了全体敌人的注意" % actor.display_name())
		SkillData.Effect.TEAM_HASTE:
			for ally in allies_of(actor):
				ally.buffs.append(BattleUnit.Buff.new(s.display_name, 0.0, s.amount, s.turns))
				ally.add_rage(s.rage_gain)
				_emit("info", ally, "加速", "")
			_emit("info", actor, "", "全队速度提升，怒气 +%d" % s.rage_gain)
		SkillData.Effect.STUN:
			var target := _pick_foe(actor, wanted)
			target.stun_turns = maxi(target.stun_turns, s.turns)
			_emit("info", target, "眩晕", "%s 被放倒了" % target.display_name())
		SkillData.Effect.STEAL:
			var target := _pick_foe(actor, wanted)
			if target.buffs.is_empty():
				_emit("info", target, "空手", "%s 身上没什么可偷的" % target.display_name())
			else:
				var b: BattleUnit.Buff = target.buffs.pop_back()
				actor.buffs.append(b)
				_emit("info", actor, "偷到 " + b.name, "%s 偷走了 %s 的「%s」" % [actor.display_name(), target.display_name(), b.name])
			_extra_action = true
			_emit("info", actor, "再动", "%s 立刻再行动一次" % actor.display_name())
		SkillData.Effect.HEAL:
			for ally in allies_of(actor):
				var amount := mini(roundi(ally.max_hp * s.amount), ally.max_hp - ally.hp)
				ally.hp += amount
				ally.stun_turns = 0
				_emit("heal", ally, "+%d" % amount, "")
			_emit("info", actor, "", "%s 为全队疗伤" % actor.display_name())
		SkillData.Effect.GUARD_STRIKE:
			_deal(actor, _pick_foe(actor, wanted), s.power)
			var shield := roundi(actor.max_hp * s.amount)
			for ally in allies_of(actor):
				ally.shield += shield
				_emit("info", ally, "护盾 +%d" % shield, "")
		SkillData.Effect.BACKSTAB:
			# 绕过嘲讽，打预告里的目标（预告时血量比例最低的人）
			var target := wanted if wanted != null and wanted.is_alive() else _weakest(foes_of(actor))
			_deal(actor, target, s.power)
	actor.add_rage(RAGE_ON_SKILL)


func _do_combo(actor: BattleUnit, combo: ComboData, wanted: BattleUnit) -> void:
	var a := _find_ally(actor, combo.hero_a)
	var b := _find_ally(actor, combo.hero_b)
	a.rage = 0
	b.rage = 0
	_emit("combo", a, combo.display_name, "%s + %s 发动组合技「%s」" % [a.display_name(), b.display_name(), combo.display_name], false, b)
	match combo.effect:
		ComboData.Effect.SHIELD_STRIKE:
			for ally in allies_of(actor):
				var amount := roundi(ally.max_hp * combo.amount)
				ally.shield += amount
				_emit("info", ally, "护盾 +%d" % amount, "")
			_deal(b, _pick_foe(b, wanted), combo.power)
		ComboData.Effect.STUN_ALL_COMBO:
			for foe in foes_of(actor):
				foe.stun_turns = maxi(foe.stun_turns, 1)
				_emit("info", foe, "眩晕", "")
			var target := _pick_foe(b, wanted)
			for i in combo.hits:
				if not target.is_alive():
					target = _pick_foe(b, null)
					if target == null:
						break
				_deal(b, target, combo.power)
		ComboData.Effect.STEAL_ALL_RAGE:
			var stolen := 0
			for foe in foes_of(actor):
				for buff in foe.buffs:
					actor.buffs.append(buff)
					stolen += 1
				foe.buffs.clear()
			_emit("info", actor, "偷到 %d 个增益" % stolen, "")
			for ally in allies_of(actor):
				ally.add_rage(combo.rage_gain)
				_emit("info", ally, "怒气 +%d" % combo.rage_gain, "")


## 按设计文档的公式结算一次伤害，返回造成的伤害（含被护盾吸收的部分）。
func _deal(attacker: BattleUnit, target: BattleUnit, multiplier: float, force_crit := false) -> int:
	if target == null or not target.is_alive():
		return 0
	var crit := force_crit or rng.randf() < CRIT_CHANCE
	var raw := attacker.atk() * multiplier * 100.0 / (100.0 + target.def()) * rng.randf_range(0.95, 1.05)
	if crit:
		raw *= CRIT_MULTIPLIER
	if target.guarding:
		raw *= 1.0 - GUARD_REDUCTION
	if target.reduction_turns >= 0:
		raw *= 1.0 - target.reduction
	var amount := maxi(1, roundi(raw))
	var absorbed := mini(target.shield, amount)
	target.shield -= absorbed
	target.hp = maxi(target.hp - (amount - absorbed), 0)
	var popup := ("暴击 -%d" if crit else "-%d") % amount
	_emit("damage", target, popup, "%s 对 %s 造成 %d 伤害" % [attacker.display_name(), target.display_name(), amount], crit, attacker)
	if not target.is_alive():
		if target.side == BattleUnit.Side.PLAYER:
			player_deaths += 1
		_emit("death", target, "倒下", "%s 倒下了" % target.display_name())
	elif target.data.is_boss and not target.enraged and target.hp_ratio() < ENRAGE_THRESHOLD:
		target.enraged = true
		target.buffs.append(BattleUnit.Buff.new(target.data.enrage_name, target.data.enrage_atk_bonus, 0.0, target.data.enrage_turns))
		_emit("banner", target, target.data.enrage_name, "%s「%s」，攻击大幅提升！" % [target.display_name(), target.data.enrage_name])
	return amount


# --- 内部工具 ---

func _finish_turn(actor: BattleUnit) -> void:
	if not _extra_action:
		actor.next_time = time + TIME_PER_ACTION / actor.spd()
	_extra_action = false
	if actor.side == BattleUnit.Side.ENEMY and actor.is_alive():
		_plan_intent(actor)
	if alive(BattleUnit.Side.ENEMY).is_empty():
		result = Result.WIN
	elif alive(BattleUnit.Side.PLAYER).is_empty():
		result = Result.LOSE


## 定下敌人下一回合要做什么，让玩家提前应对。技能在下回合能用就预告技能，
## 背后捅刀瞄准此刻血量比例最低的好汉，普攻随机挑一个。
func _plan_intent(enemy: BattleUnit) -> void:
	var foes := foes_of(enemy)
	if foes.is_empty():
		return
	# 冷却在轮到自己时才减 1，所以现在 ≤ 1 就代表下回合可用
	enemy.intent_skill = enemy.data.skill != null and enemy.skill_cooldown <= 1
	if enemy.intent_skill and enemy.data.skill.effect == SkillData.Effect.BACKSTAB:
		enemy.intent_target = _weakest(foes)
	else:
		enemy.intent_target = foes[rng.randi_range(0, foes.size() - 1)]


## 有嘲讽的敌人时必须打它；否则打指定目标，没指定就打第一个活着的。
func _pick_foe(actor: BattleUnit, wanted: BattleUnit) -> BattleUnit:
	var foes := foes_of(actor)
	if foes.is_empty():
		return null
	for f in foes:
		if f.is_taunting():
			return f
	if wanted != null and wanted in foes:
		return wanted
	return foes[0]


func _find_ally(actor: BattleUnit, hero_id: StringName) -> BattleUnit:
	if hero_id == &"":
		return null
	for u in allies_of(actor):
		if u.data.id == hero_id:
			return u
	return null


func _weakest(candidates: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = null
	for u in candidates:
		if best == null or u.hp_ratio() < best.hp_ratio():
			best = u
	return best


func _skill_worth_using(actor: BattleUnit, foes: Array[BattleUnit]) -> bool:
	match actor.data.skill.effect:
		SkillData.Effect.HEAL:
			return allies_of(actor).any(func(u: BattleUnit) -> bool: return u.hp_ratio() < AI_HEAL_THRESHOLD)
		SkillData.Effect.TAUNT:
			return not actor.is_taunting()
		SkillData.Effect.STUN:
			return foes.any(func(u: BattleUnit) -> bool: return u.stun_turns == 0)
	return true


func _skill_target(actor: BattleUnit, foes: Array[BattleUnit], weakest: BattleUnit) -> BattleUnit:
	if actor.data.skill.effect == SkillData.Effect.STUN:
		var best: BattleUnit = null
		for u in foes:
			if u.stun_turns == 0 and (best == null or u.atk() > best.atk()):
				best = u
		return best
	return weakest


func _acts_before(a: BattleUnit, a_time: float, b: BattleUnit, b_time: float) -> bool:
	if not is_equal_approx(a_time, b_time):
		return a_time < b_time
	if a.side != b.side:
		return a.side == BattleUnit.Side.PLAYER
	return a.slot < b.slot


func _emit(kind: String, unit: BattleUnit, popup: String, log_text: String, big := false, source: BattleUnit = null) -> void:
	_events.append({"kind": kind, "unit": unit, "popup": popup, "log": log_text, "big": big, "source": source})

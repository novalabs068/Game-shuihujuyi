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
## 「铁甲」精英受到的普攻伤害倍率
const IRON_BASIC_MULTIPLIER := 0.5
## 破绽：下一次挨打的伤害加成
const EXPOSE_BONUS := 0.2
## 伤害公式里防御的基准（1 级时）：伤害 = 攻击 × 倍率 × 基准 ÷ (基准 + 防御)
const DEF_BASE := 100.0
const EXECUTE_THRESHOLD := 0.3
const ENRAGE_THRESHOLD := 0.5
const TURN_PREVIEW_COUNT := 6
## 自动战斗时，有队友血量低于这个比例才用治疗技能
const AI_HEAL_THRESHOLD := 0.6
## 整场有效的增益用这么多回合表示
const WHOLE_BATTLE := 999
## 群攻技能命中时播的特效（art/fx），没列的用默认的刀光
const SKILL_FX := {
	SkillData.Effect.ALL_FOES_SLOW: "ground_slam",
	SkillData.Effect.ALL_FOES_RAGE: "ground_slam",
	SkillData.Effect.ALL_FOES_BURN: "explosion",
	SkillData.Effect.ALL_FOES_MULTI: "heavy_cleave",
}

var stage: StageData
var units: Array[BattleUnit] = []
var combos: Array[ComboData] = []
var current: BattleUnit
var result := Result.ONGOING
var time := 0.0
var player_deaths := 0
var rng := RandomNumberGenerator.new()

## 准备回合：开战时结算的开局效果（阵法、天赋、装备……），由 BattleView 在第一回合前逐条亮出来
var opening_events: Array[Dictionary] = []

var _events: Array[Dictionary] = []
var _extra_action := false
## 这次技能命中时播的特效（群攻技能各有各的），写进 damage 事件的 fx
var _hit_fx := ""


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
		var e := BattleUnit.new(stage.enemies[i], BattleUnit.Side.ENEMY, i, stage.enemy_level)
		var boss_k := stage.boss_power if e.data.is_boss else 1.0
		if not is_equal_approx(stage.enemy_power * boss_k, 1.0):
			e.strengthen(stage.enemy_power * boss_k, boss_k)
		units.append(e)
	_events = []
	for u in units:
		_apply_opening_gear(u)
		_apply_opening_talent(u)
	opening_events = _events
	_events = []
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
	if actor == null or not actor.has_full_rage() or actor.silence_turns > 0:
		return null
	for c in combos:
		var partner := _find_ally(actor, c.partner_of(actor.data.id))
		if partner != null and partner != actor and partner.has_full_rage() and partner.silence_turns == 0:
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
	if actor.has_gear(&"regen") and actor.hp < actor.max_hp:
		var amount := mini(roundi(actor.max_hp * Equipment.REGEN_RATIO), actor.max_hp - actor.hp)
		actor.hp += amount
		_emit("heal", actor, "+%d" % amount, "%s 回春，回复 %d 生命" % [actor.display_name(), amount])
	if actor.burn_turns > 0:
		actor.burn_turns -= 1
		var burn := mini(actor.burn_damage, actor.hp)
		actor.hp -= burn
		_emit("damage", actor, "灼烧 -%d" % burn, "%s 被火烧，损失 %d 生命" % [actor.display_name(), burn])
		if not actor.is_alive():
			_on_death(actor)
			_finish_turn(actor)
			return _events
	if actor.stun_turns > 0:
		actor.consume_stun()
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
		Action.ATTACK when not actor.can_attack():
			_do_guard(actor, "%s 被缴了械，只能防御" % actor.display_name())
		Action.GUARD:
			actor.guarding = true
			actor.add_rage(RAGE_ON_GUARD)
			_emit("action", actor, "防御", "%s 摆出防御架势" % actor.display_name())
		Action.COMBO when available_combo(actor) != null:
			_do_combo(actor, available_combo(actor), target)
		_ when not actor.can_attack():
			_do_guard(actor, "%s 被缴了械，只能防御" % actor.display_name())
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
	if not actor.can_attack() and not actor.skill_ready():
		return act(Action.GUARD)
	if is_threatened(actor) and not (actor.skill_ready() and actor.data.skill.effect in [SkillData.Effect.STUN, SkillData.Effect.STUN_ALL, SkillData.Effect.HEAL]):
		return act(Action.GUARD)
	if actor.skill_ready() and _skill_worth_using(actor, foes):
		return act(Action.SKILL, _skill_target(actor, foes, weakest))
	return act(Action.ATTACK, weakest)


## 敌人这一步实际会打谁：普攻会被嘲讽拉走，技能（背后捅刀）不会；原目标倒下就改打最弱的。
func intent_target_of(enemy: BattleUnit) -> BattleUnit:
	var foes := foes_of(enemy)
	if foes.is_empty():
		return null
	# 只有「背后捅刀」这类技能无视嘲讽，其他攻击都会被嘲讽拉走
	var ignores_taunt := enemy.intent_skill and enemy.data.skill != null and enemy.data.skill.effect == SkillData.Effect.BACKSTAB
	if not ignores_taunt:
		for f in foes:
			if f.is_taunting():
				return f
	if enemy.intent_target != null and enemy.intent_target.is_alive():
		return enemy.intent_target
	return _weakest(foes)


## 有没有敌人预告要用技能打这个好汉。
func is_threatened(hero: BattleUnit) -> bool:
	for e in alive(BattleUnit.Side.ENEMY):
		if e.intent_skill and e.stun_turns == 0 and e.silence_turns == 0 and intent_target_of(e) == hero:
			return true
	return false


# --- 行动结算 ---

func _do_guard(actor: BattleUnit, log_text: String) -> void:
	actor.guarding = true
	actor.add_rage(RAGE_ON_GUARD)
	_emit("action", actor, "防御", log_text)


func _do_attack(actor: BattleUnit, wanted: BattleUnit) -> void:
	var target := _pick_foe(actor, wanted)
	if target == null:
		return
	_emit("action", actor, "普攻", "%s 普攻 %s" % [actor.display_name(), target.display_name()])
	_deal(actor, target, 1.0, false, true)
	actor.add_rage(RAGE_ON_ATTACK)
	_try_pursuit(actor, target)


## 普攻之后判定追击：按来源顺序掷骰，第一个成功的生效，一次普攻最多一个。
func _try_pursuit(actor: BattleUnit, target: BattleUnit) -> void:
	if not actor.is_alive() or foes_of(actor).is_empty():
		return
	for p in Pursuit.sources_for(actor):
		if rng.randf() >= p.chance:
			continue
		var t := target
		if p.kind == &"snipe":
			t = _weakest(foes_of(actor))
		if t == null or not t.is_alive():
			return
		_emit("info", actor, "追击", "%s「%s」追击" % [actor.display_name(), p.name])
		match p.kind:
			&"hit", &"snipe":
				_hit_fx = "sword_slash"
				_deal(actor, t, p.power)
				_hit_fx = ""
			&"slow":
				t.add_buff(BattleUnit.Buff.new(p.name, 0.0, -p.power, Pursuit.SLOW_TURNS))
				_emit("info", t, "减速", "%s 行动变慢了" % t.display_name())
			&"stun":
				if _stun(actor, t, 1):
					_emit("info", t, "眩晕", "%s 被打晕了" % t.display_name())
			&"expose":
				_expose(t)
		return


## 放绝招。组合技里借放的（skill 不为空）用传进来的那招，不进冷却。
func _do_skill(actor: BattleUnit, wanted: BattleUnit, skill: SkillData = null) -> void:
	var s := skill if skill != null else actor.data.skill
	if skill == null:
		# 机变：冷却少 1 回合，最少 1 回合
		actor.skill_cooldown = maxi(s.cooldown - 1, 1) if actor.has_gear(&"nimble") else s.cooldown
	_emit("skill", actor, s.display_name, "%s 使用「%s」" % [actor.display_name(), s.display_name])
	_hit_fx = SKILL_FX.get(s.effect, "")
	match s.effect:
		SkillData.Effect.DAMAGE:
			_deal(actor, _pick_foe(actor, wanted), s.power)
		SkillData.Effect.EXECUTE:
			var target := _pick_foe(actor, wanted)
			var low := target.hp_ratio() < EXECUTE_THRESHOLD
			if low:
				_emit("info", target, "残血", "%s 伤重难支，伤害翻倍" % target.display_name())
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
				ally.add_buff(BattleUnit.Buff.new(s.display_name, 0.0, s.amount, s.turns))
				ally.add_rage(s.rage_gain)
				_emit("info", ally, "加速", "")
			_emit("info", actor, "", "全队速度提升，怒气 +%d" % s.rage_gain)
		SkillData.Effect.STUN:
			var target := _pick_foe(actor, wanted)
			if _stun(actor, target, s.turns):
				_emit("info", target, "眩晕", "%s 被放倒了" % target.display_name())
		SkillData.Effect.STEAL:
			var target := _pick_foe(actor, wanted)
			# 只偷增益，减益（减攻、减速）不偷
			var gains := target.buffs.filter(func(b: BattleUnit.Buff) -> bool: return b.atk_bonus >= 0.0 and b.spd_bonus >= 0.0)
			if gains.is_empty():
				_emit("info", target, "空手", "%s 身上没什么可偷的" % target.display_name())
			else:
				var b: BattleUnit.Buff = gains.back()
				target.buffs.erase(b)
				actor.add_buff(b)
				_emit("info", actor, "偷到 " + b.name, "%s 偷走了 %s 的「%s」" % [actor.display_name(), target.display_name(), b.name])
			_extra_action = true
			_emit("info", actor, "再动", "%s 立刻再行动一次" % actor.display_name())
		SkillData.Effect.HEAL:
			for ally in allies_of(actor):
				var amount := mini(roundi(ally.max_hp * s.amount), ally.max_hp - ally.hp)
				ally.hp += amount
				ally.stun_turns = 0
				ally.disarm_turns = 0
				ally.silence_turns = 0
				_emit("heal", ally, "+%d" % amount, "")
			_emit("info", actor, "", "%s 为全队疗伤" % actor.display_name())
		SkillData.Effect.GUARD_STRIKE:
			_deal(actor, _pick_foe(actor, wanted), s.power)
			var shield := roundi(actor.max_hp * s.amount)
			for ally in allies_of(actor):
				ally.shield += shield
				_emit("info", ally, "护盾 +%d" % shield, "")
		SkillData.Effect.PIERCE:
			_deal(actor, _pick_foe(actor, wanted), s.power, false, false, true)
		SkillData.Effect.ALL_FOES:
			for foe in foes_of(actor):
				_deal(actor, foe, s.power)
		SkillData.Effect.ALL_FOES_SLOW:
			for foe in foes_of(actor):
				_deal(actor, foe, s.power)
				if foe.is_alive():
					foe.add_buff(BattleUnit.Buff.new("踩踏", 0.0, -s.amount, s.turns))
					_emit("info", foe, "减速", "")
		SkillData.Effect.ALL_FOES_RAGE:
			var k := 1.0 + s.amount * actor.rage / BattleUnit.RAGE_MAX
			if actor.rage >= BattleUnit.RAGE_MAX / 2:
				_emit("info", actor, "怒火", "%s 怒火正盛，伤害 ×%.1f" % [actor.display_name(), k])
			for foe in foes_of(actor):
				_deal(actor, foe, s.power * k)
		SkillData.Effect.ALL_FOES_BURN:
			var burn := maxi(1, roundi(actor.atk() * s.amount))
			for foe in foes_of(actor):
				_deal(actor, foe, s.power)
				if foe.is_alive():
					foe.burn_damage = maxi(foe.burn_damage if foe.burn_turns > 0 else 0, burn)
					foe.burn_turns = maxi(foe.burn_turns, s.turns)
					_emit("info", foe, "灼烧", "")
		SkillData.Effect.ALL_FOES_MULTI:
			for i in s.hits:
				for foe in foes_of(actor):
					_deal(actor, foe, s.power)
		SkillData.Effect.CRIPPLE:
			var target := _pick_foe(actor, wanted)
			_deal(actor, target, s.power)
			if target.is_alive():
				target.add_buff(BattleUnit.Buff.new("断筋", 0.0, -s.amount, s.turns))
				_emit("info", target, "减速", "%s 行动变慢了" % target.display_name())
		SkillData.Effect.WEAKEN_ALL:
			for foe in foes_of(actor):
				foe.add_buff(BattleUnit.Buff.new("醉", -s.amount, 0.0, s.turns))
				_emit("info", foe, "减攻", "")
			_emit("info", actor, "", "敌方全体攻击下降")
		SkillData.Effect.TEAM_ATK:
			for ally in allies_of(actor):
				ally.add_buff(BattleUnit.Buff.new(s.display_name, s.amount, 0.0, s.turns))
				_emit("info", ally, "增攻", "")
			_emit("info", actor, "", "全队攻击提升")
		SkillData.Effect.STUN_ALL:
			for foe in foes_of(actor):
				if _stun(actor, foe, s.turns):
					_emit("info", foe, "昏睡", "")
			_emit("info", actor, "", "敌方全体被麻翻了")
		SkillData.Effect.DISARM, SkillData.Effect.SILENCE:
			var target := _pick_foe(actor, wanted)
			if s.power > 0.0:
				_deal(actor, target, s.power)
			if target != null and target.is_alive():
				_control(actor, target, &"disarm" if s.effect == SkillData.Effect.DISARM else &"silence", s.turns)
		SkillData.Effect.BACKSTAB:
			# 绕过嘲讽，打预告里的目标（预告时血量比例最低的人）
			var target := wanted if wanted != null and wanted.is_alive() else _weakest(foes_of(actor))
			_deal(actor, target, s.power)
	_hit_fx = ""
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
				if _stun(b, foe, 1):
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
					actor.add_buff(buff)
					stolen += 1
				foe.buffs.clear()
			_emit("info", actor, "偷到 %d 个增益" % stolen, "")
			for ally in allies_of(actor):
				ally.add_rage(combo.rage_gain)
				_emit("info", ally, "怒气 +%d" % combo.rage_gain, "")
		ComboData.Effect.ALL_FOES_COMBO:
			for i in combo.hits:
				for foe in foes_of(b):
					_deal(b, foe, combo.power)
		ComboData.Effect.HEAL_RAGE:
			for ally in allies_of(actor):
				var healed := mini(roundi(ally.max_hp * combo.amount), ally.max_hp - ally.hp)
				ally.hp += healed
				ally.stun_turns = 0
				ally.disarm_turns = 0
				ally.silence_turns = 0
				ally.add_rage(combo.rage_gain)
				_emit("heal", ally, "+%d" % healed, "")
		ComboData.Effect.SWORN:
			_deal(a, _pick_foe(a, wanted), combo.power)
			if b.data.skill != null and not foes_of(b).is_empty():
				_do_skill(b, wanted if wanted != null and wanted.is_alive() else null, Stars.upgraded_skill(b.data.skill))


## 按设计文档的公式结算一次伤害，返回造成的伤害（含被护盾吸收的部分）。basic 表示普攻（「铁甲」只减普攻）。
func _deal(attacker: BattleUnit, target: BattleUnit, multiplier: float, force_crit := false, basic := false, pierce := false) -> int:
	if target == null or not target.is_alive():
		return 0
	var crit_chance := CRIT_CHANCE + (Equipment.KEEN_CRIT if attacker.has_gear(&"keen") else 0.0)
	var crit := force_crit or attacker.first_crit_ready or rng.randf() < crit_chance
	attacker.first_crit_ready = false
	var def := 0.0 if pierce else target.def()
	# 防御的「基准」跟着挨打的人的等级一起成长：防御挡掉的比例只看自己的防御，前期后期一样
	var base := DEF_BASE * pow(BattleUnit.LEVEL_GROWTH, target.level - 1)
	var raw := attacker.atk() * multiplier * base / (base + def) * rng.randf_range(0.95, 1.05)
	if crit:
		raw *= CRIT_MULTIPLIER
	if target.guarding:
		raw *= 1.0 - GUARD_REDUCTION
	if target.reduction_turns >= 0:
		raw *= 1.0 - target.reduction
	if basic and target.data.elite_trait == &"iron" and not attacker.has_gear(&"armor_break"):
		raw *= IRON_BASIC_MULTIPLIER
	if target.data.is_boss:
		raw *= 1.0 + attacker.talent(&"boss_slayer")
	raw *= 1.0 - target.talent(&"tough")
	raw *= Roles.damage_multiplier(attacker.data.role, target.data.role)
	var exposed := target.expose_turns > 0
	if exposed:
		raw *= 1.0 + EXPOSE_BONUS
		target.expose_turns = 0
	var amount := maxi(1, roundi(raw))
	var absorbed := mini(target.shield, amount)
	target.shield -= absorbed
	target.hp = maxi(target.hp - (amount - absorbed), 0)
	var countered := Roles.beats(attacker.data.role, target.data.role)
	var popup := ("克 " if countered else "") + ("绽 " if exposed else "") + ("暴击 -%d" if crit else "-%d") % amount
	var log_text := "%s 对 %s 造成 %d 伤害" % [attacker.display_name(), target.display_name(), amount]
	if countered:
		log_text += "（%s克%s）" % [UnitData.ROLE_TAGS[attacker.data.role], UnitData.ROLE_TAGS[target.data.role]]
	_emit("damage", target, popup, log_text, crit, attacker)
	if crit and attacker.has_talent(&"crit_haste"):
		var t := attacker.data.talent
		if attacker.buffs.filter(func(b: BattleUnit.Buff) -> bool: return b.name == t.display_name).size() < TalentData.CRIT_HASTE_STACKS:
			attacker.add_buff(BattleUnit.Buff.new(t.display_name, 0.0, attacker.talent(&"crit_haste"), WHOLE_BATTLE))
			_emit("info", attacker, "加速", "%s「%s」，越打越快" % [attacker.display_name(), t.display_name])
	if not target.is_alive():
		_on_death(target)
	elif target.data.is_boss and not target.enraged and target.hp_ratio() < ENRAGE_THRESHOLD:
		target.enraged = true
		target.add_buff(BattleUnit.Buff.new(target.data.enrage_name, target.data.enrage_atk_bonus, 0.0, target.data.enrage_turns))
		_emit("banner", target, target.data.enrage_name, "%s「%s」，攻击大幅提升！" % [target.display_name(), target.data.enrage_name])
	return amount


# --- 内部工具 ---

## 眩晕 turns 回合；克制对方职业时多 1 回合。
func _stun(actor: BattleUnit, target: BattleUnit, turns: int) -> bool:
	return _control(actor, target, &"stun", turns)


const CONTROL_NAMES := {&"stun": "眩晕", &"disarm": "缴械", &"silence": "计穷"}

## 上一种控制（眩晕、缴械、计穷）：同种不叠加，取较长的回合；克制对方职业时多 1 回合；
## 头目的定力期间无效。返回是否生效。
func _control(actor: BattleUnit, target: BattleUnit, kind: StringName, turns: int) -> bool:
	if target.resists(kind):
		_emit("info", target, "定力", "%s 定力未失，%s无效" % [target.display_name(), CONTROL_NAMES[kind]])
		return false
	var n := Roles.control_turns(actor.data.role, target.data.role, turns)
	match kind:
		&"stun":
			target.stun_turns = maxi(target.stun_turns, n)
		&"disarm":
			target.disarm_turns = maxi(target.disarm_turns, n)
			_emit("info", target, "缴械", "%s 被缴了械，%d 回合不能普攻" % [target.display_name(), n])
		&"silence":
			target.silence_turns = maxi(target.silence_turns, n)
			_emit("info", target, "计穷", "%s 计穷，%d 回合放不了绝招" % [target.display_name(), n])
	return true


## 让目标露出破绽：下一次挨打伤害 +20%。
func _expose(target: BattleUnit, turns := 1) -> void:
	target.expose_turns = maxi(target.expose_turns, turns)
	_emit("info", target, "破绽", "%s 露出破绽" % target.display_name())


func _on_death(unit: BattleUnit) -> void:
	if unit.side == BattleUnit.Side.PLAYER:
		player_deaths += 1
	unit.burn_turns = 0
	_emit("death", unit, "倒下", "%s 倒下了" % unit.display_name())



## 装备的开战效果：疾风加速。
func _apply_opening_gear(u: BattleUnit) -> void:
	if u.has_gear(&"swift"):
		u.add_buff(BattleUnit.Buff.new("疾风", 0.0, Equipment.SWIFT_BONUS, Equipment.SWIFT_TURNS))
		_emit("prep", u, "疾风", "%s「疾风」：速度 +%d%%，%d 回合" % [u.display_name(), roundi(Equipment.SWIFT_BONUS * 100), Equipment.SWIFT_TURNS])


## 开战时生效的天赋：自己或全队加怒气、加攻、加速、回春。
func _apply_opening_talent(u: BattleUnit) -> void:
	if u.data.talent == null or u.data.talent_rank <= 0:
		return
	var t := u.data.talent
	var v := t.value(u.data.talent_rank)
	var allies := allies_of(u)
	if t.kind in [&"rage_start", &"team_rage_start", &"team_atk", &"team_haste_open", &"team_regen"]:
		_emit("prep", u, t.display_name, "%s「%s」：%s" % [u.display_name(), t.display_name, t.describe(u.data.talent_rank)])
	match t.kind:
		&"rage_start":
			u.add_rage(roundi(v))
		&"team_rage_start":
			for a in allies:
				a.add_rage(roundi(v))
		&"team_atk":
			for a in allies:
				a.add_buff(BattleUnit.Buff.new(t.display_name, v, 0.0, WHOLE_BATTLE))
		&"team_haste_open":
			for a in allies:
				a.add_buff(BattleUnit.Buff.new(t.display_name, 0.0, v, 2))
		&"team_regen":
			for a in allies:
				if not &"regen" in a.extra_effects:
					a.extra_effects.append(&"regen")


func _finish_turn(actor: BattleUnit) -> void:
	actor.tick_turn_end()
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
		SkillData.Effect.STUN, SkillData.Effect.STUN_ALL:
			return foes.any(func(u: BattleUnit) -> bool: return u.stun_turns == 0)
		SkillData.Effect.ALL_FOES, SkillData.Effect.ALL_FOES_SLOW, SkillData.Effect.ALL_FOES_RAGE, SkillData.Effect.ALL_FOES_BURN, SkillData.Effect.ALL_FOES_MULTI:
			return foes.size() >= 2 or foes[0].hp_ratio() > 0.5
	return true


func _skill_target(actor: BattleUnit, foes: Array[BattleUnit], weakest: BattleUnit) -> BattleUnit:
	match actor.data.skill.effect:
		SkillData.Effect.SILENCE:
			# 先封住正要放绝招的人
			for u in foes:
				if u.intent_skill and u.silence_turns == 0 and not u.resists(&"silence"):
					return u
		SkillData.Effect.DISARM:
			var strongest: BattleUnit = null
			for u in foes:
				if u.disarm_turns == 0 and not u.resists(&"disarm") and (strongest == null or u.atk() > strongest.atk()):
					strongest = u
			if strongest != null:
				return strongest
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
	_events.append({"kind": kind, "unit": unit, "popup": popup, "log": log_text, "big": big, "source": source, "fx": _hit_fx if kind == "damage" else ""})

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
##
## 站位：每方 2 排 × 3 路（见 Grid）。近战只能打到每一路最前面的人（卡位），刺客和远程不受限。

## MOVE 是「补位」：走到己方一个空格子，这一回合顺便防御
enum Action { ATTACK, SKILL, GUARD, COMBO, MOVE }
enum Result { ONGOING, WIN, LOSE }

## 统领（主角）：和好汉一起上场；他倒下全队士气受挫
const COMMANDER_ID := &"protagonist"
## 统领倒下：全队攻击 -10%
const MORALE_LOSS := 0.1
const TIME_PER_ACTION := 1000.0
const ROUND_TIME := 10.0
const RAGE_ON_ATTACK := 20
const RAGE_ON_SKILL := 10
const RAGE_ON_GUARD := 25
const GUARD_REDUCTION := 0.5
## 「铁甲」精英受到的普攻伤害倍率
const IRON_BASIC_MULTIPLIER := 0.5
## 破绽：下一次挨打的伤害加成
const EXPOSE_BONUS := 0.2
## 头目蓄满的绝招伤害倍数
const CHARGE_BONUS := 1.4
## 头目的韧性：普攻削、技能削、控制削多少；打中弱点（克）削双倍
const TOUGHNESS_BASIC := 5
const TOUGHNESS_SKILL := 8
const TOUGHNESS_CONTROL := 25
## 破绽（韧性打空）：跪地一回合，受到的伤害 +30%
const BROKEN_TAKEN := 0.3
## 头目换阶段的血量线：60% 进第二阶段，30% 进第三阶段
const PHASE_LINES: Array[float] = [0.6, 0.3]
## 攻击范围的伤害倍数：多人每人 ×0.7；穿透后一格 ×0.8；连锁每跳 ×0.75、最多跳 3 次；全范围每人 ×0.55
const ROW_MULT := 0.7
const LANE_BACK_MULT := 0.8
const CHAIN_DECAY := 0.75
const CHAIN_HOPS := 3
const ALL_MULT := 0.55
## 统领上场后我方是四个人（关卡数据还是按三人编的）。我方满四人时敌人扩编：
## 关卡里的小兵（不是头目的）按顺序再来 REINFORCE 个，最多 MAX_ENEMIES 个人，大家再略加强一点；
## 没有小兵的头目单挑（景阳冈大虫这种）不扩编，头目自己按 SOLO_* 加强。增援不给经验银两
const SQUAD_SIZE := 4
const MAX_ENEMIES := 6
const REINFORCE := 2
const SQUAD_HP_SCALE := 1.0
const SQUAD_ATK_SCALE := 1.05
const SOLO_HP_SCALE := 1.6
const SOLO_ATK_SCALE := 1.65
## 四人仗打得久一些：三星的回合限制多给这么多回合
const SQUAD_EXTRA_ROUNDS := 3
## 每方最多几个召唤物
const MAX_SUMMONS := 2
## 偷属性：偷走对方攻击、速度各两成，持续 3 回合
const STEAL_STAT := 0.2
const STEAL_TURNS := 3
## 伤害公式里防御的基准（1 级时）：伤害 = 攻击 × 倍率 × 基准 ÷ (基准 + 防御)
const DEF_BASE := 100.0
const EXECUTE_THRESHOLD := 0.3
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

## 这一仗的统计（每人输出、承伤、治疗……按回合分开），结算页看
var stats := BattleStats.new()
## 正在结算追击时为 true，伤害记成追击
var _in_pursuit := false
## 准备回合：开战时结算的开局效果（阵法、天赋、装备……），由 BattleView 在第一回合前逐条亮出来
var opening_events: Array[Dictionary] = []

var _events: Array[Dictionary] = []
var _extra_action := false
## 这次技能命中时播的特效（群攻技能各有各的），写进 damage 事件的 fx
var _hit_fx := ""
## 正在放蓄满的绝招时为 CHARGE_BONUS，伤害都乘上它
var _charge_mult := 1.0
## 正在结算阵法的反击（蛇尾追击、月角夹击）时为 true，免得反击再引出反击
var _reacting := false
## 选用的阵法（破阵时用来清加成）
var formation_id: StringName = &""
## 我方满四人（统领 + 三位好汉）：敌人按四人加强，三星回合多给几回合
var squad := false


## formation 是玩家选的阵法（Formations 的 id，空 = 不摆阵）。placement 是我方每人站的格子（和 team 对应，
## Vector2i(排, 路)；空着、不合法或重复的按阵法的阵位顺序、再按职业自动摆）。
func _init(p_stage: StageData, team: Array[UnitData], hero_level: int, p_combos: Array[ComboData], seed_value: int = -1, formation: StringName = &"", placement: Array = []) -> void:
	stage = p_stage
	combos = p_combos
	formation_id = formation
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var players: Array[BattleUnit] = []
	for i in team.size():
		players.append(BattleUnit.new(team[i], BattleUnit.Side.PLAYER, i, hero_level))
	var wanted: Array = placement.duplicate()
	if wanted.is_empty():
		wanted.assign(Formations.cells(formation))
	_place(players, wanted, Formations.cells(formation))
	var foes: Array[BattleUnit] = []
	for i in stage.enemies.size():
		var e := BattleUnit.new(stage.enemies[i], BattleUnit.Side.ENEMY, i, stage.enemy_level)
		var boss_k := stage.boss_power if e.data.is_boss else 1.0
		if not is_equal_approx(stage.enemy_power * boss_k, 1.0):
			e.strengthen(stage.enemy_power * boss_k, boss_k)
		foes.append(e)
	squad = players.size() >= SQUAD_SIZE
	if squad:
		_reinforce(foes)
	_place(foes, stage.enemy_cells)
	for u in players + foes:
		if u.row >= 0:
			units.append(u)
	_events = []
	players = alive(BattleUnit.Side.PLAYER)
	if not players.is_empty():
		var formation_text := Formations.apply(formation, players, alive(BattleUnit.Side.ENEMY))
		if formation_text != "":
			for u in players:
				if u.has_talent(&"formation_boost"):
					Formations.boost(players, u.talent(&"formation_boost"))
					formation_text += "　%s「%s」：阵法加成 +%d%%" % [u.display_name(), u.passive(&"formation_boost").display_name, roundi(u.talent(&"formation_boost") * 100)]
					break
			var eye := players.filter(func(u: BattleUnit) -> bool: return u.formation_eye)
			_emit("prep", eye[0] if not eye.is_empty() else players[0], Formations.display_name(formation), "阵法%s" % formation_text)
		var hero_ids: Array[StringName] = []
		for u in players:
			if u.data.id != COMMANDER_ID:
				hero_ids.append(u.data.id)
		var faction := Factions.shared(hero_ids)
		if faction != &"":
			var who := players.filter(func(u: BattleUnit) -> bool: return Factions.of(u.data.id) == faction)
			_emit("prep", who[0], Factions.display_name(faction), Factions.apply(faction, players))
	for u in units:
		_apply_opening_gear(u)
		_apply_opening_talent(u)
	opening_events = _events
	_events = []
	for u in units:
		u.next_time = TIME_PER_ACTION / u.spd()
	for e in alive(BattleUnit.Side.ENEMY):
		_plan_intent(e)


## 我方满四人时敌人扩编：关卡里的小兵按顺序补到 +REINFORCE 个（最多 MAX_ENEMIES 个），全体略加强；
## 没有小兵（头目单挑）时头目自己加强。
func _reinforce(foes: Array[BattleUnit]) -> void:
	var mooks := foes.filter(func(u: BattleUnit) -> bool: return not u.data.is_boss)
	if mooks.is_empty():
		for e in foes:
			e.scale_squad(SOLO_HP_SCALE, SOLO_ATK_SCALE)
		return
	var target := mini(MAX_ENEMIES, foes.size() + REINFORCE)
	var i := 0
	while foes.size() < target:
		var src: BattleUnit = mooks[i % mooks.size()]
		var e := BattleUnit.new(src.data, BattleUnit.Side.ENEMY, foes.size(), src.level)
		if not is_equal_approx(stage.enemy_power, 1.0):
			e.strengthen(stage.enemy_power)
		e.reinforcement = true
		foes.append(e)
		i += 1
	for e in foes:
		e.scale_squad(SQUAD_HP_SCALE, SQUAD_ATK_SCALE)


## 摆位：先按 wanted 里的格子（和 list 一一对应；不合法、被占的跳过），没格子的人先去 fallback 里还空着的格子
## （阵法的阵位），再按职业自动摆。
func _place(list: Array[BattleUnit], wanted: Array, fallback: Array[Vector2i] = []) -> void:
	var taken := {}
	for i in list.size():
		if i >= wanted.size():
			break
		var c: Vector2i = wanted[i] if wanted[i] is Vector2i else Grid.NONE
		if not Grid.valid(c) or list[i].data.big:
			continue
		if taken.has(c):
			continue
		Grid._put(list[i], c, taken)
	for u in list:
		if u.row >= 0 or u.data.big:
			continue
		for c in fallback:
			if not taken.has(c):
				Grid._put(u, c, taken)
				break
	Grid.auto_place(list, taken)


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


## 一方站在 c 格的人（大体型占两格都算），没有返回 null。
func occupant(side: BattleUnit.Side, c: Vector2i) -> BattleUnit:
	for u in alive(side):
		if u.occupies(c):
			return u
	return null


## 一方这一路最前面的人（前排有人就是前排的，否则后排的），没人返回 null。
func lane_front(side: BattleUnit.Side, lane: int) -> BattleUnit:
	var front := occupant(side, Vector2i(0, lane))
	return front if front != null else occupant(side, Vector2i(1, lane))


## 一方的空格子（前排在前、中路在前）。
func free_cells(side: BattleUnit.Side) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in Grid.all_cells():
		if occupant(side, c) == null:
			out.append(c)
	return out


## actor 这一下打得到的敌人：近战（刺客除外）只打得到每一路最前面的人；远程、刺客都打得到。
func reachable_foes(actor: BattleUnit) -> Array[BattleUnit]:
	var foes := foes_of(actor)
	if not actor.is_melee() or Roles.ignores_block(actor.data.role):
		return foes
	var out: Array[BattleUnit] = []
	var foe_side := BattleUnit.Side.ENEMY if actor.side == BattleUnit.Side.PLAYER else BattleUnit.Side.PLAYER
	for l in Grid.LANES:
		var u := lane_front(foe_side, l)
		if u != null and not u in out:
			out.append(u)
	return out


func can_reach(actor: BattleUnit, target: BattleUnit) -> bool:
	return target in reachable_foes(actor)


## 一招从 primary 出发实际打到的人和各自的伤害倍数：[[人, 倍数], ...]。
func area_targets(actor: BattleUnit, primary: BattleUnit, area: SkillData.Area) -> Array:
	if primary == null:
		return []
	var foes := foes_of(actor)
	match area:
		SkillData.Area.ROW:
			var out := []
			for f in foes:
				if f.cells().any(func(c: Vector2i) -> bool: return c.x == primary.row):
					out.append([f, ROW_MULT])
			return out
		SkillData.Area.LANE:
			var out := [[primary, 1.0]]
			if primary.row == 0 and not primary.data.big:
				var behind := occupant(primary.side, Vector2i(1, primary.lane))
				if behind != null:
					out.append([behind, LANE_BACK_MULT])
			return out
		SkillData.Area.CHAIN:
			var out := [[primary, 1.0]]
			var last := primary
			var k := 1.0
			for i in CHAIN_HOPS:
				var next: BattleUnit = null
				for f in foes:
					if out.any(func(p: Array) -> bool: return p[0] == f):
						continue
					if next == null or Grid.distance(f.cell(), last.cell()) < Grid.distance(next.cell(), last.cell()):
						next = f
				if next == null:
					break
				k *= CHAIN_DECAY
				out.append([next, k])
				last = next
			return out
		SkillData.Area.ALL:
			return foes.map(func(f: BattleUnit) -> Array: return [f, ALL_MULT])
	return [[primary, 1.0]]


## 头目蓄的大招要砸哪几格（对方那一边）：按绝招的范围从预告的目标展开。
func charge_cells_for(skill: SkillData, target: BattleUnit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if target == null:
		return out
	match skill.effective_area():
		SkillData.Area.LANE:
			out.assign([Vector2i(0, target.lane), Vector2i(1, target.lane)])
		SkillData.Area.ROW:
			for l in Grid.LANES:
				out.append(Vector2i(target.row, l))
		SkillData.Area.ALL:
			out = Grid.all_cells()
		_:
			out = target.cells()
	return out


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
		if c.partner_of(actor.data.id) == COMMANDER_ID:
			return c
		var partner := _find_ally(actor, c.partner_of(actor.data.id))
		if partner != null and partner != actor and partner.has_full_rage() and partner.silence_turns == 0:
			return c
	return null


## 胜利后的三颗星：获胜、无人倒下、在限定回合内获胜。
func star_conditions() -> Array[bool]:
	var won := result == Result.WIN
	return [won, won and player_deaths == 0, won and round_number() <= round_limit()]


## 三星要在几回合内打赢。
func round_limit() -> int:
	return stage.star_round_limit + (SQUAD_EXTRA_ROUNDS if squad else 0)


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
		stats.add(actor, "healed", amount, round_number())
		_emit("heal", actor, "+%d" % amount, "%s 回春，回复 %d 生命" % [actor.display_name(), amount])
	if actor.has_talent(&"cleanse_regen"):
		var heal := mini(roundi(actor.max_hp * actor.talent(&"cleanse_regen")), actor.max_hp - actor.hp)
		if heal > 0:
			actor.hp += heal
			stats.add(actor, "healed", heal, round_number())
			_emit("heal", actor, "+%d" % heal, "%s 运功疗伤，回复 %d 生命" % [actor.display_name(), heal])
		for field: String in ["stun_turns", "disarm_turns", "silence_turns"]:
			if actor.get(field) > 0:
				actor.set(field, 0)
				_emit("info", actor, "解", "%s 解开了身上的控制" % actor.display_name())
				break
	if actor.burn_turns > 0:
		actor.burn_turns -= 1
		var burn := mini(actor.burn_damage, actor.hp)
		actor.hp -= burn
		stats.damage(units[actor.burn_source] if actor.burn_source >= 0 else null, actor, burn, round_number())
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


## cell 只给 MOVE（补位）用：走到哪一格。
func act(action: Action, target: BattleUnit = null, cell := Grid.NONE) -> Array[Dictionary]:
	_events = []
	var actor := current
	if actor == null:
		return _events
	current = null
	_extra_action = false
	match action:
		Action.MOVE when can_move_to(actor, cell):
			_do_move(actor, cell)
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


## 敌人照预告的意图出手。自动战斗：能放组合技就放；站在头目大招的红格里就躲开（躲不开就防御）；
## 被敌人的技能瞄准就防御；技能值得用就用；否则普攻打得到的人里最弱的。召唤物也走这里。
func act_ai() -> Array[Dictionary]:
	var actor := current
	if actor == null:
		return []
	if actor.side == BattleUnit.Side.ENEMY:
		var use_skill := actor.intent_skill and actor.skill_ready()
		if use_skill and actor.data.is_boss and not actor.charging:
			return _charge(actor)
		return act(Action.SKILL if use_skill else Action.ATTACK, intent_target_of(actor))
	var foes := reachable_foes(actor)
	var weakest := _weakest(foes)
	if available_combo(actor) != null:
		return act(Action.COMBO, weakest)
	if in_danger(actor):
		var safe := safe_cell(actor)
		if safe != Grid.NONE:
			return act(Action.MOVE, null, safe)
		return act(Action.GUARD)
	if not actor.can_attack() and not actor.skill_ready():
		return act(Action.GUARD)
	# 有头目在蓄力：手上有控制就去削它的韧性，削空了大招就散了
	if actor.skill_ready() and actor.data.skill.effect in CONTROL_EFFECTS:
		for f in foes_of(actor):
			if f.charging and (f in foes or actor.data.skill.effect == SkillData.Effect.STUN_ALL):
				return act(Action.SKILL, f)
	if is_threatened(actor) and not (actor.skill_ready() and actor.data.skill.effect in [SkillData.Effect.STUN, SkillData.Effect.STUN_ALL, SkillData.Effect.HEAL]):
		return act(Action.GUARD)
	if actor.skill_ready() and _skill_worth_using(actor, foes_of(actor)):
		return act(Action.SKILL, _skill_target(actor, foes, weakest))
	return act(Action.ATTACK, weakest)


## 站在某个头目下一步要砸的红格里。
func in_danger(u: BattleUnit) -> bool:
	for e in foes_of(u):
		if e.charging and releases_skill_next(e) and u.cells().any(func(c: Vector2i) -> bool: return c in e.charge_cells):
			return true
	return false


## 躲开红格能去的空格子：不在任何红格里，先挑宜站的那一排、离得近的。没有返回 Grid.NONE。
func safe_cell(u: BattleUnit) -> Vector2i:
	if u.data.big:
		return Grid.NONE
	var danger: Array[Vector2i] = []
	for e in foes_of(u):
		if e.charging:
			danger.append_array(e.charge_cells)
	var best := Grid.NONE
	for c in free_cells(u.side):
		if c in danger:
			continue
		if best == Grid.NONE or _cell_score(u, c) < _cell_score(u, best):
			best = c
	return best


func _cell_score(u: BattleUnit, c: Vector2i) -> int:
	return Grid.distance(u.cell(), c) + (0 if c.x == Roles.home_row(u.data.role) else 3)


## 敌人这一步实际会打谁：普攻会被嘲讽拉走（打得到嘲讽的人才算），技能（背后捅刀）不会；原目标倒下或打不到就改打打得到的最弱的。
func intent_target_of(enemy: BattleUnit) -> BattleUnit:
	var foes := reachable_foes(enemy)
	if foes.is_empty():
		return null
	# 「背后捅刀」这类技能、头目蓄满的绝招无视嘲讽，其他攻击都会被嘲讽拉走
	var ignores_taunt := enemy.intent_skill and enemy.data.skill != null and (enemy.data.skill.effect == SkillData.Effect.BACKSTAB or enemy.charging)
	if not ignores_taunt:
		for f in foes:
			if f.is_taunting():
				return f
	if enemy.intent_target != null and enemy.intent_target.is_alive() and (enemy.intent_target in foes or ignores_taunt):
		return enemy.intent_target
	return _weakest(foes)


## 有没有敌人预告下一步要用技能打这个人（头目还没蓄力的话，下一步只是蓄力，不算；蓄满的看红格）。
func is_threatened(hero: BattleUnit) -> bool:
	for e in foes_of(hero):
		if not releases_skill_next(e):
			continue
		if e.charging and not e.charge_cells.is_empty():
			if hero.cells().any(func(c: Vector2i) -> bool: return c in e.charge_cells):
				return true
		elif intent_target_of(e) == hero:
			return true
	return false


## 敌人下一步是不是真的放绝招（不是蓄力，也没被晕、被计穷）。
func releases_skill_next(e: BattleUnit) -> bool:
	return e.intent_skill and e.stun_turns == 0 and e.silence_turns == 0 and (not e.data.is_boss or e.charging)


## 头目开始蓄力：这一回合照常普攻，同时蓄力并在地上标出下一回合要砸的格子，下一回合放出 ×1.4 的绝招。
func _charge(actor: BattleUnit) -> Array[Dictionary]:
	actor.charging = true
	var target := intent_target_of(actor)
	var s := actor.data.skill
	if s.needs_enemy_target() or s.effect in SkillData.ALL_EFFECTS or s.effect == SkillData.Effect.BACKSTAB:
		actor.charge_cells = charge_cells_for(s, actor.intent_target if actor.intent_target != null and actor.intent_target.is_alive() else target)
	var events := act(Action.ATTACK, target)
	var where := "，地上红格就是要砸的地方，挪开或者打空它的韧性" if not actor.charge_cells.is_empty() else "，打空它的韧性能打断"
	events.push_front({"kind": "charge", "unit": actor, "popup": "蓄力", "log": "%s 一边出手一边蓄力，下一步「%s」伤害 ×%.1f%s！" % [actor.display_name(), s.display_name, CHARGE_BONUS, where], "big": false, "source": null, "fx": "", "hp": actor.hp, "cells": actor.charge_cells.duplicate()})
	return events


## 能不能补位到这一格：己方的空格子，大体型不能动。
func can_move_to(actor: BattleUnit, cell: Vector2i) -> bool:
	return Grid.valid(cell) and not actor.data.big and cell in free_cells(actor.side)


## 补位：走过去，这一回合顺便防御。
func _do_move(actor: BattleUnit, cell: Vector2i) -> void:
	var from := actor.cell()
	actor.row = cell.x
	actor.lane = cell.y
	actor.guarding = true
	_emit("move", actor, "补位", "%s 从%s挪到%s，摆出防御架势" % [actor.display_name(), Grid.cell_name(from), Grid.cell_name(cell)])


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
	_events.back()["area"] = actor.data.basic_area
	stats.add(actor, "attacks")
	for h in area_targets(actor, target, actor.data.basic_area):
		_deal(actor, h[0], h[1], false, true)
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
		if not p.kind in [&"hit", &"snipe"]:
			stats.add(actor, "pursuits")
		match p.kind:
			&"hit", &"snipe":
				_hit_fx = "sword_slash"
				_in_pursuit = true
				_deal(actor, t, p.power)
				_in_pursuit = false
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
## 打单个敌人的效果按绝招的范围（多人、穿透、连锁、全范围）展开到几个人；头目蓄满的绝招打预警的格子里的人。
func _do_skill(actor: BattleUnit, wanted: BattleUnit, skill: SkillData = null) -> void:
	var s := skill if skill != null else actor.data.skill
	var cells: Array[Vector2i] = []
	if actor.charging and skill == null:
		actor.charging = false
		_charge_mult = CHARGE_BONUS
		cells = actor.charge_cells
		actor.charge_cells = []
	if skill == null:
		# 机变：冷却少 1 回合，最少 1 回合
		actor.skill_cooldown = maxi(s.cooldown - 1, 1) if actor.has_gear(&"nimble") else s.cooldown
		actor.skill_cooldown_total = actor.skill_cooldown
	_emit("skill", actor, s.display_name, "%s 使用「%s」" % [actor.display_name(), s.display_name])
	# 给画面用：这一招的范围、是不是蓄满的大招、砸哪几格
	_events.back()["area"] = s.effective_area()
	_events.back()["charged"] = _charge_mult > 1.0
	_events.back()["cells"] = cells.duplicate()
	if skill == null:
		stats.add(actor, "skills")
	_hit_fx = SKILL_FX.get(s.effect, "")
	# 这一招打谁：[[人, 倍数], ...]
	var hits := []
	if _charge_mult > 1.0 and not cells.is_empty():
		for f in foes_of(actor):
			if f.cells().any(func(c: Vector2i) -> bool: return c in cells):
				hits.append([f, 1.0])
		if hits.is_empty() and s.effect not in [SkillData.Effect.TEAM_HASTE, SkillData.Effect.HEAL, SkillData.Effect.TEAM_ATK, SkillData.Effect.TAUNT, SkillData.Effect.SUMMON]:
			_emit("info", actor, "扑空", "%s 的「%s」扑了个空" % [actor.display_name(), s.display_name])
	elif s.effect in SkillData.ALL_EFFECTS:
		hits = foes_of(actor).map(func(f: BattleUnit) -> Array: return [f, 1.0])
	elif s.effect == SkillData.Effect.BACKSTAB:
		# 绕过嘲讽和卡位，打预告里的目标（预告时血量比例最低的人）
		var t := wanted if wanted != null and wanted.is_alive() else _weakest(foes_of(actor))
		hits = area_targets(actor, t, s.area)
	elif s.needs_enemy_target():
		hits = area_targets(actor, _pick_foe(actor, wanted), s.area)
	match s.effect:
		SkillData.Effect.DAMAGE, SkillData.Effect.BACKSTAB:
			for h in hits:
				_deal(actor, h[0], s.power * h[1])
		SkillData.Effect.EXECUTE:
			for h in hits:
				var target: BattleUnit = h[0]
				var low := target.hp_ratio() < EXECUTE_THRESHOLD
				if low:
					_emit("info", target, "残血", "%s 伤重难支，伤害翻倍" % target.display_name())
				_deal(actor, target, s.power * h[1] * (2.0 if low else 1.0))
		SkillData.Effect.MULTI_HIT:
			for i in s.hits:
				var live := hits.filter(func(h: Array) -> bool: return h[0].is_alive())
				if live.is_empty():
					var t := _pick_foe(actor, null)
					if t == null:
						break
					hits = [[t, 1.0]]
					live = hits
				for h in live:
					_deal(actor, h[0], s.power * h[1])
		SkillData.Effect.SURE_CRIT:
			for h in hits:
				_deal(actor, h[0], s.power * h[1], true)
		SkillData.Effect.TAUNT:
			for h in hits:
				_deal(actor, h[0], s.power * h[1])
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
			for h in hits:
				if _stun(actor, h[0], s.turns):
					_emit("info", h[0], "眩晕", "%s 被放倒了" % h[0].display_name())
		SkillData.Effect.STEAL:
			var target: BattleUnit = hits[0][0] if not hits.is_empty() else null
			if target != null:
				_steal(actor, target)
			_extra_action = true
			_emit("info", actor, "再动", "%s 立刻再行动一次" % actor.display_name())
		SkillData.Effect.HEAL:
			var k := 1.0 + float(actor.formation_mods.get("heal", 0.0))
			for ally in allies_of(actor):
				var amount := mini(roundi(ally.max_hp * s.amount * k), ally.max_hp - ally.hp)
				ally.hp += amount
				stats.add(actor, "healed", amount, round_number())
				ally.stun_turns = 0
				ally.disarm_turns = 0
				ally.silence_turns = 0
				ally.burn_turns = 0
				_emit("heal", ally, "+%d" % amount, "")
			_emit("info", actor, "", "%s 为全队疗伤" % actor.display_name())
		SkillData.Effect.GUARD_STRIKE:
			for h in hits:
				_deal(actor, h[0], s.power * h[1])
			var shield := roundi(actor.max_hp * s.amount)
			for ally in allies_of(actor):
				ally.shield += shield
				stats.add(actor, "shielded", shield)
				_emit("info", ally, "护盾 +%d" % shield, "")
		SkillData.Effect.PIERCE:
			for h in hits:
				_deal(actor, h[0], s.power * h[1], false, false, true)
		SkillData.Effect.ALL_FOES:
			for h in hits:
				_deal(actor, h[0], s.power * h[1])
		SkillData.Effect.ALL_FOES_SLOW:
			for h in hits:
				var foe: BattleUnit = h[0]
				_deal(actor, foe, s.power * h[1])
				if foe.is_alive():
					foe.add_buff(BattleUnit.Buff.new("踩踏", 0.0, -s.amount, s.turns))
					_emit("info", foe, "减速", "")
		SkillData.Effect.ALL_FOES_RAGE:
			var k := 1.0 + s.amount * actor.rage / BattleUnit.RAGE_MAX
			if actor.rage >= BattleUnit.RAGE_MAX / 2:
				_emit("info", actor, "怒火", "%s 怒火正盛，伤害 ×%.1f" % [actor.display_name(), k])
			for h in hits:
				_deal(actor, h[0], s.power * k * h[1])
		SkillData.Effect.ALL_FOES_BURN:
			var burn := maxi(1, roundi(actor.atk() * s.amount))
			for h in hits:
				var foe: BattleUnit = h[0]
				_deal(actor, foe, s.power * h[1])
				if foe.is_alive():
					foe.burn_damage = maxi(foe.burn_damage if foe.burn_turns > 0 else 0, burn)
					foe.burn_turns = maxi(foe.burn_turns, s.turns)
					foe.burn_source = units.find(actor)
					_emit("info", foe, "灼烧", "")
		SkillData.Effect.ALL_FOES_MULTI:
			for i in s.hits:
				for h in hits:
					_deal(actor, h[0], s.power * h[1])
		SkillData.Effect.CRIPPLE:
			for h in hits:
				var target: BattleUnit = h[0]
				_deal(actor, target, s.power * h[1])
				if target.is_alive():
					target.add_buff(BattleUnit.Buff.new("断筋", 0.0, -s.amount, s.turns))
					_emit("info", target, "减速", "%s 行动变慢了" % target.display_name())
		SkillData.Effect.WEAKEN_ALL:
			for h in hits:
				h[0].add_buff(BattleUnit.Buff.new("醉", -s.amount, 0.0, s.turns))
				_emit("info", h[0], "减攻", "")
			_emit("info", actor, "", "敌方全体攻击下降")
		SkillData.Effect.TEAM_ATK:
			for ally in allies_of(actor):
				ally.add_buff(BattleUnit.Buff.new(s.display_name, s.amount, 0.0, s.turns))
				_emit("info", ally, "增攻", "")
			_emit("info", actor, "", "全队攻击提升")
		SkillData.Effect.STUN_ALL:
			for h in hits:
				if _stun(actor, h[0], s.turns):
					_emit("info", h[0], "昏睡", "")
			_emit("info", actor, "", "敌方全体被麻翻了")
		SkillData.Effect.DISARM, SkillData.Effect.SILENCE:
			for h in hits:
				var target: BattleUnit = h[0]
				if s.power > 0.0:
					_deal(actor, target, s.power * h[1])
				if target.is_alive():
					_control(actor, target, &"disarm" if s.effect == SkillData.Effect.DISARM else &"silence", s.turns)
		SkillData.Effect.SUMMON:
			_summon(actor, s)
	if s.exposes:
		for h in hits:
			if h[0].is_alive():
				_expose(h[0])
	_hit_fx = ""
	_charge_mult = 1.0
	actor.add_rage(RAGE_ON_SKILL)


## 偷取：先偷对方身上的一个增益；没有增益就偷属性——对方攻击和速度各 -STEAL_STAT，自己各 +STEAL_STAT，持续 STEAL_TURNS 回合。
func _steal(actor: BattleUnit, target: BattleUnit) -> void:
	# 只偷增益，减益（减攻、减速）不偷
	var gains := target.buffs.filter(func(b: BattleUnit.Buff) -> bool: return b.atk_bonus >= 0.0 and b.spd_bonus >= 0.0 and b.turns_left < BattleUnit.PERMANENT_TURNS)
	if not gains.is_empty():
		var b: BattleUnit.Buff = gains.back()
		target.buffs.erase(b)
		actor.add_buff(b)
		_emit("steal", actor, "偷到 " + b.name, "%s 偷走了 %s 的「%s」" % [actor.display_name(), target.display_name(), b.name], false, target)
		return
	target.add_buff(BattleUnit.Buff.new("被偷", -STEAL_STAT, 0.0, STEAL_TURNS))
	target.add_buff(BattleUnit.Buff.new("被偷", 0.0, -STEAL_STAT, STEAL_TURNS))
	actor.add_buff(BattleUnit.Buff.new("偷来的力气", STEAL_STAT, 0.0, STEAL_TURNS))
	actor.add_buff(BattleUnit.Buff.new("偷来的身法", 0.0, STEAL_STAT, STEAL_TURNS))
	_emit("steal", actor, "偷到 攻击、速度", "%s 从 %s 身上偷走了两成攻击和速度" % [actor.display_name(), target.display_name()], false, target)


## 召唤：把召唤物放进己方的空格子（前排先放），属性按施放者折算。每方最多 MAX_SUMMONS 个。
func _summon(actor: BattleUnit, s: SkillData) -> void:
	if s.summon == null:
		return
	var have := alive(actor.side).filter(func(u: BattleUnit) -> bool: return u.is_summon()).size()
	var free := free_cells(actor.side)
	var made := 0
	for i in s.hits:
		if have + made >= MAX_SUMMONS or free.is_empty():
			break
		var c: Vector2i = free.pop_front()
		var data: UnitData = s.summon.duplicate()
		var u := BattleUnit.new(data, actor.side, units.size(), actor.level)
		u.set_summon_stats(roundi(actor.max_hp * s.amount), actor.atk() * s.power)
		u.row = c.x
		u.lane = c.y
		u.summoner = actor
		u.summon_turns = s.turns
		u.next_time = time + TIME_PER_ACTION / u.spd()
		units.append(u)
		made += 1
		_emit("summon", u, data.display_name, "%s 召出了%s，站在%s" % [actor.display_name(), data.display_name, Grid.cell_name(c)], false, actor)
	if made == 0:
		_emit("info", actor, "召不出", "格子满了，召不出来")


func _do_combo(actor: BattleUnit, combo: ComboData, wanted: BattleUnit) -> void:
	var a := _find_ally(actor, combo.hero_a)
	var b := _find_ally(actor, combo.hero_b)
	# 结义同心：统领在阵外，由结义兄弟一个人放
	if a == null:
		a = b
	# 结义同心由好汉一个人怒气满就能放；统领怒气没满时不扣他的
	if combo.effect != ComboData.Effect.SWORN or a.has_full_rage() or a == b:
		a.rage = 0
	b.rage = 0
	stats.add(a, "combos")
	if b != a:
		stats.add(b, "combos")
	_emit("combo", a, combo.display_name, "%s + %s 发动组合技「%s」" % [a.display_name(), b.display_name(), combo.display_name], false, b)
	match combo.effect:
		ComboData.Effect.SHIELD_STRIKE:
			for ally in allies_of(actor):
				var amount := roundi(ally.max_hp * combo.amount)
				ally.shield += amount
				stats.add(a, "shielded", amount)
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
				stats.add(a, "healed", healed, round_number())
				ally.stun_turns = 0
				ally.disarm_turns = 0
				ally.silence_turns = 0
				ally.add_rage(combo.rage_gain)
				_emit("heal", ally, "+%d" % healed, "")
		ComboData.Effect.SWORN:
			_deal(a, _pick_foe(a, wanted), combo.power)
			if b.data.skill != null and not foes_of(b).is_empty():
				_do_skill(b, wanted if wanted != null and wanted.is_alive() else null, Stars.upgraded_skill(b.data.skill))


## 按设计文档的公式结算一次伤害，返回造成的伤害（含被护盾吸收的部分；被闪开返回 0）。basic 表示普攻（「铁甲」只减普攻）。
## 物理伤害看防御、能被闪避；道士的法术伤害看法抗、闪不开。force_crit（必中必暴）也闪不开。
func _deal(attacker: BattleUnit, target: BattleUnit, multiplier: float, force_crit := false, basic := false, pierce := false) -> int:
	if target == null or not target.is_alive():
		return 0
	var magic := Roles.is_magic(attacker.data.role)
	if not magic and not force_crit:
		var dodge := Roles.dodge_chance(target.agi())
		if attacker.data.role == UnitData.Role.ARCHER:
			dodge *= Roles.ARCHER_DODGE_FACTOR
		if dodge > 0.0 and rng.randf() < dodge:
			stats.add(target, "dodges")
			_emit("dodge", target, "闪", "%s 闪开了 %s 的攻击" % [target.display_name(), attacker.display_name()], false, attacker)
			return 0
	var role := attacker.data.role
	var crit_chance := Roles.CRIT_CHANCE[role] + attacker.crit_bonus + (Equipment.KEEN_CRIT if attacker.has_gear(&"keen") else 0.0)
	if attacker.hp_ratio() < 0.5:
		crit_chance += attacker.talent(&"low_hp_crit")
	var crit := force_crit or attacker.first_crit_ready or rng.randf() < crit_chance
	attacker.first_crit_ready = false
	var def := 0.0 if pierce else (target.res() if magic else target.def())
	# 防御的「基准」跟着挨打的人的等级一起成长：防御挡掉的比例只看自己的防御，前期后期一样
	var base := DEF_BASE * pow(BattleUnit.LEVEL_GROWTH, target.level - 1)
	var raw := attacker.atk() * multiplier * _charge_mult * base / (base + def) * rng.randf_range(0.95, 1.05)
	if crit:
		raw *= Roles.CRIT_MULT[role]
	if basic and role == UnitData.Role.ASSASSIN:
		raw *= Roles.ASSASSIN_BASIC_MULT
	raw *= Roles.melee_multiplier(role, target.data.role)
	if attacker.misplaced():
		raw *= 1.0 - Roles.MISPLACED_PENALTY
	if target.guarding:
		raw *= 1.0 - GUARD_REDUCTION
	if target.reduction_turns >= 0:
		raw *= 1.0 - target.reduction
	if basic and target.data.elite_trait == &"iron" and not attacker.has_gear(&"armor_break"):
		raw *= IRON_BASIC_MULTIPLIER
	if target.data.is_boss:
		raw *= 1.0 + attacker.talent(&"boss_slayer")
	raw *= 1.0 - target.talent(&"tough")
	raw *= target.taken_mult * (1.0 + float(target.formation_mods.get("taken", 0.0)))
	if target.broken_turns > 0:
		raw *= 1.0 + BROKEN_TAKEN
	var countered := Roles.exploits(role, target.data.role)
	if countered:
		raw *= 1.0 - target.talent(&"anti_counter")
	var exposed := target.expose_turns > 0
	if exposed:
		raw *= 1.0 + EXPOSE_BONUS
		target.expose_turns = 0
	var amount := maxi(1, roundi(raw))
	var absorbed := mini(target.shield, amount)
	target.shield -= absorbed
	var bars_before := _bars_left(target)
	target.hp = maxi(target.hp - (amount - absorbed), 0)
	stats.damage(attacker, target, amount, round_number(), crit, _in_pursuit)
	var popup := ("克 " if countered else "") + ("绽 " if exposed else "") + ("暴击 -%d" if crit else "-%d") % amount
	var log_text := "%s 对 %s 造成 %d%s伤害" % [attacker.display_name(), target.display_name(), amount, "法术" if magic else ""]
	if countered:
		log_text += Roles.matchup_text(role, target.data.role)
	_emit("damage", target, popup, log_text, crit, attacker)
	_events.back()["magic"] = magic
	if crit and attacker.has_talent(&"crit_haste"):
		var t := attacker.passive(&"crit_haste")
		if attacker.buffs.filter(func(b: BattleUnit.Buff) -> bool: return b.name == t.display_name).size() < TalentData.CRIT_HASTE_STACKS:
			attacker.add_buff(BattleUnit.Buff.new(t.display_name, 0.0, attacker.talent(&"crit_haste"), WHOLE_BATTLE))
			_emit("info", attacker, "加速", "%s「%s」，越打越快" % [attacker.display_name(), t.display_name])
	if not target.is_alive():
		stats.add(attacker, "kills")
		_on_death(target)
	elif target.data.is_boss:
		if _bars_left(target) < bars_before:
			_emit("bar", target, "", "%s 的血条又碎了一管" % target.display_name())
		_wear_toughness(target, (TOUGHNESS_BASIC if basic else TOUGHNESS_SKILL) * (2 if countered else 1))
		_check_phase(target)
	if target.is_alive() and target.side == BattleUnit.Side.PLAYER and attacker.is_alive():
		_formation_react(attacker, target)
	return amount


## 头目还剩几管血（向上取整）。
func _bars_left(u: BattleUnit) -> int:
	return ceili(float(u.hp) / u.max_hp * u.data.boss_bars) if u.data.is_boss else 0


## 削头目的韧性，打空就破绽。
func _wear_toughness(boss: BattleUnit, amount: int) -> void:
	if boss.broken_turns > 0 or not boss.is_alive():
		return
	boss.toughness = maxi(boss.toughness - amount, 0)
	if boss.toughness == 0:
		_break(boss)


## 破绽：韧性打空，跪地一回合（跳过）、受到伤害 +30%，正在蓄的大招作废、重新冷却。跪完韧性回满。
func _break(boss: BattleUnit) -> void:
	boss.broken_turns = 1
	boss.stun_turns = maxi(boss.stun_turns, 1)
	if boss.charging:
		boss.charging = false
		boss.charge_cells = []
		if boss.data.skill != null:
			boss.skill_cooldown = boss.data.skill.cooldown
			boss.skill_cooldown_total = boss.skill_cooldown
		boss.intent_skill = false
		_emit("banner", boss, "破绽", "%s 韧性被打空，蓄的大招散了！跪地一回合，受到的伤害 +%d%%" % [boss.display_name(), roundi(BROKEN_TAKEN * 100)])
	else:
		_emit("banner", boss, "破绽", "%s 韧性被打空，跪地一回合，受到的伤害 +%d%%" % [boss.display_name(), roundi(BROKEN_TAKEN * 100)])


## 头目血量过了 60%、30% 换阶段：第二阶段狂暴（原来的「半血狂暴」挪到这里），有备好的绝招就换上。
func _check_phase(boss: BattleUnit) -> void:
	while boss.phase <= PHASE_LINES.size() and boss.hp_ratio() < PHASE_LINES[boss.phase - 1]:
		boss.phase += 1
		var new_skill: SkillData = boss.data.phase_skills[boss.phase - 2] if boss.data.phase_skills.size() >= boss.phase - 1 else null
		if new_skill != null:
			boss.data = boss.data.duplicate()
			boss.data.skill = new_skill
		var text := "%s 进入第%s阶段" % [boss.display_name(), ["", "一", "二", "三"][boss.phase]]
		if boss.phase == 2 and boss.data.enrage_name != "" and not boss.enraged:
			boss.enraged = true
			boss.add_buff(BattleUnit.Buff.new(boss.data.enrage_name, boss.data.enrage_atk_bonus, 0.0, boss.data.enrage_turns))
			text += "，「%s」攻击大幅提升" % boss.data.enrage_name
		if new_skill != null:
			text += "，换上了「%s」" % new_skill.display_name
		_emit("phase", boss, boss.data.enrage_name if boss.phase == 2 and boss.data.enrage_name != "" else "第%s阶段" % ["", "一", "二", "三"][boss.phase], text + "！")


## 阵法的反击：长蛇阵蛇头（阵眼）挨打，蛇尾追击；偃月阵敌人近战打中路，两只月角各夹击一下。
func _formation_react(attacker: BattleUnit, target: BattleUnit) -> void:
	if _reacting:
		return
	_reacting = true
	for ally in alive(target.side):
		if ally == target or not attacker.is_alive():
			continue
		if ally.formation_mods.has("tail") and target.formation_eye:
			_emit("info", ally, "尾应", "击首尾应：%s 追击 %s" % [ally.display_name(), attacker.display_name()])
			_deal(ally, attacker, ally.formation_mods["tail"])
		elif ally.formation_mods.has("horn") and target.lane == 1 and attacker.is_melee():
			_emit("info", ally, "夹击", "月角夹击：%s 截住 %s" % [ally.display_name(), attacker.display_name()])
			_deal(ally, attacker, ally.formation_mods["horn"])
	_reacting = false


# --- 内部工具 ---

## 眩晕 turns 回合。
func _stun(actor: BattleUnit, target: BattleUnit, turns: int) -> bool:
	return _control(actor, target, &"stun", turns)


const CONTROL_NAMES := {&"stun": "眩晕", &"disarm": "缴械", &"silence": "计穷"}
## 能打断蓄力的技能 → 它上的控制
const CONTROL_EFFECTS := {SkillData.Effect.STUN: &"stun", SkillData.Effect.STUN_ALL: &"stun", SkillData.Effect.DISARM: &"disarm", SkillData.Effect.SILENCE: &"silence"}

## 上一种控制（眩晕、缴械、计穷）：同种不叠加，取较长的回合；站在八卦阵太极上的人多 1 回合。
## 头目不吃控制，改成削一大截韧性（打中弱点削双倍），削空就破绽。返回控制是否生效。
func _control(actor: BattleUnit, target: BattleUnit, kind: StringName, turns: int) -> bool:
	stats.add(actor, "controls")
	if target.data.is_boss:
		var k := 2 if Roles.exploits(actor.data.role, target.data.role) else 1
		_emit("info", target, "韧性 -%d" % (TOUGHNESS_CONTROL * k), "%s 不吃%s，韧性被削去一截" % [target.display_name(), CONTROL_NAMES[kind]])
		_wear_toughness(target, TOUGHNESS_CONTROL * k)
		return false
	var n := turns + int(float(actor.formation_mods.get("control", 0)))
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
	if unit.side == BattleUnit.Side.PLAYER and not unit.is_summon():
		player_deaths += 1
	unit.burn_turns = 0
	_emit("death", unit, "倒下", "%s 倒下了" % unit.display_name())
	# 召唤者倒下，召唤物一起消散
	for u in alive(unit.side):
		if u.summoner == unit:
			_vanish(u)
	if unit.formation_eye and not unit.formation_mods.is_empty():
		Formations.break_formation(alive(unit.side))
		unit.formation_mods.clear()
		_emit("banner", unit, "破阵", "阵眼上的%s倒下，「%s」被破，阵法加成全部消失！" % [unit.display_name(), Formations.display_name(formation_id)])
	if unit.data.id == COMMANDER_ID and unit.side == BattleUnit.Side.PLAYER:
		for u in alive(unit.side):
			u.add_buff(BattleUnit.Buff.new("士气受挫", -MORALE_LOSS, 0.0, WHOLE_BATTLE))
		_emit("banner", unit, "士气受挫", "统领倒下，全队攻击 -%d%%" % roundi(MORALE_LOSS * 100))


## 召唤物消散（时间到了，或者召唤者倒下）。
func _vanish(u: BattleUnit) -> void:
	u.hp = 0
	_emit("death", u, "消散", "%s 消散了" % u.display_name())



## 装备的开战效果：疾风加速。
func _apply_opening_gear(u: BattleUnit) -> void:
	if u.has_gear(&"swift"):
		u.add_buff(BattleUnit.Buff.new("疾风", 0.0, Equipment.SWIFT_BONUS, Equipment.SWIFT_TURNS))
		_emit("prep", u, "疾风", "%s「疾风」：速度 +%d%%，%d 回合" % [u.display_name(), roundi(Equipment.SWIFT_BONUS * 100), Equipment.SWIFT_TURNS])


## 开战时生效的天赋和秘籍：加怒气、加攻、加速、回春、减伤，或者给敌人计穷、减攻。
func _apply_opening_talent(u: BattleUnit) -> void:
	for p in u.passives():
		_apply_opening_passive(u, p[0], p[1])


func _apply_opening_passive(u: BattleUnit, t: TalentData, rank: int) -> void:
	var v := t.value(rank)
	var allies := allies_of(u)
	if t.kind in TalentData.OPENING_KINDS:
		_emit("prep", u, t.display_name, "%s「%s」：%s" % [u.display_name(), t.display_name, t.describe(rank)])
	match t.kind:
		&"team_guard_open":
			for a in allies:
				a.reduction = maxf(a.reduction, v)
				a.reduction_turns = maxi(a.reduction_turns, 2)
		&"open_silence":
			var strongest: BattleUnit = null
			for f in foes_of(u):
				if strongest == null or f.atk() > strongest.atk():
					strongest = f
			if strongest != null:
				_control(u, strongest, &"silence", 2)
		&"open_weaken":
			for f in foes_of(u):
				f.add_buff(BattleUnit.Buff.new(t.display_name, -v, 0.0, 2))
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
	if actor.is_summon() and actor.summon_turns > 0 and actor.is_alive():
		actor.summon_turns -= 1
		if actor.summon_turns == 0:
			_vanish(actor)
	if not _extra_action:
		actor.next_time = time + TIME_PER_ACTION / actor.spd()
	_extra_action = false
	if actor.side == BattleUnit.Side.ENEMY and actor.is_alive():
		_plan_intent(actor)
	if alive(BattleUnit.Side.ENEMY).is_empty():
		result = Result.WIN
	elif alive(BattleUnit.Side.PLAYER).is_empty():
		result = Result.LOSE


## 定下敌人下一回合要做什么，让玩家提前应对。技能在下回合能用就预告技能。
## 挑目标只在打得到的人里挑：背后捅刀瞄准血量比例最低的；刺客专找治疗、道士；射手、道士爱点后排；近战先找同一路的。
func _plan_intent(enemy: BattleUnit) -> void:
	var foes := reachable_foes(enemy)
	if foes.is_empty():
		return
	# 冷却在轮到自己时才减 1，所以现在 ≤ 1 就代表下回合可用
	enemy.intent_skill = enemy.data.skill != null and enemy.skill_cooldown <= 1
	# 蓄力中的头目盯住原来的目标不换
	if enemy.charging and enemy.intent_target != null and enemy.intent_target.is_alive():
		return
	if enemy.intent_skill and enemy.data.skill.effect == SkillData.Effect.BACKSTAB:
		enemy.intent_target = _weakest(foes_of(enemy))
		return
	var pool := foes
	match enemy.data.role:
		UnitData.Role.ASSASSIN:
			var soft := foes.filter(func(u: BattleUnit) -> bool: return u.data.role in [UnitData.Role.HEALER, UnitData.Role.TAOIST])
			if not soft.is_empty():
				pool = soft
		UnitData.Role.ARCHER, UnitData.Role.TAOIST:
			var back := foes.filter(func(u: BattleUnit) -> bool: return u.row == 1)
			if not back.is_empty() and rng.randf() < 0.6:
				pool = back
		_:
			var same := foes.filter(func(u: BattleUnit) -> bool: return u.lane == enemy.lane)
			if not same.is_empty() and rng.randf() < 0.6:
				pool = same
	var typed: Array[BattleUnit] = []
	typed.assign(pool)
	enemy.intent_target = typed[rng.randi_range(0, typed.size() - 1)]


## 打谁：只在打得到的人里挑（近战被卡位挡着的打不到）。有嘲讽的必须打它；否则打指定目标；
## 没指定（或打不到）就打同一路的、再不然第一个。头目蓄满的绝招直取预告的目标，不吃嘲讽和卡位。
func _pick_foe(actor: BattleUnit, wanted: BattleUnit) -> BattleUnit:
	var foes := reachable_foes(actor)
	if foes.is_empty():
		return null
	if _charge_mult > 1.0 and wanted != null and wanted.is_alive() and wanted.side != actor.side:
		return wanted
	for f in foes:
		if f.is_taunting():
			return f
	if wanted != null and wanted in foes:
		return wanted
	for f in foes:
		if f.lane == actor.lane:
			return f
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
	# hp：这一刻这个人还剩多少血。整个动作是一口气算完的，画面播到这一条时才按它更新血条
	_events.append({"kind": kind, "unit": unit, "popup": popup, "log": log_text, "big": big, "source": source, "fx": _hit_fx if kind == "damage" else "", "hp": unit.hp})

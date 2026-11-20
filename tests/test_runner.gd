# 战斗规则测试 + 数值模拟。
# godot --headless --path . --script res://tests/test_runner.gd
extends SceneTree

const SIM_BATTLES := 300
const SIM_TURN_LIMIT := 500

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_data_loads",
		"test_damage_formula",
		"test_guard_halves_damage",
		"test_faster_unit_acts_first",
		"test_taunt_forces_target",
		"test_stun_skips_turn",
		"test_skill_cooldown",
		"test_execute_doubles_on_low_hp",
		"test_combo_needs_both_full_rage",
		"test_steal_grants_extra_action",
		"test_backstab_intent_ignores_taunt",
		"test_ai_guards_when_threatened",
		"test_map_routes",
		"test_scene_layout",
		"test_guard_strike_shields_team",
		"test_origins_load",
		"test_iron_halves_basic_attacks",
		"test_berserk_doubles_attack",
		"test_encounter_levels",
		"test_rewards",
		"test_bounties_and_events_data",
		"test_gacha",
		"test_stars",
		"test_equipment",
		"test_story_script_parse",
		"test_story_data",
		"test_martial_data",
		"test_scene_links",
		"test_world_roads",
		"test_gear_effects",
		"test_new_skill_effects",
		"test_steal_skips_debuffs",
		"test_hero_pool_tiers",
		"test_simulated_win_rate",
	]:
		if call(t) != true:
			failed += 1
			push_error("FAIL %s: did not finish (runtime error?)" % t)
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("FAIL " + label)


func check_eq(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s: expected %s, got %s" % [label, expected, actual])


# --- 帮助函数 ---

func unit_data(id: StringName, stats: Array, skill: SkillData = null) -> UnitData:
	var u := UnitData.new()
	u.id = id
	u.display_name = String(id)
	u.base_hp = stats[0]
	u.base_atk = stats[1]
	u.base_def = stats[2]
	u.base_spd = stats[3]
	u.skill = skill
	return u


func skill(effect: SkillData.Effect, params: Dictionary = {}) -> SkillData:
	var s := SkillData.new()
	s.display_name = "技能"
	s.effect = effect
	for key: String in params:
		s.set(key, params[key])
	return s


func battle(team: Array[UnitData], enemies: Array[UnitData], combos: Array[ComboData] = []) -> BattleModel:
	var stage := StageData.new()
	stage.enemies = enemies
	stage.enemy_level = 1
	return BattleModel.new(stage, team, 1, combos, 42)


func by_id(model: BattleModel, id: StringName) -> BattleUnit:
	for u in model.units:
		if u.data.id == id:
			return u
	return null


## 推进到 id 对应的单位行动为止，其他单位都只防御。
func advance_to(model: BattleModel, id: StringName) -> void:
	for i in 50:
		model.start_next_turn()
		if model.current == null:
			continue
		if model.current.data.id == id:
			return
		model.act(BattleModel.Action.GUARD)
	push_error("advance_to: %s never acted" % id)


# --- 测试 ---

func test_data_loads() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	check_eq(GameDB.load_dir("res://data/heroes/").size(), 20, "20 heroes")
	check_eq(GameDB.load_dir("res://data/combos/").size(), 3, "3 combos")
	var stage: StageData = load("res://data/stages/stage_1_7.tres")
	check_eq(stage.enemies.size(), 3, "stage 1-7 has 3 enemies")
	check(stage.enemies[1].is_boss, "Lu Qian is the boss")
	return true


func test_damage_formula() -> bool:
	# 攻击 100、防御 100：100 × 1.0 × 100/200 = 50，随机 ±5%，暴击 ×1.5
	var m := battle([unit_data(&"a", [500, 100, 0, 100])], [unit_data(&"e", [100000, 1, 100, 1])])
	var a := by_id(m, &"a")
	var e := by_id(m, &"e")
	for i in 50:
		var dmg := m._deal(a, e, 1.0)
		check(dmg >= 47 and dmg <= 79, "damage %d in [47, 79]" % dmg)
	var crit := m._deal(a, e, 1.0, true)
	check(crit >= 71 and crit <= 79, "forced crit %d in [71, 79]" % crit)
	return true


func test_guard_halves_damage() -> bool:
	var m := battle([unit_data(&"a", [500, 100, 0, 100])], [unit_data(&"e", [100000, 1, 100, 1])])
	var e := by_id(m, &"e")
	e.guarding = true
	var dmg := m._deal(by_id(m, &"a"), e, 1.0, true)
	check(dmg >= 35 and dmg <= 40, "guarded crit %d in [35, 40]" % dmg)
	return true


func test_faster_unit_acts_first() -> bool:
	var m := battle([unit_data(&"slow", [500, 10, 10, 80])], [unit_data(&"fast", [500, 10, 10, 120])])
	m.start_next_turn()
	check_eq(m.current.data.id, &"fast", "speed 120 acts before speed 80")
	check_eq(m.turn_order_preview().size(), BattleModel.TURN_PREVIEW_COUNT, "preview length")
	# 速度 120 对 80：前 6 次行动里快的占 4 次
	var fast_count := m.turn_order_preview().filter(func(u: BattleUnit) -> bool: return u.data.id == &"fast").size()
	check_eq(fast_count, 4, "fast acts 4 of 6")
	return true


func test_taunt_forces_target() -> bool:
	var tank := unit_data(&"tank", [5000, 10, 10, 200], skill(SkillData.Effect.TAUNT, {turns = 2, amount = 0.4}))
	var m := battle([tank, unit_data(&"weak", [100, 10, 0, 50])], [unit_data(&"e", [5000, 50, 10, 100])])
	advance_to(m, &"tank")
	m.act(BattleModel.Action.SKILL)
	check(by_id(m, &"tank").is_taunting(), "tank is taunting")
	var weak := by_id(m, &"weak")
	advance_to(m, &"e")
	m.act(BattleModel.Action.ATTACK, weak)
	check_eq(weak.hp, weak.max_hp, "taunt redirects the attack away from weak")
	check(by_id(m, &"tank").hp < by_id(m, &"tank").max_hp, "tank took the hit")
	return true


func test_stun_skips_turn() -> bool:
	var m := battle([unit_data(&"a", [500, 10, 10, 200], skill(SkillData.Effect.STUN, {turns = 1}))], [unit_data(&"e", [500, 10, 10, 100])])
	advance_to(m, &"a")
	m.act(BattleModel.Action.SKILL)
	var e := by_id(m, &"e")
	check_eq(e.stun_turns, 1, "enemy stunned")
	# 下一个轮到敌人时被跳过
	for i in 5:
		m.start_next_turn()
		if m.current == null:
			break
		m.act(BattleModel.Action.GUARD)
	check_eq(e.stun_turns, 0, "stun consumed")
	return true


func test_skill_cooldown() -> bool:
	var m := battle([unit_data(&"a", [500, 10, 10, 100], skill(SkillData.Effect.DAMAGE, {power = 1.0}))], [unit_data(&"e", [100000, 1, 10, 1])])
	var a := by_id(m, &"a")
	advance_to(m, &"a")
	m.act(BattleModel.Action.SKILL)
	var ready_after := 0
	for i in 5:
		advance_to(m, &"a")
		ready_after += 1
		if a.skill_ready():
			break
		m.act(BattleModel.Action.GUARD)
	check_eq(ready_after, 3, "skill ready again on the 3rd turn after use")
	return true


func test_execute_doubles_on_low_hp() -> bool:
	var lin := unit_data(&"lin", [500, 100, 0, 100], skill(SkillData.Effect.EXECUTE, {power = 1.0}))
	var m := battle([lin], [unit_data(&"e", [10000, 1, 100, 1])])
	var e := by_id(m, &"e")
	m.rng.seed = 1
	advance_to(m, &"lin")
	m.act(BattleModel.Action.SKILL, e)
	var normal := e.max_hp - e.hp
	e.hp = int(e.max_hp * 0.2)
	var before := e.hp
	by_id(m, &"lin").skill_cooldown = 0
	advance_to(m, &"lin")
	m.act(BattleModel.Action.SKILL, e)
	var doubled := before - e.hp
	check(doubled > normal * 1.6, "execute on low hp (%d) roughly doubles normal (%d)" % [doubled, normal])
	return true


func test_combo_needs_both_full_rage() -> bool:
	var combo := ComboData.new()
	combo.hero_a = &"lu"
	combo.hero_b = &"lin"
	combo.effect = ComboData.Effect.SHIELD_STRIKE
	combo.amount = 0.2
	combo.power = 4.0
	var m := battle([unit_data(&"lu", [500, 50, 10, 100]), unit_data(&"lin", [500, 50, 10, 90])], [unit_data(&"e", [100000, 1, 10, 1])], [combo])
	var lu := by_id(m, &"lu")
	var lin := by_id(m, &"lin")
	advance_to(m, &"lu")
	lu.rage = 100
	check(m.available_combo(lu) == null, "no combo while partner rage is low")
	lin.rage = 100
	check(m.available_combo(lu) == combo, "combo when both are full")
	m.act(BattleModel.Action.COMBO, by_id(m, &"e"))
	check_eq(lu.rage, 0, "initiator rage spent")
	check_eq(lin.rage, 0, "partner rage spent")
	check_eq(lu.shield, roundi(lu.max_hp * 0.2), "shield granted")
	lin.hp = 0
	lu.rage = 100
	check(m.available_combo(lu) == null, "no combo when partner is down")
	return true


func test_steal_grants_extra_action() -> bool:
	var m := battle([unit_data(&"thief", [500, 10, 10, 100], skill(SkillData.Effect.STEAL))], [unit_data(&"e", [500, 10, 10, 90])])
	var e := by_id(m, &"e")
	e.buffs.append(BattleUnit.Buff.new("狗仗人势", 0.5, 0.0, 3))
	advance_to(m, &"thief")
	m.act(BattleModel.Action.SKILL, e)
	check(e.buffs.is_empty(), "buff removed from enemy")
	check_eq(by_id(m, &"thief").buffs.size(), 1, "thief has the buff")
	m.start_next_turn()
	check(m.current != null and m.current.data.id == &"thief", "thief acts again immediately")
	return true


func test_new_skill_effects() -> bool:
	# 无视防御：同样的攻击，打高防目标比普通伤害高得多
	var m := battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.PIERCE, {power = 1.0}))], [unit_data(&"e", [5000, 10, 300, 10])])
	m.rng.seed = 1
	advance_to(m, &"p")
	var e := by_id(m, &"e")
	m.act(BattleModel.Action.SKILL, e)
	check(e.max_hp - e.hp >= 95, "pierce ignores defense (dealt %d)" % (e.max_hp - e.hp))
	# 全体伤害
	m = battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.ALL_FOES, {power = 1.0}))], [unit_data(&"a", [5000, 10, 10, 10]), unit_data(&"b", [5000, 10, 10, 10])])
	advance_to(m, &"p")
	m.act(BattleModel.Action.SKILL)
	check(by_id(m, &"a").hp < 5000 and by_id(m, &"b").hp < 5000, "all-foes hits everyone")
	# 断筋减速
	m = battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.CRIPPLE, {power = 1.0, amount = 0.3, turns = 2}))], [unit_data(&"e", [5000, 10, 10, 100])])
	advance_to(m, &"p")
	e = by_id(m, &"e")
	m.act(BattleModel.Action.SKILL, e)
	check(is_equal_approx(e.spd(), e._spd * 0.7), "cripple slows the target")
	# 敌全体减攻、全队增攻
	m = battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.WEAKEN_ALL, {amount = 0.25, turns = 2})), unit_data(&"q", [500, 100, 10, 10], skill(SkillData.Effect.TEAM_ATK, {amount = 0.25, turns = 2}))], [unit_data(&"e", [5000, 100, 10, 50])])
	advance_to(m, &"p")
	m.act(BattleModel.Action.SKILL)
	e = by_id(m, &"e")
	check(is_equal_approx(e.atk(), e._atk * 0.75), "weaken lowers enemy attack")
	advance_to(m, &"q")
	m.act(BattleModel.Action.SKILL)
	check(is_equal_approx(by_id(m, &"p").atk(), by_id(m, &"p")._atk * 1.25), "team attack buff")
	# 减益再多，攻击也不低于三成
	for i in 10:
		e.buffs.append(BattleUnit.Buff.new("醉", -0.25, 0.0, 3))
	check(is_equal_approx(e.atk(), e._atk * BattleUnit.MIN_STAT_RATIO), "attack has a floor")
	# 敌全体昏睡
	m = battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.STUN_ALL, {turns = 1}))], [unit_data(&"a", [5000, 10, 10, 10]), unit_data(&"b", [5000, 10, 10, 10])])
	advance_to(m, &"p")
	m.act(BattleModel.Action.SKILL)
	check(by_id(m, &"a").stun_turns == 1 and by_id(m, &"b").stun_turns == 1, "stun-all stuns everyone")
	return true


func test_steal_skips_debuffs() -> bool:
	var m := battle([unit_data(&"thief", [500, 10, 10, 100], skill(SkillData.Effect.STEAL))], [unit_data(&"e", [500, 10, 10, 90])])
	var e := by_id(m, &"e")
	e.buffs.append(BattleUnit.Buff.new("狗仗人势", 0.5, 0.0, 3))
	e.buffs.append(BattleUnit.Buff.new("醉", -0.25, 0.0, 3))
	advance_to(m, &"thief")
	m.act(BattleModel.Action.SKILL, e)
	check_eq(by_id(m, &"thief").buffs.size(), 1, "thief took one buff")
	check_eq(by_id(m, &"thief").buffs[0].name, "狗仗人势", "thief took the gain, not the debuff")
	check_eq(e.buffs.size(), 1, "enemy keeps its debuff")
	return true


func test_hero_pool_tiers() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var counts := [0, 0, 0, 0]
	for res in GameDB.load_dir("res://data/heroes/"):
		var h: UnitData = res
		counts[h.tier] += 1
		check(h.skill != null and h.skill.description != "", "%s has a described skill" % h.display_name)
		check(h.portrait != null and h.bust != null and h.face != null, "%s has art" % h.display_name)
	check_eq(counts, [4, 5, 6, 5], "tier spread 甲4 乙5 丙6 丁5")
	return true


func test_backstab_intent_ignores_taunt() -> bool:
	var tank := unit_data(&"tank", [5000, 10, 10, 200], skill(SkillData.Effect.TAUNT, {turns = 2, amount = 0.4}))
	var boss := unit_data(&"boss", [5000, 50, 10, 100], skill(SkillData.Effect.BACKSTAB, {power = 2.0}))
	var m := battle([tank, unit_data(&"weak", [100, 10, 0, 50])], [boss])
	var weak := by_id(m, &"weak")
	weak.hp = 10
	m._plan_intent(by_id(m, &"boss"))
	advance_to(m, &"tank")
	m.act(BattleModel.Action.SKILL)
	var b := by_id(m, &"boss")
	check(b.intent_skill, "boss plans its skill")
	check(m.intent_target_of(b) == weak, "backstab intent stays on the weakest despite taunt")
	check(m.is_threatened(weak), "weak is threatened")
	b.intent_skill = false
	check(m.intent_target_of(b) == by_id(m, &"tank"), "a plain attack intent is pulled by taunt")
	return true


func test_ai_guards_when_threatened() -> bool:
	var boss := unit_data(&"boss", [5000, 50, 10, 50], skill(SkillData.Effect.BACKSTAB, {power = 2.0}))
	var m := battle([unit_data(&"hero", [500, 10, 10, 100])], [boss])
	var hero := by_id(m, &"hero")
	check(m.is_threatened(hero), "hero is the backstab target")
	advance_to(m, &"hero")
	m.act_ai()
	check(hero.guarding, "auto battle guards against a telegraphed skill")
	return true


func test_map_routes() -> bool:
	var map: WorldMapData = load("res://data/maps/ch1.tres")
	check_eq(map.locations.size(), 11, "the world map has 11 locations")
	var forward := map.route(&"dongjing", &"cangzhou")
	check_eq(forward[0], map.location(&"dongjing").map_position, "route starts at the origin")
	check_eq(forward[forward.size() - 1], map.location(&"cangzhou").map_position, "route ends at the destination")
	var back := map.route(&"cangzhou", &"dongjing")
	back.reverse()
	check_eq(back, forward, "walking back retraces the same road")
	check_eq(map.location(&"dongjing").road_to_next.size(), 5, "road data untouched by route()")
	check(has_stage_file(map.encounter_stage_id), "encounter stage exists")
	return true


func test_scene_layout() -> bool:
	var scene: SceneData = load("res://data/scenes/xiangguosi.tres")
	var rows := scene.rows()
	var width := rows[0].length()
	for r in rows:
		check_eq(r.length(), width, "layout row width")
	for y in rows.size():
		for x in width:
			check(SceneData.TERRAIN.has(rows[y][x]), "known terrain '%s' at %d,%d" % [rows[y][x], x, y])
	check(scene.is_walkable(scene.spawn_cell), "spawn is walkable")
	check(scene.layout.contains("E"), "scene has an exit")
	# 从出生点能走到出口，也能走到每个人物和宝箱旁边
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, scene.size())
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in rows.size():
		for x in width:
			astar.set_point_solid(Vector2i(x, y), not scene.is_walkable(Vector2i(x, y)))
	var targets: Array[Vector2i] = []
	for npc in scene.npcs:
		targets.append(npc.cell)
	for chest in scene.chests:
		targets.append(chest.cell)
	for t in targets:
		astar.set_point_solid(t, true)
	for t in targets:
		var reachable := false
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var spot: Vector2i = t + d
			if astar.is_in_boundsv(spot) and not astar.is_point_solid(spot) and not astar.get_id_path(scene.spawn_cell, spot).is_empty():
				reachable = true
		check(reachable, "object at %s reachable from spawn" % t)
	return true


func test_guard_strike_shields_team() -> bool:
	var escort := unit_data(&"escort", [500, 100, 0, 200], skill(SkillData.Effect.GUARD_STRIKE, {power = 2.0, amount = 0.1}))
	var m := battle([escort, unit_data(&"ally", [800, 10, 0, 50])], [unit_data(&"e", [100000, 1, 100, 1])])
	var e := by_id(m, &"e")
	advance_to(m, &"escort")
	m.act(BattleModel.Action.SKILL, e)
	check(e.hp < e.max_hp, "guard strike deals damage")
	var shield := roundi(by_id(m, &"escort").max_hp * 0.1)
	check_eq(by_id(m, &"escort").shield, shield, "caster gets the shield")
	check_eq(by_id(m, &"ally").shield, shield, "ally gets the same shield")
	return true


func test_origins_load() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var origins: Array[Resource] = GameDB.load_dir("res://data/origins/")
	check_eq(origins.size(), 2, "two origins")
	for res in origins:
		var o := res as OriginData
		check(o.unit != null and o.unit.skill != null, "%s has a unit and a skill" % o.id)
		check(o.unit.rarity == UnitData.Rarity.PROTAGONIST, "%s is marked as protagonist" % o.id)
		check(o.unit.map_sprite != null, "%s has a pixel sprite" % o.id)
	return true


func test_iron_halves_basic_attacks() -> bool:
	var iron := Encounters.make_elite(unit_data(&"e", [100000, 1, 100, 1]), &"iron")
	var m := battle([unit_data(&"a", [500, 100, 0, 100])], [iron])
	var a := by_id(m, &"a")
	var e := by_id(m, &"e")
	var basic := m._deal(a, e, 1.0, true, true)
	var skill_hit := m._deal(a, e, 1.0, true, false)
	check(basic * 2 >= skill_hit - 4 and basic * 2 <= skill_hit + 4, "iron halves a basic hit (%d vs %d)" % [basic, skill_hit])
	check(e.data.display_name.begins_with("铁甲·"), "elite name has its prefix")
	return true


func test_berserk_doubles_attack() -> bool:
	var m := battle([unit_data(&"a", [500, 100, 0, 100])], [Encounters.make_elite(unit_data(&"e", [1000, 50, 0, 1]), &"berserk")])
	var e := by_id(m, &"e")
	var calm := e.atk()
	e.hp = int(e.max_hp * 0.2)
	check_eq(e.atk(), calm * 2.0, "berserk doubles attack below 30% hp")
	return true


func test_encounter_levels() -> bool:
	var map: WorldMapData = load("res://data/maps/ch1.tres")
	var dongjing := map.location(&"dongjing")
	var liangshan := map.location(&"liangshan")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 50:
		var low := Encounters.build(dongjing, 15, rng)
		check(low.enemy_level <= dongjing.level_max, "a strong party still meets weak enemies in Dongjing")
		var high := Encounters.build(liangshan, 1, rng)
		check(high.enemy_level >= liangshan.level_min, "a weak party meets level %d+ enemies at Liangshan" % liangshan.level_min)
		var near := Encounters.build(dongjing, 5, rng)
		check(near.enemy_level == 5 or near.enemy_level == 6, "enemies stay near the party level")
	for loc in map.locations:
		check(loc.unlock_flag == "", "%s is open from the start" % loc.id)
		check(not loc.encounter_groups.is_empty(), "%s has encounter groups" % loc.id)
	return true


func test_rewards() -> bool:
	var stage := StageData.new()
	stage.enemies = [unit_data(&"e1", [1, 1, 0, 1]), Encounters.make_elite(unit_data(&"e2", [1, 1, 0, 1]), &"iron")]
	stage.enemy_level = 4
	var m := BattleModel.new(stage, [unit_data(&"a", [500, 100, 0, 100])], 4, [], 1)
	check_eq(Encounters.rewards(m)["exp"], 0, "no rewards before winning")
	for u in m.units:
		if u.side == BattleUnit.Side.ENEMY:
			u.hp = 0
	m.result = BattleModel.Result.WIN
	var r := Encounters.rewards(m)
	check_eq(r["exp"], 4 * Encounters.EXP_PER_LEVEL * 3, "elite counts double for exp")
	check_eq(r["silver"], 4 * Encounters.SILVER_PER_LEVEL * 3, "elite counts double for silver")
	return true


func test_bounties_and_events_data() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var bounties: Array[Resource] = GameDB.load_dir("res://data/bounties/")
	check_eq(bounties.size(), 6, "six bounties")
	var map: WorldMapData = load("res://data/maps/ch1.tres")
	for res in bounties:
		var b := res as BountyData
		check(map.location(b.location) != null, "bounty %s is at a real location" % b.id)
		check(not b.stage.enemies.is_empty() and b.stage.enemy_level > 0, "bounty %s has a fight" % b.id)
		check(b.tokens() == BountyData.GRADE_TOKENS[b.grade], "bounty %s pays by grade" % b.id)
	var events: Array[Resource] = GameDB.load_dir("res://data/events/")
	check_eq(events.size(), 6, "six roadside events")
	for res in events:
		var e := res as EventData
		check(e.choices.size() >= 2, "event %s offers a real choice" % e.id)
		for loc in e.locations:
			check(map.location(loc) != null, "event %s location %s exists" % [e.id, loc])
	var scene: SceneData = load("res://data/scenes/xiangguosi.tres")
	var li_si: NpcData = scene.npcs.filter(func(n: NpcData) -> bool: return n.id == &"li_si")[0]
	check(li_si.event != null and li_si.event.choices.size() == 3, "garden quest has three choices")
	check(li_si.event.choices.all(func(c: EventChoice) -> bool: return c.flag == "garden_done"), "every garden choice finishes the quest")
	return true


func test_stars() -> bool:
	var h := unit_data(&"h", [1000, 100, 50, 100], skill(SkillData.Effect.DAMAGE, {power = 2.0}))
	h.tier = UnitData.Tier.BING
	check(Stars.apply(h, 1) == h, "1 star returns the original")
	var s3 := Stars.apply(h, 3)
	check_eq(s3.base_hp, 1100, "3 stars: hp +10%")
	check_eq(s3.base_atk, 110, "3 stars: atk +10%")
	check_eq(s3.base_spd, 100, "speed is not boosted")
	check(is_equal_approx(s3.skill.power, 2.5), "3 stars: skill power x1.25")
	check(is_equal_approx(h.skill.power, 2.0), "original skill untouched")
	check(is_equal_approx(Stars.apply(h, 2).skill.power, 2.0), "2 stars: skill not upgraded yet")
	var stun := Stars.upgraded_skill(skill(SkillData.Effect.STUN, {turns = 1}))
	check_eq(stun.turns, 2, "control skills last one more turn")
	check_eq(Stars.max_stars(h), 5, "丙 caps at 5 stars")
	check_eq(Stars.cost(1) + Stars.cost(2) + Stars.cost(3) + Stars.cost(4), 100, "1→5 stars costs 100 souls")
	check_eq(Stars.soul_price(h), 2, "丙 souls cost 2 义气")
	return true


func test_equipment() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var all: Array = GameDB.load_dir("res://data/equipment/")
	check_eq(all.size(), 15, "15 equipment templates")
	var per_quality := [0, 0, 0]
	for res in all:
		var e: EquipData = res
		per_quality[e.quality] += 1
		check_eq(e.effects.size(), e.quality, "%s has %d effects" % [e.display_name, e.quality])
		for fx in e.effects:
			check(EquipData.EFFECTS.has(fx), "%s effect %s is known" % [e.display_name, fx])
	check_eq(per_quality, [6, 6, 3], "6 凡品 6 良品 3 精品")
	var h := unit_data(&"h", [1000, 100, 50, 100])
	var sword := EquipData.new()
	sword.atk_pct = 0.12
	sword.effects.assign([&"keen"])
	var boots := EquipData.new()
	boots.spd_pct = 0.08
	boots.effects.assign([&"swift", &"keen"])
	var geared := Equipment.apply(h, [sword, boots] as Array[EquipData])
	check_eq(geared.base_atk, 112, "weapon adds attack %")
	check_eq(geared.base_spd, 108, "charm adds speed %")
	check_eq(geared.gear_effects.size(), 2, "effects are merged without duplicates")
	check(h.gear_effects.is_empty(), "original data untouched")
	check(Equipment.apply(h, [] as Array[EquipData]) == h, "no gear returns the original")
	return true


func test_gear_effects() -> bool:
	var geared := func(id: StringName, effects: Array, stats := [1000, 100, 10, 100]) -> UnitData:
		var u := unit_data(id, stats)
		u.gear_effects.assign(effects)
		return u
	var m := battle([geared.call(&"p", [&"swift"])], [unit_data(&"e", [5000, 10, 10, 10])])
	var p := by_id(m, &"p")
	check(is_equal_approx(p.spd(), 120.0), "swift speeds up at the start")
	# 机变：冷却少 1 回合
	var quick: UnitData = geared.call(&"q", [&"nimble"], [1000, 10, 10, 200])
	quick.skill = skill(SkillData.Effect.DAMAGE, {power = 1.0, cooldown = 3})
	m = battle([quick], [unit_data(&"e", [5000, 10, 10, 10])])
	advance_to(m, &"q")
	m.act(BattleModel.Action.SKILL, by_id(m, &"e"))
	check_eq(by_id(m, &"q").skill_cooldown, 2, "nimble shortens cooldown by one")
	# 回春：轮到自己时回血
	m = battle([geared.call(&"p", [&"regen"], [1000, 10, 10, 200])], [unit_data(&"e", [5000, 10, 10, 10])])
	p = by_id(m, &"p")
	p.hp = 500
	advance_to(m, &"p")
	check_eq(p.hp, 520, "regen heals 2% at turn start")
	# 破甲：普攻打铁甲不减半
	var iron := unit_data(&"e", [5000, 10, 0, 10])
	iron.elite_trait = &"iron"
	m = battle([geared.call(&"p", [&"armor_break"], [1000, 100, 10, 200]), unit_data(&"q", [1000, 100, 10, 199])], [iron])
	m.rng.seed = 3
	advance_to(m, &"p")
	var e := by_id(m, &"e")
	m.act(BattleModel.Action.ATTACK, e)
	var with_break := e.max_hp - e.hp
	advance_to(m, &"q")
	var before := e.hp
	m.act(BattleModel.Action.ATTACK, e)
	var without := before - e.hp
	check(with_break > without * 1.6, "armor break ignores iron halving (%d vs %d)" % [with_break, without])
	return true


func test_story_script_parse() -> bool:
	var ops := StoryScript.parse("# 注释\n@bg dongjing\n@show left lin_chong\n林冲：台词\n旁白一句\n? 甲 > a\n? 乙 > b\n* a\n@goto end\n* b\n@battle x\n* end")
	check_eq(ops.size(), 10, "comments skipped, choice options grouped")
	check_eq(ops[2]["speaker"], "林冲", "speaker parsed")
	check_eq(ops[3]["speaker"], "", "narration has no speaker")
	check_eq((ops[4]["options"] as Array).size(), 2, "two options in one choice")
	check_eq(StoryScript.find_label(ops, "end"), 9, "label found")
	return true


func test_story_data() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var stories: Array = GameDB.load_dir("res://data/stories/")
	check_eq(stories.size(), 4, "林冲列传 has 4 segments")
	var map: WorldMapData = load("res://data/maps/ch1.tres")
	for res in stories:
		var story: StoryData = res
		check(FileAccess.file_exists(story.script_path), "%s script exists" % story.title)
		check(ResourceLoader.exists("res://data/heroes/%s.tres" % story.hero), "%s hero exists" % story.title)
		check(map.location(story.location) != null, "%s location exists" % story.title)
		var ops := StoryScript.load_file(story.script_path)
		var battles := 0
		for op in ops:
			match op["op"]:
				"bg":
					check(StoryScript.background_path(op["key"]) != "", "%s: background %s has art" % [story.title, op["key"]])
				"show":
					var id: String = op["id"]
					check(id in ["me", "none"] or ResourceLoader.exists("res://data/heroes/%s.tres" % id) or ResourceLoader.exists("res://data/enemies/%s.tres" % id), "%s: unit %s exists" % [story.title, id])
					check(op["side"] in ["left", "right"], "%s: side %s" % [story.title, op["side"]])
				"battle":
					battles += 1
					var path := story.script_path.get_base_dir().path_join(op["stage"] + ".tres")
					check(ResourceLoader.exists(path), "%s: stage %s exists" % [story.title, op["stage"]])
				"choice":
					check((op["options"] as Array).size() <= 3, "%s: at most 3 options" % story.title)
					for option: Dictionary in op["options"]:
						check(StoryScript.find_label(ops, option["label"]) >= 0, "%s: label %s exists" % [story.title, option["label"]])
				"goto":
					check(StoryScript.find_label(ops, op["label"]) >= 0, "%s: goto %s exists" % [story.title, op["label"]])
		check_eq(battles, 1, "%s has one battle" % story.title)
	return true


func test_martial_data() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var all: Array = GameDB.load_dir("res://data/martial/")
	check_eq(all.size(), 5, "5 martial arts")
	for res in all:
		var m: MartialData = res
		check(m.skill != null and m.skill.description != "", "%s has a described skill" % m.display_name)
		check(m.side_summary() != "", "%s has a side bonus" % m.display_name)
		check(m.source != "", "%s says where it is learned" % m.display_name)
	for res in GameDB.load_dir("res://data/origins/"):
		var o: OriginData = res
		check(o.martial != null, "origin %s starts with a martial art" % o.display_name)
	var lin: MartialData = load("res://data/martial/lin_jia_qiang_fa.tres")
	var h := unit_data(&"h", [1000, 100, 50, 100])
	var boosted := Equipment.apply(h, [lin.side_as_gear()] as Array[EquipData])
	check_eq(boosted.base_atk, 108, "林家枪法 side: attack +8%")
	check(&"keen" in boosted.gear_effects, "林家枪法 side: keen")
	var story: StoryData = load("res://data/stories/lin_chong_4.tres")
	check(story.martial == lin, "林冲列传 finale teaches 林家枪法")
	return true


func test_scene_links() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var map: WorldMapData = load("res://data/maps/ch1.tres")
	var ids: Array[String] = []
	var scenes: Array = GameDB.load_dir("res://data/scenes/")
	for res in scenes:
		ids.append((res as SceneData).id)
	for res in scenes:
		var sd: SceneData = res
		check(sd.is_walkable(sd.spawn_cell), "%s spawn is walkable" % sd.id)
		for spot in sd.roam_spots:
			check(sd.is_walkable(spot), "%s roam spot %s is walkable" % [sd.id, spot])
		if not sd.roam_spots.is_empty():
			check(map.location(sd.region) != null, "%s region %s exists" % [sd.id, sd.region])
		for cell in sd.doors:
			check(sd.terrain_at(cell) == "D", "%s door %s sits on a D cell" % [sd.id, cell])
			check(sd.doors[cell] in ids, "%s door leads to an existing scene" % sd.id)
		if sd.exit_scene != "":
			check(sd.exit_scene in ids, "%s exit leads to an existing scene" % sd.id)
			var target: SceneData = scenes.filter(func(r: Resource) -> bool: return (r as SceneData).id == sd.exit_scene)[0]
			check(target.is_walkable(sd.exit_cell), "%s exit cell is walkable in %s" % [sd.id, sd.exit_scene])
		for npc in sd.npcs:
			check(not sd.is_walkable(npc.cell) or sd.terrain_at(npc.cell) in [".", ",", "_"], "%s npc %s stands on open ground" % [sd.id, npc.display_name])
	for loc in map.locations:
		if loc.scene_id != "":
			check(loc.scene_id in ids, "%s scene %s exists" % [loc.display_name, loc.scene_id])
	return true


func test_world_roads() -> bool:
	var map: WorldMapData = load("res://data/maps/ch1.tres")
	for loc in map.locations:
		if loc.id == map.start_location:
			continue
		var pts := map.route(map.start_location, loc.id)
		check(pts.size() >= 2, "%s is reachable by road" % loc.display_name)
		check(pts[0].distance_to(map.location(map.start_location).map_position) < 1.0, "route to %s starts at the start" % loc.display_name)
		check(pts[pts.size() - 1].distance_to(loc.map_position) < 1.0, "route to %s ends at %s" % [loc.display_name, loc.display_name])
		check(Rect2(Vector2.ZERO, map.size).has_point(loc.map_position), "%s is on the map" % loc.display_name)
	for road in map.roads:
		check(map.location(road.a) != null and map.location(road.b) != null, "road %s-%s joins real places" % [road.a, road.b])
	return true


func test_gacha() -> bool:
	var pool: Array[UnitData] = []
	for t in [UnitData.Tier.JIA, UnitData.Tier.YI, UnitData.Tier.BING]:
		var h := unit_data(StringName("h%d" % t), [100, 10, 10, 100])
		h.tier = t
		pool.append(h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 300:
		var out: Dictionary = Gacha.pull(pool, 10, 0, rng)
		var heroes: Array = out["heroes"]
		check(heroes.any(func(h: UnitData) -> bool: return h.tier <= UnitData.Tier.YI), "a ten-pull has at least one 乙 or better")
	var pity: Dictionary = Gacha.pull(pool, 1, Gacha.PITY_JIA - 1, rng)
	check_eq((pity["heroes"][0] as UnitData).tier, UnitData.Tier.JIA, "the 50th pull without a 甲 is a 甲")
	check_eq(pity["pulls_since_jia"], 0, "pity counter resets after a 甲")
	for i in 50:
		var first: Dictionary = Gacha.pull(pool, 10, 0, rng, true)
		check((first["heroes"] as Array).any(func(h: UnitData) -> bool: return h.tier == UnitData.Tier.JIA), "the first ten-pull has a 甲")
	var counts := [0, 0, 0, 0]
	for i in 100000:
		counts[Gacha._roll_tier(rng)] += 1
	for t in 4:
		var pct: float = counts[t] / 1000.0
		check(absf(pct - Gacha.RATES[t]) < 1.0, "tier %d rate %.1f%% close to %d%%" % [t, pct, Gacha.RATES[t]])
	check_eq(Gacha._pick(pool, UnitData.Tier.DING, rng).tier, UnitData.Tier.BING, "an empty 丁 falls back to 丙")
	return true


func has_stage_file(id: String) -> bool:
	return ResourceLoader.exists("res://data/stages/%s.tres" % id.replace("-", "_")) or ResourceLoader.exists("res://data/stages/%s.tres" % id)


## 用设计文档里的默认队伍（鲁智深、林冲、武松）自动打 1-7，看胜率和回合数是否在目标附近。
func test_simulated_win_rate() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var heroes: Dictionary[StringName, UnitData] = {}
	for res in GameDB.load_dir("res://data/heroes/"):
		var h := res as UnitData
		heroes[h.id] = h
	var combos: Array[ComboData] = []
	for res in GameDB.load_dir("res://data/combos/"):
		combos.append(res as ComboData)
	var stage: StageData = load("res://data/stages/stage_1_7.tres")
	for team_ids: Array in [[&"lu_zhishen", &"lin_chong", &"wu_song"], [&"sun_erniang", &"wu_song", &"an_daoquan"], [&"shi_qian", &"wu_yong", &"hua_rong"]]:
		var team: Array[UnitData] = []
		var label := ""
		for id: StringName in team_ids:
			team.append(heroes[id])
			label += heroes[id].display_name
		for run: Array in [[stage.recommended_level, false], [stage.recommended_level - 3, false], [stage.recommended_level, true]]:
			var level: int = run[0]
			var naive: bool = run[1]
			var wins := 0
			var rounds := 0
			var stars := 0
			for n in SIM_BATTLES:
				var m := BattleModel.new(stage, team, level, combos, n)
				var turns := 0
				while m.result == BattleModel.Result.ONGOING and turns < SIM_TURN_LIMIT:
					m.start_next_turn()
					if m.current != null:
						if naive and m.current.side == BattleUnit.Side.PLAYER:
							m.act(BattleModel.Action.ATTACK, m._weakest(m.foes_of(m.current)))
						else:
							m.act_ai()
					turns += 1
				check(m.result != BattleModel.Result.ONGOING, "battle %d ends within %d turns" % [n, SIM_TURN_LIMIT])
				if m.result == BattleModel.Result.WIN:
					wins += 1
					rounds += m.round_number()
					stars += m.stars()
			print("  %s Lv%d%s: win %d%%, avg %.1f rounds, avg %.1f stars" % [
				label, level, "（只点普攻）" if naive else "", wins * 100 / SIM_BATTLES,
				float(rounds) / maxi(wins, 1), float(stars) / maxi(wins, 1)])
	return true

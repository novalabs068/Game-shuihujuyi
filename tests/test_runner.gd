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
		"test_role_counters",
		"test_disarm_and_silence",
		"test_pursuit",
		"test_miji",
		"test_formations_and_factions",
		"test_opening_events",
		"test_same_buffs_do_not_stack",
		"test_expose_and_boss_resist",
		"test_boss_charge",
		"test_defense_scales_with_level",
		"test_danger_and_boss_power",
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
		"test_aoe_skill_effects",
		"test_talents",
		"test_bonds",
		"test_mingqi",
		"test_new_combos",
		"test_vitality",
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
	check_eq(GameDB.load_dir("res://data/heroes/").size(), 24, "24 heroes")
	check_eq(GameDB.load_dir("res://data/combos/").size(), 15, "15 combos")
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


func test_role_counters() -> bool:
	check(Roles.beats(UnitData.Role.WARRIOR, UnitData.Role.ARCHER), "武克射")
	check(Roles.beats(UnitData.Role.ARCHER, UnitData.Role.STRATEGIST), "射克谋")
	check(Roles.beats(UnitData.Role.STRATEGIST, UnitData.Role.TANK), "谋克猛")
	check(Roles.beats(UnitData.Role.TANK, UnitData.Role.MYSTIC), "猛克奇")
	check(Roles.beats(UnitData.Role.MYSTIC, UnitData.Role.WARRIOR), "奇克武")
	check(not Roles.beats(UnitData.Role.WARRIOR, UnitData.Role.TANK), "武和猛不相干")
	check_eq(Roles.beaten_by(UnitData.Role.WARRIOR), UnitData.Role.MYSTIC, "武被奇克")
	# 克制 +20%、被克 -15%：攻击 100、防御 100 的基准伤害 50
	var archer := unit_data(&"e", [100000, 1, 100, 1])
	archer.role = UnitData.Role.ARCHER
	var mystic := unit_data(&"m", [100000, 1, 100, 1])
	mystic.role = UnitData.Role.MYSTIC
	var warrior := unit_data(&"a", [500, 100, 0, 100])
	warrior.role = UnitData.Role.WARRIOR
	var m := battle([warrior], [archer, mystic])
	var a := by_id(m, &"a")
	for i in 20:
		var up := m._deal(a, by_id(m, &"e"), 1.0, true)
		check(up >= 85 and up <= 95, "武打射 crit %d in [85, 95]" % up)
		var down := m._deal(a, by_id(m, &"m"), 1.0, true)
		check(down >= 60 and down <= 67, "武打奇 crit %d in [60, 67]" % down)
	check(m._events.any(func(e: Dictionary) -> bool: return String(e["popup"]).begins_with("克")), "countered hits pop 克")
	# 克制方的眩晕多 1 回合
	m._stun(a, by_id(m, &"e"), 1)
	check_eq(by_id(m, &"e").stun_turns, 2, "advantaged stun lasts one more turn")
	m._stun(a, by_id(m, &"m"), 1)
	check_eq(by_id(m, &"m").stun_turns, 1, "plain stun keeps its turns")
	return true


func test_disarm_and_silence() -> bool:
	var disarm := skill(SkillData.Effect.DISARM, {"power": 0.0, "turns": 1})
	var e := unit_data(&"e", [5000, 50, 0, 50], skill(SkillData.Effect.DAMAGE, {"power": 2.0}))
	var m := battle([unit_data(&"a", [5000, 50, 0, 200], disarm)], [e])
	advance_to(m, &"a")
	m.act(BattleModel.Action.SKILL, by_id(m, &"e"))
	var foe := by_id(m, &"e")
	check_eq(foe.disarm_turns, 1, "disarm lands for 1 turn")
	check(not foe.can_attack(), "disarmed unit cannot attack")
	advance_to(m, &"e")
	var hp_before := by_id(m, &"a").hp
	foe.skill_cooldown = 1  # 让它只能普攻
	m.act(BattleModel.Action.ATTACK, by_id(m, &"a"))
	check_eq(by_id(m, &"a").hp, hp_before, "a disarmed attack turns into guarding")
	check(foe.guarding, "disarmed unit guards instead")
	check_eq(foe.disarm_turns, 0, "disarm wears off after its turn")
	# 计穷：绝招和组合技都放不了
	var silence := skill(SkillData.Effect.SILENCE, {"power": 0.0, "turns": 2})
	var m2 := battle([unit_data(&"a", [5000, 50, 0, 200], silence)], [unit_data(&"e", [5000, 50, 0, 50], skill(SkillData.Effect.DAMAGE, {"power": 2.0}))])
	advance_to(m2, &"a")
	m2.act(BattleModel.Action.SKILL, by_id(m2, &"e"))
	var silenced := by_id(m2, &"e")
	check(not silenced.skill_ready(), "silenced unit's skill is not ready")
	check(silenced.can_attack(), "silence still allows attacks")
	return true


func _pursuer(kind: StringName, chance: float, amount: float) -> UnitData:
	var u := unit_data(&"a", [5000, 100, 0, 200])
	var t := TalentData.new()
	t.display_name = "追"
	t.kind = &"pursuit"
	t.chance = chance
	t.amount = amount
	t.pursuit_kind = kind
	u.talent = t
	u.talent_rank = 1
	return u


func test_pursuit() -> bool:
	# 几率 100%：每次普攻后都追加一下，只追一次
	var m := battle([_pursuer(&"hit", 1.0, 0.5)], [unit_data(&"e", [100000, 1, 0, 1])])
	advance_to(m, &"a")
	var events := m.act(BattleModel.Action.ATTACK, by_id(m, &"e"))
	var hits := events.filter(func(e: Dictionary) -> bool: return e["kind"] == "damage")
	check_eq(hits.size(), 2, "attack + one pursuit hit")
	check(events.any(func(e: Dictionary) -> bool: return e["popup"] == "追击"), "pursuit pops 追击")
	# 几率 0：不追
	var m0 := battle([_pursuer(&"hit", 0.0, 0.5)], [unit_data(&"e", [100000, 1, 0, 1])])
	advance_to(m0, &"a")
	check_eq(m0.act(BattleModel.Action.ATTACK, by_id(m0, &"e")).filter(func(e: Dictionary) -> bool: return e["kind"] == "damage").size(), 1, "no pursuit at 0%")
	# 偷袭：绕开嘲讽，打血最少的
	var tank := unit_data(&"t", [100000, 1, 0, 1])
	var weak := unit_data(&"w", [100000, 1, 0, 1])
	var ms := battle([_pursuer(&"snipe", 1.0, 0.5)], [tank, weak])
	by_id(ms, &"t").taunt_turns = 5
	by_id(ms, &"w").hp = 100
	advance_to(ms, &"a")
	var ev := ms.act(BattleModel.Action.ATTACK, by_id(ms, &"w"))
	var hit_units := ev.filter(func(e: Dictionary) -> bool: return e["kind"] == "damage").map(func(e: Dictionary) -> StringName: return e["unit"].data.id)
	check_eq(hit_units, [&"t", &"w"], "attack hits the taunter, the snipe hits the weakest")
	# 减速
	var mslow := battle([_pursuer(&"slow", 1.0, 0.2)], [unit_data(&"e", [100000, 1, 0, 100])])
	advance_to(mslow, &"a")
	mslow.act(BattleModel.Action.ATTACK, by_id(mslow, &"e"))
	check(by_id(mslow, &"e").spd() < 100.0, "slow pursuit lowers speed")
	# 被缴械不能普攻，也就没有追击
	var md := battle([_pursuer(&"hit", 1.0, 0.5)], [unit_data(&"e", [100000, 1, 0, 1])])
	advance_to(md, &"a")
	by_id(md, &"a").disarm_turns = 1
	check_eq(md.act(BattleModel.Action.ATTACK, by_id(md, &"e")).filter(func(e: Dictionary) -> bool: return e["kind"] == "damage").size(), 0, "disarmed: no attack, no pursuit")
	# 装备特效「追击」也算来源
	var geared := unit_data(&"g", [100, 1, 0, 1])
	geared.gear_effects = [&"pursuit"]
	check_eq(Pursuit.sources_for(BattleUnit.new(geared, BattleUnit.Side.PLAYER, 0, 1)).size(), 1, "gear pursuit is a source")
	# 改成追击型的三位好汉
	for id in [&"shi_jin", &"shi_qian", &"wang_dingliu"]:
		var h: UnitData = load("res://data/heroes/%s.tres" % id)
		check_eq(h.talent.kind, &"pursuit", "%s has a pursuit talent" % id)
		check(h.talent.pursuit_kind in Pursuit.KINDS, "%s pursuit kind is known" % id)
	return true


func _miji_effect(kind: StringName, amount: float, extra := {}) -> TalentData:
	var t := TalentData.new()
	t.display_name = "秘"
	t.kind = kind
	t.amount = amount
	t.text = "{x}"
	for key: String in extra:
		t.set(key, extra[key])
	return t


func test_miji() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var all: Array = GameDB.load_dir("res://data/miji/")
	var heroes: Array = GameDB.load_dir("res://data/heroes/")
	var jue: Array = all.filter(func(m: MijiData) -> bool: return m.quality == MijiData.Quality.JUE)
	check_eq(jue.size(), heroes.size(), "one 绝品秘籍 per hero")
	for h: UnitData in heroes:
		check(jue.any(func(m: MijiData) -> bool: return m.owner == h.id), "%s teaches a 秘籍" % h.display_name)
	for m: MijiData in all:
		check(TalentData.KINDS.has(m.effect.kind), "%s uses a known kind" % m.display_name)
		check(m.summary().find("{x}") < 0, "%s describes itself" % m.display_name)
		if m.effect.kind == &"pursuit":
			check(m.effect.pursuit_kind in Pursuit.KINDS, "%s pursuit kind known" % m.display_name)
		if m.effect.kind == &"effect":
			check(EquipData.EFFECTS.has(m.effect.effect), "%s effect known" % m.display_name)
	for q in [MijiData.Quality.FAN, MijiData.Quality.LIANG, MijiData.Quality.JING]:
		check(all.any(func(m: MijiData) -> bool: return m.quality == q), "there are %s 秘籍" % MijiData.QUALITY_NAMES[q])
	# 属性类秘籍直接改数据；天赋和秘籍同种的数值相加
	var stat_miji := MijiData.new()
	stat_miji.effect = _miji_effect(&"stat", 0.1, {"stats": [&"atk"] as Array[StringName]})
	var base := unit_data(&"a", [100, 100, 10, 100])
	check_eq(Miji.apply(base, stat_miji).base_atk, 110, "stat 秘籍 adds attack")
	check_eq(base.base_atk, 100, "apply copies the unit")
	check(Miji.apply(base, null) == base, "no 秘籍, same unit")
	var tough := unit_data(&"t", [100, 10, 10, 100])
	tough.talent = _miji_effect(&"tough", 0.1)
	tough.talent_rank = 1
	tough.miji_effect = _miji_effect(&"tough", 0.05)
	var tu := BattleUnit.new(tough, BattleUnit.Side.PLAYER, 0, 1)
	check(is_equal_approx(tu.talent(&"tough"), 0.15), "talent and 秘籍 of the same kind add up")
	# 秘籍追击
	var p := unit_data(&"a", [5000, 100, 0, 200])
	p.miji_effect = _miji_effect(&"pursuit", 0.5, {"chance": 1.0, "pursuit_kind": &"hit"})
	check_eq(Pursuit.sources_for(BattleUnit.new(p, BattleUnit.Side.PLAYER, 0, 1)).size(), 1, "秘籍 pursuit is a source")
	# 开局：计穷敌方攻击最高的、全队减伤、敌方减攻
	var wy := unit_data(&"a", [500, 10, 10, 100])
	wy.miji_effect = _miji_effect(&"open_silence", 0.0)
	var m := battle([wy], [unit_data(&"weak", [500, 10, 10, 100]), unit_data(&"strong", [500, 90, 10, 100])])
	check_eq(by_id(m, &"strong").silence_turns, 2, "open_silence hits the strongest foe")
	check_eq(by_id(m, &"weak").silence_turns, 0, "others are fine")
	check(m.opening_events.any(func(e: Dictionary) -> bool: return e["kind"] == "prep"), "秘籍 shows in the 准备回合")
	var guard := unit_data(&"a", [500, 10, 10, 100])
	guard.miji_effect = _miji_effect(&"team_guard_open", 0.15)
	var weak := unit_data(&"e", [500, 10, 10, 100])
	var mg := battle([guard, unit_data(&"b", [500, 10, 10, 100])], [weak])
	check(is_equal_approx(by_id(mg, &"b").reduction, 0.15), "team_guard_open protects allies")
	check(by_id(mg, &"e").reduction_turns < 0, "not the enemy")
	# 运功：轮到自己时回血、解控
	var healer := unit_data(&"a", [1000, 10, 10, 100])
	healer.miji_effect = _miji_effect(&"cleanse_regen", 0.05)
	var mh := battle([healer], [unit_data(&"e", [500, 10, 10, 50])])
	var h := by_id(mh, &"a")
	h.hp = 500
	h.stun_turns = 1
	mh.start_next_turn()
	check_eq(h.hp, 550, "cleanse_regen heals 5%")
	check(mh.current == h, "cleanse_regen clears the stun before it bites")
	# 破计：被克时少挨打
	var anti := unit_data(&"e", [100000, 1, 100, 1])
	anti.role = UnitData.Role.ARCHER
	anti.miji_effect = _miji_effect(&"anti_counter", 0.2)
	var warrior := unit_data(&"a", [500, 100, 0, 100])
	warrior.role = UnitData.Role.WARRIOR
	var ma := battle([warrior], [anti])
	for i in 10:
		var dmg := ma._deal(by_id(ma, &"a"), by_id(ma, &"e"), 1.0, true)
		check(dmg >= 68 and dmg <= 76, "anti_counter cuts the counter hit (%d)" % dmg)
	return true


func test_formations_and_factions() -> bool:
	for id: StringName in Formations.ALL:
		check(Formations.display_name(id) != "", "formation %s has a name" % id)
	check_eq(Formations.unlock_condition(Formations.DEFAULT), "", "the default formation is open from the start")
	var lead := unit_data(&"p", [1000, 100, 50, 100])
	var h1 := unit_data(&"lu_zhishen", [1000, 100, 50, 100])
	var h2 := unit_data(&"yang_zhi", [1000, 100, 50, 100])
	var foe := unit_data(&"e", [1000, 100, 50, 100])
	var stage := StageData.new()
	stage.enemies = [foe]
	var team: Array[UnitData] = [lead, h1, h2]
	# 鱼鳞阵：好汉防御 +20%，主角不变
	var m := BattleModel.new(stage, team, 1, [], 1, &"yu_lin")
	check_eq(roundi(by_id(m, &"lu_zhishen").def()), 60, "鱼鳞阵 raises a hero's defense")
	check_eq(roundi(by_id(m, &"p").def()), 50, "the protagonist is unchanged")
	check(m.opening_events.any(func(e: Dictionary) -> bool: return String(e["log"]).begins_with("阵法")), "the formation shows in the 准备回合")
	# 鲁智深 + 杨志 同出二龙山：全队生命 +8%
	check_eq(Factions.shared([&"lu_zhishen", &"yang_zhi"] as Array[StringName]), &"er_long_shan", "both from 二龙山")
	check_eq(Factions.shared([&"lu_zhishen", &"lin_chong"] as Array[StringName]), &"", "different 山头")
	check_eq(by_id(m, &"p").max_hp, 1080, "山头 bonus reaches the whole team")
	# 八卦阵：敌方减攻 3 回合
	var mb := BattleModel.new(stage, team, 1, [], 1, &"ba_gua")
	check(by_id(mb, &"e").atk() < 100.0, "八卦阵 weakens the enemy")
	# 长蛇阵：主角多挨打
	var mc := BattleModel.new(stage, team, 1, [], 1, &"chang_she")
	check(is_equal_approx(by_id(mc, &"p").taken_mult, 1.15), "长蛇阵 lead takes more")
	check(is_equal_approx(by_id(mc, &"yang_zhi").taken_mult, 0.9), "长蛇阵 heroes take less")
	# 不摆阵、不同山头：什么也不加
	var plain := BattleModel.new(stage, [lead, h1, unit_data(&"x", [1000, 100, 50, 100])] as Array[UnitData], 1, [], 1)
	check(plain.opening_events.is_empty(), "no formation, no 山头, nothing to show")
	return true


func test_opening_events() -> bool:
	var u := unit_data(&"a", [500, 10, 10, 100])
	u.gear_effects = [&"swift"]
	var m := battle([u], [unit_data(&"e", [500, 10, 10, 100])])
	check_eq(m.opening_events.size(), 1, "swift shows up in the 准备回合")
	check_eq(m.opening_events[0]["kind"], "prep", "opening events are prep events")
	var plain := battle([unit_data(&"a", [500, 10, 10, 100])], [unit_data(&"e", [500, 10, 10, 100])])
	check(plain.opening_events.is_empty(), "nothing to show without opening effects")
	return true


func test_same_buffs_do_not_stack() -> bool:
	var u := BattleUnit.new(unit_data(&"a", [100, 100, 0, 100]), BattleUnit.Side.PLAYER, 0, 1)
	u.add_buff(BattleUnit.Buff.new("醉", -0.25, 0.0, 2))
	u.add_buff(BattleUnit.Buff.new("醉", -0.25, 0.0, 2))
	u.add_buff(BattleUnit.Buff.new("另一种减攻", -0.1, 0.0, 4))
	check_eq(u.buffs.size(), 1, "attack debuffs merge into one")
	check(is_equal_approx(u.buffs[0].atk_bonus, -0.25), "the stronger value is kept")
	check_eq(u.buffs[0].turns_left, 4, "the longer duration is kept")
	u.add_buff(BattleUnit.Buff.new("踩踏", 0.0, -0.2, 2))
	check_eq(u.buffs.size(), 2, "a slow is a different kind")
	u.add_buff(BattleUnit.Buff.new("天赋", 0.1, 0.0, BattleModel.WHOLE_BATTLE))
	u.add_buff(BattleUnit.Buff.new("天赋", 0.1, 0.0, BattleModel.WHOLE_BATTLE))
	check_eq(u.buffs.size(), 4, "whole-battle talent buffs stay separate")
	return true


func test_expose_and_boss_resist() -> bool:
	var m := battle([unit_data(&"a", [500, 100, 0, 100])], [unit_data(&"e", [100000, 1, 100, 1])])
	var a := by_id(m, &"a")
	var e := by_id(m, &"e")
	m._expose(e)
	var hit := m._deal(a, e, 1.0, true)
	check(hit >= 85 and hit <= 95, "exposed crit %d in [85, 95]" % hit)
	check_eq(e.expose_turns, 0, "expose is used up by one hit")
	var normal := m._deal(a, e, 1.0, true)
	check(normal >= 71 and normal <= 79, "next hit is normal again (%d)" % normal)
	# 头目：眩晕结束后的那一回合里，再眩晕无效
	var boss := unit_data(&"b", [100000, 1, 0, 100])
	boss.is_boss = true
	var m2 := battle([unit_data(&"a", [500, 1, 0, 100])], [boss])
	var b := by_id(m2, &"b")
	advance_to(m2, &"a")
	check(m2._stun(by_id(m2, &"a"), b, 1), "first stun lands")
	m2.act(BattleModel.Action.GUARD)
	advance_to(m2, &"a")  # 头目这回合被跳过，定力开始
	check(b.resists(&"stun"), "boss resists stun right after one")
	check(not m2._stun(by_id(m2, &"a"), b, 1), "second stun is resisted")
	m2.act(BattleModel.Action.GUARD)
	advance_to(m2, &"a")  # 头目又动了一次，定力还剩一回合
	check(b.resists(&"stun"), "resist lasts two boss turns")
	m2.act(BattleModel.Action.GUARD)
	advance_to(m2, &"a")  # 再动一次，定力过去
	check(not b.resists(&"stun"), "resist wears off after the boss acts twice")
	check(m2._stun(by_id(m2, &"a"), b, 1), "stun works again")
	# 普通敌人没有定力
	var m3 := battle([unit_data(&"a", [500, 1, 0, 100])], [unit_data(&"e", [100000, 1, 0, 100])])
	m3._stun(by_id(m3, &"a"), by_id(m3, &"e"), 1)
	advance_to(m3, &"a")
	check(m3._stun(by_id(m3, &"a"), by_id(m3, &"e"), 1), "regular enemies can be stunned again")
	return true


func test_boss_charge() -> bool:
	var boss := unit_data(&"b", [100000, 100, 0, 100], skill(SkillData.Effect.DAMAGE, {"power": 2.0, "cooldown": 3}))
	boss.is_boss = true
	var m := battle([unit_data(&"a", [100000, 1, 0, 90])], [boss])
	var b := by_id(m, &"b")
	var a := by_id(m, &"a")
	advance_to(m, &"b")
	check(not m.is_threatened(a), "before the charge the boss only gets ready")
	var ev := m.act_ai()
	check(b.charging, "a boss charges before its skill")
	check_eq(ev[0]["kind"], "charge", "the charge is announced first")
	check_eq(ev.filter(func(e: Dictionary) -> bool: return e["kind"] == "damage").size(), 1, "the boss still attacks while charging")
	check(m.is_threatened(a), "after charging, the release is the next hit")
	m.start_next_turn()
	m.act(BattleModel.Action.ATTACK, b)
	m.start_next_turn()
	var hp := a.hp
	m.act_ai()
	var dealt := hp - a.hp
	# 攻击 100 × 2.0 × 1.4 = 280（±5%），不蓄力是 200
	check(dealt >= 266 and dealt <= 294, "charged skill hits ×1.4 (%d)" % dealt)
	check(not b.charging, "the charge is spent")
	# 蓄力中被眩晕：打断，重新冷却，露出破绽
	var boss2 := unit_data(&"b", [100000, 100, 0, 100], skill(SkillData.Effect.DAMAGE, {"power": 2.0, "cooldown": 3}))
	boss2.is_boss = true
	var m2 := battle([unit_data(&"a", [100000, 1, 0, 90])], [boss2])
	advance_to(m2, &"b")
	m2.act_ai()
	var b2 := by_id(m2, &"b")
	check(m2._stun(by_id(m2, &"a"), b2, 1), "stun lands on a charging boss")
	check(not b2.charging, "stun interrupts the charge")
	check_eq(b2.skill_cooldown, 3, "the skill goes back on cooldown")
	check(b2.expose_turns > 0, "an interrupted boss is exposed")
	# 头目身上的控制最多 1 回合
	var boss3 := unit_data(&"b", [100000, 100, 0, 100])
	boss3.is_boss = true
	var m4 := battle([unit_data(&"a", [100000, 1, 0, 90])], [boss3])
	m4._stun(by_id(m4, &"a"), by_id(m4, &"b"), 3)
	check_eq(by_id(m4, &"b").stun_turns, 1, "a boss is stunned for at most 1 turn")
	# 蓄满的绝招不吃嘲讽：打预告里的人
	var boss4 := unit_data(&"b", [100000, 100, 0, 100], skill(SkillData.Effect.DAMAGE, {"power": 2.0, "cooldown": 3}))
	boss4.is_boss = true
	var m5 := battle([unit_data(&"tank", [100000, 1, 0, 80]), unit_data(&"soft", [100000, 1, 0, 70])], [boss4])
	advance_to(m5, &"b")
	m5.act_ai()
	var b5 := by_id(m5, &"b")
	b5.intent_target = by_id(m5, &"soft")
	by_id(m5, &"tank").taunt_turns = 5
	check(m5.intent_target_of(b5) == by_id(m5, &"soft"), "a charged boss ignores taunt in its intent")
	var soft_hp := by_id(m5, &"soft").hp
	advance_to(m5, &"b")
	m5.act_ai()
	check(by_id(m5, &"soft").hp < soft_hp, "the charged blow lands on the announced target")
	# 普通敌人不蓄力
	var m3 := battle([unit_data(&"a", [100000, 1, 0, 90])], [unit_data(&"e", [100000, 100, 0, 100], skill(SkillData.Effect.DAMAGE, {"power": 2.0}))])
	advance_to(m3, &"e")
	m3.act_ai()
	check(not by_id(m3, &"e").charging, "regular enemies don't charge")
	return true


func test_defense_scales_with_level() -> bool:
	# 同级相打，防御挡掉的比例前期后期一样：同一对人 1 级和 20 级的「伤害 / 对方生命」相同
	var ratios: Array[float] = []
	for level in [1, 20]:
		var stage := StageData.new()
		stage.enemies = [unit_data(&"e", [1000, 50, 60, 1])]
		stage.enemy_level = level
		var team: Array[UnitData] = [unit_data(&"a", [800, 80, 40, 100])]
		var m := BattleModel.new(stage, team, level, [], 1)
		var a := by_id(m, &"a")
		var e := by_id(m, &"e")
		var total := 0
		for i in 40:
			total += m._deal(a, e, 1.0, true)
			e.hp = e.max_hp
		ratios.append(float(total) / 40 / e.max_hp)
	check(absf(ratios[0] - ratios[1]) / ratios[0] < 0.03, "damage share at Lv1 %.4f ≈ Lv20 %.4f" % ratios)
	return true


func test_danger_and_boss_power() -> bool:
	var map: WorldMapData = load("res://data/maps/ch1.tres")
	var liangshan := map.location(&"liangshan")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 30:
		var st := Encounters.build(liangshan, 28, rng)
		check(st.enemy_level >= 26, "danger %d region follows a Lv28 party (got %d)" % [liangshan.danger, st.enemy_level])
		check(is_equal_approx(st.enemy_power, 1.0 + Encounters.POWER_PER_DANGER * (liangshan.danger - 1)), "enemy power follows danger")
	check(is_equal_approx(Encounters.power_of(1), 1.0), "one-star regions are unchanged")
	check(Encounters.elite_chance(4) > Encounters.elite_chance(1), "more elites in dangerous regions")
	# 敌人加强在开战时生效，头目再乘上 boss_power
	var stage := StageData.new()
	var boss := unit_data(&"b", [1000, 100, 50, 1])
	boss.is_boss = true
	stage.enemies = [unit_data(&"e", [1000, 100, 50, 1]), boss]
	stage.enemy_power = 1.5
	stage.boss_power = 2.0
	var team: Array[UnitData] = [unit_data(&"a", [500, 10, 10, 100])]
	var m := BattleModel.new(stage, team, 1, [], 1)
	check_eq(by_id(m, &"e").max_hp, 1500, "regular enemy gets enemy_power")
	check_eq(by_id(m, &"b").max_hp, 3000, "boss gets enemy_power × boss_power")
	check_eq(roundi(by_id(m, &"b").def()), 100, "boss defense follows boss_power only")
	# 养成翻倍，头目也跟着翻倍；没养成就不变
	var raw: Array[UnitData] = [unit_data(&"x", [100, 10, 10, 100])]
	var grown: Array[UnitData] = [unit_data(&"x", [200, 20, 20, 100])]
	check(is_equal_approx(Encounters.boss_power(raw, raw), 1.0), "no growth, no boss boost")
	check(is_equal_approx(Encounters.boss_power(raw, grown), 1.0 + Encounters.BOSS_GROWTH_SHARE), "boss keeps up with growth")
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


func test_aoe_skill_effects() -> bool:
	var foes: Array[UnitData] = [unit_data(&"a", [5000, 10, 100, 100]), unit_data(&"b", [5000, 10, 100, 100])]
	# 连环马：全体挨打并减速
	var m := battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.ALL_FOES_SLOW, {power = 1.0, amount = 0.3, turns = 2}))], foes)
	advance_to(m, &"p")
	m.act(BattleModel.Action.SKILL)
	for id: StringName in [&"a", &"b"]:
		var u := by_id(m, id)
		check(u.hp < 5000 and is_equal_approx(u.spd(), 70.0), "slow-all hits and slows %s" % id)
	# 烈火燎原：怒气越高越疼，满怒时翻倍，不消耗怒气
	var blaze := skill(SkillData.Effect.ALL_FOES_RAGE, {power = 1.0, amount = 1.0})
	m = battle([unit_data(&"p", [500, 100, 10, 200], blaze)], [unit_data(&"e", [50000, 10, 0, 10])])
	advance_to(m, &"p")
	m.act(BattleModel.Action.SKILL)
	var calm := 50000 - by_id(m, &"e").hp
	m = battle([unit_data(&"p", [500, 100, 10, 200], blaze)], [unit_data(&"e", [50000, 10, 0, 10])])
	advance_to(m, &"p")
	m.current.rage = BattleUnit.RAGE_MAX
	m.act(BattleModel.Action.SKILL)
	check(50000 - by_id(m, &"e").hp > calm * 1.8, "rage-all nearly doubles at full rage")
	check_eq(by_id(m, &"p").rage, BattleUnit.RAGE_MAX, "rage-all keeps the rage")
	# 轰天雷：全体灼烧，轮到时掉血（无视防御），烧完就停
	m = battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.ALL_FOES_BURN, {power = 1.0, amount = 0.4, turns = 2}))], foes)
	advance_to(m, &"p")
	m.act(BattleModel.Action.SKILL)
	var a := by_id(m, &"a")
	check_eq(a.burn_turns, 2, "burn lasts 2 turns")
	check(a.status_tags().has("灼烧"), "burn shows as a status")
	var before := a.hp
	advance_to(m, &"a")
	check_eq(before - a.hp, 40, "burn deals 40% of the caster's attack")
	m.act(BattleModel.Action.GUARD)
	advance_to(m, &"a")
	m.act(BattleModel.Action.GUARD)
	before = a.hp
	advance_to(m, &"a")
	check_eq(a.hp, before, "burn stops after its turns")
	# 灼烧烧死最后一个敌人：直接赢
	m = battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.ALL_FOES_BURN, {power = 0.01, amount = 0.4, turns = 2}))], [unit_data(&"e", [5000, 10, 10, 100])])
	advance_to(m, &"p")
	m.act(BattleModel.Action.SKILL)
	by_id(m, &"e").hp = 10
	for i in 6:
		m.start_next_turn()
		if m.result != BattleModel.Result.ONGOING:
			break
		if m.current != null:
			m.act(BattleModel.Action.GUARD)
	check_eq(m.result, BattleModel.Result.WIN, "burning to death wins the fight")
	# 旋风卷地：全体连打两轮
	m = battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.ALL_FOES_MULTI, {power = 0.5, hits = 2}))], foes)
	advance_to(m, &"p")
	var hits_on_b := m.act(BattleModel.Action.SKILL).filter(func(e: Dictionary) -> bool: return e["kind"] == "damage" and e["unit"] == by_id(m, &"b"))
	check_eq(hits_on_b.size(), 2, "multi-all hits each foe twice")
	# 群攻技能的命中带上各自的特效
	m = battle([unit_data(&"p", [500, 100, 10, 200], skill(SkillData.Effect.ALL_FOES_BURN, {power = 1.0, amount = 0.4, turns = 2}))], foes)
	advance_to(m, &"p")
	var events := m.act(BattleModel.Action.SKILL)
	var hits := events.filter(func(e: Dictionary) -> bool: return e["kind"] == "damage")
	check(hits.size() == 2 and hits.all(func(e: Dictionary) -> bool: return e["fx"] == "explosion"), "burn hits carry the explosion fx")
	return true


func talent(kind: StringName, amount := 0.0, extra := {}) -> TalentData:
	var t := TalentData.new()
	t.display_name = "天赋"
	t.kind = kind
	t.amount = amount
	for key: String in extra:
		if extra[key] is Array:
			(t.get(key) as Array).assign(extra[key])
		else:
			t.set(key, extra[key])
	return t


## 带一个已解锁天赋的单位（rank 1）。
func with_talent(u: UnitData, t: TalentData, rank := 1) -> UnitData:
	u.talent = t
	u.talent_rank = rank
	return u


func test_talents() -> bool:
	# 档次：一颗没亮未解锁，亮了解锁，全亮强化；强化后数值 ×1.5
	var h := unit_data(&"h", [1000, 100, 100, 100], skill(SkillData.Effect.DAMAGE, {power = 2.0}))
	h.tier = UnitData.Tier.DING
	h.talent = talent(&"stat", 0.1, {stats = [&"atk"]})
	check_eq(Stars.talent_rank(h, 1), 0, "no lit magatama: talent locked")
	check_eq(Stars.talent_rank(h, 2), 1, "1 lit: talent unlocked")
	check_eq(Stars.talent_rank(h, Stars.max_stars(h)), 2, "all lit: talent enhanced")
	check_eq(Stars.apply(h, 2).base_atk, roundi(roundi(100 * 1.1) * 1.1), "stat talent adds attack on top of the star bonus")
	check_eq(Stars.apply(h, 3).base_atk, roundi(roundi(100 * 1.2) * 1.15), "enhanced stat talent is x1.5")
	# 特效类天赋和装备特效合在一起
	h.talent = talent(&"effect", 0.0, {effect = &"keen"})
	var gear := EquipData.new()
	gear.effects = [&"swift"]
	var geared := Equipment.apply(Stars.apply(h, 2), [gear] as Array[EquipData])
	check(&"keen" in geared.gear_effects and &"swift" in geared.gear_effects, "talent effect survives equipment")
	check_eq(Stars.apply(h, 3).base_atk, roundi(roundi(100 * 1.2) * 1.1), "enhanced effect talent gives +10% attack")
	h.talent = talent(&"skill_power", 0.15)
	check(is_equal_approx(Stars.apply(h, 2).skill.power, 2.0 * 1.15), "skill-power talent")
	check(is_equal_approx(h.skill.power, 2.0), "original skill untouched")

	# 首击必暴；打头目加伤；受伤减免
	var archer := with_talent(unit_data(&"a", [500, 100, 0, 200]), talent(&"first_crit"))
	var boss := unit_data(&"boss", [50000, 1, 0, 1])
	boss.is_boss = true
	var m := battle([archer], [boss])
	advance_to(m, &"a")
	var events := m.act(BattleModel.Action.ATTACK, by_id(m, &"boss"))
	check(events.any(func(e: Dictionary) -> bool: return e["kind"] == "damage" and e["big"]), "first attack crits")
	check(not by_id(m, &"a").first_crit_ready, "only the first attack")
	m = battle([unit_data(&"p", [500, 100, 0, 200])], [boss])
	advance_to(m, &"p")
	m.act(BattleModel.Action.ATTACK, by_id(m, &"boss"))
	var plain := 50000 - by_id(m, &"boss").hp
	m = battle([with_talent(unit_data(&"p", [500, 100, 0, 200]), talent(&"boss_slayer", 0.3))], [boss])
	advance_to(m, &"p")
	m.act(BattleModel.Action.ATTACK, by_id(m, &"boss"))
	check(50000 - by_id(m, &"boss").hp > plain * 1.2, "boss slayer hits bosses harder")
	var tank := with_talent(unit_data(&"t", [50000, 1, 0, 1]), talent(&"tough", 0.5))
	m = battle([tank], [unit_data(&"e", [500, 100, 0, 200])])
	advance_to(m, &"e")
	m.act(BattleModel.Action.ATTACK, by_id(m, &"t"))
	check(50000 - by_id(m, &"t").hp <= 55, "tough halves damage taken")

	# 残血加攻；暴击加速叠 3 层
	var berserker := with_talent(unit_data(&"k", [1000, 100, 0, 100]), talent(&"bloodlust", 0.4))
	m = battle([berserker], [unit_data(&"e", [500, 1, 0, 1])])
	var k := by_id(m, &"k")
	check(is_equal_approx(k.atk(), 100.0), "bloodlust off at full hp")
	k.hp = 400
	check(is_equal_approx(k.atk(), 140.0), "bloodlust on below half")
	var leopard := with_talent(unit_data(&"l", [1000, 100, 0, 100]), talent(&"crit_haste", 0.1))
	m = battle([leopard], [unit_data(&"e", [500000, 1, 0, 1])])
	advance_to(m, &"l")
	for i in 5:
		m._deal(by_id(m, &"l"), by_id(m, &"e"), 1.0, true)
	check(is_equal_approx(by_id(m, &"l").spd(), 130.0), "crit haste stacks to 3")

	# 开战时：怒气、全队怒气、全队攻击、全队加速、全队回春
	var team: Array[UnitData] = [
		with_talent(unit_data(&"qin", [500, 10, 0, 100]), talent(&"rage_start", 30.0)),
		with_talent(unit_data(&"shi", [500, 10, 0, 100]), talent(&"team_rage_start", 15.0)),
		with_talent(unit_data(&"wu", [500, 100, 0, 100]), talent(&"team_atk", 0.08)),
	]
	m = battle(team, [unit_data(&"e", [500, 1, 0, 1])])
	check_eq(by_id(m, &"qin").rage, 45, "rage start: own 30 + team 15")
	check_eq(by_id(m, &"wu").rage, 15, "team rage start")
	check(is_equal_approx(by_id(m, &"qin").atk(), 10 * 1.08), "team attack aura")
	team = [with_talent(unit_data(&"zhu", [500, 10, 0, 100]), talent(&"team_haste_open", 0.15), 2), with_talent(unit_data(&"an", [500, 10, 0, 100]), talent(&"team_regen"))]
	m = battle(team, [unit_data(&"e", [500, 1, 0, 1])])
	check(is_equal_approx(by_id(m, &"an").spd(), 100 * 1.225), "enhanced team haste")
	check(by_id(m, &"zhu").has_gear(&"regen"), "team regen")
	# 卡池里每个好汉都有天赋
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	for res in GameDB.load_dir("res://data/heroes/"):
		var hero: UnitData = res
		check(hero.talent != null and hero.talent.kind in TalentData.KINDS and hero.talent.describe(1) != "", "%s has a talent" % hero.display_name)
		check(not hero.talent.describe(1).contains("{x}"), "%s talent text filled" % hero.display_name)
	return true


func test_bonds() -> bool:
	check_eq(Bonds.level(0), 0, "相识 at 0")
	check_eq(Bonds.level(29), 0, "still 相识 at 29")
	check_eq(Bonds.level(30), 1, "相熟 at 30")
	check_eq(Bonds.level(500), 3, "知己 caps")
	check_eq(Bonds.progress_text(45), "相熟（45 / 80）", "progress text")
	check_eq(Bonds.progress_text(200), "知己", "max progress text")
	var h := unit_data(&"h", [1000, 100, 100, 100])
	check(Bonds.apply(h, 0) == h, "no bonus at 相识")
	check_eq(Bonds.apply(h, 80).base_atk, 106, "相知 gives +6%")
	check_eq(Bonds.apply(h, 80).base_spd, 100, "speed untouched")
	return true


func test_mingqi() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var all: Array = GameDB.load_dir("res://data/equipment/")
	var heroes: Array = GameDB.load_dir("res://data/heroes/")
	var flags: Array[String] = []
	for res in GameDB.load_dir("res://data/stories/"):
		flags.append((res as StoryData).flag())
	for res in GameDB.load_dir("res://data/bounties/"):
		flags.append("bounty_" + String((res as BountyData).id))
	for res in GameDB.load_dir("res://data/scenes/"):
		var sd: SceneData = res
		for c in sd.chests:
			flags.append("chest_%s_%s" % [sd.id, c.id])
	var weapons_of := {}
	var sources: Array[String] = []
	for res in all:
		var e: EquipData = res
		if e.quality != EquipData.Quality.MING:
			continue
		check(e.owner == &"" or heroes.any(func(h: UnitData) -> bool: return h.id == e.owner), "%s owner exists" % e.display_name)
		if e.slot == EquipData.Slot.WEAPON:
			weapons_of[e.owner] = weapons_of.get(e.owner, 0) + 1
		if e.source == "":
			continue
		check(not e.source in sources, "%s source is not shared" % e.display_name)
		sources.append(e.source)
		if e.source.begins_with("arena:"):
			check(int(e.source.get_slice(":", 1)) in range(1, 11), "%s arena round exists" % e.display_name)
		else:
			check(e.source in flags, "%s source %s exists" % [e.display_name, e.source])
		check(e.source_text != "", "%s says where it comes from" % e.display_name)
	for res in heroes:
		check_eq(weapons_of.get((res as UnitData).id, 0), 1, "%s has one signature weapon" % (res as UnitData).display_name)
	# 专属：只有原主人装着才强化绝招
	var lin := unit_data(&"lin_chong", [1000, 100, 50, 100], skill(SkillData.Effect.DAMAGE, {power = 2.0}))
	var other := unit_data(&"wu_song", [1000, 100, 50, 100], skill(SkillData.Effect.DAMAGE, {power = 2.0}))
	var spear: EquipData = load("res://data/equipment/zhang_ba_she_mao.tres")
	check(is_equal_approx(Equipment.apply(lin, [spear] as Array[EquipData]).skill.power, 2.5), "owner gets the exclusive boost")
	check(is_equal_approx(Equipment.apply(other, [spear] as Array[EquipData]).skill.power, 2.0), "others only get stats")
	check(not spear.can_sell(), "名器 can't be sold")
	# 随机掉落不出名器和马
	var rng := RandomNumberGenerator.new()
	for i in 50:
		var drop := Equipment.random_of(all, EquipData.Quality.FAN, rng)
		check(drop.slot != EquipData.Slot.MOUNT, "random drops are never horses")
	var horse: EquipData = load("res://data/equipment/huang_biao_ma.tres")
	check_eq(horse.buy_price(), EquipData.MOUNT_PRICE, "horses cost more")
	check(horse.summary().contains("赶路"), "horse summary mentions travel")
	return true


func combo(id: StringName, a: StringName, b: StringName, effect: ComboData.Effect, params := {}) -> ComboData:
	var c := ComboData.new()
	c.id = id
	c.display_name = String(id)
	c.hero_a = a
	c.hero_b = b
	c.effect = effect
	for key: String in params:
		c.set(key, params[key])
	return c


func test_new_combos() -> bool:
	var foes: Array[UnitData] = [unit_data(&"x", [50000, 1, 0, 1]), unit_data(&"y", [50000, 1, 0, 1])]
	# 全体连打
	var c := combo(&"aoe", &"a", &"b", ComboData.Effect.ALL_FOES_COMBO, {power = 1.0, hits = 2})
	var m := battle([unit_data(&"a", [500, 100, 0, 200]), unit_data(&"b", [500, 100, 0, 10])], foes, [c])
	advance_to(m, &"a")
	by_id(m, &"a").rage = BattleUnit.RAGE_MAX
	by_id(m, &"b").rage = BattleUnit.RAGE_MAX
	var events := m.act(BattleModel.Action.COMBO)
	check_eq(events.filter(func(e: Dictionary) -> bool: return e["kind"] == "damage").size(), 4, "all-foes combo hits each foe twice")
	check(by_id(m, &"a").rage < BattleUnit.RAGE_MAX, "combo spends rage")
	# 全队疗伤回怒
	c = combo(&"heal", &"a", &"b", ComboData.Effect.HEAL_RAGE, {amount = 0.3, rage_gain = 20})
	m = battle([unit_data(&"a", [1000, 10, 0, 200]), unit_data(&"b", [1000, 10, 0, 10])], foes, [c])
	advance_to(m, &"a")
	by_id(m, &"b").hp = 100
	by_id(m, &"b").stun_turns = 2
	by_id(m, &"a").rage = BattleUnit.RAGE_MAX
	by_id(m, &"b").rage = BattleUnit.RAGE_MAX
	m.act(BattleModel.Action.COMBO)
	check_eq(by_id(m, &"b").hp, 400, "heal combo restores 30%")
	check_eq(by_id(m, &"b").stun_turns, 0, "heal combo clears stun")
	check_eq(by_id(m, &"b").rage, 20, "heal combo gives rage")
	# 结义同心：主角先打，好汉放一次强化过的绝招，不进冷却
	var hero := unit_data(&"h", [1000, 100, 0, 10], skill(SkillData.Effect.DAMAGE, {power = 2.0, cooldown = 4}))
	hero.display_name = "好汉"
	c = Bonds.sworn_combo(hero, &"me")
	check(c.description.contains("好汉"), "sworn combo names the hero")
	m = battle([unit_data(&"me", [1000, 100, 0, 200]), hero], [unit_data(&"x", [50000, 1, 0, 1])], [c])
	advance_to(m, &"me")
	by_id(m, &"me").rage = BattleUnit.RAGE_MAX
	by_id(m, &"h").rage = BattleUnit.RAGE_MAX
	events = m.act(BattleModel.Action.COMBO, by_id(m, &"x"))
	check(events.any(func(e: Dictionary) -> bool: return e["kind"] == "skill" and e["unit"] == by_id(m, &"h")), "sworn brother casts his skill")
	check_eq(events.filter(func(e: Dictionary) -> bool: return e["kind"] == "damage").size(), 2, "protagonist hit + skill hit")
	check_eq(by_id(m, &"h").skill_cooldown, 0, "borrowed skill does not go on cooldown")
	# 组合技数据：两人都在卡池里、说明不空、需要目标的有目标
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var ids: Array[StringName] = []
	for res in GameDB.load_dir("res://data/heroes/"):
		ids.append((res as UnitData).id)
	var pairs: Array[String] = []
	for res in GameDB.load_dir("res://data/combos/"):
		var cd: ComboData = res
		check(cd.hero_a in ids and cd.hero_b in ids and cd.hero_a != cd.hero_b, "%s heroes exist" % cd.display_name)
		check(cd.description != "", "%s described" % cd.display_name)
		var key := "%s+%s" % ([cd.hero_a, cd.hero_b] if String(cd.hero_a) < String(cd.hero_b) else [cd.hero_b, cd.hero_a])
		check(not key in pairs, "%s pair is unique" % cd.display_name)
		pairs.append(key)
	return true


func test_vitality() -> bool:
	# 开战按记下的气血扣血，至少 1 点；没记的满血
	var m := battle([unit_data(&"a", [1000, 10, 0, 100]), unit_data(&"b", [1000, 10, 0, 100])], [unit_data(&"e", [500, 1, 0, 1])])
	Vitality.apply_start(m, {&"a": 0.4, &"b": 0.0})
	check_eq(by_id(m, &"a").hp, 400, "starts at remembered vitality")
	check_eq(by_id(m, &"b").hp, 1, "never starts at 0")
	# 打完：活着的按比例，倒下的重伤；输了全队重伤
	by_id(m, &"a").hp = 250
	by_id(m, &"b").hp = 0
	m.result = BattleModel.Result.WIN
	var after := Vitality.after_battle(m)
	check(is_equal_approx(after[&"a"], 0.25), "alive keeps its ratio")
	check(is_equal_approx(after[&"b"], Vitality.WOUNDED), "fallen is wounded")
	check(not after.has(&"e"), "enemies are not recorded")
	m.result = BattleModel.Result.LOSE
	after = Vitality.after_battle(m)
	check(is_equal_approx(after[&"a"], Vitality.WOUNDED), "losing wounds everyone")
	check(Vitality.is_wounded(after[&"a"]), "wounded check")
	# 活下来但血很少的，也至少记一成
	by_id(m, &"a").hp = 5
	m.result = BattleModel.Result.WIN
	check(is_equal_approx(Vitality.after_battle(m)[&"a"], Vitality.WOUNDED), "a sliver of hp counts as wounded")
	# 赶路回血，有神医翻倍，不超过满
	var r := {&"a": 0.5, &"b": 0.95}
	Vitality.road_regen(r, false)
	check(is_equal_approx(r[&"a"], 0.6) and is_equal_approx(r[&"b"], 1.0), "road regen +10%, capped")
	Vitality.road_regen(r, true)
	check(is_equal_approx(r[&"a"], 0.8), "healer doubles road regen")
	check_eq(Vitality.rest_price(1), Vitality.REST_MIN, "rest has a floor price")
	check_eq(Vitality.rest_price(20), 40, "rest price grows with level")
	for id: StringName in Vitality.MEDICINES:
		check(Vitality.medicine_heal(id) > 0.0 and Vitality.medicine_price(id) > 0, "%s heals and costs" % Vitality.medicine_name(id))
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
	check_eq(counts, [7, 5, 7, 5], "tier spread 甲7 乙5 丙7 丁5")
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
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	for res in GameDB.load_dir("res://data/scenes/"):
		_check_scene_layout(res as SceneData)
	return true


func _check_scene_layout(scene: SceneData) -> void:
	var rows := scene.rows()
	var width := rows[0].length()
	for r in rows:
		check_eq(r.length(), width, "%s layout row width" % scene.id)
	for y in rows.size():
		for x in width:
			check(SceneData.TERRAIN.has(rows[y][x]), "%s known terrain '%s' at %d,%d" % [scene.id, rows[y][x], x, y])
	check(scene.is_walkable(scene.spawn_cell), "%s spawn is walkable" % scene.id)
	check(scene.layout.contains("E") or scene.layout.contains("D"), "%s has a way out" % scene.id)
	# 从出生点能走到出口、每个小怪出生点，也能走到每个人物和宝箱旁边
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, scene.size())
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	var exits: Array[Vector2i] = []
	for y in rows.size():
		for x in width:
			astar.set_point_solid(Vector2i(x, y), not scene.is_walkable(Vector2i(x, y)))
			if rows[y][x] in ["E", "D"]:
				exits.append(Vector2i(x, y))
	check(exits.any(func(c: Vector2i) -> bool: return not astar.get_id_path(scene.spawn_cell, c).is_empty()), "%s exit reachable from spawn" % scene.id)
	for spot in scene.roam_spots:
		check(not astar.get_id_path(scene.spawn_cell, spot).is_empty(), "%s roam spot %s reachable" % [scene.id, spot])
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
		check(reachable, "%s object at %s reachable from spawn" % [scene.id, t])


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
	check_eq(bounties.size(), 13, "13 bounties")
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
	check_eq(s3.base_hp, 1200, "2 lit magatama: hp +20%")
	check_eq(s3.base_atk, 120, "2 lit magatama: atk +20%")
	check_eq(s3.base_spd, 100, "speed is not boosted")
	check(is_equal_approx(s3.skill.power, 2.5), "3 stars: skill power x1.25")
	check(is_equal_approx(h.skill.power, 2.0), "original skill untouched")
	check(is_equal_approx(Stars.apply(h, 2).skill.power, 2.0), "2 stars: skill not upgraded yet")
	var stun := Stars.upgraded_skill(skill(SkillData.Effect.STUN, {turns = 1}))
	check_eq(stun.turns, 2, "control skills last one more turn")
	check_eq(Stars.max_stars(h), 4, "丙 has 3 magatama (star cap 4)")
	check_eq(UiKit.tier_magatama(UnitData.Tier.JIA), 5, "甲 has 5 magatama")
	check_eq(UiKit.tier_magatama(UnitData.Tier.DING), 2, "丁 has 2 magatama")
	check_eq(Stars.cost(1) + Stars.cost(2) + Stars.cost(3), 120, "lighting all 3 of 丙 costs 120 souls")
	check_eq(Stars.soul_price(h), 2, "丙 souls cost 2 义气")
	return true


func test_equipment() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var all: Array = GameDB.load_dir("res://data/equipment/")
	var per_quality := [0, 0, 0, 0]
	var mounts := 0
	for res in all:
		var e: EquipData = res
		per_quality[e.quality] += 1
		if e.slot == EquipData.Slot.MOUNT:
			mounts += 1
		elif e.quality != EquipData.Quality.MING:
			check_eq(e.effects.size(), e.quality, "%s has %d effects" % [e.display_name, e.quality])
		for fx in e.effects:
			check(EquipData.EFFECTS.has(fx), "%s effect %s is known" % [e.display_name, fx])
	check_eq(per_quality, [9, 7, 4, 26], "9 凡品（含 3 匹马）7 良品 4 精品 26 名器")
	check_eq(mounts, 5, "3 horses + 2 famous horses")
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
	var bg_ops := StoryScript.parse("@bg weizhou\n甲：一\n@bg wutaishan\n乙：二\n@battle x\n@bg dongjing")
	check_eq(StoryScript.background_before(bg_ops, 4), "wutaishan", "battle uses the latest background")
	check_eq(StoryScript.background_before(bg_ops, 0), "", "no background before the first op")
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var stories: Array = GameDB.load_dir("res://data/stories/")
	check_eq(stories.size(), 16, "林冲、武松、杨志、鲁智深列传各 4 段")
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
	check_eq(all.size(), 8, "8 martial arts")
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
	var wu_song_4: StoryData = load("res://data/stories/wu_song_4.tres")
	check(wu_song_4.martial != null and wu_song_4.martial.id == &"yu_huan_bu", "武松列传 ends by teaching 玉环步鸳鸯脚")
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

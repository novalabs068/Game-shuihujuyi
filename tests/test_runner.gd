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
		"test_font_covers_text",
		"test_volumes",
		"test_guide_track",
		"test_city_jobs",
		"test_jiama",
		"test_damage_formula",
		"test_role_counters",
		"test_grid_and_blocking",
		"test_skill_areas",
		"test_move_and_summon",
		"test_boss_phases_and_morale",
		"test_class_stats_and_martial_levels",
		"test_hero_levels",
		"test_books",
		"test_disarm_and_silence",
		"test_pursuit",
		"test_miji",
		"test_formations_and_factions",
		"test_commander_off_field",
		"test_opening_events",
		"test_same_buffs_do_not_stack",
		"test_expose_and_boss_resist",
		"test_boss_charge",
		"test_defense_scales_with_level",
		"test_danger_and_boss_power",
		"test_guard_halves_damage",
		"test_events_carry_hp",
		"test_battle_stats",
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
		"test_arrivals_not_hidden",
		"test_world_links",
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
		"test_renown_and_realms",
		"test_commands",
		"test_foreign_martial_and_role_talents",
		"test_story_placeholders",
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
	check_eq(GameDB.load_dir("res://data/heroes/").size(), 28, "28 位好汉（新加戴宗）")
	check_eq(GameDB.load_dir("res://data/combos/").size(), 15, "15 combos")
	var stage: StageData = load("res://data/stages/stage_1_7.tres")
	check_eq(stage.enemies.size(), 3, "stage 1-7 has 3 enemies")
	check(stage.enemies[1].is_boss, "Lu Qian is the boss")
	return true


## 打包的字体只收了 art/fonts/chars.txt 里的字：脚本和数据里出现的字都得在里面，不然手机上会显示成方框。
## 江湖年表：8 卷按先后排好、编号不重复；眼下只有卷一能玩，开局就是「正在发生」；
## 没开发的卷是传闻，外传是远方传闻；开了的卷境界门槛不比前一卷低。
func test_volumes() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var list := Volumes.sorted(GameDB.load_dir("res://data/volumes/"))
	check_eq(list.size(), 8, "年表 8 卷（卷一到卷六、两部外传）")
	var ids := {}
	var orders := {}
	var gate := 0
	for v in list:
		ids[v.id] = true
		orders[v.order] = true
		check(v.realm_gate >= gate, "%s 的境界门槛不比前一卷低" % v.title)
		gate = v.realm_gate
		check(not v.affairs.is_empty(), "%s 列了经典场面" % v.title)
		check(v.status == VolumeData.Status.OPEN or v.rumor != "", "%s 没开发的卷要有传闻" % v.title)
		check(v.side_story == (v.status == VolumeData.Status.FAR), "%s 外传才是远期" % v.title)
	check_eq(ids.size(), 8, "卷编号不重复")
	check_eq(orders.size(), 8, "卷先后不重复")
	check_eq(list[0].id, &"v1_luo_cao", "第一卷是落草")
	check_eq(Volumes.state_of(list[0], 0), Volumes.State.ACTIVE, "开局卷一就是正在发生")
	check_eq(Volumes.state_of(list[1], 5), Volumes.State.RUMOR, "卷二还没开发：满境界也只是传闻")
	check_eq(Volumes.state_of(list[7], 5), Volumes.State.FAR, "抗金是远方传闻")
	check_eq(Volumes.current(list, 0), list[0], "年表停在卷一")
	# 以后卷二开发好了：境界不够时是「等你扬名」，够了是「正在发生」
	var v2: VolumeData = list[1].duplicate()
	v2.status = VolumeData.Status.OPEN
	check_eq(Volumes.state_of(v2, v2.realm_gate - 1), Volumes.State.LOCKED, "开发好的卷境界不够时等你扬名")
	check_eq(Volumes.state_of(v2, v2.realm_gate), Volumes.State.ACTIVE, "境界够了就开启")
	return true


## 指引：推荐先列传后悬赏、太难的不推荐、养成不推荐；「上梁山」按境界和名望给进度和下一步。
func test_guide_track() -> bool:
	var items: Array[Dictionary] = [
		{"kind": "宝箱", "text": "宝箱", "detail": "", "location": &"dongjing", "level": 0},
		{"kind": "悬赏", "text": "悬赏远", "detail": "", "location": &"weizhou", "level": 30},
		{"kind": "悬赏", "text": "悬赏近", "detail": "", "location": &"dongjing", "level": 8},
		{"kind": "列传", "text": "列传太难", "detail": "", "location": &"dongjing", "level": 18},
		{"kind": "列传", "text": "列传", "detail": "", "location": &"dongjing", "level": 6},
		{"kind": "养成", "text": "升星", "detail": "", "location": &"", "level": 0},
		{"kind": "列传", "text": "招到杨志后", "detail": "", "location": &"", "level": 0},
	]
	var picks := Guide.recommended(items, 2, 5)
	check_eq(picks.map(func(it: Dictionary) -> String: return it["text"]), ["列传", "悬赏近"], "先列传、再悬赏，太难的、养成、列传预告不推荐")
	check_eq(Guide.recommended(items, 9, 5).size(), 3, "5 级能推荐三件（列传、近悬赏、宝箱）")
	var info := Guide.default_info(0, 80, items, 5)
	check_eq(info["seal"], "上梁山", "默认指引叫上梁山")
	check_eq(info["progress_text"], "80/100", "名望进度")
	check(String(info["next"]).contains("再攒 20 名望") and String(info["next"]).contains("列传"), "名望不够：说还差多少、推荐一件事")
	check_eq(info["location"], &"dongjing", "推荐的事在哪")
	var only_chest: Array[Dictionary] = [items[0]]
	check(not String(Guide.default_info(0, 80, only_chest, 5)["next"]).contains("宝箱"), "上梁山不推荐不涨名望的宝箱")
	check(String(Guide.default_info(0, 120, items, 5)["next"]).contains("投名状"), "名望够了：去纳投名状")
	check(String(Guide.default_info(Renown.MAX_REALM, 9999, items, 5)["next"]).contains("江湖年表"), "满境界：去看江湖年表")
	return true


## 城中悬赏：第一次来给一张；每天多一张；几天不来攒着、最多 7 张（含正在贴的）；贴出来必给 2～3 枚聚义令。
func test_city_jobs() -> bool:
	var e := CityJobs.accrue({}, 100)
	check_eq(e["stock"], 1, "第一次来攒着一张")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pool: Array[UnitData] = [load("res://data/enemies/po_pi.tres")]
	e = CityJobs.post_next(e, pool, rng)
	check(not (e["job"] as Dictionary).is_empty() and e["stock"] == 0, "贴出一张，攒的扣掉")
	var job: Dictionary = e["job"]
	check(job["tokens"] >= CityJobs.TOKENS_MIN and job["tokens"] <= CityJobs.TOKENS_MAX, "必给 2～3 枚聚义令")
	check(job["need"] >= CityJobs.NEED_MIN and job["need"] <= CityJobs.NEED_MAX, "要打 3～5 拨")
	check_eq(CityJobs.accrue(e, 100)["stock"], 0, "同一天不多给")
	check_eq(CityJobs.accrue(e, 102)["stock"], 2, "过两天多两张")
	check_eq(CityJobs.accrue(e, 130)["stock"], CityJobs.MAX_STOCK - 1, "攒太久：连正在贴的最多 7 张")
	var empty := {"day": 100, "stock": 0, "job": {}}
	check_eq(CityJobs.accrue(empty, 200)["stock"], CityJobs.MAX_STOCK, "没在贴的时候能攒满 7 张")
	check_eq(CityJobs.accrue(e, 90)["day"], 100, "手机时间往回调不倒扣")
	check_eq(CityJobs.post_next(e, pool, rng)["job"], job, "正在贴的没做完，不换")
	check_eq(Renown.compute({"city_jobs": 2}), 2 * Renown.PER_CITY_JOB, "城中悬赏涨名望")
	return true


## 甲马：戴宗第一次当天就写 5 张；按天攒；身上最多 15 张；集市每天限买 5 张、也不超过身上上限。
func test_jiama() -> bool:
	check_eq(Jiama.dai_write(0, 0, 100), [5, 100, 5], "第一次当天写 5 张")
	check_eq(Jiama.dai_write(5, 100, 100), [5, 100, 0], "同一天不再写")
	check_eq(Jiama.dai_write(5, 100, 101), [10, 101, 5], "过一天多 5 张")
	check_eq(Jiama.dai_write(5, 100, 110), [15, 110, 10], "几天不来：攒到上限 15 张为止")
	check_eq(Jiama.dai_write(20, 100, 101), [20, 101, 0], "已经超过上限的不扣")
	check_eq(Jiama.shop_left({}, 100, 0), 5, "今天还没买：能买 5 张")
	check_eq(Jiama.shop_left({"day": 100, "bought": 3}, 100, 0), 2, "今天买了 3 张：还能买 2 张")
	check_eq(Jiama.shop_left({"day": 99, "bought": 5}, 100, 0), 5, "换天了重新算")
	check_eq(Jiama.shop_left({}, 100, 13), 2, "身上 13 张：最多再买 2 张")
	return true


func test_font_covers_text() -> bool:
	var have := {}
	for ch in FileAccess.get_file_as_string("res://art/fonts/chars.txt"):
		have[ch] = true
	var missing := {}
	var dirs: Array[String] = ["res://scripts", "res://data"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir + "/" + sub)
		for f in DirAccess.get_files_at(dir):
			if not (f.ends_with(".gd") or f.ends_with(".tres") or f.ends_with(".txt")):
				continue
			for ch in FileAccess.get_file_as_string(dir + "/" + f):
				if ch.unicode_at(0) > 0x2000 and not have.has(ch):
					missing[ch] = f
	check(missing.is_empty(), "font has every character used in the game; missing: %s（重新生成字体，见 art/fonts/README.md）" % ", ".join(missing.keys().map(func(c: String) -> String: return "%s(%s)" % [c, missing[c]])))
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


func role_unit(id: StringName, role: UnitData.Role, stats: Array, skill_data: SkillData = null) -> UnitData:
	var u := unit_data(id, stats, skill_data)
	u.role = role
	return u


func test_role_counters() -> bool:
	var W := UnitData.Role.WARRIOR
	var A := UnitData.Role.ASSASSIN
	var R := UnitData.Role.ARCHER
	var T := UnitData.Role.TAOIST
	var H := UnitData.Role.HEALER
	check(Roles.is_melee(W) and Roles.is_melee(A) and not Roles.is_melee(R), "战士、刺客近战，射手远程")
	check(Roles.is_magic(T) and not Roles.is_magic(R), "道士打法术")
	check(Roles.exploits(W, A) and Roles.exploits(W, H) and not Roles.exploits(W, W), "近身战士压制别的职业")
	check(Roles.exploits(T, W) and Roles.exploits(T, H) and not Roles.exploits(T, T), "法术打法抗低的战士、治疗")
	check(Roles.exploits(R, T) and Roles.exploits(A, T) and not Roles.exploits(R, W), "物理打防御低的道士")
	check(is_equal_approx(Roles.melee_multiplier(W, R), 1.2) and is_equal_approx(Roles.melee_multiplier(A, W), 0.85) and is_equal_approx(Roles.melee_multiplier(R, W), 1.0), "近身压制只看近战")
	# 闪避按敏捷算：30 以下不躲，最多 40%
	check_eq(Roles.dodge_chance(25), 0.0, "敏捷低不躲")
	check(absf(Roles.dodge_chance(130) - 100.0 / 380.0) < 0.001, "敏捷 130 闪避 26%")
	check_eq(Roles.dodge_chance(10000), Roles.DODGE_MAX, "闪避有上限")
	# 法抗：没填按职业从防御折算
	var w := role_unit(&"w", W, [100, 10, 100, 100])
	check_eq(w.res(), 35, "战士法抗 = 防御 ×0.35")
	var t := role_unit(&"t", T, [100, 10, 10, 100])
	check_eq(t.res(), 30, "道士法抗 = 防御 ×3")
	w.base_res = 77
	check_eq(w.res(), 77, "填了法抗就用填的")
	# 法术看法抗：道士打战士（法抗 35）比打道士（法抗 300）疼得多；物理看防御
	var m := battle([role_unit(&"mage", T, [500, 100, 0, 100]), role_unit(&"bow", R, [500, 100, 0, 100])], [role_unit(&"e", W, [100000, 1, 100, 1]), role_unit(&"e2", T, [100000, 1, 100, 1])])
	by_id(m, &"mage").row = 1
	by_id(m, &"bow").row = 1
	for i in 10:
		var on_w := m._deal(by_id(m, &"mage"), by_id(m, &"e"), 1.0, true)
		check(on_w >= 105 and on_w <= 117, "道士打战士 crit %d（法抗 35：100×100/135×1.5≈111）" % on_w)
		var on_t := m._deal(by_id(m, &"mage"), by_id(m, &"e2"), 1.0, true)
		check(on_t >= 36 and on_t <= 40, "道士打道士 crit %d（法抗 300）" % on_t)
		var bow_w := m._deal(by_id(m, &"bow"), by_id(m, &"e"), 1.0, true)
		check(bow_w >= 71 and bow_w <= 79, "射手打战士 crit %d（防御 100）" % bow_w)
	check(m._events.any(func(e: Dictionary) -> bool: return String(e["popup"]).begins_with("克")), "打在弱点上跳「克」")
	# 近身压制：战士打刺客 ×1.2，刺客打战士 ×0.85
	var mm := battle([role_unit(&"w", W, [500, 100, 0, 100]), role_unit(&"a", A, [500, 100, 0, 100])], [role_unit(&"ea", A, [100000, 1, 100, 1]), role_unit(&"ew", W, [100000, 1, 100, 1])])
	by_id(mm, &"ea")._agi = 0
	for i in 10:
		var up := mm._deal(by_id(mm, &"w"), by_id(mm, &"ea"), 1.0, true)
		check(up >= 85 and up <= 95, "战士打刺客 crit %d" % up)
	# 刺客暴击 ×2.2、普攻 ×0.75，打战士再 ×0.85
	for i in 10:
		var a_hit := mm._deal(by_id(mm, &"a"), by_id(mm, &"ew"), 1.0, true, true)
		check(a_hit >= 67 and a_hit <= 74, "刺客普攻暴击打战士 %d（50×2.2×0.75×0.85≈70）" % a_hit)
	# 闪避：法术、必中闪不开；物理会被闪开（敏捷拉满 40%）
	var md := battle([role_unit(&"mage", T, [500, 100, 0, 100]), role_unit(&"w", W, [500, 100, 0, 100])], [role_unit(&"e", A, [100000, 1, 0, 1])])
	by_id(md, &"e")._agi = 100000
	by_id(md, &"mage").row = 1
	var magic_miss := 0
	var phys_miss := 0
	for i in 200:
		if md._deal(by_id(md, &"mage"), by_id(md, &"e"), 1.0) == 0:
			magic_miss += 1
		if md._deal(by_id(md, &"w"), by_id(md, &"e"), 1.0) == 0:
			phys_miss += 1
	check_eq(magic_miss, 0, "法术不能闪避")
	check(phys_miss > 50 and phys_miss < 110, "物理被闪开约 40%%（%d/200）" % phys_miss)
	check(md._events.any(func(e: Dictionary) -> bool: return e["kind"] == "dodge"), "闪开有 dodge 事件")
	# 站错排：近战站后排伤害 −20%
	var mp := battle([role_unit(&"w", W, [500, 100, 0, 100])], [role_unit(&"e", W, [100000, 1, 100, 1])])
	by_id(mp, &"w").row = 1
	for i in 10:
		var hit := mp._deal(by_id(mp, &"w"), by_id(mp, &"e"), 1.0, true)
		check(hit >= 57 and hit <= 63, "近战站后排 crit %d（75×0.8）" % hit)
	return true


func test_grid_and_blocking() -> bool:
	var W := UnitData.Role.WARRIOR
	# 自动摆位：近战站前排、远程站后排，从中路往两边
	var m := battle([role_unit(&"w", W, [500, 100, 0, 100]), role_unit(&"bow", UnitData.Role.ARCHER, [500, 100, 0, 100]), role_unit(&"cut", UnitData.Role.ASSASSIN, [500, 100, 0, 100])],
		[role_unit(&"f0", W, [1000, 1, 0, 1]), role_unit(&"b0", UnitData.Role.HEALER, [1000, 1, 0, 1]), role_unit(&"f1", W, [1000, 1, 0, 1])])
	check_eq(by_id(m, &"w").cell(), Vector2i(0, 1), "战士站中路前排")
	check_eq(by_id(m, &"bow").cell(), Vector2i(1, 1), "射手站中路后排")
	check_eq(by_id(m, &"cut").cell(), Vector2i(0, 0), "刺客站上路前排")
	check_eq(by_id(m, &"b0").cell(), Vector2i(1, 1), "敌方治疗站中路后排")
	# 卡位：近战只打得到每一路最前面的人；中路后排的治疗被前排挡住
	var reach := m.reachable_foes(by_id(m, &"w"))
	check(by_id(m, &"f0") in reach and by_id(m, &"f1") in reach, "前排打得到")
	check(not by_id(m, &"b0") in reach, "后排被挡住，近战打不到")
	check(by_id(m, &"b0") in m.reachable_foes(by_id(m, &"bow")), "远程打得到后排")
	check(by_id(m, &"b0") in m.reachable_foes(by_id(m, &"cut")), "刺客越过前排")
	# 点了打不到的人：改打同一路最前面的
	check(m._pick_foe(by_id(m, &"w"), by_id(m, &"b0")) == by_id(m, &"f0"), "打不到的目标换成同路前排")
	# 前排倒下，这一路破口，后排暴露
	by_id(m, &"f0").hp = 0
	check(by_id(m, &"b0") in m.reachable_foes(by_id(m, &"w")), "破口：后排暴露给近战")
	# 指定站位：用给的格子
	var mp := BattleModel.new(StageData.new(), [unit_data(&"a", [100, 1, 0, 100])] as Array[UnitData], 1, [], 1, &"", [Vector2i(1, 2)])
	check_eq(by_id(mp, &"a").cell(), Vector2i(1, 2), "按给的格子站")
	# 敌人照关卡给的格子站
	var st := StageData.new()
	st.enemies = [unit_data(&"e", [100, 1, 0, 1])]
	st.enemy_cells = [Vector2i(1, 0)]
	var me := BattleModel.new(st, [unit_data(&"a", [100, 1, 0, 100])] as Array[UnitData], 1, [], 1)
	check_eq(by_id(me, &"e").cell(), Vector2i(1, 0), "敌人按关卡的格子站")
	# 大体型：占一路前后两格，把这一路堵住
	var big := unit_data(&"boss", [1000, 1, 0, 1])
	big.big = true
	var mb := battle([unit_data(&"a", [100, 1, 0, 100])], [unit_data(&"e1", [100, 1, 0, 1]), big])
	check(by_id(mb, &"boss").occupies(Vector2i(0, 1)) and by_id(mb, &"boss").occupies(Vector2i(1, 1)), "大体型占中路两格")
	check(mb.occupant(BattleUnit.Side.ENEMY, Vector2i(1, 1)) == by_id(mb, &"boss"), "后排那格也算它")
	# 敌人近战预告只挑打得到的
	for i in 20:
		var mi := battle([role_unit(&"front", W, [1000, 1, 0, 100]), role_unit(&"back", UnitData.Role.HEALER, [1000, 1, 0, 100])], [role_unit(&"e", W, [1000, 1, 0, 1])], [])
		mi.rng.seed = i
		mi._plan_intent(by_id(mi, &"e"))
		check(by_id(mi, &"e").intent_target == by_id(mi, &"front"), "敌方近战盯不上被挡住的后排")
	return true


func test_skill_areas() -> bool:
	var W := UnitData.Role.WARRIOR
	var foes: Array[UnitData] = []
	for id in [&"f0", &"f1", &"f2", &"b1", &"b2"]:
		foes.append(role_unit(id, W, [100000, 1, 0, 1]))
	var st := StageData.new()
	st.enemies = foes
	st.enemy_cells = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 1), Vector2i(1, 2)]
	var m := BattleModel.new(st, [role_unit(&"a", UnitData.Role.ARCHER, [500, 100, 0, 100])] as Array[UnitData], 1, [], 1)
	var a := by_id(m, &"a")
	var ids := func(list: Array) -> Array: return list.map(func(p: Array) -> StringName: return p[0].data.id)
	check_eq(ids.call(m.area_targets(a, by_id(m, &"f1"), SkillData.Area.SINGLE)), [&"f1"], "单人一格")
	var row := m.area_targets(a, by_id(m, &"f1"), SkillData.Area.ROW)
	check_eq(ids.call(row), [&"f0", &"f1", &"f2"], "多人：整排")
	check(row.all(func(p: Array) -> bool: return is_equal_approx(p[1], BattleModel.ROW_MULT)), "多人每人 ×0.7")
	var lane := m.area_targets(a, by_id(m, &"f1"), SkillData.Area.LANE)
	check_eq(ids.call(lane), [&"f1", &"b1"], "穿透：一路前后")
	check(is_equal_approx(lane[1][1], BattleModel.LANE_BACK_MULT), "穿透后格 ×0.8")
	var chain := m.area_targets(a, by_id(m, &"f0"), SkillData.Area.CHAIN)
	check_eq(chain.size(), 1 + BattleModel.CHAIN_HOPS, "连锁跳 3 次")
	check_eq(chain[1][0].data.id, &"f1", "连锁先跳最近的")
	check(chain[3][1] < chain[1][1], "连锁越跳越轻")
	check_eq(m.area_targets(a, by_id(m, &"f0"), SkillData.Area.ALL).size(), 5, "全范围打全部")
	# 普攻带范围：林冲式的穿透普攻打到身后的人
	var spear := role_unit(&"s", W, [500, 100, 0, 200])
	spear.basic_area = SkillData.Area.LANE
	var m2 := BattleModel.new(st, [spear] as Array[UnitData], 1, [], 1)
	advance_to(m2, &"s")
	var hit := m2.act(BattleModel.Action.ATTACK, by_id(m2, &"f1")).filter(func(e: Dictionary) -> bool: return e["kind"] == "damage").map(func(e: Dictionary) -> StringName: return e["unit"].data.id)
	check_eq(hit, [&"f1", &"b1"], "穿透普攻打穿一路")
	# 绝招按范围展开
	var sweep := role_unit(&"s", W, [500, 100, 0, 200], skill(SkillData.Effect.DAMAGE, {"power": 1.0, "area": SkillData.Area.ROW}))
	var m3 := BattleModel.new(st, [sweep] as Array[UnitData], 1, [], 1)
	advance_to(m3, &"s")
	var swept := m3.act(BattleModel.Action.SKILL, by_id(m3, &"f1")).filter(func(e: Dictionary) -> bool: return e["kind"] == "damage")
	check_eq(swept.size(), 3, "多人绝招扫一排")
	return true


func test_move_and_summon() -> bool:
	# 补位：走到空格子，这回合防御；不能走到有人的格子
	var m := battle([unit_data(&"a", [500, 10, 0, 200]), unit_data(&"b", [500, 10, 0, 100])], [unit_data(&"e", [500, 10, 0, 1])])
	var a := by_id(m, &"a")
	advance_to(m, &"a")
	check(not m.can_move_to(a, by_id(m, &"b").cell()), "有人的格子去不了")
	var ev := m.act(BattleModel.Action.MOVE, null, Vector2i(1, 2))
	check_eq(a.cell(), Vector2i(1, 2), "挪过去了")
	check(a.guarding, "补位时防御")
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "move"), "有 move 事件")
	# 召唤：放进空格子，有自己的出手顺序；召唤者倒下就消散；最多两个
	var minion := unit_data(&"minion", [1, 1, 10, 100])
	minion.display_name = "天将"
	var call := skill(SkillData.Effect.SUMMON, {"summon": minion, "hits": 3, "power": 0.5, "amount": 0.4, "turns": 0, "cooldown": 1})
	var caster := role_unit(&"c", UnitData.Role.TAOIST, [1000, 100, 0, 200], call)
	var ms := battle([caster], [unit_data(&"e", [100000, 1, 0, 1])])
	advance_to(ms, &"c")
	ms.act(BattleModel.Action.SKILL)
	var summons := ms.units.filter(func(u: BattleUnit) -> bool: return u.is_summon())
	check_eq(summons.size(), BattleModel.MAX_SUMMONS, "最多召两个")
	check_eq(summons[0].max_hp, 400, "生命按召唤者 ×0.4")
	check_eq(summons[0].cell().x, 0, "先放前排")
	check(summons[0] in ms.turn_order_preview(), "召唤物有出手顺序")
	# 召唤物堵路：前排有召唤物，敌方近战打不到身后的道士
	check(not by_id(ms, &"c") in ms.reachable_foes(by_id(ms, &"e")), "召唤物挡在前面，召唤者打不到")
	ms._deal(by_id(ms, &"e"), by_id(ms, &"c"), 100000.0)
	check(summons.all(func(u: BattleUnit) -> bool: return not u.is_alive()), "召唤者倒下，召唤物消散")
	check_eq(ms.player_deaths, 1, "召唤物不算阵亡")
	# 持续几回合的召唤物到时间就消散
	var timed := skill(SkillData.Effect.SUMMON, {"summon": minion, "hits": 1, "power": 0.5, "amount": 0.4, "turns": 1})
	var mt := battle([role_unit(&"c", UnitData.Role.TAOIST, [1000, 100, 0, 100], timed)], [unit_data(&"e", [100000, 1, 0, 1])])
	advance_to(mt, &"c")
	mt.act(BattleModel.Action.SKILL)
	var sm: BattleUnit = mt.units.back()
	for i in 6:
		mt.start_next_turn()
		if mt.current != null:
			mt.act(BattleModel.Action.GUARD)
	check(not sm.is_alive(), "一回合的召唤物到时就消散")
	return true


func test_boss_phases_and_morale() -> bool:
	var boss := unit_data(&"b", [1000, 100, 0, 100], skill(SkillData.Effect.DAMAGE, {"power": 1.0}))
	boss.is_boss = true
	boss.boss_bars = 5
	boss.enrage_name = "狂怒"
	boss.enrage_atk_bonus = 0.5
	var p2 := skill(SkillData.Effect.DAMAGE, {"power": 1.5, "area": SkillData.Area.ROW})
	p2.display_name = "一掀"
	var p3 := skill(SkillData.Effect.ALL_FOES, {"power": 1.0})
	p3.display_name = "一剪"
	boss.phase_skills = [p2, p3]
	var m := battle([unit_data(&"a", [500, 100, 0, 100])], [boss])
	var b := by_id(m, &"b")
	var a := by_id(m, &"a")
	b.hp = 620
	m._deal(a, b, 0.5)
	check_eq(b.phase, 2, "血量过 60% 进第二阶段")
	check(b.enraged, "第二阶段狂暴")
	check_eq(b.data.skill.display_name, "一掀", "第二阶段换招")
	check_eq(boss.skill.display_name, "技能", "换招不改原数据")
	check(m._events.any(func(e: Dictionary) -> bool: return e["kind"] == "phase"), "换阶段有事件")
	check(m._events.any(func(e: Dictionary) -> bool: return e["kind"] == "bar"), "打碎一管血有事件")
	b.hp = 310
	m._deal(a, b, 0.5)
	check_eq(b.phase, 3, "过 30% 进第三阶段")
	check_eq(b.data.skill.display_name, "一剪", "第三阶段换招")
	# 统领倒下：全队士气受挫
	var lead := unit_data(BattleModel.COMMANDER_ID, [100, 10, 0, 100])
	var mm := battle([lead, unit_data(&"h", [1000, 100, 0, 100])], [unit_data(&"e", [100000, 100, 0, 1])])
	var before := by_id(mm, &"h").atk()
	mm._deal(by_id(mm, &"e"), by_id(mm, BattleModel.COMMANDER_ID), 100.0)
	check(by_id(mm, &"h").atk() < before, "统领倒下，全队攻击下降")
	check(mm._events.any(func(e: Dictionary) -> bool: return e["popup"] == "士气受挫"), "有士气受挫横幅")
	# 我方满四人：关卡里的小兵补两个（最多 6 个），增援不给经验；头目单挑时头目自己加强
	var four: Array[UnitData] = [unit_data(&"p1", [100, 1, 0, 100]), unit_data(&"p2", [100, 1, 0, 100]), unit_data(&"p3", [100, 1, 0, 100]), unit_data(&"p4", [100, 1, 0, 100])]
	var st4 := StageData.new()
	var bossy := unit_data(&"boss", [1000, 10, 0, 1])
	bossy.is_boss = true
	st4.enemies = [unit_data(&"m1", [100, 10, 0, 1]), unit_data(&"m2", [100, 10, 0, 1]), bossy]
	var m4 := BattleModel.new(st4, four, 1, [], 1)
	var foes4 := m4.alive(BattleUnit.Side.ENEMY)
	check_eq(foes4.size(), 5, "三个敌人扩到五个")
	check_eq(foes4.filter(func(u: BattleUnit) -> bool: return u.reinforcement).size(), 2, "两个增援")
	check(foes4.filter(func(u: BattleUnit) -> bool: return u.data.is_boss).size() == 1, "头目不会多出来")
	st4.enemies = [unit_data(&"a1", [100, 10, 0, 1]), unit_data(&"a2", [100, 10, 0, 1]), unit_data(&"a3", [100, 10, 0, 1]), unit_data(&"a4", [100, 10, 0, 1]), unit_data(&"a5", [100, 10, 0, 1])]
	check_eq(BattleModel.new(st4, four, 1, [], 1).alive(BattleUnit.Side.ENEMY).size(), BattleModel.MAX_ENEMIES, "最多六个")
	var three: Array[UnitData] = [unit_data(&"p1", [100, 1, 0, 100])]
	check_eq(BattleModel.new(st4, three, 1, [], 1).alive(BattleUnit.Side.ENEMY).size(), 5, "我方不满四人不扩编")
	st4.enemies = [bossy]
	var solo := BattleModel.new(st4, four, 1, [], 1)
	check_eq(solo.alive(BattleUnit.Side.ENEMY).size(), 1, "头目单挑不加人")
	check_eq(solo.alive(BattleUnit.Side.ENEMY)[0].max_hp, roundi(1000 * BattleModel.SOLO_HP_SCALE), "头目单挑时自己加强")
	return true


## 好汉各自的等级：升级曲线、比统领低时多拿经验、开战时每人按自己的等级；升星、羁绊也放大填写的法抗。
func test_hero_levels() -> bool:
	check_eq(Leveling.gain_exp(1, 0, Leveling.exp_to_next(1) - 1), [1, Leveling.exp_to_next(1) - 1] as Array[int], "差 1 点经验不升级")
	var two := Leveling.exp_to_next(1) + Leveling.exp_to_next(2)
	check_eq(Leveling.gain_exp(1, 0, two + 5), [3, 5] as Array[int], "一次连升两级，余下的经验留着")
	check_eq(Leveling.gain_exp(98, 0, 999999), [99, 0] as Array[int], "到 99 级封顶，经验清零")
	check(is_equal_approx(Leveling.catch_up_mult(10, 10), 1.0), "和统领同级拿原样")
	check(is_equal_approx(Leveling.catch_up_mult(20, 10), 1.0), "比统领高也拿原样")
	check(is_equal_approx(Leveling.catch_up_mult(5, 10), 1.5), "低 5 级经验 ×1.5")
	check(is_equal_approx(Leveling.catch_up_mult(1, 60), Leveling.CATCH_UP_MAX), "低很多最多 ×3")
	# 开战时每人按自己的等级
	var a := unit_data(&"a", [100, 10, 10, 100])
	var b := unit_data(&"b", [100, 10, 10, 90])
	var stage := StageData.new()
	stage.enemies = [unit_data(&"e", [100, 10, 10, 80])] as Array[UnitData]
	stage.enemy_level = 1
	var m := BattleModel.new(stage, [a, b] as Array[UnitData], 1, [], 1, &"", [], [10, 1])
	var lv := {}
	for u in m.units:
		lv[u.data.id] = u.level
	check_eq(lv[&"a"], 10, "第一个人 10 级")
	check_eq(lv[&"b"], 1, "第二个人 1 级")
	check(m.units.filter(func(u: BattleUnit) -> bool: return u.data.id == &"a")[0].max_hp > 100, "10 级的人血更厚")
	# 好汉数据里写了法抗：升星、羁绊一起放大
	var h := unit_data(&"h", [1000, 100, 100, 100])
	h.base_res = 50
	check_eq(Stars.apply(h, 3).base_res, 60, "点亮 2 颗勾玉：法抗 +20%")
	check_eq(Bonds.apply(h, Bonds.THRESHOLDS[3]).base_res, roundi(50 * 1.09), "知己：法抗 +9%")
	h.base_res = -1
	check_eq(Stars.apply(h, 3).base_res, -1, "没填法抗的仍按防御折算")
	return true


func test_class_stats_and_martial_levels() -> bool:
	# 品级范围：甲 = 丁 ×1.3；速度、敏捷甲 +12
	check_eq(Roles.stat_range(UnitData.Role.WARRIOR, UnitData.Tier.DING, 0), Vector2i(430, 480), "丁品战士气血")
	check_eq(Roles.stat_range(UnitData.Role.WARRIOR, UnitData.Tier.JIA, 0), Vector2i(559, 624), "甲品战士气血 ×1.3")
	check_eq(Roles.stat_range(UnitData.Role.ASSASSIN, UnitData.Tier.JIA, 5), Vector2i(122, 152), "甲品刺客敏捷 +12")
	var ps := Roles.protagonist_stats(UnitData.Role.TAOIST)
	check(ps[3] > ps[2] * 2, "统领当道士：法抗远高于防御")
	# 等级成长按品级：好汉按品级，敌人 1.03
	var hero := unit_data(&"h", [100, 10, 10, 100])
	hero.rarity = UnitData.Rarity.TIANGANG
	hero.tier = UnitData.Tier.JIA
	check(is_equal_approx(Roles.level_growth(hero), 1.033), "甲品每级 ×1.033")
	hero.tier = UnitData.Tier.YI
	check(is_equal_approx(Roles.level_growth(hero), 1.030), "乙品每级 ×1.030")
	hero.tier = UnitData.Tier.JIA
	check(is_equal_approx(Roles.level_growth(unit_data(&"e", [1, 1, 1, 1])), BattleUnit.LEVEL_GROWTH), "敌人照旧")
	# 武学十重：每重 +6%，第 5 重附带破绽，第 7 重冷却 -1，第 10 重范围升级
	var m := MartialData.new()
	m.skill = skill(SkillData.Effect.DAMAGE, {"power": 2.0, "cooldown": 3})
	check(is_equal_approx(m.skill_at(1).power, 2.0), "第一重原样")
	check(is_equal_approx(m.skill_at(4).power, 2.0 * 1.18), "第四重 +18%")
	check(not m.skill_at(4).exposes and m.skill_at(5).exposes, "第五重打中露出破绽")
	check_eq(m.skill_at(7).cooldown, 2, "第七重冷却 -1")
	check_eq(m.skill_at(9).area, SkillData.Area.SINGLE, "第九重还是单人")
	check_eq(m.skill_at(10).area, SkillData.Area.LANE, "大成：单人升穿透")
	check(is_equal_approx(m.skill.power, 2.0), "修炼不改原数据")
	check_eq(MartialData.level_cost(3), 1350, "修炼价钱 150 × 重²")
	# 第五重的破绽在战斗里生效
	var exp_skill := m.skill_at(5)
	var mm := battle([unit_data(&"a", [500, 100, 0, 200], exp_skill)], [unit_data(&"e", [100000, 1, 0, 1])])
	advance_to(mm, &"a")
	mm.act(BattleModel.Action.SKILL, by_id(mm, &"e"))
	check(by_id(mm, &"e").expose_turns > 0, "第五重绝招打出破绽")
	return true


func test_books() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var heroes := {}
	for h: UnitData in GameDB.load_dir("res://data/heroes/"):
		heroes[h.id] = h
	var books: Array = GameDB.load_dir("res://data/miji/").filter(func(m: MijiData) -> bool: return m.is_book())
	check_eq(books.size(), 9, "9 本技能书")
	var roles := {}
	for mj: MijiData in books:
		for id in mj.recipe:
			check(heroes.has(id), "《%s》要的 %s 是现有好汉" % [mj.display_name, id])
		var n := mj.recipe.size()
		var want := MijiData.Quality.LIANG if n <= 3 else (MijiData.Quality.JING if n <= 6 else MijiData.Quality.JUE)
		check_eq(mj.quality, want, "《%s》品质按人数" % mj.display_name)
		check(mj.martial != null and mj.martial.skill != null, "《%s》能研读出武学" % mj.display_name)
		check(mj.story != "", "《%s》写了故事" % mj.display_name)
		roles[mj.martial.role] = true
	check_eq(roles.size(), 5, "五个职业都有技能书可研读")
	# 合成：缺的将魂用残页顶
	var mj: MijiData = books.filter(func(m: MijiData) -> bool: return m.recipe.size() == 2)[0]
	var need := Books.souls_per_hero(mj)
	var souls := {mj.recipe[0]: need, mj.recipe[1]: need - 2}
	check_eq(Books.missing(mj, souls), 2, "缺 2 个")
	check(not Books.can_craft(mj, souls, 1), "残页不够")
	check(Books.can_craft(mj, souls, 2), "残页够顶")
	# 召唤书：武学的绝招是召唤、召出来的能堵路
	var summon_book: Array = books.filter(func(m: MijiData) -> bool: return m.martial.skill.effect == SkillData.Effect.SUMMON)
	check_eq(summon_book.size(), 1, "有一本召唤书")
	check(summon_book[0].martial.skill.summon != null, "召唤书带召唤物")
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
	var jue: Array = all.filter(func(m: MijiData) -> bool: return m.quality == MijiData.Quality.JUE and not m.is_book())
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
	# 破计：被打在弱点上（克）时少挨打。战士近身打射手 ×1.2，破计再 ×0.8
	var anti := unit_data(&"e", [100000, 1, 100, 1])
	anti.role = UnitData.Role.ARCHER
	anti.base_agi = 0
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
	var team: Array[UnitData] = [unit_data(&"wu_song", [1000, 100, 50, 100]), h1, h2]
	lead = team[0]
	# 鱼鳞阵：按阵位顺序站，两鳞防御 +15%，鱼头（阵眼）受到伤害 -20%，宜战士站对了 ×1.5
	var m := BattleModel.new(stage, team, 1, [], 1, &"yu_lin")
	check_eq(by_id(m, &"wu_song").cell(), Vector2i(0, 0), "按阵位顺序站：第一位站上路前排")
	check_eq(roundi(by_id(m, &"wu_song").def()), 57, "鳞：防御 +15%")
	check(by_id(m, &"lu_zhishen").formation_eye, "鱼头是阵眼")
	check(is_equal_approx(by_id(m, &"lu_zhishen").formation_mods["taken"], -0.3), "鱼头宜战士：减伤 20% ×1.5")
	check(m.opening_events.any(func(e: Dictionary) -> bool: return String(e["log"]).begins_with("阵法")), "the formation shows in the 准备回合")
	# 阵眼没人就摆不成阵
	var m_no := BattleModel.new(stage, team, 1, [], 1, &"yu_lin", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 2)])
	check(not m_no.opening_events.any(func(e: Dictionary) -> bool: return String(e["log"]).begins_with("阵法")), "阵眼空着摆不成阵")
	check(by_id(m_no, &"wu_song").formation_mods.is_empty(), "摆不成阵没有加成")
	# 阵眼倒下就破阵：加成全部消失
	var eye := by_id(m, &"lu_zhishen")
	m._deal(by_id(m, &"e"), eye, 1000.0)
	check(not eye.is_alive(), "阵眼倒下")
	check(by_id(m, &"wu_song").formation_mods.is_empty(), "破阵：别人的加成也没了")
	check(m._events.any(func(e: Dictionary) -> bool: return e["popup"] == "破阵"), "破阵有横幅")
	# 鲁智深 + 杨志 同出二龙山：全队生命 +8%
	check_eq(Factions.shared([&"lu_zhishen", &"yang_zhi", &"wu_song"] as Array[StringName]), &"er_long_shan", "all three from 二龙山")
	check_eq(Factions.shared([&"lu_zhishen", &"yang_zhi"] as Array[StringName]), &"", "two are not enough")
	check_eq(by_id(m, &"wu_song").max_hp, 1080, "山头 bonus reaches the whole team")
	# 八卦阵：敌方减攻 3 回合
	var mb := BattleModel.new(stage, team, 1, [], 1, &"ba_gua")
	check(by_id(mb, &"e").atk() < 100.0, "八卦阵 weakens the enemy")
	# 长蛇阵：蛇头多挨打，蛇身少挨打；蛇头挨打时蛇尾追击
	var snake: Array[UnitData] = [unit_data(&"head", [100000, 100, 50, 100]), unit_data(&"b1", [1000, 100, 50, 100]), unit_data(&"b2", [1000, 100, 50, 100]), unit_data(&"tail", [1000, 100, 50, 100])]
	var mc := BattleModel.new(stage, snake, 1, [], 1, &"chang_she")
	check(is_equal_approx(by_id(mc, &"head").formation_mods["taken"], 0.15), "长蛇阵 蛇头多挨打")
	check(is_equal_approx(by_id(mc, &"b1").formation_mods["taken"], -0.1), "长蛇阵 蛇身少挨打")
	var foe_hp := by_id(mc, &"e").hp
	mc._deal(by_id(mc, &"e"), by_id(mc, &"head"), 1.0)
	check(by_id(mc, &"e").hp < foe_hp, "击首尾应：蛇尾追击打的人")
	# 偃月阵：敌人近战打中路，月角夹击
	var moon: Array[UnitData] = [unit_data(&"h1", [1000, 100, 50, 100]), unit_data(&"h2", [1000, 100, 50, 100]), unit_data(&"heart", [100000, 100, 50, 100]), unit_data(&"back", [1000, 100, 50, 100])]
	var my := BattleModel.new(stage, moon, 1, [], 1, &"yan_yue")
	check_eq(by_id(my, &"heart").cell(), Vector2i(1, 1), "月心在中路后排")
	var before := by_id(my, &"e").hp
	my._deal(by_id(my, &"e"), by_id(my, &"heart"), 1.0)
	check(by_id(my, &"e").hp < before, "月角夹击中路来犯的近战")
	# 不摆阵、不同山头：什么也不加
	var plain := BattleModel.new(stage, [lead, h1, unit_data(&"x", [1000, 100, 50, 100])] as Array[UnitData], 1, [], 1)
	check(plain.opening_events.is_empty(), "no formation, no 山头, nothing to show")
	return true


func test_commander_off_field() -> bool:
	# 结义同心：统领不在阵上，结义的好汉一个人怒气满就能放
	var hero := unit_data(&"h", [5000, 100, 0, 200], skill(SkillData.Effect.DAMAGE, {"power": 2.0}))
	var sworn := Bonds.sworn_combo(hero, BattleModel.COMMANDER_ID)
	var m := battle([hero, unit_data(&"x", [5000, 10, 0, 50])], [unit_data(&"e", [100000, 1, 0, 1])], [sworn])
	advance_to(m, &"h")
	var h := by_id(m, &"h")
	check(m.available_combo(h) == null, "needs full rage")
	h.rage = BattleUnit.RAGE_MAX
	check(m.available_combo(h) == sworn, "the sworn hero alone can call 结义同心")
	var ev := m.act(BattleModel.Action.COMBO, by_id(m, &"e"))
	check(ev.filter(func(e: Dictionary) -> bool: return e["kind"] == "damage").size() >= 2, "hit + upgraded skill")
	check_eq(h.rage, 0 + BattleModel.RAGE_ON_SKILL, "rage is spent")
	# 山头：三人里有两人同出就算
	check_eq(Factions.shared([&"lin_chong", &"lu_zhishen", &"yang_zhi"] as Array[StringName]), &"", "two of three is not enough")
	check_eq(Factions.shared([&"lin_chong", &"lu_zhishen", &"hua_rong"] as Array[StringName]), &"", "all different")
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
	# 头目不吃控制，控制改成削韧性；韧性打空就破绽：跪地一回合、受到伤害 +30%，跪完韧性回满
	var boss := unit_data(&"b", [100000, 1, 0, 100])
	boss.is_boss = true
	var m2 := battle([unit_data(&"a", [500, 1, 0, 100])], [boss])
	var b := by_id(m2, &"b")
	var a2 := by_id(m2, &"a")
	check(not m2._stun(a2, b, 1), "头目不吃眩晕")
	check_eq(b.stun_turns, 0, "没晕")
	check_eq(b.toughness, BattleUnit.TOUGHNESS_MAX - BattleModel.TOUGHNESS_CONTROL, "控制削一截韧性")
	for i in 3:
		m2._stun(a2, b, 1)
	check_eq(b.toughness, 0, "韧性打空")
	check_eq(b.broken_turns, 1, "破绽")
	check(m2._events.any(func(e: Dictionary) -> bool: return e["popup"] == "破绽"), "破绽有横幅")
	var hp := b.hp
	m2._deal(a2, b, 100.0, true)
	var broken_hit := hp - b.hp
	for i in 4:
		m2.start_next_turn()
		if m2.current != null:
			m2.act(BattleModel.Action.GUARD)
	check_eq(b.broken_turns, 0, "跪完一回合")
	check_eq(b.toughness, BattleUnit.TOUGHNESS_MAX, "韧性回满")
	hp = b.hp
	m2._deal(a2, b, 100.0, true)
	check(broken_hit > (hp - b.hp) * 1.2, "破绽时受到伤害更多（%d vs %d）" % [broken_hit, hp - b.hp])
	# 普攻削韧性：5 点
	var t := b.toughness
	m2._deal(a2, b, 1.0, false, true)
	check_eq(b.toughness, t - BattleModel.TOUGHNESS_BASIC, "普攻削 5 点韧性")
	# 普通敌人照常被控
	var m3 := battle([unit_data(&"a", [500, 1, 0, 100])], [unit_data(&"e", [100000, 1, 0, 100])])
	check(m3._stun(by_id(m3, &"a"), by_id(m3, &"e"), 1), "regular enemies can be stunned")
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
	# 蓄力中韧性被打空：大招作废、重新冷却
	var boss2 := unit_data(&"b", [100000, 100, 0, 100], skill(SkillData.Effect.DAMAGE, {"power": 2.0, "cooldown": 3}))
	boss2.is_boss = true
	var m2 := battle([unit_data(&"a", [100000, 1, 0, 90])], [boss2])
	advance_to(m2, &"b")
	m2.act_ai()
	var b2 := by_id(m2, &"b")
	check(not b2.charge_cells.is_empty(), "蓄力时标出要砸的格子")
	m2._wear_toughness(b2, 1000)
	check(not b2.charging, "韧性打空打断蓄力")
	check(b2.charge_cells.is_empty(), "红格撤掉")
	check_eq(b2.skill_cooldown, 3, "the skill goes back on cooldown")
	# 红格：大招打格子里的人；挪出红格就躲开了
	var boss4 := unit_data(&"b", [100000, 100, 0, 100], skill(SkillData.Effect.DAMAGE, {"power": 2.0, "cooldown": 3}))
	boss4.is_boss = true
	var m5 := battle([unit_data(&"tank", [100000, 1, 0, 80]), unit_data(&"soft", [100000, 1, 0, 70])], [boss4])
	advance_to(m5, &"b")
	m5.act_ai()
	var b5 := by_id(m5, &"b")
	var marked: BattleUnit = null
	for u in [by_id(m5, &"tank"), by_id(m5, &"soft")]:
		if u.cell() in b5.charge_cells:
			marked = u
	check(marked != null, "预告的目标站在红格里")
	check(m5.is_threatened(marked), "红格里的人受威胁")
	check(m5.in_danger(marked), "红格里的人有危险")
	var safe := m5.safe_cell(marked)
	check(safe != Grid.NONE and not safe in b5.charge_cells, "有能躲的空格子")
	# 轮到它就躲开
	advance_to(m5, marked.data.id)
	m5.act_ai()
	check(not marked.cell() in b5.charge_cells, "自动战斗会挪出红格")
	var hp_marked := marked.hp
	advance_to(m5, &"b")
	var ev5 := m5.act_ai()
	check_eq(marked.hp, hp_marked, "挪开了就没挨打")
	check(ev5.any(func(e: Dictionary) -> bool: return e["popup"] == "扑空"), "大招扑空")
	# 普通敌人不蓄力
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


func test_events_carry_hp() -> bool:
	# 连击三下：每一下的 damage 事件都带着那一刻目标还剩的血，一下比一下少，最后一下就是最终血量
	var multi := skill(SkillData.Effect.MULTI_HIT, {"power": 1.0, "hits": 3})
	var m := battle([unit_data(&"a", [500, 100, 0, 100], multi)], [unit_data(&"e", [100000, 1, 0, 1])])
	advance_to(m, &"a")
	var hits := m.act(BattleModel.Action.SKILL, by_id(m, &"e")).filter(func(e: Dictionary) -> bool: return e["kind"] == "damage")
	check_eq(hits.size(), 3, "three hits")
	check(hits[0]["hp"] > hits[1]["hp"] and hits[1]["hp"] > hits[2]["hp"], "hp goes down hit by hit")
	check_eq(hits[2]["hp"], by_id(m, &"e").hp, "the last hit shows the final hp")
	return true


func test_battle_stats() -> bool:
	var m := battle([unit_data(&"a", [500, 100, 0, 100])], [unit_data(&"e", [150, 1, 0, 1])])
	var a := by_id(m, &"a")
	var e := by_id(m, &"e")
	advance_to(m, &"a")
	m.act(BattleModel.Action.ATTACK, e)
	var dealt := m.stats.total(a, "dealt")
	check(dealt > 0, "attack damage counts as dealt")
	check_eq(m.stats.total(e, "taken"), dealt, "the same damage counts as taken")
	check_eq(m.stats.total(a, "attacks"), 1, "one attack")
	check_eq(m.stats.at_round(a, "dealt", 1), dealt, "recorded in round 1")
	while e.is_alive():
		advance_to(m, &"a")
		m.act(BattleModel.Action.ATTACK, e)
	check_eq(m.stats.total(a, "kills"), 1, "the killing blow counts")
	# 治疗、护盾、控制
	var heal := skill(SkillData.Effect.HEAL, {"amount": 0.5})
	var mh := battle([unit_data(&"h", [1000, 1, 0, 100], heal)], [unit_data(&"e", [1000, 1, 0, 1])])
	by_id(mh, &"h").hp = 400
	advance_to(mh, &"h")
	mh.act(BattleModel.Action.SKILL)
	check_eq(mh.stats.total(by_id(mh, &"h"), "healed"), 500, "healing counts")
	check_eq(mh.stats.total(by_id(mh, &"h"), "skills"), 1, "one skill")
	var stun := skill(SkillData.Effect.STUN, {"turns": 1})
	var ms := battle([unit_data(&"s", [1000, 1, 0, 100], stun)], [unit_data(&"e", [1000, 1, 0, 1])])
	advance_to(ms, &"s")
	ms.act(BattleModel.Action.SKILL, by_id(ms, &"e"))
	check_eq(ms.stats.total(by_id(ms, &"s"), "controls"), 1, "control counts")
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
	# 客栈按伤势收钱：伤得越重越贵，等级越高越贵，轻伤有底价
	check_eq(Vitality.rest_price(1, {&"a": 0.9}), Vitality.INN_MIN, "a scratch costs the floor price")
	check_eq(Vitality.rest_price(50, {&"a": 0.1, &"b": 0.1, &"c": 0.1}), 205, "three wounded at Lv50: 2.7 × 50 × 1.5 ≈ 205")
	check(Vitality.rest_price(50, {&"a": 0.1}) > Vitality.rest_price(50, {&"a": 0.6}), "worse wounds cost more")
	check(Vitality.rest_price(20, {&"a": 0.1}) > Vitality.rest_price(10, {&"a": 0.1}), "higher level costs more")
	# 药：固定价钱、按点数回血，档次越高回得越多
	var prev := 0
	for id: StringName in [&"zhi_xue_cao", &"jin_chuang_yao", &"xu_ming_gao", &"huan_hun_dan"]:
		check(Vitality.medicine_heal(id) > prev, "%s heals more than the tier below" % Vitality.medicine_name(id))
		prev = Vitality.medicine_heal(id)
	check(Vitality.medicine_effect(&"jin_chuang_yao").contains("800"), "effect text shows the points")
	check(Vitality.medicine_effect(&"hui_chun_san").begins_with("全队"), "team medicine says 全队")
	# 野外歇脚：打坐的时长、冷却
	check_eq(Vitality.CAMP_SECONDS, 300, "camp takes 5 minutes")
	check_eq(Vitality.CAMP_COOLDOWN, 3600, "one camp per hour")
	for id: StringName in Vitality.MEDICINES:
		check(Vitality.medicine_heal(id) > 0 and Vitality.medicine_price(id) > 0, "%s heals and costs" % Vitality.medicine_name(id))
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
	check_eq(counts, [8, 7, 8, 5], "tier spread 甲8 乙7 丙8 丁5（新加戴宗乙）")
	# 三位召唤型道士：绝招是召唤、带召唤物、召唤物有战斗小人
	for id in [&"gongsun_sheng", &"zhu_wu", &"fan_rui"]:
		var h: UnitData = load("res://data/heroes/%s.tres" % id)
		check_eq(h.role, UnitData.Role.TAOIST, "%s 是道士" % h.display_name)
		check(h.skill.effect == SkillData.Effect.SUMMON and h.skill.summon != null and h.skill.summon.battle_sprite != null, "%s 召唤物齐全" % h.display_name)
	# 朱武在场：阵法加成放大
	var zw: UnitData = load("res://data/heroes/zhu_wu.tres")
	var zhu := Stars.apply(zw, 2)
	var st := StageData.new()
	st.enemies = [unit_data(&"e", [1000, 10, 10, 1])]
	var with_zhu := BattleModel.new(st, [unit_data(&"a", [1000, 10, 50, 100]), unit_data(&"b", [1000, 10, 50, 100]), unit_data(&"c", [1000, 10, 50, 100]), zhu] as Array[UnitData], 1, [], 1, &"yu_lin")
	check(is_equal_approx(by_id(with_zhu, &"a").formation_mods["def"], 0.15 * 1.5), "朱武「神机军师」让阵法加成 +50%")
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


## 进场景时站的格子（出生格、从别的场景走过来的到达格）不能藏在建筑、门楼的图后面，
## 不然一进来就找不到自己（东京街市的出生格曾经就在南城门楼背后）。
func test_arrivals_not_hidden() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var scenes := {}
	for sd: SceneData in GameDB.load_dir("res://data/scenes/"):
		scenes[sd.id] = sd
	var arrivals := {}
	for id: String in scenes:
		var sd: SceneData = scenes[id]
		arrivals[id] = arrivals.get(id, []) + [sd.spawn_cell]
		for door: Vector2i in sd.doors:
			var target: String = sd.doors[door]
			if scenes.has(target):
				arrivals[target] = arrivals.get(target, []) + [sd.door_arrivals.get(door, (scenes[target] as SceneData).spawn_cell)]
	for id: String in arrivals:
		var sd: SceneData = scenes[id]
		var tp := float(sd.tile_pixels)
		for cell: Vector2i in arrivals[id]:
			# 脚底的位置（以格为单位），见 LocationView._feet；场景里的图放大 3 倍（LocationView.PIXEL_SCALE，测试里引用它会拉进 GameState 编译不过）
			var feet := Vector2(cell) + Vector2(0.5, 0.8)
			for prop in sd.props:
				if prop.texture == null or cell.y >= prop.cell.y:
					continue
				var bottom := prop.cell.y + 0.95 + prop.offset.y / (tp * 3)
				var cx := prop.cell.x + 0.5 + prop.offset.x / (tp * 3)
				var half := prop.texture.get_width() / tp / 2.0
				var top := bottom - prop.texture.get_height() / tp
				var hidden := absf(feet.x - cx) < half and feet.y > top and feet.y < bottom
				check(not hidden, "%s 的到达格 %s 藏在 %s 后面" % [id, cell, prop.texture.resource_path.get_file()])
	return true


func test_scene_layout() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	for res in GameDB.load_dir("res://data/scenes/"):
		_check_scene_layout(res as SceneData)
	return true


## 走遍江湖：每扇门通到存在的场景、进门站的格子能站；只靠走门，从东京能走到大地图上的每个地点。
func test_world_links() -> bool:
	var GameDB: GDScript = load("res://scripts/autoload/game_db.gd")
	var scenes := {}
	for sd: SceneData in GameDB.load_dir("res://data/scenes/"):
		scenes[sd.id] = sd
	for sd: SceneData in scenes.values():
		for d: Vector2i in sd.doors:
			var target: String = sd.doors[d]
			check(scenes.has(target), "%s door %s leads to existing %s" % [sd.id, d, target])
			if scenes.has(target):
				var arrive: Vector2i = sd.door_arrivals.get(d, scenes[target].spawn_cell)
				check(scenes[target].is_walkable(arrive), "%s door %s arrives on walkable %s in %s" % [sd.id, d, arrive, target])
		if sd.exit_scene != "":
			check(scenes.has(sd.exit_scene) and scenes[sd.exit_scene].is_walkable(sd.exit_cell), "%s exit lands on walkable %s" % [sd.id, sd.exit_cell])
	var map: WorldMapData = load("res://data/maps/ch1.tres")
	var seen := {"dongjing_street": true}
	var queue: Array = ["dongjing_street"]
	while not queue.is_empty():
		var sd: SceneData = scenes[queue.pop_back()]
		var nexts: Array = sd.doors.values()
		if sd.exit_scene != "":
			nexts.append(sd.exit_scene)
		for n: String in nexts:
			if not seen.has(n) and scenes.has(n):
				seen[n] = true
				queue.append(n)
	for loc in map.locations:
		check(seen.has(loc.scene_id), "%s reachable on foot from 东京" % loc.display_name)
	for road in map.roads:
		check(scenes.has("road_%s_%s" % [road.a, road.b]), "road %s—%s has a map" % [road.a, road.b])
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
	check_eq(origins.size(), 5, "五个职业各一个出身")
	var roles := {}
	for res in origins:
		var o := res as OriginData
		check(o.unit != null, "%s has a unit" % o.id)
		check(o.unit.rarity == UnitData.Rarity.PROTAGONIST, "%s is marked as protagonist" % o.id)
		check(o.unit.map_sprite != null and o.unit.portrait != null, "%s has art" % o.id)
		check(o.martial != null and o.martial.role == o.unit.role, "%s 的开局武学是本职业的" % o.id)
		check_eq(o.start_location, &"dongjing", "%s 从东京开局（别处的怪太强）" % o.id)
		roles[o.unit.role] = true
	check_eq(roles.size(), 5, "五个出身职业各不相同")
	return true


## 名望按做过的事现算；境界决定属性倍数、武学上限、天赋档次；投名状的关卡能生成。
func test_renown_and_realms() -> bool:
	check_eq(Renown.compute({}), 0, "什么都没做名望 0")
	var r := Renown.compute({"heroes": 3, "stories": 1, "bounties": [1, 1, 1], "odd_jobs": 2, "bosses": 1, "arena": 2, "events": 1})
	check_eq(r, 3 * 20 + 30 + 15 + 25 + 40 + 2 * 3 + 25 + 2 * 20 + 10, "名望各项加起来")
	check(not Renown.can_try(0, 99) and Renown.can_try(0, 100), "100 名望能打一阶的投名状")
	check(not Renown.can_try(Renown.MAX_REALM, 99999), "满阶不能再打")
	check(is_equal_approx(Renown.stat_mult(0), 1.0) and is_equal_approx(Renown.stat_mult(5), 1.5), "五阶属性 +50%")
	check_eq(Renown.martial_cap(0), 4, "开局武学最多四重")
	check_eq(Renown.martial_cap(3), 10, "三阶能修到大成")
	check_eq([Renown.talent_rank(0), Renown.talent_rank(1), Renown.talent_rank(4)], [0, 1, 2], "天赋一阶解锁、四阶强化")
	check_eq(Renown.next_threshold(Renown.MAX_REALM), -1, "满阶没有下一阶")
	for n in range(1, Renown.MAX_REALM + 1):
		var st := Renown.trial_stage(n)
		check_eq(st.enemies.size(), 3, "投名状 %d 有三个对手" % n)
		check(st.enemy_level > (Renown.TRIALS[n - 2][1] if n > 1 else 0), "投名状 %d 一阶比一阶强" % n)
		check(Renown.trial_bonus(n).get("trial") == n, "投名状 %d 的奖励带阶数" % n)
	return true


## 号令：随境界解锁；只有统领能用、每场一次、不占出手；自动战斗统领第一次轮到就用。
func test_commands() -> bool:
	check(Commands.unlocked(1).is_empty(), "一阶还没有号令")
	check_eq(Commands.unlocked(2), [Commands.LEIGU] as Array[StringName], "二阶擂鼓")
	check_eq(Commands.unlocked(5).size(), 3, "五阶三个号令都有")
	for id: StringName in Commands.ALL:
		check(Commands.describe(id) != "", "%s 有说明" % id)
	var boss := unit_data(BattleModel.COMMANDER_ID, [500, 100, 0, 200])
	var mate := unit_data(&"b", [500, 100, 0, 50])
	var m := battle([boss, mate], [unit_data(&"e", [100000, 1, 0, 1])])
	m.command = Commands.LEIGU
	advance_to(m, BattleModel.COMMANDER_ID)
	var leader := m.current
	var b := by_id(m, &"b")
	var rage_before := b.rage
	var atk_before := b.atk()
	check(m.can_command(), "统领轮到了能发号令")
	m.use_command()
	check(m.current == leader, "号令不占出手：还是统领的回合")
	check_eq(b.rage, rage_before + Commands.LEIGU_RAGE, "擂鼓加怒气")
	check(b.atk() > atk_before, "擂鼓加攻击")
	check(not m.can_command(), "每场只能用一次")
	m.act(BattleModel.Action.GUARD)
	# 列阵给护盾，鸣金回血；好汉轮到时不能发号令
	var m2 := battle([unit_data(BattleModel.COMMANDER_ID, [500, 100, 0, 200]), unit_data(&"b", [500, 100, 0, 300])], [unit_data(&"e", [100000, 1, 0, 1])])
	m2.command = Commands.LIEZHEN
	advance_to(m2, &"b")
	check(not m2.can_command(), "好汉不能发号令")
	m2.act(BattleModel.Action.GUARD)
	advance_to(m2, BattleModel.COMMANDER_ID)
	m2.use_command()
	check_eq(by_id(m2, &"b").shield, roundi(by_id(m2, &"b").max_hp * Commands.LIEZHEN_SHIELD), "列阵给护盾")
	var m3 := battle([unit_data(BattleModel.COMMANDER_ID, [500, 100, 0, 200])], [unit_data(&"e", [100000, 1, 0, 1])])
	m3.command = Commands.MINGJIN
	advance_to(m3, BattleModel.COMMANDER_ID)
	var me := m3.current
	me.hp = 100
	me.stun_turns = 2
	m3.use_command()
	check_eq(me.hp, 100 + roundi(me.max_hp * Commands.MINGJIN_HEAL), "鸣金回血")
	check_eq(me.stun_turns, 0, "鸣金解控")
	# 自动战斗：统领第一次轮到就发号令，接着照常出手
	var m4 := battle([unit_data(BattleModel.COMMANDER_ID, [500, 100, 0, 200])], [unit_data(&"e", [100000, 1, 0, 1])])
	m4.command = Commands.LEIGU
	advance_to(m4, BattleModel.COMMANDER_ID)
	var events := m4.act_ai()
	check(m4.command_used, "自动战斗会用号令")
	check(m4.current == null, "用完号令接着出手，回合结束")
	check(events.any(func(e: Dictionary) -> bool: return e["kind"] == "skill" and e["popup"] == "擂鼓"), "事件里有号令")
	return true


## 外门武学打七折；每个职业的统领天赋都是现成的天赋种类。
func test_foreign_martial_and_role_talents() -> bool:
	var s := skill(SkillData.Effect.DAMAGE, {"power": 2.0})
	var f := MartialData.foreign(s)
	check(is_equal_approx(f.power, 2.0 * MartialData.FOREIGN_POWER), "外门威力七成")
	check(is_equal_approx(s.power, 2.0), "不改原招")
	for role in 5:
		var t := Renown.role_talent(role)
		check(TalentData.KINDS.has(t.kind), "%s 的统领天赋种类存在" % UiKit.ROLE_NAMES[role])
		check(t.describe(1) != "" and not "{x}" in t.describe(2), "%s 的统领天赋有说明" % UiKit.ROLE_NAMES[role])
	# 统领天赋带进战斗：道士聚气开战全队加怒气
	var taoist := unit_data(&"t", [500, 100, 0, 100])
	taoist.talent = Renown.role_talent(UnitData.Role.TAOIST)
	taoist.talent_rank = 1
	var m := battle([taoist, unit_data(&"b", [500, 100, 0, 100])], [unit_data(&"e", [100000, 1, 0, 1])])
	check_eq(by_id(m, &"b").rage, 20, "聚气：开战全队怒气 +20")
	return true


## 剧本、场景台词里的占位词只用认得的几个（{name}、{兄弟}、{后生}），不然会原样显示出来。
func test_story_placeholders() -> bool:
	var known := ["{name}", "{兄弟}", "{后生}"]
	var re := RegEx.create_from_string("\\{[A-Za-z_\\p{Han}]{1,8}\\}")
	var files: Array[String] = []
	for dir in DirAccess.get_directories_at("res://data/stories"):
		for f in DirAccess.get_files_at("res://data/stories/" + dir):
			if f.ends_with(".txt"):
				files.append("res://data/stories/%s/%s" % [dir, f])
	for f in DirAccess.get_files_at("res://data/scenes"):
		files.append("res://data/scenes/" + f)
	var count := 0
	for path in files:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			check(m.get_string() in known, "%s 里的占位词 %s 认得" % [path.get_file(), m.get_string()])
			if m.get_string() == "{兄弟}":
				count += 1
	check(count >= 20, "列传里好汉称呼统领都换成了 {兄弟}（%d 处）" % count)
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
	check_eq(r["silver"], roundi(4 * Encounters.SILVER_PER_LEVEL) * 3, "elite counts double for silver")
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
	check_eq(Stars.cost(1) + Stars.cost(2) + Stars.cost(3), 60, "lighting all 3 of 丙 costs 60 souls")
	check_eq(Stars.cost(1) + Stars.cost(2) + Stars.cost(3) + Stars.cost(4) + Stars.cost(5), 150, "甲 5 颗全亮要 150 将魂")
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
	check_eq(per_quality, [9, 7, 4, 30], "9 凡品（含 3 匹马）7 良品 4 精品 30 名器（新加戴宗的神行甲马）")
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
	check_eq(all.size(), 20, "11 门武学（5 个出身各一门）+ 9 本技能书的武学")
	for res in all:
		var m: MartialData = res
		check(m.skill != null and m.skill.description != "", "%s has a described skill" % m.display_name)
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
		# 统领（镖师出身、主修押镖横刀的战士）和三位好汉一起上场
		var lead := UnitData.new()
		lead.id = BattleModel.COMMANDER_ID
		lead.display_name = "统领"
		lead.rarity = UnitData.Rarity.PROTAGONIST
		var lead_martial: MartialData = load("res://data/martial/ya_biao_heng_dao.tres")
		lead.role = lead_martial.role
		lead.skill = lead_martial.skill
		var st := Roles.protagonist_stats(lead.role)
		lead.base_hp = st[0]
		lead.base_atk = st[1]
		lead.base_def = st[2]
		lead.base_res = st[3]
		lead.base_spd = st[4]
		lead.base_agi = st[5]
		var team: Array[UnitData] = [lead]
		var label := "统领+"
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

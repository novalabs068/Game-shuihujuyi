extends Node
## 存档：主角（名字、出身）、随行好汉、剧情标记、所在地点（自动加载为 GameState）。
## 存在手机本地 user://save.json。

const SAVE_PATH := "user://save.json"
## 版本不同的旧存档不兼容，当作没有存档
const SAVE_VERSION := 2
## 队伍是主角 + 最多这么多位好汉
const MAX_HEROES := 2
## 新开局送的聚义令，正好一次十连
const STARTING_TOKENS := 10
const DEFAULT_MAP := "ch1"
const PROTAGONIST_ID := &"protagonist"
## 队伍等级上限（M3 做养成时再细分到每个人）
const MAX_LEVEL := 30

var player_name := ""
var origin_id: StringName = &""
var team_ids: Array[StringName] = []
var flags: Dictionary[String, bool] = {}
var location_id: StringName = &""
## 主角和随行好汉共用的队伍等级（M3 前的简化）
var level := 1
var experience := 0
var silver := 0
## 聚义令：抽卡用，只能靠闯荡获得
var tokens := 0
## 已招募的好汉、每位好汉攒下的将魂（重复抽到时得到，M3 升星用）、距上次抽出甲级已经抽了几次
var owned: Array[StringName] = []
var souls: Dictionary[StringName, int] = {}
var pulls_since_jia := 0
## 每位好汉的星数（没记的就是 1 星）、通用货币义气（将魂化来，可换指定好汉的将魂）
var stars: Dictionary[StringName, int] = {}
var yiqi := 0
## 主角和每位好汉的羁绊点数（见 Bonds）
var bonds: Dictionary[StringName, int] = {}
## 气血：没回满的人剩多少（0～1，见 Vitality）；没记的就是满血
var vitality: Dictionary[StringName, float] = {}
## 身上带的药：id → 数量
var medicines: Dictionary[StringName, int] = {}
## 背包里的装备：每件 {"uid": 编号, "id": 模板 id, "holder": 装备在谁身上（空 = 没装备）}
var items: Array[Dictionary] = []
## 主角学会的武学、主修（战斗里放的技能）、副修（被动加成，可以空着）
var martials: Array[StringName] = []
var martial_main: StringName = &""
var martial_side: StringName = &""
## 江湖履历：打赢几场、其中游荡小怪几只、闯荡了多少秒（主角页显示）
var record: Dictionary = {"wins": 0, "roamers": 0, "play_seconds": 0.0, "arena": 0}
## 小悬赏：{地区 id: [{enemy, name, need, have, silver, exp, tokens}, ...]}，见 OddJobs
var jobs: Dictionary = {}
var _next_uid := 1

## 场景里的临时状态（不存档）：{场景 id: {"cleared": 打败的小怪序号, "cell": 打完仗回来站的格子}}。
## 离开场景就清掉，再进来小怪会重新出现
var scene_memory: Dictionary = {}
## 正在打的场景小怪 [场景 id, 序号]；打赢了记进 scene_memory
var pending_roamer: Array = []

var _protagonist: UnitData


func _ready() -> void:
	load_game()


func _process(delta: float) -> void:
	if player_name != "":
		record["play_seconds"] += delta


## 打赢一场就记一笔，同场的好汉羁绊各涨一点（main 在战斗结算时调用）。返回羁绊升级的提示。
func record_win() -> String:
	record["wins"] += 1
	var parts := PackedStringArray()
	for id in team_ids:
		var up := add_bond(id, Bonds.BATTLE_POINTS)
		if up != "":
			parts.append(up)
	return "　".join(parts)


func bond_of(id: StringName) -> int:
	return bonds.get(id, 0)


func sworn(id: StringName) -> bool:
	return has_flag("sworn_" + String(id))


func can_swear(id: StringName) -> bool:
	return owns(id) and not sworn(id) and Bonds.level(bond_of(id)) >= Bonds.SWEAR_LEVEL


## 和羁绊到了知己的好汉结义。
func swear(id: StringName) -> bool:
	if not can_swear(id):
		return false
	set_flag("sworn_" + String(id))
	save_game()
	return true


## 战斗里能用的组合技：好汉之间的，加上和结义兄弟的「结义同心」。
func combos() -> Array[ComboData]:
	var out: Array[ComboData] = GameDB.combos.duplicate()
	for id in owned:
		if sworn(id):
			out.append(Bonds.sworn_combo(GameDB.hero(id), PROTAGONIST_ID))
	return out


## 涨羁绊；升了一级时返回「与林冲的羁绊升到了相熟」，否则返回空。
func add_bond(id: StringName, points: int) -> String:
	if id == PROTAGONIST_ID or not owns(id):
		return ""
	var before := Bonds.level(bond_of(id))
	bonds[id] = bond_of(id) + points
	var after := Bonds.level(bond_of(id))
	if after == before:
		return ""
	return "与%s的羁绊升到了「%s」" % [GameDB.hero(id).display_name, Bonds.NAMES[after]]


## 开新档：起名、选出身，从出身的开局地点出发。
func new_game(p_name: String, origin: OriginData) -> void:
	reset()
	player_name = p_name
	origin_id = origin.id
	location_id = origin.start_location
	tokens = STARTING_TOKENS
	_learn_origin_martial()
	set_flag("tut_on")
	_protagonist = null
	save_game()


func origin() -> OriginData:
	return GameDB.origins.get(origin_id)


## 主角的战斗数据：出身模板的一份复制，名字换成玩家起的名字。
func protagonist() -> UnitData:
	if _protagonist == null:
		var o := origin()
		if o == null:
			return null
		_protagonist = o.unit.duplicate(true)
		_protagonist.id = PROTAGONIST_ID
		_protagonist.display_name = player_name
		_protagonist.rarity = UnitData.Rarity.PROTAGONIST
		var main := martial(martial_main)
		if main != null:
			_protagonist.skill = main.skill
			_protagonist.role = main.role
	return _protagonist


func heroes() -> Array[UnitData]:
	var out: Array[UnitData] = []
	for id in team_ids:
		var hero := GameDB.hero(id)
		if hero != null and id in owned:
			out.append(hero)
	return out


func owns(id: StringName) -> bool:
	return id in owned


## 用聚义令招募 count 次（1 或 10）。返回每一抽的结果 [{hero, is_new}]；聚义令不够时返回空。
## 队伍没满时，新招到的好汉按品级从高到低自动补进去；第一次十连保证出一个甲。
func recruit(count: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if tokens < count:
		return results
	tokens -= count
	var first_ten := count >= 10 and not has_flag("first_ten_pull")
	if count >= 10:
		set_flag("first_ten_pull")
	var outcome := Gacha.pull(GameDB.heroes, count, pulls_since_jia, rng, first_ten)
	pulls_since_jia = outcome["pulls_since_jia"]
	var drawn: Array[UnitData] = []
	drawn.assign(outcome["heroes"])
	var newcomers: Array[UnitData] = []
	for hero in drawn:
		var is_new := not owns(hero.id)
		if is_new:
			owned.append(hero.id)
			newcomers.append(hero)
		else:
			souls[hero.id] = souls.get(hero.id, 0) + Gacha.DUPLICATE_SOULS
		results.append({"hero": hero, "is_new": is_new})
	newcomers.sort_custom(func(a: UnitData, b: UnitData) -> bool: return a.tier < b.tier)
	for hero in newcomers:
		if team_ids.size() < MAX_HEROES:
			team_ids.append(hero.id)
	save_game()
	return results


func star_of(id: StringName) -> int:
	var star: int = stars.get(id, 1)
	# 旧存档按以前的上限（10/8/5/3 星）升过的，压到现在的上限
	var hero := GameDB.hero(id)
	return mini(star, Stars.max_stars(hero)) if hero != null else star


func souls_of(id: StringName) -> int:
	return souls.get(id, 0)


func can_star_up(hero: UnitData) -> bool:
	var star := star_of(hero.id)
	return owns(hero.id) and star < Stars.max_stars(hero) and souls_of(hero.id) >= Stars.cost(star)


## 消耗将魂升 1 星，成功返回 true。
func star_up(hero: UnitData) -> bool:
	if not can_star_up(hero):
		return false
	souls[hero.id] = souls_of(hero.id) - Stars.cost(star_of(hero.id))
	stars[hero.id] = star_of(hero.id) + 1
	save_game()
	return true


## 把 count 个将魂化成义气。
func souls_to_yiqi(id: StringName, count: int) -> bool:
	if count <= 0 or souls_of(id) < count:
		return false
	souls[id] = souls_of(id) - count
	yiqi += count * Stars.YIQI_PER_SOUL
	save_game()
	return true


## 用义气换 count 个指定好汉的将魂（没招到的也能换，攒够了直接招募）。
func buy_souls(hero: UnitData, count: int) -> bool:
	var price := Stars.soul_price(hero) * count
	if count <= 0 or yiqi < price:
		return false
	yiqi -= price
	souls[hero.id] = souls_of(hero.id) + count
	save_game()
	return true


## 没招到的好汉，用将魂直接招募。
func recruit_with_souls(hero: UnitData) -> bool:
	if owns(hero.id) or souls_of(hero.id) < Stars.RECRUIT_SOULS:
		return false
	souls[hero.id] = souls_of(hero.id) - Stars.RECRUIT_SOULS
	owned.append(hero.id)
	if team_ids.size() < MAX_HEROES:
		team_ids.append(hero.id)
	save_game()
	return true


## 战斗用的队伍：好汉带上星级加成，所有人带上装备加成，主角再加上副修武学的加成。
func battle_team() -> Array[UnitData]:
	var out: Array[UnitData] = []
	for u in team():
		var unit := Bonds.apply(Stars.apply(u, star_of(u.id)), bond_of(u.id)) if u.id != PROTAGONIST_ID else u
		out.append(Equipment.apply(unit, effective_gear(u.id)))
	return out


## 开打前的关卡：头目按队伍的养成程度加强（复制一份，不改原关卡）。
func prepare_stage(stage: StageData) -> StageData:
	var st: StageData = stage.duplicate()
	st.boss_power = Encounters.boss_power(team(), battle_team())
	return st


## 算属性时用的「装备」：身上的装备，主角再加副修武学。
func effective_gear(holder: StringName) -> Array[EquipData]:
	var gear := gear_of(holder)
	if holder == PROTAGONIST_ID and martial(martial_side) != null:
		gear.append(martial(martial_side).side_as_gear())
	return gear


# --- 武学 ---

func martial(id: StringName) -> MartialData:
	return GameDB.martials.get(id)


## 学会一门武学，已经会了返回 false。学会的第一门直接主修，第二门直接副修。
func learn_martial(m: MartialData) -> bool:
	if m == null or m.id in martials:
		return false
	martials.append(m.id)
	if martial_main == &"":
		martial_main = m.id
		_protagonist = null
	elif martial_side == &"":
		martial_side = m.id
	save_game()
	return true


## 换主修；原来副修这门的话，两门对调。
func set_martial_main(id: StringName) -> void:
	if not id in martials or id == martial_main:
		return
	if id == martial_side:
		martial_side = martial_main
	martial_main = id
	_protagonist = null
	save_game()


## 换副修；原来主修这门的话，两门对调。
func set_martial_side(id: StringName) -> void:
	if not id in martials or id == martial_side:
		return
	if id == martial_main:
		martial_main = martial_side
		_protagonist = null
	martial_side = id
	save_game()


func _learn_origin_martial() -> void:
	var o := origin()
	if o != null and o.martial != null and not o.martial.id in martials:
		martials.append(o.martial.id)
		if martial_main == &"":
			martial_main = o.martial.id
		_protagonist = null


# --- 场景小怪 ---

func scene_state(scene_id: String) -> Dictionary:
	if not scene_memory.has(scene_id):
		scene_memory[scene_id] = {"cleared": [], "cell": null}
	return scene_memory[scene_id]


## 一场仗打完：如果是场景小怪，赢了就记下它已被打败。
func finish_roamer(won: bool) -> void:
	if won and pending_roamer.size() == 2:
		scene_state(pending_roamer[0])["cleared"].append(pending_roamer[1])
		record["roamers"] += 1
	pending_roamer = []


# --- 列传 ---

func story_done(story: StoryData) -> bool:
	return has_flag(story.flag())


## 能玩的列传：招到了这位好汉、前一段打完了、这一段还没打。
func story_available(story: StoryData) -> bool:
	if not owns(story.hero) or story_done(story):
		return false
	for s in GameDB.stories:
		if s.hero == story.hero and s.order < story.order and not story_done(s):
			return false
	return true


## 某位好汉的列传：[已完成段数, 总段数]
func story_progress(hero_id: StringName) -> Array[int]:
	var done := 0
	var total := 0
	for s in GameDB.stories:
		if s.hero == hero_id:
			total += 1
			if story_done(s):
				done += 1
	return [done, total]


# --- 装备 ---

## 出处已经达成、还没拿到的名器发给玩家（列传完结、悬赏揭下、宝箱打开、擂台打到第几关）。
## 每件只发一次（标记 mingqi_<id>）。返回提示，没有新的返回空。
func claim_mingqi() -> String:
	var parts := PackedStringArray()
	for e: EquipData in GameDB.equipment.values():
		if e.quality != EquipData.Quality.MING or e.source == "" or has_flag("mingqi_" + String(e.id)):
			continue
		if _source_done(e.source):
			set_flag("mingqi_" + String(e.id))
			add_item(e.id)
			parts.append("得到%s「%s」" % [e.quality_name(), e.display_name])
	return "　".join(parts)


func _source_done(source: String) -> bool:
	if source.begins_with("arena:"):
		return Arena.best() >= int(source.get_slice(":", 1))
	return has_flag(source)


## 主角的坐骑（决定在大地图上赶路多快、遇敌多少），没有返回 null。
func mount() -> EquipData:
	for g in gear_of(PROTAGONIST_ID):
		if g.slot == EquipData.Slot.MOUNT:
			return g
	return null


## 放进背包，返回这件的编号。
func add_item(id: StringName) -> int:
	var uid := _next_uid
	_next_uid += 1
	items.append({"uid": uid, "id": id, "holder": &""})
	return uid


func item(uid: int) -> Dictionary:
	for it in items:
		if it["uid"] == uid:
			return it
	return {}


static func item_data(it: Dictionary) -> EquipData:
	return GameDB.equipment.get(it["id"])


## 某人身上的装备（按栏位顺序）。
func gear_of(holder: StringName) -> Array[EquipData]:
	var out: Array[EquipData] = []
	for it in items:
		if it["holder"] == holder:
			out.append(item_data(it))
	out.sort_custom(func(a: EquipData, b: EquipData) -> bool: return a.slot < b.slot)
	return out


## 某人某个栏位上的那件（没有就返回空字典）。
func equipped(holder: StringName, slot: EquipData.Slot) -> Dictionary:
	for it in items:
		if it["holder"] == holder and item_data(it).slot == slot:
			return it
	return {}


## 给 holder 穿上这件：同一栏位原来那件卸下；这件原来在别人身上就从那人身上拿过来。
func equip(holder: StringName, uid: int) -> void:
	var it := item(uid)
	if it.is_empty():
		return
	var old := equipped(holder, item_data(it).slot)
	if not old.is_empty():
		old["holder"] = &""
	it["holder"] = holder
	save_game()


func unequip(uid: int) -> void:
	var it := item(uid)
	if not it.is_empty():
		it["holder"] = &""
		save_game()


## 卖给集市，返回得到的银两。
func sell_item(uid: int) -> int:
	var it := item(uid)
	if it.is_empty():
		return 0
	if not item_data(it).can_sell():
		return 0
	var price := item_data(it).sell_price()
	items.erase(it)
	silver += price
	save_game()
	return price


func buy_item(data: EquipData) -> bool:
	if silver < data.buy_price():
		return false
	silver -= data.buy_price()
	add_item(data.id)
	save_game()
	return true


## 出战队伍：主角在第一位，后面是随行好汉。
func team() -> Array[UnitData]:
	var out: Array[UnitData] = []
	var p := protagonist()
	if p != null:
		out.append(p)
	out.append_array(heroes())
	return out


func set_heroes(list: Array[UnitData]) -> void:
	team_ids.clear()
	for h in list.slice(0, MAX_HEROES):
		team_ids.append(h.id)


## 从 level 升到下一级需要的经验。
static func exp_to_next(at_level: int) -> int:
	return 40 + 30 * at_level


## 加经验和银两，返回升了几级。
func add_rewards(gained_exp: int, gained_silver: int) -> int:
	silver += gained_silver
	experience += gained_exp
	var ups := 0
	while level < MAX_LEVEL and experience >= exp_to_next(level):
		experience -= exp_to_next(level)
		level += 1
		ups += 1
	if level >= MAX_LEVEL:
		experience = 0
	# 升级时全队气血回满
	if ups > 0:
		vitality.clear()
	return ups


# --- 气血和药 ---

func vitality_of(id: StringName) -> float:
	return vitality.get(id, 1.0)


## 打完一仗（赢、输、撤退都算）记下我方每人剩的气血。擂台不算（main 不调这里）。
func record_battle(model: BattleModel) -> void:
	var after := Vitality.after_battle(model)
	for id in after:
		_set_vitality(id, after[id])


func _set_vitality(id: StringName, ratio: float) -> void:
	if ratio >= 0.999:
		vitality.erase(id)
	else:
		vitality[id] = ratio


## 队里有人带「神医」这类全队回春的天赋，赶路回血翻倍。
func has_healer() -> bool:
	for u in battle_team():
		if u.talent != null and u.talent_rank > 0 and u.talent.kind == &"team_regen":
			return true
	return false


## 走完一段路：每人回一点气血。
func road_regen() -> void:
	Vitality.road_regen(vitality, has_healer())
	for id in vitality.keys():
		_set_vitality(id, vitality[id])


## 在有店的地方歇脚：花银两，全队回满。
func rest() -> bool:
	var price := Vitality.rest_price(level)
	if vitality.is_empty() or silver < price:
		return false
	silver -= price
	vitality.clear()
	save_game()
	return true


func buy_medicine(id: StringName) -> bool:
	var price := Vitality.medicine_price(id)
	if silver < price:
		return false
	silver -= price
	medicines[id] = medicines.get(id, 0) + 1
	save_game()
	return true


## 用一份药：全队药不看 target，单人药用在 target 身上。
func use_medicine(id: StringName, target: StringName) -> bool:
	if medicines.get(id, 0) <= 0:
		return false
	var heal := Vitality.medicine_heal(id)
	if Vitality.medicine_for_team(id):
		if vitality.is_empty():
			return false
		for k in vitality.keys():
			_set_vitality(k, vitality[k] + heal)
	else:
		if vitality_of(target) >= 0.999:
			return false
		_set_vitality(target, minf(vitality_of(target) + heal, 1.0))
	medicines[id] -= 1
	if medicines[id] <= 0:
		medicines.erase(id)
	save_game()
	return true


func has_flag(flag: String) -> bool:
	if flag == "":
		return true
	var on: bool = flags.get(flag, false)
	return on


func set_flag(flag: String) -> void:
	if flag != "":
		flags[flag] = true


func reset() -> void:
	player_name = ""
	origin_id = &""
	team_ids.clear()
	owned.clear()
	souls.clear()
	pulls_since_jia = 0
	stars.clear()
	yiqi = 0
	bonds.clear()
	vitality.clear()
	medicines.clear()
	items.clear()
	_next_uid = 1
	martials.clear()
	martial_main = &""
	martial_side = &""
	record = {"wins": 0, "roamers": 0, "play_seconds": 0.0, "arena": 0}
	jobs = {}
	flags.clear()
	location_id = GameDB.maps[DEFAULT_MAP].start_location
	level = 1
	experience = 0
	silver = 0
	tokens = 0
	_protagonist = null


## 新手引导走到第几步（0 = 不用引导，老存档和走完的都是 0）：
## 1 招募 → 2 编队 → 3 打一仗 → 4 看「好汉」页 → 5 看「江湖榜」。
func tutorial_step() -> int:
	if not has_flag("tut_on") or has_flag("tut_done"):
		return 0
	if owned.is_empty():
		return 1
	if team_ids.size() <= 1:
		return 2
	if record["wins"] == 0:
		return 3
	if not has_flag("tut_heroes"):
		return 4
	if not has_flag("tut_jianghu"):
		return 5
	return 0


## 引导里要求看的页面看过了，或者玩家点了「跳过引导」。
func mark_tutorial(flag: String) -> void:
	if tutorial_step() == 0 or has_flag(flag):
		return
	set_flag(flag)
	save_game()


## 清空存档：内存里的进度清掉，存档文件删掉（设置里的「重新开始」）。
func delete_save() -> void:
	reset()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func has_save() -> bool:
	return player_name != "" and origin() != null


func save_game() -> void:
	var team_names: Array[String] = []
	for id in team_ids:
		team_names.append(String(id))
	var data := {
		"version": SAVE_VERSION,
		"name": player_name,
		"origin": String(origin_id),
		"team": team_names,
		"flags": flags.keys(),
		"location": String(location_id),
		"level": level,
		"exp": experience,
		"silver": silver,
		"tokens": tokens,
		"owned": owned.map(func(id: StringName) -> String: return String(id)),
		"souls": _ids_to_json(souls),
		"pulls_since_jia": pulls_since_jia,
		"stars": _ids_to_json(stars),
		"bonds": _ids_to_json(bonds),
		"vitality": _floats_to_json(vitality),
		"medicines": _ids_to_json(medicines),
		"yiqi": yiqi,
		"record": record,
		"jobs": jobs,
		"martials": martials.map(func(id: StringName) -> String: return String(id)),
		"martial_main": String(martial_main),
		"martial_side": String(martial_side),
		"items": items.map(func(it: Dictionary) -> Dictionary: return {"uid": it["uid"], "id": String(it["id"]), "holder": String(it["holder"])}),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("存档失败：%s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_game() -> void:
	reset()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_warning("存档损坏，已重新开始")
		return
	var data: Dictionary = parsed
	var version: int = data.get("version", 0)
	if version != SAVE_VERSION:
		return
	player_name = data.get("name", "")
	origin_id = StringName(data.get("origin", ""))
	var saved_team: Array = data.get("team", [])
	team_ids.clear()
	for id: String in saved_team:
		team_ids.append(StringName(id))
	var saved_flags: Array = data.get("flags", [])
	for flag: String in saved_flags:
		flags[flag] = true
	var saved_location: String = data.get("location", "")
	if saved_location != "":
		location_id = StringName(saved_location)
	level = data.get("level", 1)
	experience = data.get("exp", 0)
	silver = data.get("silver", 0)
	tokens = data.get("tokens", 0)
	var saved_owned: Array = data.get("owned", saved_team)
	for id: String in saved_owned:
		owned.append(StringName(id))
	var saved_souls: Dictionary = data.get("souls", {})
	for id: String in saved_souls:
		souls[StringName(id)] = int(saved_souls[id])
	pulls_since_jia = data.get("pulls_since_jia", 0)
	var saved_stars: Dictionary = data.get("stars", {})
	for id: String in saved_stars:
		stars[StringName(id)] = int(saved_stars[id])
	var saved_vitality: Dictionary = data.get("vitality", {})
	for id: String in saved_vitality:
		vitality[StringName(id)] = float(saved_vitality[id])
	var saved_medicines: Dictionary = data.get("medicines", {})
	for id: String in saved_medicines:
		if Vitality.MEDICINES.has(StringName(id)):
			medicines[StringName(id)] = int(saved_medicines[id])
	var saved_bonds: Dictionary = data.get("bonds", {})
	for id: String in saved_bonds:
		bonds[StringName(id)] = int(saved_bonds[id])
	yiqi = data.get("yiqi", 0)
	var saved_record: Dictionary = data.get("record", {})
	for key in record:
		record[key] = saved_record.get(key, record[key])
	jobs = data.get("jobs", {})
	var saved_martials: Array = data.get("martials", [])
	for id: String in saved_martials:
		if GameDB.martials.has(StringName(id)):
			martials.append(StringName(id))
	martial_main = StringName(data.get("martial_main", ""))
	martial_side = StringName(data.get("martial_side", ""))
	if not martial_main in martials:
		martial_main = &""
	if not martial_side in martials:
		martial_side = &""
	# 有武学之前的旧存档：补上出身自带的那门
	_learn_origin_martial()
	var saved_items: Array = data.get("items", [])
	for it: Dictionary in saved_items:
		if GameDB.equipment.has(StringName(it.get("id", ""))):
			var uid := int(it["uid"])
			items.append({"uid": uid, "id": StringName(it["id"]), "holder": StringName(it.get("holder", ""))})
			_next_uid = maxi(_next_uid, uid + 1)
	# 有名器之前的旧存档：已经打完的列传、揭下的悬赏、开过的宝箱，补发对应的名器
	claim_mingqi()


func _floats_to_json(values: Dictionary[StringName, float]) -> Dictionary:
	var out := {}
	for id in values:
		out[String(id)] = values[id]
	return out


func _ids_to_json(values: Dictionary[StringName, int]) -> Dictionary:
	var out := {}
	for id in values:
		out[String(id)] = values[id]
	return out

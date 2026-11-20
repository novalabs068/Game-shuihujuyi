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

var _protagonist: UnitData


func _ready() -> void:
	load_game()


## 开新档：起名、选出身，从出身的开局地点出发。
func new_game(p_name: String, origin: OriginData) -> void:
	reset()
	player_name = p_name
	origin_id = origin.id
	location_id = origin.start_location
	tokens = STARTING_TOKENS
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
	return stars.get(id, 1)


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


## 战斗用的队伍：好汉带上星级加成。
func battle_team() -> Array[UnitData]:
	var out: Array[UnitData] = []
	for u in team():
		out.append(Stars.apply(u, star_of(u.id)) if u.id != PROTAGONIST_ID else u)
	return out


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
	return ups


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
	flags.clear()
	location_id = GameDB.maps[DEFAULT_MAP].start_location
	level = 1
	experience = 0
	silver = 0
	tokens = 0
	_protagonist = null


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
		"yiqi": yiqi,
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
	yiqi = data.get("yiqi", 0)


func _ids_to_json(values: Dictionary[StringName, int]) -> Dictionary:
	var out := {}
	for id in values:
		out[String(id)] = values[id]
	return out

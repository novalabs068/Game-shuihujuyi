extends Node
## 存档：主角（名字、出身）、随行好汉、剧情标记、所在地点（自动加载为 GameState）。
## 存在手机本地 user://save.json。

const SAVE_PATH := "user://save.json"
## 版本不同的旧存档不兼容，当作没有存档
const SAVE_VERSION := 2
## 队伍是主角 + 最多这么多位好汉
const MAX_HEROES := 2
## M2 还没有抽卡，先给两位不在大相国寺场景里出现的好汉
const DEFAULT_HEROES: Array[StringName] = [&"wu_song", &"hua_rong"]
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

var _protagonist: UnitData


func _ready() -> void:
	load_game()


## 开新档：起名、选出身，从出身的开局地点出发。
func new_game(p_name: String, origin: OriginData) -> void:
	reset()
	player_name = p_name
	origin_id = origin.id
	location_id = origin.start_location
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
		if hero != null:
			out.append(hero)
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
	team_ids = DEFAULT_HEROES.duplicate()
	flags.clear()
	location_id = GameDB.maps[DEFAULT_MAP].start_location
	level = 1
	experience = 0
	silver = 0
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

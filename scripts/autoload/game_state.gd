extends Node
## 存档：队伍、剧情标记、所在地点（自动加载为 GameState）。存在手机本地 user://save.json。

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const DEFAULT_TEAM: Array[StringName] = [&"lu_zhishen", &"lin_chong", &"wu_song"]
const DEFAULT_MAP := "ch1"

var team_ids: Array[StringName] = []
var flags: Dictionary[String, bool] = {}
var location_id: StringName = &""


func _ready() -> void:
	load_game()


func has_flag(flag: String) -> bool:
	if flag == "":
		return true
	var on: bool = flags.get(flag, false)
	return on


func set_flag(flag: String) -> void:
	if flag != "":
		flags[flag] = true


func team() -> Array[UnitData]:
	var out: Array[UnitData] = []
	for id in team_ids:
		var hero := GameDB.hero(id)
		if hero != null:
			out.append(hero)
	return out


func set_team(heroes: Array[UnitData]) -> void:
	team_ids.clear()
	for h in heroes:
		team_ids.append(h.id)


func reset() -> void:
	team_ids = DEFAULT_TEAM.duplicate()
	flags.clear()
	location_id = GameDB.maps[DEFAULT_MAP].start_location


func save_game() -> void:
	var team_names: Array[String] = []
	for id in team_ids:
		team_names.append(String(id))
	var data := {"version": SAVE_VERSION, "team": team_names, "flags": flags.keys(), "location": String(location_id)}
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
	var saved_team: Array = data.get("team", [])
	if not saved_team.is_empty():
		team_ids.clear()
		for id: String in saved_team:
			team_ids.append(StringName(id))
	var saved_flags: Array = data.get("flags", [])
	for flag: String in saved_flags:
		flags[flag] = true
	var saved_location: String = data.get("location", "")
	if saved_location != "":
		location_id = StringName(saved_location)

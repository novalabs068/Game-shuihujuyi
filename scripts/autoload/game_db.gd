extends Node
## 启动时读入 data/ 下的所有好汉、组合技和关卡（自动加载为 GameDB）。

const HEROES_DIR := "res://data/heroes/"
const COMBOS_DIR := "res://data/combos/"
const STAGES_DIR := "res://data/stages/"
const MAPS_DIR := "res://data/maps/"
const SCENES_DIR := "res://data/scenes/"
const ORIGINS_DIR := "res://data/origins/"
const BOUNTIES_DIR := "res://data/bounties/"
const EVENTS_DIR := "res://data/events/"
const EQUIPMENT_DIR := "res://data/equipment/"
const STORIES_DIR := "res://data/stories/"
const MARTIAL_DIR := "res://data/martial/"
const MIJI_DIR := "res://data/miji/"
const VOLUMES_DIR := "res://data/volumes/"

var heroes: Array[UnitData] = []
var combos: Array[ComboData] = []
var stages: Dictionary[String, StageData] = {}
var maps: Dictionary[String, WorldMapData] = {}
var scenes: Dictionary[String, SceneData] = {}
var origins: Dictionary[StringName, OriginData] = {}
var bounties: Array[BountyData] = []
## 赶路时可能发生的奇遇（支线事件挂在 NPC 上，不在这里）
var events: Array[EventData] = []
var equipment: Dictionary[StringName, EquipData] = {}
## 好汉列传，按好汉、段数排好
var stories: Array[StoryData] = []
var martials: Dictionary[StringName, MartialData] = {}
var mijis: Dictionary[StringName, MijiData] = {}
## 江湖年表的各卷，按先后排好（见 VolumeData）
var volumes: Array[VolumeData] = []


func _ready() -> void:
	for res in load_dir(MIJI_DIR):
		var mj := res as MijiData
		mijis[mj.id] = mj
	for res in load_dir(MARTIAL_DIR):
		var m := res as MartialData
		martials[m.id] = m
	for res in load_dir(STORIES_DIR):
		stories.append(res as StoryData)
	stories.sort_custom(func(a: StoryData, b: StoryData) -> bool: return [a.hero, a.order] < [b.hero, b.order])
	for res in load_dir(EQUIPMENT_DIR):
		var item := res as EquipData
		equipment[item.id] = item
	for res in load_dir(HEROES_DIR):
		heroes.append(res as UnitData)
	heroes.sort_custom(func(a: UnitData, b: UnitData) -> bool: return a.sort_order < b.sort_order)
	for res in load_dir(COMBOS_DIR):
		combos.append(res as ComboData)
	for res in load_dir(STAGES_DIR):
		var stage := res as StageData
		stages[stage.id] = stage
	for res in load_dir(MAPS_DIR):
		var map := res as WorldMapData
		maps[map.id] = map
	for res in load_dir(SCENES_DIR):
		var scene := res as SceneData
		scenes[scene.id] = scene
	for res in load_dir(ORIGINS_DIR):
		var origin := res as OriginData
		origins[origin.id] = origin
	for res in load_dir(BOUNTIES_DIR):
		bounties.append(res as BountyData)
	bounties.sort_custom(func(a: BountyData, b: BountyData) -> bool: return a.grade < b.grade)
	for res in load_dir(EVENTS_DIR):
		events.append(res as EventData)
	volumes = Volumes.sorted(load_dir(VOLUMES_DIR))


## 这位好汉结义时传授的独门秘籍（绝品），没有返回 null。
func miji_of_hero(hero_id: StringName) -> MijiData:
	for mj: MijiData in mijis.values():
		if mj.quality == MijiData.Quality.JUE and mj.owner == hero_id:
			return mj
	return null


## 出身按 sort_order 排好的列表，给创建角色界面用。
func origin_list() -> Array[OriginData]:
	var out: Array[OriginData] = []
	out.assign(origins.values())
	out.sort_custom(func(a: OriginData, b: OriginData) -> bool: return a.sort_order < b.sort_order)
	return out


## 某个地点还没揭下的悬赏。
func open_bounties(location_id: StringName) -> Array[BountyData]:
	var out: Array[BountyData] = []
	for b in bounties:
		if b.location == location_id and not GameState.has_flag("bounty_" + String(b.id)):
			out.append(b)
	return out


func hero(id: StringName) -> UnitData:
	for h in heroes:
		if h.id == id:
			return h
	return null


## 导出后的包里文件名会变（.remap），所以用 ResourceLoader.list_directory 而不是 DirAccess。
static func load_dir(path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for file in ResourceLoader.list_directory(path):
		if file.ends_with(".tres") or file.ends_with(".res"):
			out.append(load(path + file))
	return out

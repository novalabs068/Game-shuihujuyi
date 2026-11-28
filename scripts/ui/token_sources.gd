class_name TokenSources
extends Control
## 「聚义令从哪来」：盖在招募页（或行囊）上的一张单子，列出眼下还能拿到聚义令的事，等级合适、离得近的排前面，
## 每条带「前往」，点了去大地图看那里。聚义令只能闯荡江湖得来，玩家不知道去哪拿时就看这里。

signal closed
signal travel_requested(location_id: StringName)

## 同一类最多列几条（太多就看江湖榜）
const PER_KIND := 3
const KIND_COLORS := {
	"城中悬赏": Color("b0401a"), "初到": Color("2f5f8a"), "宝箱": Color("7a5a2a"),
	"悬赏": Color("a8291d"), "列传": Color("8a5a12"), "擂台": Color("8a5a12"), "差事": Color("9a4a1a"),
}


## 眼下还能拿聚义令的事：[{kind, text, detail, gain, location, level}]，按种类分组、每组按等级。
static func sources() -> Array[Dictionary]:
	var map: WorldMapData = GameDB.maps[GameState.DEFAULT_MAP]
	var out: Array[Dictionary] = []
	# 城中悬赏：每天每处一张，必给
	for region in GameState.visited_regions():
		var city := GameState.city_entry(region)
		var job: Dictionary = city.get("job", {})
		if not job.is_empty():
			out.append({"kind": "城中悬赏", "text": "%s：%s" % [map.location(region).display_name, OddJobs.describe(job)], "detail": "每天每处贴一张，攒着不过期", "gain": "%d 枚" % job["tokens"], "location": region, "level": map.location(region).level_min})
	# 第一次去
	for loc in map.locations:
		if not GameState.has_flag("visited_" + String(loc.id)) and loc.id != GameState.location_id:
			out.append({"kind": "初到", "text": "第一次去%s" % loc.display_name, "detail": "%d 级起" % loc.level_min, "gain": "%d 枚" % WorldMapView.FIRST_VISIT_TOKENS, "location": loc.id, "level": loc.level_min})
	# 宝箱：按地方合在一起
	for loc in map.locations:
		var scene: SceneData = GameDB.scenes.get(loc.scene_id)
		if scene == null:
			continue
		var n := 0
		var sum := 0
		for chest in scene.chests:
			if chest.tokens > 0 and not GameState.has_flag("chest_%s_%s" % [scene.id, chest.id]):
				n += 1
				sum += chest.tokens
		if n > 0:
			out.append({"kind": "宝箱", "text": "%s还有 %d 个宝箱藏着聚义令" % [loc.display_name, n], "detail": "进去四处找找", "gain": "共 %d 枚" % sum, "location": loc.id, "level": loc.level_min})
	# 大悬赏
	for b in GameDB.bounties:
		if not GameState.has_flag("bounty_" + String(b.id)):
			out.append({"kind": "悬赏", "text": "%s等悬赏「%s」" % [b.grade_name(), b.target], "detail": "在%s" % map.location(b.location).display_name, "gain": "%d 枚" % b.tokens(), "location": b.location, "level": b.stage.enemy_level})
	# 列传
	for story in GameDB.stories:
		if story.tokens > 0 and GameState.story_available(story):
			out.append({"kind": "列传", "text": "%s列传·%s" % [GameDB.hero(story.hero).display_name, story.title], "detail": "在%s" % map.location(story.location).display_name, "gain": "%d 枚" % story.tokens, "location": story.location, "level": story.recommended_level})
	# 擂台：下一个给聚义令的关
	for n: int in Arena.FIRST_TOKENS:
		if n > Arena.best():
			out.append({"kind": "擂台", "text": "擂台第 %d 关首胜" % n, "detail": "东京街市的擂台", "gain": "%d 枚" % Arena.FIRST_TOKENS[n], "location": &"dongjing", "level": Arena.stage(n).enemy_level})
			break
	# 小悬赏：能一直做
	out.append({"kind": "差事", "text": "小悬赏（各地告示栏，做完马上换新的）", "detail": "不用接，打赢了就算", "gain": "有时 1 枚", "location": &"", "level": 0})
	return out


## 一次性的还能拿多少枚（初到、宝箱、悬赏、列传、擂台加起来）。
static func one_time_total() -> int:
	var total := 0
	var map: WorldMapData = GameDB.maps[GameState.DEFAULT_MAP]
	for loc in map.locations:
		if not GameState.has_flag("visited_" + String(loc.id)) and loc.id != GameState.location_id:
			total += WorldMapView.FIRST_VISIT_TOKENS
		var scene: SceneData = GameDB.scenes.get(loc.scene_id)
		if scene != null:
			for chest in scene.chests:
				if not GameState.has_flag("chest_%s_%s" % [scene.id, chest.id]):
					total += chest.tokens
	for b in GameDB.bounties:
		if not GameState.has_flag("bounty_" + String(b.id)):
			total += b.tokens()
	for story in GameDB.stories:
		if not GameState.story_done(story):
			total += story.tokens
	for n: int in Arena.FIRST_TOKENS:
		if n > Arena.best():
			total += Arena.FIRST_TOKENS[n]
	return total


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	panel.custom_minimum_size = Vector2(820, 600)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var ink := Color("1e1c1a")
	var title := UiKit.brush_label("聚义令从哪来", 36, ink)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var lead := UiKit.label("聚义令只能闯荡江湖得来。下面是你眼下还能拿到的，等级合适的排前面。", 16, Color("5a4a3a"))
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lead)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var all := sources()
	var lv := GameState.level
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# 没有地点的（小悬赏）放最后；打得过的先（等级不超过统领 3 级），同样打得过的按等级从低到高
		if (a["location"] == &"") != (b["location"] == &""):
			return b["location"] == &""
		var fa := int(a["level"]) <= lv + Guide.LEVEL_SLACK
		var fb := int(b["level"]) <= lv + Guide.LEVEL_SLACK
		if fa != fb:
			return fa
		return int(a["level"]) < int(b["level"]))
	var shown := {}
	for item in all:
		var kind: String = item["kind"]
		if int(shown.get(kind, 0)) >= PER_KIND:
			continue
		shown[kind] = int(shown.get(kind, 0)) + 1
		list.add_child(_row(item))
	var foot := UiKit.label("一次性的还能拿约 %d 枚；城中悬赏每天每个去过的地方再贴一张（2～3 枚），几天不来就攒着。" % one_time_total(), 15, Color("5a4a3a"))
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(foot)
	var close := UiKit.plaque_button("知道了", Vector2(170, 54), false, 26)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: closed.emit())
	v.add_child(close)


func _row(item: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiKit.note_box())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var tag := UiKit.seal_label(item["kind"], 16, false, KIND_COLORS.get(item["kind"], UiKit.CINNABAR))
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	h.add_child(info)
	info.add_child(UiKit.label(item["text"], 18, UiKit.INK))
	var level: int = item["level"]
	info.add_child(UiKit.label(item["detail"] + ("　%d 级" % level if level > 0 and item["kind"] != "初到" else ""), 13, UiKit.INK_DIM))
	var gain := UiKit.label(item["gain"], 17, UiKit.CINNABAR)
	gain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gain.custom_minimum_size.x = 80
	gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(gain)
	var loc: StringName = item["location"]
	if loc != &"":
		var go := UiKit.button("前往", Vector2(84, 38), 17)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(func() -> void: travel_requested.emit(loc))
		h.add_child(go)
	return row

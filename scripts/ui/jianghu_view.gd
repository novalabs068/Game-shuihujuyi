class_name JiangHuView
extends Control
## 江湖榜：没有主线时，玩家从这里看「接下来能做什么」。三页：可以做的事、悬赏榜、好汉图鉴。

signal back_requested
## 点「在哪」：打开大地图看这个地点（怎么走过去）
signal travel_requested(location_id: StringName)
## 点图鉴里的好汉或「去升星」：打开好汉页
signal heroes_requested

enum Tab { TODO, BOUNTIES, ALBUM }

## 图鉴竖卡的大小：一行 8 张
const ALBUM_CARD := Vector2(140, 210)
const TAB_NAMES: Array[String] = ["可以做的事", "悬赏榜", "好汉图鉴"]
const KIND_COLORS := {
	"列传": Color("e0b040"),
	"悬赏": Color("e05a4a"),
	"初到": Color("6aa8f0"),
	"宝箱": Color("c8a060"),
	"支线": Color("a070e0"),
	"养成": Color("7be07f"),
	"差事": Color("e09a5a"),
	"擂台": Color("e0b040"),
}

var _tab := Tab.TODO
var _tab_buttons: Array[Button] = []
var _body: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	GameState.mark_tutorial("tut_jianghu")
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	top.add_child(UiKit.label("江湖榜", 32, UiKit.GOLD))
	for i in TAB_NAMES.size():
		var b := UiKit.button(TAB_NAMES[i], Vector2(150, 46), 20)
		b.pressed.connect(_switch.bind(i))
		top.add_child(b)
		_tab_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var back := UiKit.button("返回", Vector2(110, 46), 22)
	back.pressed.connect(func() -> void: back_requested.emit())
	top.add_child(back)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)
	_switch(Tab.TODO)


func _switch(tab: int) -> void:
	_tab = tab as Tab
	for i in _tab_buttons.size():
		_tab_buttons[i].disabled = i == tab
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical = 0
	match _tab:
		Tab.TODO:
			_show_todo()
		Tab.BOUNTIES:
			_show_bounties()
		Tab.ALBUM:
			_show_album()


# --- 可以做的事 ---

func _show_todo() -> void:
	var items := todo_items()
	if items.is_empty():
		_body.add_child(UiKit.label("眼下没什么急事。四处走走，说不定会碰上奇遇。", 22, UiKit.TEXT_DIM))
	for item in items:
		_body.add_child(_todo_row(item))


## 现在能做的事，按种类排好：{kind, text, detail, location, level}。location 为空表示不用赶路。
static func todo_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var map: WorldMapData = GameDB.maps[GameState.DEFAULT_MAP]
	var here := GameState.location_id
	var name_of := func(id: StringName) -> String: return map.location(id).display_name
	# 列传：能玩的段，和还没招到人的列传
	var teased: Array[StringName] = []
	for story in GameDB.stories:
		var hero := GameDB.hero(story.hero)
		if GameState.story_available(story):
			out.append({"kind": "列传", "text": "%s列传·%s" % [hero.display_name, story.title], "detail": "在%s" % name_of.call(story.location), "location": story.location, "level": story.recommended_level})
		elif not GameState.owns(story.hero) and not story.hero in teased:
			teased.append(story.hero)
			var count := GameDB.stories.filter(func(s: StoryData) -> bool: return s.hero == story.hero).size()
			out.append({"kind": "列传", "text": "招到%s后，可以玩「%s列传」（%d 段）" % [hero.display_name, hero.display_name, count], "detail": "去聚义厅招募", "location": &"", "level": 0})
	# 悬赏：按等级从低到高
	var open: Array[BountyData] = []
	for b in GameDB.bounties:
		if not GameState.has_flag("bounty_" + String(b.id)):
			open.append(b)
	open.sort_custom(func(a: BountyData, b: BountyData) -> bool: return a.stage.enemy_level < b.stage.enemy_level)
	for b in open:
		out.append({"kind": "悬赏", "text": "%s等悬赏「%s」" % [b.grade_name(), b.target], "detail": "在%s，赏聚义令 %d、%s装备" % [name_of.call(b.location), b.tokens(), EquipData.QUALITY_NAMES[b.equip_quality()]], "location": b.location, "level": b.stage.enemy_level})
	# 小悬赏：已经在告示栏上看过的地区
	for region in GameState.jobs:
		for job: Dictionary in GameState.jobs[region]:
			out.append({"kind": "差事", "text": "小悬赏：" + OddJobs.describe(job), "detail": "在%s一带，赏%s" % [name_of.call(StringName(region)), OddJobs.reward_text(job)], "location": StringName(region), "level": 0})
	# 擂台
	if Arena.best() < Arena.round_count():
		var next := Arena.best() + 1
		out.append({"kind": "擂台", "text": "擂台第 %d 关" % next, "detail": "在东京街市，首胜赏%s" % Arena.first_reward_text(next), "location": &"dongjing", "level": Arena.stage(next).enemy_level})
	# 初到：第一次去一个地点给聚义令（眼下所在的地方要离开再回来才算，不列出）
	for loc in map.locations:
		if loc.id != here and not GameState.has_flag("visited_" + String(loc.id)):
			out.append({"kind": "初到", "text": "第一次去%s" % loc.display_name, "detail": "聚义令 +%d" % WorldMapView.FIRST_VISIT_TOKENS, "location": loc.id, "level": loc.level_min})
	# 地点场景里没开的宝箱、没做的支线
	for loc in map.locations:
		var scene: SceneData = GameDB.scenes.get(loc.scene_id)
		if scene == null:
			continue
		for chest in scene.chests:
			if not GameState.has_flag("chest_%s_%s" % [scene.id, chest.id]):
				out.append({"kind": "宝箱", "text": "%s还有一个宝箱没打开" % scene.title, "detail": "在%s，进去找找" % loc.display_name, "location": loc.id, "level": 0})
		for npc in scene.npcs:
			if npc.event != null and not GameState.has_flag("event_" + String(npc.event.id)) and (npc.hide_flag == "" or not GameState.has_flag(npc.hide_flag)):
				out.append({"kind": "支线", "text": "%s：%s那边好像有事" % [scene.title, npc.display_name], "detail": "在%s，进去和他说说话" % loc.display_name, "location": loc.id, "level": 0})
	# 养成
	var can_up := GameDB.heroes.filter(func(h: UnitData) -> bool: return GameState.can_star_up(h))
	for h: UnitData in can_up:
		out.append({"kind": "养成", "text": "%s的将魂够升星了" % h.display_name, "detail": "去好汉页", "location": &"", "level": 0})
	if GameState.tokens >= Gacha.MULTI:
		out.append({"kind": "养成", "text": "聚义令有 %d 枚，够一次五连" % GameState.tokens, "detail": "去聚义厅招募", "location": &"", "level": 0})
	return out


func _todo_row(item: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.PANEL_LIGHT, 1, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var kind: String = item["kind"]
	var tag := UiKit.label(kind, 20, KIND_COLORS[kind])
	tag.custom_minimum_size.x = 56
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(tag)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	h.add_child(info)
	info.add_child(UiKit.label(item["text"], 22))
	info.add_child(UiKit.label(item["detail"], 16, UiKit.TEXT_DIM))
	var level: int = item["level"]
	if level > 0:
		h.add_child(_level_label(level))
	var location: StringName = item["location"]
	if location != &"":
		var go := UiKit.button("就在这里" if location == GameState.location_id else "在哪", Vector2(120, 46), 20)
		go.pressed.connect(func() -> void: travel_requested.emit(location))
		h.add_child(go)
	elif kind == "养成" or kind == "列传":
		var open := UiKit.button("去看看", Vector2(120, 46), 20)
		open.pressed.connect(func() -> void: heroes_requested.emit())
		h.add_child(open)
	return row


## 「推荐 12 级」：比队伍等级高得多时变红，略高时变橙。
func _level_label(level: int) -> Label:
	var gap := level - GameState.level
	var color := UiKit.HEAL if gap <= 0 else (UiKit.RAGE if gap <= 3 else UiKit.DAMAGE)
	var label := UiKit.label("%d 级" % level, 20, color)
	label.custom_minimum_size.x = 70
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


# --- 悬赏榜 ---

func _show_bounties() -> void:
	var all := GameDB.bounties.duplicate()
	all.sort_custom(func(a: BountyData, b: BountyData) -> bool: return a.stage.enemy_level < b.stage.enemy_level)
	var done := all.filter(func(b: BountyData) -> bool: return GameState.has_flag("bounty_" + String(b.id))).size()
	_body.add_child(UiKit.label("已揭下 %d / %d 张悬赏。按难度从低到高排。" % [done, all.size()], 20, UiKit.TEXT_DIM))
	var map: WorldMapData = GameDB.maps[GameState.DEFAULT_MAP]
	for b: BountyData in all:
		var taken := GameState.has_flag("bounty_" + String(b.id))
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.PANEL_LIGHT, 1, 8))
		row.modulate = Color(0.6, 0.6, 0.6) if taken else Color.WHITE
		_body.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var grade := UiKit.label(b.grade_name(), 30, KIND_COLORS["悬赏"])
		grade.custom_minimum_size.x = 50
		grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(grade)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		h.add_child(info)
		info.add_child(UiKit.label("%s　%s" % [b.target, map.location(b.location).display_name], 22))
		info.add_child(UiKit.label("赏：聚义令 %d、%s装备一件%s、%s" % [b.tokens(), EquipData.QUALITY_NAMES[b.equip_quality()], b.miji_text(), Vitality.medicine_name(b.medicine())], 16, UiKit.TEXT_DIM))
		h.add_child(_level_label(b.stage.enemy_level))
		if taken:
			h.add_child(UiKit.label("已揭", 20, UiKit.TEXT_DIM))
		else:
			var go := UiKit.button("就在这里" if b.location == GameState.location_id else "在哪", Vector2(120, 46), 20)
			go.pressed.connect(func() -> void: travel_requested.emit(b.location))
			h.add_child(go)


# --- 好汉图鉴 ---

func _show_album() -> void:
	var owned := GameDB.heroes.filter(func(h: UnitData) -> bool: return GameState.owns(h.id)).size()
	var counts := {}
	for h in GameDB.heroes:
		var key: int = h.rarity
		if not counts.has(key):
			counts[key] = [0, 0]
		counts[key][1] += 1
		if GameState.owns(h.id):
			counts[key][0] += 1
	var parts := PackedStringArray()
	for r in counts:
		parts.append("%s %d/%d" % [UiKit.RARITY_NAMES[r], counts[r][0], counts[r][1]])
	_body.add_child(UiKit.label("已招募 %d / %d 位（%s）。108 将会陆续加入卡池。点卡片看详情。" % [owned, GameDB.heroes.size(), "、".join(parts)], 20, UiKit.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(grid)
	var heroes := GameDB.heroes.duplicate()
	heroes.sort_custom(func(a: UnitData, b: UnitData) -> bool: return [a.tier, a.sort_order] < [b.tier, b.sort_order])
	for h: UnitData in heroes:
		grid.add_child(_album_cell(h))


## 图鉴里一张竖卡：招到的照常显示（勾玉按星级点亮），没招到的只露一个黑影。
func _album_cell(hero: UnitData) -> Control:
	var owned := GameState.owns(hero.id)
	var cell := HeroCard.make(hero, ALBUM_CARD, Stars.lit(GameState.star_of(hero.id)) if owned else 0, "", UiKit.GOLD, not owned)
	UiKit.ignore_mouse(cell)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	var pressed_at := [Vector2.INF]
	cell.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or click.button_index != MOUSE_BUTTON_LEFT:
			return
		if click.pressed:
			pressed_at[0] = click.global_position
		elif owned and click.global_position.distance_to(pressed_at[0]) < TeamSelect.TAP_SLOP:
			heroes_requested.emit())
	return cell

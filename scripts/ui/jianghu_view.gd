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
## 每种事前面那方小印的颜色（压在宣纸字条上，用深色）
const KIND_COLORS := {
	"列传": Color("8a5a12"),
	"悬赏": Color("a8291d"),
	"初到": Color("2f5f8a"),
	"宝箱": Color("7a5a2a"),
	"支线": Color("5a3480"),
	"养成": Color("3f6a3a"),
	"差事": Color("9a4a1a"),
	"擂台": Color("8a5a12"),
}
## 告示墙的木板宽
const PLANK := 160.0
## 悬赏告示一行至少几张、每张多宽、间距（屏幕宽了一行多贴几张）
const NOTICE_COLUMNS := 4
const NOTICE_WIDTH := 250.0
const NOTICE_GAP := 24

var _tab := Tab.TODO
var _tab_buttons: Array[Button] = []
var _body: VBoxContainer
var _scroll: ScrollContainer
var _notice_grid: GridContainer


func _ready() -> void:
	GameState.mark_tutorial("tut_jianghu")
	_build_wall()
	var title := UiKit.title_plaque("江　湖　榜", 40)
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 14
	var back := UiKit.back_button()
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -74
	back.offset_right = -20
	back.offset_top = 16
	back.pressed.connect(func() -> void: back_requested.emit())
	var margin := MarginContainer.new()
	# 内容区不吃点击，免得盖住左边的木签（它铺满全屏，左边只是留了边距）
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 104)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 92)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	margin.add_child(v)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_scroll.resized.connect(func() -> void:
		if _tab == Tab.BOUNTIES:
			_layout_notices())
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)
	# 左边挂三支木签切页（加在内容区后面，压在上面才点得到）
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 18)
	tabs.position = Vector2(24, 104)
	add_child(tabs)
	for i in TAB_NAMES.size():
		var b := UiKit.slip_button(TAB_NAMES[i], 52, 22)
		b.pressed.connect(_switch.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_switch(Tab.TODO)


func _switch(tab: int) -> void:
	_tab = tab as Tab
	for i in _tab_buttons.size():
		UiKit.set_slip_lit(_tab_buttons[i], i == tab)
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
		_body.add_child(UiKit.label("眼下没什么急事。四处走走，说不定会碰上奇遇。", 22, Color("e9d3a0")))
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
	row.add_theme_stylebox_override("panel", UiKit.note_box())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var kind: String = item["kind"]
	var tag := UiKit.seal_label(kind, 18, false, KIND_COLORS[kind])
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	h.add_child(info)
	info.add_child(UiKit.label(item["text"], 19, UiKit.INK))
	info.add_child(UiKit.label(item["detail"], 14, UiKit.INK_DIM))
	var level: int = item["level"]
	if level > 0:
		h.add_child(_level_label(level))
	var location: StringName = item["location"]
	if location != &"":
		var go := UiKit.button("就在这里" if location == GameState.location_id else "在哪", Vector2(110, 42), 20)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(func() -> void: travel_requested.emit(location))
		h.add_child(go)
	elif kind == "养成" or kind == "列传":
		var open := UiKit.button("去看看", Vector2(110, 42), 20)
		open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		open.pressed.connect(func() -> void: heroes_requested.emit())
		h.add_child(open)
	return row


## 「推荐 12 级」：比队伍等级高得多时变红，略高时变橙。
func _level_label(level: int) -> Label:
	var gap := level - GameState.level
	var color := Color("3f6a3a") if gap <= 0 else (Color("b0661a") if gap <= 3 else UiKit.CINNABAR)
	var label := UiKit.label("%d 级" % level, 17, color)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size.x = 70
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


# --- 悬赏榜 ---

func _show_bounties() -> void:
	var all := GameDB.bounties.duplicate()
	all.sort_custom(func(a: BountyData, b: BountyData) -> bool: return a.stage.enemy_level < b.stage.enemy_level)
	var done := all.filter(func(b: BountyData) -> bool: return GameState.has_flag("bounty_" + String(b.id))).size()
	_body.add_child(UiKit.label("已揭下 %d / %d 张悬赏，按难度从低到高贴" % [done, all.size()], 16, Color("e9d3a0")))
	var map: WorldMapData = GameDB.maps[GameState.DEFAULT_MAP]
	var grid := GridContainer.new()
	grid.columns = NOTICE_COLUMNS
	grid.add_theme_constant_override("h_separation", NOTICE_GAP)
	grid.add_theme_constant_override("v_separation", 22)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(grid)
	_notice_grid = grid
	var i := 0
	for b: BountyData in all:
		grid.add_child(_notice(b, map, i))
		i += 1
	_layout_notices()


## 屏幕宽了一行多贴几张告示（按内容区宽算），整排居中。
func _layout_notices() -> void:
	if _notice_grid == null or not is_instance_valid(_notice_grid):
		return
	_notice_grid.columns = maxi(1, int((_scroll.size.x - 16 + NOTICE_GAP) / (NOTICE_WIDTH + NOTICE_GAP)))


## 一张钉在墙上的悬赏告示：「悬赏」大字、对象、地点等级、赏格；揭过的盖「已揭」大红印。
func _notice(b: BountyData, map: WorldMapData, index: int) -> Control:
	var taken := GameState.has_flag("bounty_" + String(b.id))
	var paper := PanelContainer.new()
	var style := UiKit.note_box()
	style.content_margin_top = 18
	style.content_margin_bottom = 12
	paper.add_theme_stylebox_override("panel", style)
	paper.custom_minimum_size = Vector2(NOTICE_WIDTH, 0)
	# 每张歪一点，像随手钉上去的
	paper.rotation = deg_to_rad([-1.4, 1.0, -0.5, 1.6][index % 4])
	paper.resized.connect(func() -> void: paper.pivot_offset = paper.size / 2)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	paper.add_child(v)
	var head := UiKit.brush_label("%s等悬赏" % b.grade_name(), 34, UiKit.INK)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var line := ColorRect.new()
	line.color = Color(UiKit.GILT, 0.7)
	line.custom_minimum_size.y = 1
	v.add_child(line)
	var target := UiKit.brush_label(b.target, 24, UiKit.INK)
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(target)
	var where := HBoxContainer.new()
	where.alignment = BoxContainer.ALIGNMENT_CENTER
	where.add_theme_constant_override("separation", 10)
	where.add_child(UiKit.label(map.location(b.location).display_name, 15, UiKit.INK_DIM))
	where.add_child(_level_label(b.stage.enemy_level))
	v.add_child(where)
	var reward := UiKit.label("赏 聚义令 %d　%s装备一件%s\n%s" % [b.tokens(), EquipData.QUALITY_NAMES[b.equip_quality()], b.miji_text(), Vitality.medicine_name(b.medicine())], 13, UiKit.INK)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(reward)
	if taken:
		var gap := Control.new()
		gap.custom_minimum_size.y = 42
		v.add_child(gap)
		var stamp := UiKit.seal_label("已揭", 34, false, Color(UiKit.CINNABAR, 0.88))
		stamp.rotation = deg_to_rad(-14)
		paper.add_child(stamp)
		stamp.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		paper.modulate = Color(0.88, 0.85, 0.8)
	else:
		var go := UiKit.button("就在这里" if b.location == GameState.location_id else "在哪", Vector2(110, 40), 19)
		go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(func() -> void: travel_requested.emit(b.location))
		v.add_child(go)
	return paper


## 告示墙：一块块竖着的木板，四周压暗。
func _build_wall() -> void:
	var wall := Control.new()
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wall)
	wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wall.draw.connect(func() -> void:
		var x := 0.0
		var i := 0
		while x < wall.size.x:
			var tone := Color("3b2616").lerp(Color("33200f"), float(i % 3) / 2.0)
			wall.draw_rect(Rect2(x, 0, PLANK, wall.size.y), tone)
			for k in 6:
				var gx := x + 18 + k * 24 + (i * 7 % 11)
				wall.draw_line(Vector2(gx, 0), Vector2(gx + 6, wall.size.y), Color(0, 0, 0, 0.12), 1.0)
			wall.draw_rect(Rect2(x + PLANK - 4, 0, 4, wall.size.y), Color("1e130a"))
			x += PLANK
			i += 1)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.65))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.1, 1.1)
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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
	_body.add_child(UiKit.label("已招募 %d / %d 位（%s）。108 将会陆续加入卡池。点卡片看详情。" % [owned, GameDB.heroes.size(), "、".join(parts)], 16, Color("e9d3a0")))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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

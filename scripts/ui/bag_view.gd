class_name BagView
extends Control
## 行囊：身上带的所有东西都在这一页看——装备（兵器、护具、饰物、坐骑）、秘籍、药、将魂、残页、甲马。
## 左边木签分类，中间一格一样东西（格子底下的色条是品质，右上角是数目，「装」= 有人正用着），
## 右边是选中那样的详情和能做的事（卖掉、给谁用、去好汉页换装……）。
## 换装、换秘籍还是在好汉页做，这里只给个「去好汉页」，免得两处都能改、玩家搞混。

signal back_requested
## 去好汉页（换装、升星、换秘籍）
signal heroes_requested
## 点了顶上的「聚义令」：打开「聚义令从哪来」，里面点「在哪」去大地图
signal travel_requested(location_id: StringName)

const TAB_NAMES: Array[String] = ["全部", "兵甲", "秘籍", "药物", "杂物"]
## 品质色条：凡品 灰、良品 绿、精品 蓝、名器 / 绝品 金
const QUALITY_COLORS: Array[Color] = [Color("7a6a58"), Color("3f7a3a"), Color("2f5f9a"), Color("b0661a")]
## 装备栏位在格子里写的字
const SLOT_GLYPHS: Array[String] = ["兵", "甲", "饰", "骑"]
## 一行几格、格子多大
const COLUMNS := 8
const CELL := Vector2(78, 84)

var _tab := 0
var _picked := 0
var _tab_buttons: Array[Button] = []
var _grid: GridContainer
var _detail: VBoxContainer
var _purse: HBoxContainer
var _entries: Array[Dictionary] = []


func _ready() -> void:
	var wall := ColorRect.new()
	wall.color = Color("33200f")
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wall)
	wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := UiKit.title_plaque("行　　囊", 40)
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
	# 家当：银两、聚义令、义气、残页、修为
	_purse = HBoxContainer.new()
	_purse.add_theme_constant_override("separation", 22)
	_purse.position = Vector2(104, 78)
	add_child(_purse)
	# 中间格子（可以滚）
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 104
	scroll.offset_top = 116
	scroll.offset_bottom = -40
	scroll.offset_right = 104 + COLUMNS * (CELL.x + 10) + 10
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	var legend := UiKit.label("格子底下的色条是品质：灰 凡品 · 绿 良品 · 蓝 精品 · 金 名器 / 绝品；「装」= 有人正用着", 13, Color("c9b48a"))
	add_child(legend)
	legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	legend.offset_left = 104
	legend.offset_top = -32
	# 右边详情
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", UiKit.note_box())
	add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	paper.offset_left = -470
	paper.offset_right = -28
	paper.offset_top = 108
	paper.offset_bottom = -40
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	paper.add_child(_detail)
	# 左边木签分类（加在最后，压在上面才点得到）
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	tabs.position = Vector2(24, 104)
	add_child(tabs)
	for i in TAB_NAMES.size():
		var b := UiKit.slip_button(TAB_NAMES[i], 52, 22)
		b.pressed.connect(func() -> void:
			_tab = i
			_picked = 0
			_refresh())
		tabs.add_child(b)
		_tab_buttons.append(b)
	_refresh()


func _refresh() -> void:
	for i in _tab_buttons.size():
		UiKit.set_slip_lit(_tab_buttons[i], i == _tab)
	for child in _purse.get_children():
		child.queue_free()
	_purse.add_child(UiKit.amount_row(UiKit.coin_icon(18), "银两 %d" % GameState.silver, 17))
	var tokens := UiKit.button("聚义令 %d　从哪来 ›" % GameState.tokens, Vector2(0, 32), 16)
	tokens.pressed.connect(_show_sources)
	_purse.add_child(tokens)
	for text in ["义气 %d" % GameState.yiqi, "残页 %d" % GameState.pages, "修为 %d" % GameState.xiuwei]:
		var l := UiKit.label(text, 17, Color("f4e2b4"))
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_purse.add_child(l)
	_entries = entries(TAB_NAMES[_tab])
	_picked = clampi(_picked, 0, maxi(_entries.size() - 1, 0))
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for i in _entries.size():
		_grid.add_child(_cell(_entries[i], i))
	_show_detail()


## 某一类的东西，排好序：[{tab, glyph, name, quality, color, count, user, kind, desc, actions:[[文字, Callable]]}]
func entries(tab: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# 装备：有人用着的在前，同样的按品质从高到低
	var gear := GameState.items.duplicate()
	gear.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := GameState.item_data(a)
		var db := GameState.item_data(b)
		if (a["holder"] != &"") != (b["holder"] != &""):
			return a["holder"] != &""
		if da.quality != db.quality:
			return da.quality > db.quality
		return da.slot < db.slot)
	for it: Dictionary in gear:
		var d := GameState.item_data(it)
		if d == null:
			continue
		var uid: int = it["uid"]
		var actions: Array = []
		if it["holder"] == &"" and d.can_sell():
			actions.append(["卖 %d 两" % d.sell_price(), func() -> void:
				GameState.sell_item(uid)
				_refresh()])
		actions.append(["去好汉页换装", func() -> void: heroes_requested.emit()])
		out.append({"tab": "兵甲", "glyph": SLOT_GLYPHS[d.slot], "name": d.display_name, "quality": d.quality_name(),
			"color": QUALITY_COLORS[d.quality], "count": 0, "user": _holder_name(it["holder"]),
			"kind": EquipData.SLOT_NAMES[d.slot], "desc": d.flavor, "effect": d.summary(), "actions": actions})
	# 秘籍和技能书
	for sc: Dictionary in GameState.scrolls:
		var m := GameState.scroll_data(sc)
		if m == null:
			continue
		out.append({"tab": "秘籍", "glyph": "书" if m.is_book() else "秘", "name": m.display_name, "quality": m.quality_name(),
			"color": QUALITY_COLORS[m.quality], "count": 0, "user": _holder_name(sc["holder"]),
			"kind": m.category(), "desc": "", "effect": m.summary(), "actions": [["去好汉页换秘籍", func() -> void: heroes_requested.emit()]]})
	# 药
	for id: StringName in Vitality.MEDICINES:
		var n: int = GameState.medicines.get(id, 0)
		if n <= 0:
			continue
		var quality := mini(Vitality.MEDICINES.keys().find(id), 3)
		var actions: Array = []
		if Vitality.medicine_for_team(id):
			actions.append(["给全队用", func() -> void:
				GameState.use_medicine(id, &"")
				_refresh()])
		else:
			for u: UnitData in GameState.team():
				var who: StringName = u.id
				if Vitality.is_wounded(GameState.vitality_of(who)):
					actions.append(["给%s用" % u.display_name, func() -> void:
						GameState.use_medicine(id, who)
						_refresh()])
		var desc: String = Vitality.MEDICINES[id][1]
		out.append({"tab": "药物", "glyph": "药", "name": Vitality.medicine_name(id), "quality": "", "color": QUALITY_COLORS[quality],
			"count": n, "user": "", "kind": "药", "desc": desc, "effect": Vitality.medicine_effect(id) + ("" if not actions.is_empty() else "\n眼下没人受伤，用不着"), "actions": actions})
	# 杂物：将魂、残页
	for hero in GameDB.heroes:
		var souls := GameState.souls_of(hero.id)
		if souls <= 0:
			continue
		out.append({"tab": "杂物", "glyph": "魂", "name": "%s将魂" % hero.display_name, "quality": "", "color": QUALITY_COLORS[0],
			"count": souls, "user": "", "kind": "将魂", "desc": "重复招到%s得来。" % hero.display_name,
			"effect": "攒够了给%s点亮勾玉；也能换成义气，或合成技能书。" % hero.display_name, "actions": [["去好汉页", func() -> void: heroes_requested.emit()]]})
	if GameState.jiama > 0:
		out.append({"tab": "杂物", "glyph": "马", "name": "甲马", "quality": "", "color": QUALITY_COLORS[1], "count": GameState.jiama,
			"user": "", "kind": "道具", "desc": "画着奔马的黄纸。",
			"effect": "在大地图上点一个去过的地方，用一张直接到。\n最多带 %d 张；集市每天限买 %d 张；招到戴宗后他每天写 %d 张。" % [Jiama.MAX_CARRY, Jiama.SHOP_PER_DAY, Jiama.DAI_PER_DAY],
			"actions": [["去大地图", func() -> void: travel_requested.emit(GameState.location_id)]]})
	if GameState.pages > 0:
		out.append({"tab": "杂物", "glyph": "页", "name": "残页", "quality": "", "color": QUALITY_COLORS[0], "count": GameState.pages,
			"user": "", "kind": "杂物", "desc": "残缺的书页。", "effect": "合成技能书时，一张顶一个缺的将魂。", "actions": []})
	if tab == "全部":
		return out
	return out.filter(func(e: Dictionary) -> bool: return e["tab"] == tab)


func _holder_name(holder: StringName) -> String:
	if holder == &"":
		return ""
	if holder == GameState.PROTAGONIST_ID:
		return "统领"
	var h := GameDB.hero(holder)
	return h.display_name if h != null else String(holder)


## 一格：中间一个大字（兵、甲、饰、骑、书、药、魂），下面名字，底下品质色条；右上数目，左上「装」。
func _cell(e: Dictionary, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CELL
	b.focus_mode = Control.FOCUS_NONE
	UiKit.skin(b, UiKit.kit_box(&"slot"))
	b.pressed.connect(func() -> void:
		_picked = index
		_refresh())
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var glyph := UiKit.brush_label(e["glyph"], 30, e["color"].lightened(0.35))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(glyph)
	var title := UiKit.label(e["name"], 11, Color("e9d3a0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.custom_minimum_size.x = CELL.x - 8
	v.add_child(title)
	var bar := ColorRect.new()
	bar.color = e["color"]
	b.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -5
	bar.offset_left = 6
	bar.offset_right = -6
	bar.offset_bottom = -3
	if int(e["count"]) > 0:
		var count := UiKit.outlined("×%d" % e["count"], 13, Color("f6e7c8"))
		b.add_child(count)
		count.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		count.offset_left = -40
		count.offset_right = -4
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if e["user"] != "":
		var worn := UiKit.seal_label("装", 11)
		b.add_child(worn)
		worn.position = Vector2(-2, -4)
	if index == _picked:
		b.modulate = Color(1.25, 1.18, 1.0)
		var ring := ReferenceRect.new()
		ring.border_color = Color("f2d79a")
		ring.border_width = 2.0
		ring.editor_only = false
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ring)
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiKit.ignore_mouse(v)
	return b


func _show_detail() -> void:
	for child in _detail.get_children():
		child.queue_free()
	if _entries.is_empty():
		_detail.add_child(UiKit.label("这一格还空着。", 20, UiKit.INK_DIM))
		return
	var e: Dictionary = _entries[_picked]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_detail.add_child(head)
	head.add_child(UiKit.brush_label(e["name"], 32, UiKit.INK))
	if e["quality"] != "":
		var q := UiKit.seal_label(e["quality"], 15, false, e["color"])
		q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(q)
	var kind := UiKit.label(e["kind"] + ("　×%d" % e["count"] if int(e["count"]) > 0 else ""), 15, UiKit.INK_DIM)
	kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(kind)
	if e["desc"] != "":
		var desc := UiKit.label(e["desc"], 15, Color("5a4a3a"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(desc)
	var line := ColorRect.new()
	line.color = Color("b8955a")
	line.custom_minimum_size.y = 1
	_detail.add_child(line)
	var effect := UiKit.label(e["effect"], 17, UiKit.INK)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(effect)
	if e["user"] != "":
		_detail.add_child(UiKit.label("%s正用着" % e["user"], 15, UiKit.CINNABAR))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(gap)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 8)
	_detail.add_child(buttons)
	for a: Array in e["actions"]:
		var b := UiKit.button(a[0], Vector2(130, 46), 18)
		b.pressed.connect(a[1])
		buttons.add_child(b)


func _show_sources() -> void:
	var panel := TokenSources.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(panel.queue_free)
	panel.travel_requested.connect(func(id: StringName) -> void: travel_requested.emit(id))

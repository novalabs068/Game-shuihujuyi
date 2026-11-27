class_name TeamSelect
extends Control
## 编队：统领一定上场，再点卡片选最多 3 位好汉；右边布阵——选阵法，把四个人摆进我方 2 排 × 3 路的格子里
## （点一个人再点一格，那格有人就换位）。底部提示山头和能触发的组合技。
## stage 为空时不显示关卡信息。

## heroes 只含好汉，不含统领
signal start_requested(heroes: Array[UnitData])

const MAX_TEAM := GameState.MAX_HEROES
const TILE_SIZE := Vector2(250, 186)
## 布阵格子的大小
const CELL_SIZE := Vector2(150, 62)
## 手指按下后移动超过这么多像素算拖动滚屏，不算点选
const TAP_SLOP := 12.0

var stage: StageData

var _selected: Array[UnitData] = []
var _tiles: Dictionary[UnitData, PanelContainer] = {}
var _badges: Dictionary[UnitData, Label] = {}
var _team_label: Label
var _combo_label: Label
var _formation_label: Label
var _formation_buttons: Dictionary[StringName, Button] = {}
var _cell_buttons: Dictionary[Vector2i, Button] = {}
var _cell_label: Label
var _start_button: Button
var _show_all := false
var _empty_hint: Label
## 布阵时点中的人（再点一格就挪过去）
var _picked: StringName = &""


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var title_row := HBoxContainer.new()
	v.add_child(title_row)
	var title := UiKit.label("编队：统领 %s 一定上场，再选 %d 位好汉；右边布阵" % [GameState.player_name, MAX_TEAM], 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	# 默认只列已招募的好汉；打开开关才显示没招到的（变暗，不能选）
	var show_all := CheckButton.new()
	show_all.text = "显示未招募"
	show_all.add_theme_font_override("font", UiKit.cjk_font())
	show_all.add_theme_font_size_override("font_size", 20)
	show_all.toggled.connect(func(on: bool) -> void:
		_show_all = on
		_refresh())
	title_row.add_child(show_all)
	_start_button = UiKit.button("确定", Vector2(120, 50), 24)
	_start_button.pressed.connect(func() -> void: start_requested.emit(_selected.duplicate()))
	title_row.add_child(_start_button)
	if stage != null:
		var enemy_names := PackedStringArray()
		for e in stage.enemies:
			enemy_names.append(e.display_name)
		v.add_child(UiKit.label("%s「%s」　敌人：%s　推荐等级 %d" % [stage.id, stage.title, "、".join(enemy_names), stage.recommended_level], 20, UiKit.TEXT_DIM))

	var loc: LocationData = GameDB.maps[GameState.DEFAULT_MAP].location(GameState.location_id)
	if loc != null and not loc.encounter_groups.is_empty():
		v.add_child(UiKit.label("%s一带的%s" % [loc.display_name, Roles.region_hint(loc.encounter_groups)], 19, UiKit.GOLD))

	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 18)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(middle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	# 已招募的排前面，同一组里按品级、再按原来的顺序
	var heroes := GameDB.heroes.duplicate()
	heroes.sort_custom(func(a: UnitData, b: UnitData) -> bool:
		if GameState.owns(a.id) != GameState.owns(b.id):
			return GameState.owns(a.id)
		if a.tier != b.tier:
			return a.tier < b.tier
		return a.sort_order < b.sort_order)
	for hero: UnitData in heroes:
		grid.add_child(_make_tile(hero))
	_empty_hint = UiKit.label("还没有招募到好汉。去大地图点「招募」，用聚义令到聚义厅招人。统领一个人也能出发。", 20, UiKit.TEXT_DIM)
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_hint.custom_minimum_size.x = 400
	grid.add_child(_empty_hint)

	middle.add_child(_build_board())

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	v.add_child(info)
	_team_label = UiKit.label("", 20)
	info.add_child(_team_label)
	_combo_label = UiKit.label("", 17, UiKit.GOLD)
	_combo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_combo_label)

	_selected = GameState.heroes()
	_refresh()


## 右边的布阵板：阵法按钮、我方 2 × 3 格（左边后排、右边前排，和战场上一样）、这一格的说明、一键布阵。
func _build_board() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.CARD_FRAME, 2, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UiKit.label("布阵　左后排 · 右前排（敌人在右边）", 18, UiKit.ACCENT))
	var forms := GridContainer.new()
	forms.columns = 3
	forms.add_theme_constant_override("h_separation", 6)
	forms.add_theme_constant_override("v_separation", 6)
	box.add_child(forms)
	for id: StringName in Formations.ALL:
		var b := UiKit.button(Formations.display_name(id), Vector2(100, 36), 17)
		b.toggle_mode = true
		b.disabled = not GameState.formation_unlocked(id)
		b.tooltip_text = Formations.description(id) if not b.disabled else "%s后解锁" % Formations.unlock_text(id)
		b.pressed.connect(func() -> void:
			GameState.set_formation(id)
			_picked = &""
			_refresh())
		forms.add_child(b)
		_formation_buttons[id] = b
	var arrange := UiKit.button("按阵位摆", Vector2(100, 36), 16)
	arrange.tooltip_text = "把统领和好汉按这个阵的阵位摆好：阵位宜站什么职业就先放那个职业的人"
	arrange.pressed.connect(func() -> void:
		GameState.arrange_by_formation(GameState.current_formation())
		_picked = &""
		_refresh())
	forms.add_child(arrange)
	_formation_label = UiKit.label("", 14, UiKit.TEXT_DIM)
	_formation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_formation_label.custom_minimum_size.x = CELL_SIZE.x * 2 + 60
	box.add_child(_formation_label)

	var cells := GridContainer.new()
	cells.columns = 2
	cells.add_theme_constant_override("h_separation", 8)
	cells.add_theme_constant_override("v_separation", 8)
	box.add_child(cells)
	for lane in Grid.LANES:
		for row in [1, 0]:
			var c := Vector2i(row, lane)
			var b := Button.new()
			b.custom_minimum_size = CELL_SIZE
			b.add_theme_font_override("font", UiKit.cjk_font())
			b.add_theme_font_size_override("font_size", 17)
			b.pressed.connect(_on_cell.bind(c))
			cells.add_child(b)
			_cell_buttons[c] = b
	_cell_label = UiKit.label("", 15, UiKit.GOLD)
	_cell_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cell_label.custom_minimum_size = Vector2(CELL_SIZE.x * 2 + 60, 40)
	box.add_child(_cell_label)
	return panel


func _make_tile(hero: UnitData) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = TILE_SIZE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	tile.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	top.add_child(UiKit.picture(hero.bust, 88))
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override("separation", 0)
	top.add_child(head)
	var name_row := HBoxContainer.new()
	head.add_child(name_row)
	var name_label := UiKit.label(hero.display_name, 26, UiKit.TIER_COLORS[hero.tier])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	var badge := UiKit.label("", 22, UiKit.ACCENT)
	name_row.add_child(badge)
	_badges[hero] = badge
	head.add_child(UiKit.label(hero.nickname, 17, UiKit.TEXT_DIM))
	var marks := HBoxContainer.new()
	marks.add_theme_constant_override("separation", 6)
	marks.add_child(IdentitySeal.make(hero.rarity, 22))
	marks.add_child(MagatamaRow.for_hero(hero, GameState.star_of(hero.id), 14))
	marks.add_child(UiKit.role_tag(hero, 13))
	head.add_child(marks)
	var area := hero.skill.effective_area()
	v.add_child(UiKit.label("「%s」%s" % [hero.skill.display_name, "" if area == SkillData.Area.SINGLE else "（%s）" % SkillData.AREA_NAMES[area]], 19))
	var desc := UiKit.label(hero.skill.description, 15, UiKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = TILE_SIZE.x - 24
	v.add_child(desc)

	UiKit.ignore_mouse(tile)
	# PASS：拖动时事件继续传给外面的滚动区；松手时没怎么移动才算点选
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var pressed_at := [Vector2.INF]
	tile.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or click.button_index != MOUSE_BUTTON_LEFT:
			return
		if click.pressed:
			pressed_at[0] = click.global_position
		elif click.global_position.distance_to(pressed_at[0]) < TAP_SLOP:
			_toggle(hero))
	_tiles[hero] = tile
	return tile


## 选好汉、取消都马上记进存档（布阵板要按现在的队伍画）。
func _toggle(hero: UnitData) -> void:
	if not GameState.owns(hero.id):
		return
	if hero in _selected:
		_selected.erase(hero)
		GameState.positions.erase(hero.id)
	elif _selected.size() < MAX_TEAM:
		_selected.append(hero)
	GameState.set_heroes(_selected)
	GameState.save_game()
	_picked = &""
	_refresh()


## 点格子：没点中人时点有人的格子就点中他；已经点中了人，再点一格就挪过去（有人就换位）。
func _on_cell(c: Vector2i) -> void:
	var cells := GameState.current_cells()
	var who: StringName = &""
	for id: StringName in cells:
		if cells[id] == c:
			who = id
	if _picked == &"":
		_picked = who
	elif _picked == who:
		_picked = &""
	else:
		GameState.move_to_cell(_picked, c)
		_picked = &""
	_refresh()


func _refresh() -> void:
	for hero in _tiles:
		var picked := hero in _selected
		_tiles[hero].add_theme_stylebox_override("panel", UiKit.card_box(UiKit.ACCENT if picked else UiKit.CARD_FRAME, 4 if picked else 2))
		# 还没招募的好汉变暗，标「未招募」，不能选
		var owned := GameState.owns(hero.id)
		_tiles[hero].visible = owned or _show_all
		_tiles[hero].modulate = Color.WHITE if owned else Color(0.45, 0.45, 0.45)
		_badges[hero].text = "出战" if picked else ""
		if not owned:
			_badges[hero].text = "未招募"

	var names := PackedStringArray()
	for hero in _selected:
		names.append(hero.display_name)
	_team_label.text = "出战：统领 %s　%s（%d/%d）" % [GameState.player_name, "、".join(names) if not names.is_empty() else "还没选好汉", _selected.size(), MAX_TEAM]

	var current := GameState.current_formation()
	for id: StringName in _formation_buttons:
		_formation_buttons[id].button_pressed = id == current
	_formation_label.text = "「%s」%s" % [Formations.display_name(current), Formations.description(current)]
	_refresh_board(current)

	var lines := PackedStringArray()
	var hero_ids: Array[StringName] = []
	for hero in _selected:
		hero_ids.append(hero.id)
	var faction := Factions.shared(hero_ids)
	if faction != &"":
		lines.append("◆ 三人同出%s：%s" % [Factions.display_name(faction), Factions.bonus_text(faction)])
	else:
		# 差一个人就凑齐一个山头时提醒一下
		var tally := {}
		for id in hero_ids:
			var f := Factions.of(id)
			if f != &"":
				tally[f] = int(tally.get(f, 0)) + 1
		for f: StringName in tally:
			if tally[f] == Factions.TEAM_SIZE - 1:
				lines.append("☆ 三人都出自%s才有山头加成（%s）" % [Factions.display_name(f), Factions.bonus_text(f)])
	for combo in GameState.combos():
		# 统领一定上场，所以结义同心只看好汉在不在
		var a := GameDB.hero(combo.hero_a)
		var b := GameDB.hero(combo.hero_b)
		var has_a := combo.hero_a == GameState.PROTAGONIST_ID or a in _selected
		var has_b := b in _selected
		if has_a and has_b:
			lines.append("★ 组合技「%s」：%s" % [combo.display_name, combo.description])
		elif (has_a or has_b) and combo.hero_a != GameState.PROTAGONIST_ID:
			lines.append("☆ 再加上%s可解锁「%s」" % [(b if has_a else a).display_name, combo.display_name])
	_combo_label.text = "\n".join(lines.slice(0, 3))
	_start_button.disabled = false
	_empty_hint.visible = GameState.owned.is_empty() and not _show_all


## 画布阵板：每格写站的人（职业色底）、阵位名；阵眼金边；点中的人亮边。
func _refresh_board(formation: StringName) -> void:
	var cells := GameState.current_cells()
	var by_cell := {}
	for u in GameState.team():
		if cells.has(u.id):
			by_cell[cells[u.id]] = u
	for c: Vector2i in _cell_buttons:
		var b := _cell_buttons[c]
		var u: UnitData = by_cell.get(c)
		var slot := Formations.slot_name(formation, c)
		var eye := slot != "" and Formations.eye_cell(formation) == c
		var lines := PackedStringArray()
		if u != null:
			lines.append("%s %s" % [UnitData.ROLE_TAGS[u.role], u.display_name])
		else:
			lines.append("（空）")
		if slot != "":
			lines.append(("◆" if eye else "") + slot)
		b.text = "\n".join(lines)
		var fill := UiKit.ROLE_COLORS[u.role] if u != null else Color(UiKit.BG, 0.6)
		var border := UiKit.ACCENT if (u != null and u.id == _picked) else (UiKit.GOLD if eye else (Color("8a7a5c") if slot != "" else UiKit.CARD_FRAME))
		var style := UiKit.box(fill, border, 4 if (u != null and u.id == _picked) or eye else 2, 6)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, style)
		b.add_theme_color_override("font_color", UiKit.TEXT if u != null else UiKit.TEXT_DIM)
	if _picked != &"":
		var name := GameState.player_name if _picked == GameState.PROTAGONIST_ID else GameDB.hero(_picked).display_name
		var at: Vector2i = cells.get(_picked, Grid.NONE)
		var slot_tip := Formations.slot_text(formation, at)
		_cell_label.text = "点中了%s%s：再点一格挪过去（有人就换位）" % [name, ("（" + slot_tip + "）") if slot_tip != "" else ""]
	else:
		_cell_label.text = "点格子里的人，再点另一格就能挪动；◆是阵眼，倒下就破阵"

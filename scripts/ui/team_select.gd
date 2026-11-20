class_name TeamSelect
extends Control
## 编队：主角固定上场，再点卡片选最多 2 位随行好汉，底部提示能触发的组合技。
## stage 为空时不显示关卡信息。

## heroes 只含好汉，不含主角
signal start_requested(heroes: Array[UnitData])

const MAX_TEAM := GameState.MAX_HEROES
const TILE_SIZE := Vector2(282, 196)
## 手指按下后移动超过这么多像素算拖动滚屏，不算点选
const TAP_SLOP := 12.0

var stage: StageData

var _selected: Array[UnitData] = []
var _tiles: Dictionary[UnitData, PanelContainer] = {}
var _badges: Dictionary[UnitData, Label] = {}
var _team_label: Label
var _combo_label: Label
var _start_button: Button
var _show_all := false
var _empty_hint: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)

	var title_row := HBoxContainer.new()
	v.add_child(title_row)
	var title := UiKit.label("编队：主角%s固定上场，再选 %d 位好汉随行" % [GameState.player_name, MAX_TEAM], 32)
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
	if stage != null:
		var enemy_names := PackedStringArray()
		for e in stage.enemies:
			enemy_names.append(e.display_name)
		v.add_child(UiKit.label("%s「%s」　敌人：%s　推荐等级 %d" % [stage.id, stage.title, "、".join(enemy_names), stage.recommended_level], 20, UiKit.TEXT_DIM))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
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
	_empty_hint = UiKit.label("还没有招募到好汉。去大地图点「招募」，用聚义令到聚义厅招人。", 22, UiKit.TEXT_DIM)
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_empty_hint)
	v.move_child(_empty_hint, scroll.get_index())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	v.add_child(bottom)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(info)
	_team_label = UiKit.label("", 22)
	info.add_child(_team_label)
	_combo_label = UiKit.label("", 18, UiKit.GOLD)
	_combo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_combo_label)
	_start_button = UiKit.button("确定", Vector2(200, 80), 30)
	_start_button.pressed.connect(func() -> void: start_requested.emit(_selected.duplicate()))
	bottom.add_child(_start_button)

	_selected = GameState.heroes()
	_refresh()


func _make_tile(hero: UnitData) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = TILE_SIZE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	tile.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	top.add_child(UiKit.picture(hero.bust, 100))
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override("separation", 0)
	top.add_child(head)
	var name_row := HBoxContainer.new()
	head.add_child(name_row)
	var name_label := UiKit.label(hero.display_name, 28, UiKit.TIER_COLORS[hero.tier])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	var badge := UiKit.label("", 26, UiKit.ACCENT)
	name_row.add_child(badge)
	_badges[hero] = badge
	head.add_child(UiKit.label(hero.nickname, 18, UiKit.TEXT_DIM))
	var marks := HBoxContainer.new()
	marks.add_theme_constant_override("separation", 6)
	marks.add_child(IdentitySeal.make(hero.rarity, 24))
	marks.add_child(MagatamaRow.for_hero(hero, GameState.star_of(hero.id), 16))
	marks.add_child(UiKit.role_tag(hero, 13))
	head.add_child(marks)
	v.add_child(UiKit.label("「%s」" % hero.skill.display_name, 20))
	var desc := UiKit.label(hero.skill.description, 16, UiKit.TEXT_DIM)
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


func _toggle(hero: UnitData) -> void:
	if not GameState.owns(hero.id):
		return
	if hero in _selected:
		_selected.erase(hero)
	elif _selected.size() < MAX_TEAM:
		_selected.append(hero)
	_refresh()


func _refresh() -> void:
	for hero in _tiles:
		var picked := hero in _selected
		_tiles[hero].add_theme_stylebox_override("panel", UiKit.card_box(UiKit.ACCENT if picked else UiKit.CARD_FRAME, 4 if picked else 2))
		# 还没招募的好汉变暗，标「未招募」，不能选
		var owned := GameState.owns(hero.id)
		_tiles[hero].visible = owned or _show_all
		_tiles[hero].modulate = Color.WHITE if owned else Color(0.45, 0.45, 0.45)
		_badges[hero].text = "①②③"[_selected.find(hero)] if picked else ""
		if not owned:
			_badges[hero].text = "未招募"

	var names := PackedStringArray()
	for hero in _selected:
		names.append(hero.display_name)
	_team_label.text = "出战：%s + %s（%d/%d）" % [GameState.player_name, "、".join(names) if not names.is_empty() else "未选", _selected.size(), MAX_TEAM]

	var lines := PackedStringArray()
	for combo in GameDB.combos:
		var a := GameDB.hero(combo.hero_a)
		var b := GameDB.hero(combo.hero_b)
		var has_a := a in _selected
		var has_b := b in _selected
		if has_a and has_b:
			lines.append("★ 组合技「%s」：%s" % [combo.display_name, combo.description])
		elif has_a or has_b:
			lines.append("☆ 再加上%s可解锁「%s」" % [(b if has_a else a).display_name, combo.display_name])
	_combo_label.text = "\n".join(lines)
	# 一个好汉都没有时主角也能单独出发
	_start_button.disabled = false
	_empty_hint.visible = GameState.owned.is_empty() and not _show_all

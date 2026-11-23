class_name BattleStatsPanel
extends Control
## 战斗统计：「总览」每人一行（输出、承伤、治疗、护盾、暴击、追击、击倒、控制、出手次数），
## 「每回合」折线图加逐回合数字表，可切换看输出、承伤、治疗，看我方或敌方。

signal closed

const SIDE_COLORS := [
	[Color("e8b04a"), Color("5aa8e8"), Color("74c26a")],
	[Color("e86a5a"), Color("c88ad8"), Color("b0a898")],
]
## 总览表的列：统计项 → 列宽
const COLUMNS := {"dealt": 210, "taken": 84, "healed": 84, "shielded": 84, "crits": 60, "pursuits": 60, "kills": 60, "controls": 60}

var model: BattleModel

var _body: VBoxContainer
var _tab := "total"
var _metric := "dealt"
var _side := BattleUnit.Side.PLAYER


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.GOLD, 2, 10))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		panel.set("offset_" + side, {"left": 40, "right": -40, "top": 30, "bottom": -30}[side])
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pad.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var title := UiKit.label("战斗统计　共 %d 回合" % model.round_number(), 26, UiKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	for tab: Array in [["总览", "total"], ["每回合", "rounds"]]:
		var b := UiKit.button(tab[0], Vector2(110, 44), 20)
		var key: String = tab[1]
		b.pressed.connect(func() -> void:
			_tab = key
			_rebuild())
		head.add_child(b)
	var close := UiKit.button("关闭", Vector2(100, 44), 20)
	close.pressed.connect(func() -> void: closed.emit())
	head.add_child(close)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	set_meta("close_on_back", func() -> void: closed.emit())
	_rebuild()


func _units(side: BattleUnit.Side) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in model.units:
		if u.side == side:
			out.append(u)
	return out


func _color(u: BattleUnit) -> Color:
	var palette: Array = SIDE_COLORS[0 if u.side == BattleUnit.Side.PLAYER else 1]
	return palette[_units(u.side).find(u) % palette.size()]


func _rebuild() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _tab == "total":
		_build_totals()
	else:
		_build_rounds()


# --- 总览 ---

func _build_totals() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS.size() + 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	# 表头
	grid.add_child(_cell("", 150))
	for key: String in COLUMNS:
		grid.add_child(_cell(BattleStats.TOTALS[key], COLUMNS[key], UiKit.TEXT_DIM, 17))
	grid.add_child(_cell("出手 普攻/绝招/组合", 170, UiKit.TEXT_DIM, 17))
	for side in [BattleUnit.Side.PLAYER, BattleUnit.Side.ENEMY]:
		var units := _units(side)
		# 每一列里的最大值标金色
		var best := {}
		var side_dealt := 0
		for key: String in COLUMNS:
			best[key] = 0
			for u in units:
				best[key] = maxi(best[key], model.stats.total(u, key))
		for u in units:
			side_dealt += model.stats.total(u, "dealt")
		grid.add_child(_cell("我方" if side == BattleUnit.Side.PLAYER else "敌方", 150, UiKit.ACCENT if side == BattleUnit.Side.PLAYER else UiKit.DAMAGE, 18))
		for i in COLUMNS.size() + 1:
			grid.add_child(Control.new())
		for u in units:
			grid.add_child(_name_cell(u))
			for key: String in COLUMNS:
				var n := model.stats.total(u, key)
				var color := UiKit.GOLD if n > 0 and n == best[key] else (UiKit.TEXT if n > 0 else UiKit.TEXT_DIM)
				if key == "dealt":
					grid.add_child(_bar_cell(n, side_dealt, _color(u), color))
				else:
					grid.add_child(_cell(_num(n), COLUMNS[key], color, 18))
			grid.add_child(_cell("%d / %d / %d" % [model.stats.total(u, "attacks"), model.stats.total(u, "skills"), model.stats.total(u, "combos")], 170, UiKit.TEXT, 18))


func _name_cell(u: BattleUnit) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.x = 150
	row.add_theme_constant_override("separation", 6)
	var dot := ColorRect.new()
	dot.color = _color(u)
	dot.custom_minimum_size = Vector2(6, 24)
	row.add_child(dot)
	row.add_child(UiKit.picture(u.data.face, 30))
	var name := UiKit.label(u.display_name(), 18, UiKit.TEXT if u.is_alive() else UiKit.TEXT_DIM)
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	return row


## 输出：数字加一条占全队比例的色条。
func _bar_cell(n: int, side_total: int, bar_color: Color, text_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.x = COLUMNS["dealt"]
	row.add_theme_constant_override("separation", 8)
	var share := float(n) / side_total if side_total > 0 else 0.0
	var track := Control.new()
	track.custom_minimum_size = Vector2(90, 14)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.08)
	bg.size = Vector2(90, 14)
	track.add_child(bg)
	var fill := ColorRect.new()
	fill.color = bar_color
	fill.size = Vector2(90 * share, 14)
	track.add_child(fill)
	row.add_child(track)
	row.add_child(UiKit.label("%s %d%%" % [_num(n), roundi(share * 100)], 18, text_color))
	return row


func _cell(text: String, width: int, color := UiKit.TEXT, font_size := 18) -> Label:
	var l := UiKit.label(text, font_size, color)
	l.custom_minimum_size.x = width
	return l


static func _num(n: int) -> String:
	return "%d" % n if n < 10000 else "%.1f万" % (n / 10000.0)


# --- 每回合 ---

func _build_rounds() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	_body.add_child(bar)
	for m: String in BattleStats.PER_ROUND:
		var b := UiKit.button(BattleStats.PER_ROUND[m], Vector2(90, 40), 18)
		b.toggle_mode = true
		b.button_pressed = m == _metric
		b.pressed.connect(func() -> void:
			_metric = m
			_rebuild())
		bar.add_child(b)
	var gap := Control.new()
	gap.custom_minimum_size.x = 24
	bar.add_child(gap)
	for side in [BattleUnit.Side.PLAYER, BattleUnit.Side.ENEMY]:
		var b := UiKit.button("我方" if side == BattleUnit.Side.PLAYER else "敌方", Vector2(90, 40), 18)
		b.toggle_mode = true
		b.button_pressed = side == _side
		b.pressed.connect(func() -> void:
			_side = side
			_rebuild())
		bar.add_child(b)
	# 图例
	var units := _units(_side)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 16)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.alignment = BoxContainer.ALIGNMENT_END
	bar.add_child(legend)
	for u in units:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.color = _color(u)
		swatch.custom_minimum_size = Vector2(18, 6)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(swatch)
		item.add_child(UiKit.label(u.display_name(), 17))
		legend.add_child(item)
	var rounds := model.stats.rounds
	var chart := RoundChart.new()
	chart.custom_minimum_size.y = 230
	var series: Array[Dictionary] = []
	for u in units:
		var values := []
		for r in range(1, rounds + 1):
			values.append(model.stats.at_round(u, _metric, r))
		series.append({"name": u.display_name(), "color": _color(u), "values": values})
	chart.rounds = rounds
	chart.series = series
	_body.add_child(chart)
	# 逐回合的数字表
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = units.size() + 1
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	grid.add_child(_cell("回合", 80, UiKit.TEXT_DIM, 17))
	for u in units:
		grid.add_child(_cell(u.display_name(), 130, _color(u), 17))
	for r in range(1, rounds + 1):
		grid.add_child(_cell("第 %d 回合" % r, 80, UiKit.TEXT_DIM, 17))
		for u in units:
			var n := model.stats.at_round(u, _metric, r)
			grid.add_child(_cell(_num(n) if n > 0 else "·", 130, UiKit.TEXT if n > 0 else UiKit.TEXT_DIM, 17))

class_name MarketPanel
extends Control
## 集市：买凡品装备，把背包里没穿着的装备卖成银两。盖在大地图上。

signal closed

const INK := Color("1e1c1a")
const RED := Color("be3226")
const DIM := Color("5a4a3a")

var _selling := false
var _list: VBoxContainer
var _silver: Label
var _buy_tab: Button
var _sell_tab: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(Color("efe7d4"), INK, 3, 6))
	panel.custom_minimum_size = Vector2(820, 560)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	top.add_child(UiKit.label("集市", 34, RED))
	_buy_tab = UiKit.button("买", Vector2(90, 46), 22)
	_buy_tab.pressed.connect(_switch.bind(false))
	top.add_child(_buy_tab)
	_sell_tab = UiKit.button("卖", Vector2(90, 46), 22)
	_sell_tab.pressed.connect(_switch.bind(true))
	top.add_child(_sell_tab)
	_silver = UiKit.label("", 22, INK)
	_silver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_silver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_silver)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var close := UiKit.button("离开", Vector2(160, 52), 22)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: closed.emit())
	v.add_child(close)
	_refresh()


func _switch(selling: bool) -> void:
	_selling = selling
	_refresh()


func _refresh() -> void:
	_silver.text = "银两 %d" % GameState.silver
	_buy_tab.disabled = not _selling
	_sell_tab.disabled = _selling
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _selling:
		var spare := GameState.items.filter(func(it: Dictionary) -> bool: return it["holder"] == &"" and GameState.item_data(it).can_sell())
		if spare.is_empty():
			_list.add_child(UiKit.label("背包里没有可卖的装备。穿在身上的要先在「好汉」页卸下。", 20, DIM))
		for it: Dictionary in spare:
			var data := GameState.item_data(it)
			var uid: int = it["uid"]
			_list.add_child(_row(data, "卖 %d 两" % data.sell_price(), true, func() -> void:
				GameState.sell_item(uid)
				_refresh()))
	else:
		var wares := GameDB.equipment.values().filter(func(e: EquipData) -> bool: return e.quality == EquipData.Quality.FAN)
		wares.sort_custom(func(a: EquipData, b: EquipData) -> bool: return a.slot < b.slot)
		# 药放最前面：受了伤最先要找的
		for id: StringName in Vitality.MEDICINES:
			var price := Vitality.medicine_price(id)
			_list.add_child(_medicine_row(id, "买 %d 两" % price, GameState.silver >= price, func() -> void:
				GameState.buy_medicine(id)
				_refresh()))
		for data: EquipData in wares:
			_list.add_child(_row(data, "买 %d 两" % data.buy_price(), GameState.silver >= data.buy_price(), func() -> void:
				GameState.buy_item(data)
				_refresh()))


func _medicine_row(id: StringName, action: String, enabled: bool, on_press: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	info.add_child(name_row)
	name_row.add_child(UiKit.label(Vitality.medicine_name(id), 24, INK))
	name_row.add_child(UiKit.label("药 · 身上有 %d 份" % GameState.medicines.get(id, 0), 18, RED))
	var desc := UiKit.label(Vitality.MEDICINES[id][1], 16, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 560
	info.add_child(desc)
	var button := UiKit.button(action, Vector2(130, 50), 20)
	button.disabled = not enabled
	button.pressed.connect(on_press)
	row.add_child(button)
	return row


func _row(data: EquipData, action: String, enabled: bool, on_press: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	info.add_child(name_row)
	name_row.add_child(UiKit.label(data.display_name, 24, INK))
	name_row.add_child(UiKit.label("%s · %s" % [EquipData.SLOT_NAMES[data.slot], data.quality_name()], 18, UiKit.QUALITY_INK[data.quality]))
	name_row.add_child(UiKit.label(data.summary(), 18, RED))
	var flavor := UiKit.label(data.flavor, 16, DIM)
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.custom_minimum_size.x = 560
	info.add_child(flavor)
	var button := UiKit.button(action, Vector2(130, 50), 20)
	button.disabled = not enabled
	button.pressed.connect(on_press)
	row.add_child(button)
	return row

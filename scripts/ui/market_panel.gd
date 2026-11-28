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
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	panel.custom_minimum_size = Vector2(820, 560)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	top.add_child(UiKit.brush_label("集市", 38, INK))
	_buy_tab = UiKit.tab_button("买", 24)
	_buy_tab.custom_minimum_size = Vector2(80, 42)
	_buy_tab.pressed.connect(_switch.bind(false))
	top.add_child(_buy_tab)
	_sell_tab = UiKit.tab_button("卖", 24)
	_sell_tab.custom_minimum_size = Vector2(80, 42)
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

	var close := UiKit.plaque_button("离　开", Vector2(170, 54), false, 26)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: closed.emit())
	v.add_child(close)
	_refresh()


func _switch(selling: bool) -> void:
	_selling = selling
	_refresh()


func _refresh() -> void:
	_silver.text = "银两 %d" % GameState.silver
	UiKit.set_tab_on(_buy_tab, not _selling)
	UiKit.set_tab_on(_sell_tab, _selling)
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
		# 甲马放最前面：每天限买几张
		var left := GameState.jiama_shop_left()
		_list.add_child(_jiama_row(left, GameState.silver >= Jiama.PRICE and left > 0, func() -> void:
			GameState.buy_jiama()
			_refresh()))
		# 药紧跟着：受了伤最先要找的
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
	name_row.add_child(UiKit.label("×%d" % GameState.medicines.get(id, 0), 18, RED))
	var desc := UiKit.label("%s　%s" % [Vitality.medicine_effect(id), Vitality.MEDICINES[id][1]], 16, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 560
	info.add_child(desc)
	var button := UiKit.button(action, Vector2(130, 50), 20)
	button.disabled = not enabled
	button.pressed.connect(on_press)
	row.add_child(button)
	return row


func _jiama_row(left: int, enabled: bool, on_press: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	info.add_child(name_row)
	name_row.add_child(UiKit.label("甲马", 24, INK))
	name_row.add_child(UiKit.label("×%d　今日可买 %d" % [GameState.jiama, left], 18, RED))
	var desc := UiKit.label("在大地图上点一个去过的地方，用一张直接到。每天限买 %d 张，最多带 %d 张。" % [Jiama.SHOP_PER_DAY, Jiama.MAX_CARRY], 16, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 560
	info.add_child(desc)
	var button := UiKit.button("买 %d 两" % Jiama.PRICE, Vector2(130, 50), 20)
	button.disabled = not enabled
	button.pressed.connect(on_press)
	row.add_child(button)
	return row


func _scroll_row(mj: MijiData, action: String, enabled: bool, on_press: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	info.add_child(name_row)
	name_row.add_child(UiKit.label("《%s》" % mj.display_name, 24, INK))
	name_row.add_child(UiKit.label("秘籍 · %s" % mj.quality_name(), 18, UiKit.QUALITY_INK[mj.quality]))
	name_row.add_child(UiKit.label(mj.summary(), 18, RED))
	var flavor := UiKit.label(mj.flavor, 16, DIM)
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.custom_minimum_size.x = 560
	info.add_child(flavor)
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

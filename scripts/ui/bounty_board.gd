class_name BountyBoard
extends Control
## 一个地点的悬赏告示：列出还没揭下的悬赏，点「接下」就开打。盖在大地图上。

signal accepted(bounty: BountyData)
signal closed

var bounties: Array[BountyData] = []
## 哪个地区的告示栏：下面还贴着这里的小悬赏（OddJobs）
var region: StringName = &""


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
	panel.add_theme_stylebox_override("panel", UiKit.box(Color("efe7d4"), Color("1e1c1a"), 3, 6))
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var ink := Color("1e1c1a")
	var title := UiKit.label("悬赏告示", 34, Color("be3226"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	if bounties.is_empty():
		var none := UiKit.label("告示都揭完了。", 22, ink)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(none)
	for b in bounties:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		v.add_child(row)
		var grade := UiKit.label(b.grade_name(), 40, Color("be3226"))
		grade.custom_minimum_size.x = 56
		grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(grade)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiKit.label("%s　%d 级" % [b.target, b.stage.enemy_level], 26, ink))
		var desc := UiKit.label(b.description, 17, Color("5a4a3a"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 440
		info.add_child(desc)
		info.add_child(UiKit.label("赏：聚义令 %d、%s装备一件%s、%s" % [b.tokens(), EquipData.QUALITY_NAMES[b.equip_quality()], b.miji_text(), Vitality.medicine_name(b.medicine())], 18, Color("be3226")))
		var take := UiKit.button("接下", Vector2(120, 56), 22)
		take.pressed.connect(func() -> void: accepted.emit(b))
		row.add_child(take)
	if region != &"":
		var jobs := OddJobs.jobs_for(region)
		if not jobs.is_empty():
			v.add_child(UiKit.label("小悬赏（不用接，打赢了就算；做完马上换新的）", 22, Color("be3226")))
			for job: Dictionary in jobs:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 14)
				v.add_child(row)
				var text := UiKit.label(OddJobs.describe(job), 20, ink)
				text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(text)
				row.add_child(UiKit.label("赏：" + OddJobs.reward_text(job), 17, Color("be3226")))
	var close := UiKit.button("离开", Vector2(160, 52), 22)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: closed.emit())
	v.add_child(close)

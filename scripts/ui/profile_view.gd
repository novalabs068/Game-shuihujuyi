class_name ProfileView
extends Control
## 主角页：立绘和出身、等级和家当、属性（算上武学和装备）、主修副修、身上装备、江湖履历。
## 换武学和装备在「好汉」页主角那里做，这里有按钮直接过去。

signal back_requested
signal heroes_requested

const SECTION_GAP := 14


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	margin.add_child(body)

	var me := GameState.protagonist()
	var origin := GameState.origin()

	# 左边：立绘、名字、出身
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 360
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	var pic := UiKit.picture(me.portrait if me.portrait != null else me.bust, 470)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(pic)
	var name := UiKit.label(me.display_name, 40, UiKit.GOLD)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(name)
	var from := UiKit.label("出身：%s" % origin.display_name, 22, UiKit.ACCENT)
	from.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(from)
	var desc := UiKit.label(origin.description, 16, UiKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(desc)

	# 右边：可以上下滑
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	scroll.add_child(right)

	var top := HBoxContainer.new()
	right.add_child(top)
	var title := UiKit.label("主角", 30, UiKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var music := UiKit.button("音乐：开" if Music.enabled else "音乐：关", Vector2(120, 46), 20)
	music.pressed.connect(func() -> void:
		Music.enabled = not Music.enabled
		music.text = "音乐：开" if Music.enabled else "音乐：关")
	top.add_child(music)
	var adjust := UiKit.button("换武学、装备", Vector2(170, 46), 20)
	adjust.pressed.connect(func() -> void: heroes_requested.emit())
	top.add_child(adjust)
	var back := UiKit.button("返回", Vector2(110, 46), 22)
	back.pressed.connect(func() -> void: back_requested.emit())
	top.add_child(back)

	# 等级和家当
	var lv := GameState.level
	var need := GameState.exp_to_next(lv)
	right.add_child(UiKit.label("%d 级　经验 %d / %d" % [lv, GameState.experience, need], 22))
	var bar := ProgressBar.new()
	bar.max_value = need
	bar.value = GameState.experience
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("background", UiKit.box(UiKit.PANEL_LIGHT, Color(0, 0, 0, 0), 0, 4))
	bar.add_theme_stylebox_override("fill", UiKit.box(UiKit.GOLD, Color(0, 0, 0, 0), 0, 4))
	right.add_child(bar)
	right.add_child(UiKit.label("银两 %d　聚义令 %d　义气 %d" % [GameState.silver, GameState.tokens, GameState.yiqi], 20, UiKit.TEXT_DIM))

	# 属性：算上副修武学和装备，和战斗里一样
	var unit := Equipment.apply(me, GameState.effective_gear(GameState.PROTAGONIST_ID))
	_section(right, "属性")
	var at := func(base: int) -> int: return roundi(base * pow(BattleUnit.LEVEL_GROWTH, lv - 1))
	right.add_child(UiKit.label("生命 %d　攻击 %d　防御 %d　速度 %d" % [at.call(unit.base_hp), at.call(unit.base_atk), at.call(unit.base_def), at.call(unit.base_spd)], 22))
	if not unit.gear_effects.is_empty():
		right.add_child(UiKit.label("特效：" + "、".join(unit.gear_effects.map(func(e: StringName) -> String: return "%s（%s）" % EquipData.EFFECTS[e])), 17, UiKit.TEXT_DIM))

	# 武学
	_section(right, "武学")
	var main := GameState.martial(GameState.martial_main)
	var side := GameState.martial(GameState.martial_side)
	right.add_child(_line("主修", "%s：%s" % [main.display_name, main.skill.description] if main != null else "（无）"))
	right.add_child(_line("副修", "%s：%s" % [side.display_name, side.side_summary()] if side != null else "（空着，学会第二门武学后填上）"))
	right.add_child(UiKit.label("已学会 %d 门武学" % GameState.martials.size(), 16, UiKit.TEXT_DIM))

	# 装备
	_section(right, "装备")
	for slot in EquipData.Slot.values():
		var it := GameState.equipped(GameState.PROTAGONIST_ID, slot)
		var text := "（空）"
		if not it.is_empty():
			var data := GameState.item_data(it)
			text = "%s · %s　%s" % [data.display_name, data.quality_name(), data.summary()]
		right.add_child(_line(EquipData.SLOT_NAMES[slot], text))

	# 江湖履历
	_section(right, "江湖履历")
	var map: WorldMapData = GameDB.maps[GameState.DEFAULT_MAP]
	var visited := map.locations.filter(func(l: LocationData) -> bool: return l.id == GameState.location_id or GameState.has_flag("visited_" + String(l.id))).size()
	var bounties := GameDB.bounties.filter(func(b: BountyData) -> bool: return GameState.has_flag("bounty_" + String(b.id))).size()
	var stories := GameDB.stories.filter(func(s: StoryData) -> bool: return GameState.story_done(s)).size()
	var minutes := int(GameState.record["play_seconds"]) / 60
	var lines := [
		"招募好汉 %d / %d 位" % [GameState.owned.size(), GameDB.heroes.size()],
		"走过的地方 %d / %d 处" % [visited, map.locations.size()],
		"揭下悬赏 %d / %d 张" % [bounties, GameDB.bounties.size()],
		"列传完成 %d / %d 段" % [stories, GameDB.stories.size()],
		"打赢 %d 场（其中街头巷尾的小怪 %d 只）" % [GameState.record["wins"], GameState.record["roamers"]],
		"擂台最高第 %d / %d 关" % [Arena.best(), Arena.round_count()],
		"闯荡江湖 %d 小时 %d 分" % [minutes / 60, minutes % 60],
	]
	for l: String in lines:
		right.add_child(UiKit.label(l, 20))


func _section(parent: Control, title: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = SECTION_GAP
	parent.add_child(gap)
	parent.add_child(UiKit.label(title, 24, UiKit.GOLD))


func _line(head: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var h := UiKit.label(head, 20, UiKit.ACCENT)
	h.custom_minimum_size.x = 56
	row.add_child(h)
	var t := UiKit.label(text, 19)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	return row

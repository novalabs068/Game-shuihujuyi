class_name HeroesView
extends Control
## 好汉：左边是名单（主角在最上面），右边是选中的人的详情；在这里换装备、升星、
## 把将魂化成义气、用义气换将魂、用将魂招募。

signal back_requested

const ROW_HEIGHT := 64
const LIST_WIDTH := 400
## 一次化掉 / 换来多少将魂
const SOUL_STEP := 10

var _show_all := false
var _selected: UnitData
var _list: VBoxContainer
var _rows: Dictionary[UnitData, PanelContainer] = {}
var _detail: VBoxContainer
var _bottom: VBoxContainer
var _yiqi_label: Label
var _notice: Label


func _ready() -> void:
	GameState.mark_tutorial("tut_heroes")
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
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	v.add_child(top)
	top.add_child(UiKit.label("好汉", 32, UiKit.GOLD))
	var show_all := CheckButton.new()
	show_all.text = "显示未招募"
	show_all.add_theme_font_override("font", UiKit.cjk_font())
	show_all.add_theme_font_size_override("font_size", 18)
	show_all.toggled.connect(func(on: bool) -> void:
		_show_all = on
		_refresh_list())
	top.add_child(show_all)
	_yiqi_label = UiKit.label("", 22)
	_yiqi_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_yiqi_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_yiqi_label)
	var back := UiKit.button("返回", Vector2(110, 44), 22)
	back.pressed.connect(func() -> void: back_requested.emit())
	top.add_child(back)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	v.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = LIST_WIDTH
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.PANEL_LIGHT, 2, 10))
	body.add_child(panel)
	var detail_margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		detail_margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(detail_margin)
	# 内容多了（绝招、天赋、名器、组合技）可以上下滑
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_margin.add_child(detail_scroll)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 8)
	detail_margin.remove_child(detail_scroll)
	detail_margin.add_child(detail_box)
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)
	# 装备栏和按钮固定在底下，不跟着滑
	_bottom = VBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 8)
	detail_box.add_child(_bottom)

	_notice = UiKit.label("", 20, UiKit.GOLD)
	v.add_child(_notice)

	var heroes := GameDB.heroes.duplicate()
	heroes.sort_custom(func(a: UnitData, b: UnitData) -> bool:
		if GameState.owns(a.id) != GameState.owns(b.id):
			return GameState.owns(a.id)
		if a.tier != b.tier:
			return a.tier < b.tier
		return a.sort_order < b.sort_order)
	heroes.push_front(GameState.protagonist())
	for hero: UnitData in heroes:
		_list.add_child(_make_row(hero))
	_selected = heroes[0]
	_refresh_list()
	_show_detail()


func _make_row(hero: UnitData) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	h.add_child(UiKit.unit_picture(hero, ROW_HEIGHT - 8, false, true))
	h.add_child(IdentitySeal.make(hero.rarity, 26))
	var name := UiKit.label(hero.display_name, 24, UiKit.ACCENT if _is_protagonist(hero) else UiKit.TIER_COLORS[hero.tier])
	name.custom_minimum_size.x = 96
	h.add_child(name)
	if not _is_protagonist(hero):
		h.add_child(MagatamaRow.for_hero(hero, GameState.star_of(hero.id), 17))
	var right := UiKit.label("", 18, UiKit.GOLD)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.name = "Right"
	h.add_child(right)
	UiKit.ignore_mouse(row)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var pressed_at := [Vector2.INF]
	row.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or click.button_index != MOUSE_BUTTON_LEFT:
			return
		if click.pressed:
			pressed_at[0] = click.global_position
		elif click.global_position.distance_to(pressed_at[0]) < TeamSelect.TAP_SLOP:
			_selected = hero
			_notice.text = ""
			_refresh_list()
			_show_detail())
	_rows[hero] = row
	return row


func _refresh_list() -> void:
	_yiqi_label.text = "义气 %d" % GameState.yiqi
	for hero in _rows:
		var row := _rows[hero]
		var owned := _owned(hero)
		row.visible = owned or _show_all
		row.modulate = Color.WHITE if owned else Color(0.5, 0.5, 0.5)
		var picked := hero == _selected
		row.add_theme_stylebox_override("panel", UiKit.card_box(UiKit.ACCENT if picked else UiKit.CARD_FRAME, 3 if picked else 1))
		var right: Label = row.find_child("Right", true, false)
		if _is_protagonist(hero):
			right.text = ""
		elif owned:
			right.text = "可升星" if GameState.can_star_up(hero) else ""
		else:
			right.text = "将魂 %d/%d" % [GameState.souls_of(hero.id), Stars.RECRUIT_SOULS]


func _show_detail() -> void:
	for box: VBoxContainer in [_detail, _bottom]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	if _selected == null:
		_detail.add_child(UiKit.label("还没有招募到好汉。去大地图点「招募」，用聚义令到聚义厅招人。", 22, UiKit.TEXT_DIM))
		return
	var hero := _selected
	var protagonist := _is_protagonist(hero)
	var owned := _owned(hero)
	var star := GameState.star_of(hero.id)
	var effective := Equipment.apply(hero if protagonist else Bonds.apply(Stars.apply(hero, star), GameState.bond_of(hero.id)), GameState.effective_gear(hero.id))
	var held_scroll := GameState.scroll_of(hero.id)
	effective = Miji.apply(effective, GameState.scroll_data(held_scroll) if not held_scroll.is_empty() else null)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_detail.add_child(head)
	head.add_child(UiKit.unit_picture(hero, 170))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	head.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	info.add_child(name_row)
	name_row.add_child(IdentitySeal.make(hero.rarity, 40))
	name_row.add_child(UiKit.label(hero.display_name, 34, UiKit.ACCENT if protagonist else UiKit.TIER_COLORS[hero.tier]))
	name_row.add_child(UiKit.label(hero.nickname, 22, UiKit.TEXT_DIM))
	if protagonist:
		info.add_child(UiKit.label("统领 · %s · 不上阵，在阵外领兵" % GameState.origin().display_name, 20, UiKit.ACCENT))
	else:
		var marks := HBoxContainer.new()
		marks.add_theme_constant_override("separation", 8)
		marks.add_child(MagatamaRow.for_hero(hero, star, 24))
		marks.add_child(UiKit.role_tag(hero, 15))
		marks.add_child(UiKit.label("%s · %s（%s）" % [UiKit.RARITY_NAMES[hero.rarity], UiKit.ROLE_NAMES[hero.role], Roles.summary(hero.role)], 18, UiKit.TEXT_DIM))
		info.add_child(marks)
		var faction := Factions.of(hero.id)
		if faction != &"":
			info.add_child(UiKit.label("山头：%s（出战三人都出自%s时：%s）" % [Factions.display_name(faction), Factions.display_name(faction), Factions.bonus_text(faction)], 17, UiKit.TEXT_DIM))
	if protagonist:
		var aura := GameState.commander_aura()
		var m := GameState.martial(GameState.martial_main)
		info.add_child(UiKit.label("%d 级　队伍等级" % GameState.level, 20))
		info.add_child(_wrapped("统领光环：%s" % (("主修「%s」，出战的每位好汉 %s" % [m.display_name, aura.summary()]) if aura != null else "还没有主修武学"), UiKit.GOLD))
		info.add_child(_wrapped("换主修就换光环。学到的武学越多，能统领的打法越多。", UiKit.TEXT_DIM))
	elif owned:
		var lv := GameState.level
		info.add_child(UiKit.label("%d 级　生命 %d　攻击 %d　防御 %d　速度 %d" % [lv, _at(effective.base_hp, lv), _at(effective.base_atk, lv), _at(effective.base_def, lv), _at(effective.base_spd, lv)], 20))
		var vit := GameState.vitality_of(hero.id)
		if vit < 0.999:
			var hurt := "气血 %d%%" % roundi(vit * 100)
			if Vitality.is_wounded(vit):
				hurt += "（重伤）"
			info.add_child(UiKit.label(hurt + "　歇脚、吃药、赶路都能回", 18, UiKit.DAMAGE))
		var bonus := PackedStringArray()
		if star > 1 and not protagonist:
			bonus.append("勾玉：生命、攻击、防御 +%d%%" % roundi(Stars.STAT_BONUS * (star - 1) * 100))
		if Bonds.level(GameState.bond_of(hero.id)) > 0 and not protagonist:
			bonus.append("羁绊：+%d%%" % roundi(Bonds.STAT_BONUS * Bonds.level(GameState.bond_of(hero.id)) * 100))
		if not effective.gear_effects.is_empty():
			bonus.append("特效：" + "、".join(effective.gear_effects.map(func(e: StringName) -> String: return EquipData.EFFECTS[e][0])))
		if not bonus.is_empty():
			info.add_child(UiKit.label("　".join(bonus), 17, UiKit.TEXT_DIM))
	else:
		info.add_child(UiKit.label("未招募", 26, UiKit.TEXT_DIM))

	if owned and not protagonist:
		info.add_child(UiKit.label("羁绊　%s　（带他打赢一场 +%d，打完他的一段列传 +%d）" % [Bonds.progress_text(GameState.bond_of(hero.id)), Bonds.BATTLE_POINTS, Bonds.STORY_POINTS], 17, UiKit.GOLD))
	if not protagonist:
		var progress := GameState.story_progress(hero.id)
		if progress[1] > 0:
			var tip := "列传 %d / %d 段" % progress
			if not owned:
				tip += "（招到他才能玩）"
			elif progress[0] < progress[1]:
				var next := GameDB.stories.filter(func(s: StoryData) -> bool: return s.hero == hero.id and not GameState.story_done(s))[0] as StoryData
				tip += "　下一段「%s」在%s，推荐 %d 级" % [next.title, GameDB.maps[GameState.DEFAULT_MAP].location(next.location).display_name, next.recommended_level]
			else:
				tip += "　已完结"
			info.add_child(UiKit.label(tip, 17, UiKit.GOLD))
	if not protagonist:
		_detail.add_child(UiKit.label("「%s」" % effective.skill.display_name, 24))
		var desc := UiKit.label(effective.skill.description, 18, UiKit.TEXT_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(desc)
	if not protagonist and star < Stars.SKILL_UP_STAR and Stars.max_stars(hero) >= Stars.SKILL_UP_STAR:
		_detail.add_child(UiKit.label("点亮 %d 颗勾玉时强化：%s" % [Stars.lit(Stars.SKILL_UP_STAR), Stars.upgrade_text(hero.skill)], 17, UiKit.TEXT_DIM))
	if hero.talent != null:
		var rank := Stars.talent_rank(hero, star) if owned else 0
		var note := ""
		if rank == 0:
			note = "（点亮第 1 颗勾玉解锁）"
		elif rank == 1:
			note = "（勾玉全亮时再强化）"
		var talent := UiKit.label("天赋「%s」：%s%s" % [hero.talent.display_name, hero.talent.describe(rank), note], 18, UiKit.TEXT if rank > 0 else UiKit.TEXT_DIM)
		talent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(talent)
	for e: EquipData in GameDB.equipment.values():
		if e.quality == EquipData.Quality.MING and e.owner == hero.id:
			var got := GameState.has_flag("mingqi_" + String(e.id))
			var where := "已得到" if got else "出处：%s" % e.source_text
			_detail.add_child(UiKit.label("%s「%s」：%s　%s" % [e.quality_name(), e.display_name, e.summary(), where], 17, UiKit.QUALITY_COLORS[EquipData.Quality.MING] if got else UiKit.TEXT_DIM))
	if owned and not held_scroll.is_empty():
		var held := GameState.scroll_data(held_scroll)
		_detail.add_child(_wrapped("秘籍《%s》%s" % [held.display_name, held.summary()], UiKit.QUALITY_COLORS[mini(held.quality, EquipData.Quality.MING)]))
	if not protagonist:
		var own_miji := GameDB.miji_of_hero(hero.id)
		if own_miji != null:
			var taught := GameState.has_flag("miji_" + String(hero.id))
			_detail.add_child(_wrapped("独门秘籍《%s》%s　%s" % [own_miji.display_name, own_miji.summary(), "已传授" if taught else "结义时传授"], UiKit.GOLD if taught else UiKit.TEXT_DIM))
		for combo in GameDB.combos:
			var partner := combo.partner_of(hero.id)
			if partner != &"":
				var partner_owned := GameState.owns(partner)
				_detail.add_child(_wrapped("组合技「%s」（和%s同上阵%s）：%s" % [combo.display_name, GameDB.hero(partner).display_name, "" if partner_owned else "，还没招到", combo.description], UiKit.TEXT_DIM if partner_owned else Color(UiKit.TEXT_DIM, 0.6)))
		var sworn := Bonds.sworn_combo(hero, GameState.PROTAGONIST_ID)
		if GameState.sworn(hero.id):
			_detail.add_child(_wrapped("已结义　组合技「%s」：%s" % [sworn.display_name, sworn.description], UiKit.GOLD))
		elif GameState.can_swear(hero.id):
			_detail.add_child(_wrapped("羁绊已到「%s」，点下面的「结义」义结金兰，解锁「%s」：%s" % [Bonds.NAMES[Bonds.SWEAR_LEVEL], sworn.display_name, sworn.description], UiKit.GOLD))
		elif owned:
			_detail.add_child(_wrapped("羁绊到「%s」后可以结义，解锁「%s」：%s" % [Bonds.NAMES[Bonds.SWEAR_LEVEL], sworn.display_name, sworn.description], UiKit.TEXT_DIM))


	if protagonist:
		var martial_row := HBoxContainer.new()
		martial_row.add_theme_constant_override("separation", 10)
		_bottom.add_child(martial_row)
		martial_row.add_child(_martial_button(true))
		martial_row.add_child(_slot_button(hero, EquipData.Slot.MOUNT))
	if owned and not protagonist:
		var gear_row := HBoxContainer.new()
		gear_row.add_theme_constant_override("separation", 10)
		_bottom.add_child(gear_row)
		for slot in EquipData.Slot.values():
			gear_row.add_child(_slot_button(hero, slot))
		gear_row.add_child(_scroll_button(hero))
	if protagonist:
		return

	var souls := GameState.souls_of(hero.id)
	if owned:
		var need := "勾玉已全部点亮" if star >= Stars.max_stars(hero) else "点亮下一颗需要 %d" % Stars.cost(star)
		_bottom.add_child(UiKit.label("将魂 %d（%s）" % [souls, need], 20))
	else:
		_bottom.add_child(UiKit.label("将魂 %d / %d，攒够了就能直接招募" % [souls, Stars.RECRUIT_SOULS], 20))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_bottom.add_child(buttons)
	if owned:
		var up := UiKit.button("升星", Vector2(120, 56), 24)
		up.disabled = not GameState.can_star_up(hero)
		up.pressed.connect(func() -> void:
			if GameState.star_up(hero):
				_done("%s 点亮了第 %d 颗勾玉！" % [hero.display_name, Stars.lit(GameState.star_of(hero.id))]))
		buttons.add_child(up)
		buttons.add_child(_medicine_button(hero))
		if GameState.can_swear(hero.id):
			var swear := UiKit.button("结义", Vector2(100, 56), 24)
			swear.add_theme_color_override("font_color", UiKit.GOLD)
			swear.pressed.connect(func() -> void:
				if GameState.swear(hero.id):
					_done("%s与%s义结金兰！解锁组合技「结义同心」。%s" % [GameState.player_name, hero.display_name, GameState.taught_text(hero.id)]))
			buttons.add_child(swear)
	else:
		var join := UiKit.button("招募", Vector2(150, 56), 24)
		join.disabled = souls < Stars.RECRUIT_SOULS
		join.pressed.connect(func() -> void:
			if GameState.recruit_with_souls(hero):
				_done("%s 加入了！" % hero.display_name))
		buttons.add_child(join)
	var price := Stars.soul_price(hero) * SOUL_STEP
	var buy := UiKit.button("义气 %d 换 %d 将魂" % [price, SOUL_STEP], Vector2(190, 56), 19)
	buy.disabled = GameState.yiqi < price
	buy.pressed.connect(func() -> void:
		if GameState.buy_souls(hero, SOUL_STEP):
			_done("换来 %s 的将魂 %d 个" % [hero.display_name, SOUL_STEP]))
	buttons.add_child(buy)
	var melt := UiKit.button("%d 将魂化为义气" % SOUL_STEP, Vector2(170, 56), 19)
	melt.disabled = souls < SOUL_STEP
	melt.pressed.connect(func() -> void:
		if GameState.souls_to_yiqi(hero.id, SOUL_STEP):
			_done("%d 个将魂化成了 %d 点义气" % [SOUL_STEP, SOUL_STEP * Stars.YIQI_PER_SOUL]))
	buttons.add_child(melt)


## 用药：列出身上带的药，单人药用在这位身上，全队药全队都回。
func _open_medicines(hero: UnitData) -> void:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.GOLD, 2, 10))
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var max_hp := GameState.max_hp_of(hero.id)
	var vit := GameState.vitality_of(hero.id)
	v.add_child(UiKit.label("给%s用药　气血 %d / %d" % [hero.display_name, roundi(vit * max_hp), max_hp], 26, UiKit.GOLD))
	var close := func() -> void:
		overlay.queue_free()
		_refresh_list()
		_show_detail()
	overlay.set_meta("close_on_back", close)
	for id: StringName in GameState.medicines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var text := UiKit.label("%s ×%d　%s" % [Vitality.medicine_name(id), GameState.medicines[id], Vitality.medicine_effect(id)], 18)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var team := Vitality.medicine_for_team(id)
		var use := UiKit.button("全队用" if team else "用", Vector2(110, 48), 20)
		use.disabled = GameState.vitality.is_empty() if team else GameState.vitality_of(hero.id) >= 0.999
		use.pressed.connect(func() -> void:
			if GameState.use_medicine(id, hero.id):
				close.call()
				_done("用了%s" % Vitality.medicine_name(id)))
		row.add_child(use)
	var back := UiKit.button("返回", Vector2(160, 50), 22)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	v.add_child(back)


func _wrapped(text: String, color: Color) -> Label:
	var l := UiKit.label(text, 17, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## 主修按钮：显示现在练的那门（就是统领光环），点开换。
func _martial_button(main: bool) -> Button:
	var m := GameState.martial(GameState.martial_main) if main else null
	var text := "%s：%s" % ["主修" if main else "副修", m.display_name if m != null else "空"]
	if main:
		text = "统领光环：%s" % (m.display_name if m != null else "空")
	var button := UiKit.button(text, Vector2(220, 50), 19)
	button.add_theme_color_override("font_color", UiKit.ACCENT if m != null else UiKit.TEXT_DIM)
	button.pressed.connect(_open_martials)
	return button


## 武学：列出学会的每一门和它作统领光环时给全队加什么，点按钮换主修。
func _open_martials() -> void:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 560)
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.ACCENT, 2, 10))
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)
	v.add_child(UiKit.label("武学：主修的那门就是统领光环，加给出战的每一位好汉", 22, UiKit.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var close := func() -> void:
		overlay.queue_free()
		_refresh_list()
		_show_detail()
	# 手机返回键先关这一层（见 main._go_back）
	overlay.set_meta("close_on_back", close)
	for id in GameState.martials:
		var m := GameState.martial(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 10)
		info.add_child(name_row)
		name_row.add_child(UiKit.label(m.display_name, 24))
		var state := "主修中" if id == GameState.martial_main else ""
		name_row.add_child(UiKit.label(state, 18, UiKit.ACCENT))
		name_row.add_child(UiKit.label(m.source, 16, UiKit.TEXT_DIM))
		info.add_child(UiKit.label("统领光环：全队 %s" % GameState.aura_of(m).summary(), 17))
		var flavor := UiKit.label(m.flavor, 16, UiKit.TEXT_DIM)
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(flavor)
		var as_main := UiKit.button("主修", Vector2(90, 46), 20)
		as_main.disabled = id == GameState.martial_main
		as_main.pressed.connect(func() -> void:
			GameState.set_martial_main(id)
			close.call())
		row.add_child(as_main)
	if GameState.martials.size() < 2:
		list.add_child(UiKit.label("武学从奇遇和好汉列传里学：比如路上遇到的卖艺汉子、落难书生，林冲列传完结时林冲也会传授枪法。", 18, UiKit.TEXT_DIM))
	var back := UiKit.button("返回", Vector2(160, 50), 22)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	v.add_child(back)


## 一个装备栏位：显示穿着的那件，点开挑别的。
func _slot_button(hero: UnitData, slot: EquipData.Slot) -> Button:
	var it := GameState.equipped(hero.id, slot)
	var text := "%s：空" % EquipData.SLOT_NAMES[slot]
	var color := UiKit.TEXT_DIM
	if not it.is_empty():
		var data := GameState.item_data(it)
		text = "%s：%s" % [EquipData.SLOT_NAMES[slot], data.display_name]
		color = UiKit.QUALITY_COLORS[data.quality]
	var button := UiKit.button(text, Vector2(130, 50), 17)
	button.clip_text = true
	button.add_theme_color_override("font_color", color)
	button.pressed.connect(_open_picker.bind(hero, slot))
	return button


func _medicine_button(hero: UnitData) -> Button:
	var carried := 0
	for id in GameState.medicines:
		carried += GameState.medicines[id]
	var med := UiKit.button("用药（%d）" % carried, Vector2(124, 50), 17)
	med.disabled = carried == 0
	med.pressed.connect(_open_medicines.bind(hero))
	return med


## 挑装备：列出这个栏位的所有装备，品质高的在前；点「穿上」换上，点「卸下」脱掉。
func _open_picker(hero: UnitData, slot: EquipData.Slot) -> void:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 520)
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.GOLD, 2, 10))
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)
	v.add_child(UiKit.label("给%s挑%s" % [hero.display_name, EquipData.SLOT_NAMES[slot]], 28, UiKit.GOLD))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var candidates := GameState.items.filter(func(it: Dictionary) -> bool: return GameState.item_data(it).slot == slot)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return GameState.item_data(a).quality > GameState.item_data(b).quality)
	if candidates.is_empty():
		var where := "集市有马卖；名马要去江湖里找。" if slot == EquipData.Slot.MOUNT else "路上遇敌、悬赏、宝箱会掉，东京、渭州、沧州的集市也有卖。"
		list.add_child(UiKit.label("还没有%s。%s" % [EquipData.SLOT_NAMES[slot], where], 20, UiKit.TEXT_DIM))
	var close := func() -> void:
		overlay.queue_free()
		_refresh_list()
		_show_detail()
	# 手机返回键先关这一层（见 main._go_back）
	overlay.set_meta("close_on_back", close)
	for it: Dictionary in candidates:
		var data := GameState.item_data(it)
		var uid: int = it["uid"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 10)
		info.add_child(name_row)
		name_row.add_child(UiKit.label(data.display_name, 24, UiKit.QUALITY_COLORS[data.quality]))
		name_row.add_child(UiKit.label(data.quality_name(), 17, UiKit.QUALITY_COLORS[data.quality]))
		name_row.add_child(UiKit.label(data.summary(), 18))
		var holder: StringName = it["holder"]
		if holder != &"" and holder != hero.id:
			name_row.add_child(UiKit.label("（%s 穿着）" % _holder_name(holder), 17, UiKit.TEXT_DIM))
		if not data.effects.is_empty():
			info.add_child(UiKit.label(data.effects_text(), 16, UiKit.TEXT_DIM))
		if data.owner != &"":
			var mine := data.owner == hero.id
			info.add_child(UiKit.label("%s的%s：装在他身上绝招再强化一次%s" % [GameDB.hero(data.owner).display_name, data.quality_name(), "（正是本人）" if mine else ""], 16, UiKit.GOLD if mine else UiKit.TEXT_DIM))
		var wearing := holder == hero.id
		var action := UiKit.button("卸下" if wearing else "穿上", Vector2(110, 48), 20)
		action.pressed.connect(func() -> void:
			if wearing:
				GameState.unequip(uid)
			else:
				GameState.equip(hero.id, uid)
			close.call())
		row.add_child(action)
	var back := UiKit.button("返回", Vector2(160, 50), 22)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	v.add_child(back)


## 秘籍栏：显示装着的那本（主角也可能是一门武学），点开挑别的。
func _scroll_button(hero: UnitData) -> Button:
	var slot_name := GameState.scroll_slot_name(hero.id)
	var button := UiKit.button("秘籍：%s" % (slot_name if slot_name != "" else "空"), Vector2(170, 50), 17)
	button.clip_text = true
	var sc := GameState.scroll_of(hero.id)
	button.add_theme_color_override("font_color", UiKit.QUALITY_COLORS[mini(GameState.scroll_data(sc).quality, EquipData.Quality.MING)] if not sc.is_empty() else (UiKit.ACCENT if slot_name != "" else UiKit.TEXT_DIM))
	button.pressed.connect(_open_scrolls.bind(hero))
	return button


## 挑秘籍：列出所有秘籍（品质高的在前），主角还能把学会的武学放进来。
func _open_scrolls(hero: UnitData) -> void:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 540)
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.GOLD, 2, 10))
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)
	v.add_child(UiKit.label("给%s挑秘籍：每人一格，被动、追击、开局三类" % hero.display_name, 26, UiKit.GOLD))
	var scroll_box := ScrollContainer.new()
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll_box)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll_box.add_child(list)
	var close := func() -> void:
		overlay.queue_free()
		_refresh_list()
		_show_detail()
	overlay.set_meta("close_on_back", close)
	var row_for := func(title: String, color: Color, line: String, note: String, wearing: bool, on_pick: Callable) -> void:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 10)
		info.add_child(name_row)
		name_row.add_child(UiKit.label(title, 22, color))
		if note != "":
			name_row.add_child(UiKit.label(note, 16, UiKit.TEXT_DIM))
		var desc := UiKit.label(line, 17)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
		var action := UiKit.button("卸下" if wearing else "装上", Vector2(110, 48), 20)
		action.pressed.connect(func() -> void:
			on_pick.call(wearing)
			close.call())
		row.add_child(action)
	var candidates := GameState.scrolls.duplicate()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return GameState.scroll_data(a).quality > GameState.scroll_data(b).quality)
	for sc: Dictionary in candidates:
		var data := GameState.scroll_data(sc)
		var uid: int = sc["uid"]
		var holder: StringName = sc["holder"]
		var note := data.quality_name()
		if holder != &"" and holder != hero.id:
			note += "（%s 装着）" % _holder_name(holder)
		row_for.call("《%s》" % data.display_name, UiKit.QUALITY_COLORS[mini(data.quality, EquipData.Quality.MING)], data.summary(), note, holder == hero.id, func(wearing: bool) -> void:
			if wearing:
				GameState.unequip_scroll(hero.id)
			else:
				GameState.equip_scroll(hero.id, uid))
	if list.get_child_count() == 0:
		list.add_child(UiKit.label("还没有秘籍。和好汉结义时他会传授独门秘籍；悬赏、宝箱会给，集市也有卖凡品。", 20, UiKit.TEXT_DIM))
	var back := UiKit.button("返回", Vector2(160, 50), 22)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	v.add_child(back)


func _holder_name(id: StringName) -> String:
	if id == GameState.PROTAGONIST_ID:
		return GameState.player_name
	var h := GameDB.hero(id)
	return h.display_name if h != null else String(id)


func _is_protagonist(hero: UnitData) -> bool:
	return hero.id == GameState.PROTAGONIST_ID


func _owned(hero: UnitData) -> bool:
	return _is_protagonist(hero) or GameState.owns(hero.id)


func _done(text: String) -> void:
	_notice.text = text
	_refresh_list()
	_show_detail()


## 当前队伍等级下的属性，和战斗里的算法一致。
static func _at(base: int, level: int) -> int:
	return roundi(base * pow(BattleUnit.LEVEL_GROWTH, level - 1))




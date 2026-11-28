class_name HeroesView
extends Control
## 好汉：左边是名单（主角在最上面），右边是选中的人的详情；在这里换装备、升星、
## 把将魂化成义气、用义气换将魂、用将魂招募。

signal back_requested

const ROW_HEIGHT := 62
const LIST_WIDTH := 280
## 一次化掉 / 换来多少将魂
const SOUL_STEP := 10
## 纸面上的字色：淡墨、赭金；品级名字压在宣纸上用深一点的颜色
const DIM := UiKit.INK_DIM
const GOLD_INK := Color("8a5a12")
const TIER_INK: Array[Color] = [Color("8a5a12"), Color("5a3480"), Color("2f5f8a"), Color("4a4640")]
## 中间立绘的宽
const PORTRAIT_WIDTH := 330

var _show_all := false
var _selected: UnitData
var _list: VBoxContainer
var _rows: Dictionary[UnitData, PanelContainer] = {}
var _detail: VBoxContainer
var _bottom: VBoxContainer
var _yiqi_label: Label
var _notice: Label
var _portrait: TextureRect
var _portrait_name: Label
var _portrait_marks: VBoxContainer


func _ready() -> void:
	GameState.mark_tutorial("tut_heroes")
	UiKit.backdrop(self)

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
	top.add_child(UiKit.page_title("好汉", "群英", 46))
	var show_all := CheckButton.new()
	show_all.text = "显示未招募"
	show_all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	show_all.add_theme_font_override("font", UiKit.cjk_font())
	show_all.add_theme_font_size_override("font_size", 16)
	show_all.add_theme_color_override("font_color", Color("e9d3a0"))
	show_all.add_theme_color_override("font_pressed_color", Color("e9d3a0"))
	show_all.toggled.connect(func(on: bool) -> void:
		_show_all = on
		_refresh_list())
	top.add_child(show_all)
	_yiqi_label = _label("", 20, Color("f4e2b4"))
	_yiqi_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_yiqi_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_yiqi_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_yiqi_label)
	var books := UiKit.plaque_button("技能书", Vector2(140, 48), false, 24)
	books.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	books.pressed.connect(_open_books)
	top.add_child(books)
	var back := UiKit.back_button()
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

	# 中间：选中的人的大立绘，右上竖写名字、盖品级和身份印
	var stage := Control.new()
	stage.custom_minimum_size.x = PORTRAIT_WIDTH
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(stage)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_portrait)
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.offset_left = -40
	_portrait.offset_right = 10
	var marks := VBoxContainer.new()
	marks.add_theme_constant_override("separation", 8)
	marks.alignment = BoxContainer.ALIGNMENT_BEGIN
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(marks)
	marks.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	marks.offset_left = -70
	marks.offset_right = -4
	marks.offset_top = 8
	_portrait_name = UiKit.brush_label("", 60, Color("f4e2b4"))
	_portrait_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_name.add_theme_constant_override("line_spacing", -16)
	_portrait_name.add_theme_constant_override("outline_size", 8)
	_portrait_name.add_theme_color_override("font_outline_color", Color("1a0f08"))
	marks.add_child(_portrait_name)
	_portrait_marks = VBoxContainer.new()
	_portrait_marks.add_theme_constant_override("separation", 6)
	_portrait_marks.alignment = BoxContainer.ALIGNMENT_CENTER
	marks.add_child(_portrait_marks)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	body.add_child(panel)
	var detail_margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		detail_margin.add_theme_constant_override("margin_" + side, 0)
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

	_notice = UiKit.brush_label("", 24, Color("f4e2b4"))
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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(col)
	var name := UiKit.brush_label(hero.display_name, 26, UiKit.INDIGO if _is_protagonist(hero) else TIER_INK[hero.tier])
	col.add_child(name)
	if not _is_protagonist(hero):
		var marks := HBoxContainer.new()
		marks.add_theme_constant_override("separation", 6)
		marks.add_child(MagatamaRow.for_hero(hero, GameState.star_of(hero.id), 13))
		if GameState.owns(hero.id):
			marks.add_child(_label("%d 级" % GameState.level_of(hero.id), 13, DIM))
		col.add_child(marks)
	var right := _label("", 14, UiKit.CINNABAR)
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
		var style := UiKit.box(UiKit.PAPER, UiKit.CINNABAR if picked else UiKit.GILT, 3 if picked else 1, 2)
		style.set_content_margin_all(4)
		style.content_margin_right = 10
		style.shadow_color = Color(0.9, 0.6, 0.3, 0.5) if picked else Color(0, 0, 0, 0.4)
		style.shadow_size = 8 if picked else 4
		row.add_theme_stylebox_override("panel", style)
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
		_detail.add_child(_label("还没有招募到好汉。去大地图点「招募」，用聚义令到聚义厅招人。", 22, DIM))
		return
	var hero := _selected
	var protagonist := _is_protagonist(hero)
	var owned := _owned(hero)
	var star := GameState.star_of(hero.id)
	if protagonist:
		hero = GameState.protagonist()
	var effective := Equipment.apply(hero if protagonist else Bonds.apply(Stars.apply(hero, star), GameState.bond_of(hero.id)), GameState.effective_gear(hero.id))
	var held_scroll := GameState.scroll_of(hero.id)
	effective = Miji.apply(effective, GameState.scroll_data(held_scroll) if not held_scroll.is_empty() else null)

	_show_portrait(hero, owned, star)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_detail.add_child(head)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	info.add_child(name_row)
	name_row.add_child(UiKit.brush_label(hero.display_name, 32, UiKit.INDIGO if protagonist else TIER_INK[hero.tier]))
	var nick := _label(hero.nickname, 18, DIM)
	nick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(nick)
	if protagonist:
		var pm := HBoxContainer.new()
		pm.add_theme_constant_override("separation", 8)
		pm.add_child(UiKit.role_tag(hero, 15))
		pm.add_child(_label("统领 · %s · %s · %s（%s）" % [Renown.realm_name(GameState.realm), GameState.origin().display_name, UiKit.ROLE_NAMES[hero.role], Roles.summary(hero.role)], 20, UiKit.INDIGO))
		info.add_child(pm)
	else:
		var marks := HBoxContainer.new()
		marks.add_theme_constant_override("separation", 8)
		marks.add_child(MagatamaRow.for_hero(hero, star, 24))
		marks.add_child(UiKit.role_tag(hero, 15))
		marks.add_child(_label("%s · %s（%s）" % [UiKit.RARITY_NAMES[hero.rarity], UiKit.ROLE_NAMES[hero.role], Roles.summary(hero.role)], 18, DIM))
		info.add_child(marks)
		var faction := Factions.of(hero.id)
		if faction != &"":
			info.add_child(_label("山头：%s（出战三人都出自%s时：%s）" % [Factions.display_name(faction), Factions.display_name(faction), Factions.bonus_text(faction)], 17, DIM))
	if protagonist:
		var m := GameState.martial(GameState.martial_main)
		var lv0 := GameState.level
		info.add_child(_label("%d 级　生命 %d　攻击 %d　防御 %d　法抗 %d　速度 %d　敏捷 %d" % [lv0, _at(effective.base_hp, lv0), _at(effective.base_atk, lv0), _at(effective.base_def, lv0), _at(effective.res(), lv0), effective.base_spd, effective.agi()], 17))
		info.add_child(_wrapped("主修「%s」第 %d 重：统领上阵放它的绝招%s" % [m.display_name, GameState.martial_level(m.id), "（外门武学，威力七成）" if m.role != hero.role else ""] if m != null else "还没有主修武学", GOLD_INK))
		info.add_child(_wrapped("统领和好汉一起上场；统领倒下全队攻击 -%d%%。职业开局定下不变；换主修只换绝招，在「武学」里花修为修炼。境界、名望、号令在主角页。" % roundi(BattleModel.MORALE_LOSS * 100), DIM))
	elif owned:
		var lv := GameState.level_of(hero.id)
		info.add_child(_label("%d 级　生命 %d　攻击 %d　防御 %d　法抗 %d　速度 %d　敏捷 %d" % [lv, _at(effective.base_hp, lv, effective), _at(effective.base_atk, lv, effective), _at(effective.base_def, lv, effective), _at(effective.res(), lv, effective), effective.base_spd, effective.agi()], 17))
		info.add_child(_label(_exp_text(hero.id), 16, DIM))
		var vit := GameState.vitality_of(hero.id)
		if vit < 0.999:
			var hurt := "气血 %d%%" % roundi(vit * 100)
			if Vitality.is_wounded(vit):
				hurt += "（重伤）"
			info.add_child(_label(hurt + "　歇脚、吃药、赶路都能回", 18, UiKit.CINNABAR))
		var bonus := PackedStringArray()
		if star > 1 and not protagonist:
			bonus.append("勾玉：生命、攻击、防御、法抗 +%d%%" % roundi(Stars.STAT_BONUS * (star - 1) * 100))
		if Bonds.level(GameState.bond_of(hero.id)) > 0 and not protagonist:
			bonus.append("羁绊：+%d%%" % roundi(Bonds.STAT_BONUS * Bonds.level(GameState.bond_of(hero.id)) * 100))
		if not effective.gear_effects.is_empty():
			bonus.append("特效：" + "、".join(effective.gear_effects.map(func(e: StringName) -> String: return EquipData.EFFECTS[e][0])))
		if not bonus.is_empty():
			info.add_child(_label("　".join(bonus), 17, DIM))
	else:
		info.add_child(_label("未招募", 26, DIM))

	if owned and not protagonist:
		info.add_child(_label("羁绊　%s　（带他打赢一场 +%d，打完他的一段列传 +%d）" % [Bonds.progress_text(GameState.bond_of(hero.id)), Bonds.BATTLE_POINTS, Bonds.STORY_POINTS], 17, GOLD_INK))
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
			info.add_child(_label(tip, 17, GOLD_INK))
	if protagonist and hero.skill != null:
		_detail.add_child(_label("「%s」%s" % [hero.skill.display_name, _area_text(hero.skill)], 24))
		var pdesc := _label(hero.skill.description, 18, DIM)
		pdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(pdesc)
	if not protagonist:
		_detail.add_child(_label("「%s」%s" % [effective.skill.display_name, _area_text(effective.skill)], 24))
		var desc := _label(effective.skill.description, 18, DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(desc)
	if not protagonist and star < Stars.SKILL_UP_STAR and Stars.max_stars(hero) >= Stars.SKILL_UP_STAR:
		_detail.add_child(_label("点亮 %d 颗勾玉时强化：%s" % [Stars.lit(Stars.SKILL_UP_STAR), Stars.upgrade_text(hero.skill)], 17, DIM))
	if hero.talent != null:
		var rank := Stars.talent_rank(hero, star) if owned else 0
		var note := ""
		if rank == 0:
			note = "（点亮第 1 颗勾玉解锁）"
		elif rank == 1:
			note = "（勾玉全亮时再强化）"
		var talent := _label("天赋「%s」：%s%s" % [hero.talent.display_name, hero.talent.describe(rank), note], 18, UiKit.INK if rank > 0 else DIM)
		talent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(talent)
	for e: EquipData in GameDB.equipment.values():
		if e.quality == EquipData.Quality.MING and e.owner == hero.id:
			var got := GameState.has_flag("mingqi_" + String(e.id))
			var where := "已得到" if got else "出处：%s" % e.source_text
			_detail.add_child(_label("%s「%s」：%s　%s" % [e.quality_name(), e.display_name, e.summary(), where], 17, UiKit.QUALITY_INK[EquipData.Quality.MING] if got else DIM))
	if owned and not held_scroll.is_empty():
		var held := GameState.scroll_data(held_scroll)
		_detail.add_child(_wrapped("秘籍《%s》%s" % [held.display_name, held.summary()], UiKit.QUALITY_INK[mini(held.quality, EquipData.Quality.MING)]))
	if not protagonist:
		var own_miji := GameDB.miji_of_hero(hero.id)
		if own_miji != null:
			var taught := GameState.has_flag("miji_" + String(hero.id))
			_detail.add_child(_wrapped("独门秘籍《%s》%s　%s" % [own_miji.display_name, own_miji.summary(), "已传授" if taught else "结义时传授"], GOLD_INK if taught else DIM))
		for combo in GameDB.combos:
			var partner := combo.partner_of(hero.id)
			if partner != &"":
				var partner_owned := GameState.owns(partner)
				_detail.add_child(_wrapped("组合技「%s」（和%s同上阵%s）：%s" % [combo.display_name, GameDB.hero(partner).display_name, "" if partner_owned else "，还没招到", combo.description], DIM if partner_owned else Color(DIM, 0.6)))
		var sworn := Bonds.sworn_combo(hero, GameState.PROTAGONIST_ID)
		if GameState.sworn(hero.id):
			_detail.add_child(_wrapped("已结义　组合技「%s」：%s" % [sworn.display_name, sworn.description], GOLD_INK))
		elif GameState.can_swear(hero.id):
			_detail.add_child(_wrapped("羁绊已到「%s」，点下面的「结义」义结金兰，解锁「%s」：%s" % [Bonds.NAMES[Bonds.SWEAR_LEVEL], sworn.display_name, sworn.description], GOLD_INK))
		elif owned:
			_detail.add_child(_wrapped("羁绊到「%s」后可以结义，解锁「%s」：%s" % [Bonds.NAMES[Bonds.SWEAR_LEVEL], sworn.display_name, sworn.description], DIM))


	if protagonist:
		var martial_row := HBoxContainer.new()
		martial_row.add_theme_constant_override("separation", 10)
		_bottom.add_child(martial_row)
		martial_row.add_child(_martial_button(true))
	if owned:
		var gear_row := HFlowContainer.new()
		gear_row.add_theme_constant_override("h_separation", 8)
		gear_row.add_theme_constant_override("v_separation", 8)
		_bottom.add_child(gear_row)
		for slot in EquipData.Slot.values():
			gear_row.add_child(_slot_button(hero, slot))
		gear_row.add_child(_scroll_button(hero))
	if protagonist:
		return

	var souls := GameState.souls_of(hero.id)
	if owned:
		var need := "勾玉已全部点亮" if star >= Stars.max_stars(hero) else "点亮下一颗需要 %d" % Stars.cost(star)
		_bottom.add_child(_label("将魂 %d（%s）" % [souls, need], 20))
	else:
		_bottom.add_child(_label("将魂 %d / %d，攒够了就能直接招募" % [souls, Stars.RECRUIT_SOULS], 20))

	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 8)
	_bottom.add_child(buttons)
	if owned:
		var up := UiKit.plaque_button("升星", Vector2(130, 54), GameState.can_star_up(hero), 26)
		up.disabled = not GameState.can_star_up(hero)
		up.pressed.connect(func() -> void:
			if GameState.star_up(hero):
				_done("%s 点亮了第 %d 颗勾玉！" % [hero.display_name, Stars.lit(GameState.star_of(hero.id))]))
		buttons.add_child(up)
		buttons.add_child(_medicine_button(hero))
		if GameState.can_swear(hero.id):
			var swear := UiKit.button("结义", Vector2(100, 56), 24)
			swear.add_theme_color_override("font_color", Color("ffcf7a"))
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
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var max_hp := GameState.max_hp_of(hero.id)
	var vit := GameState.vitality_of(hero.id)
	v.add_child(_label("给%s用药　气血 %d / %d" % [hero.display_name, roundi(vit * max_hp), max_hp], 26, GOLD_INK))
	var close := func() -> void:
		overlay.queue_free()
		_refresh_list()
		_show_detail()
	overlay.set_meta("close_on_back", close)
	for id: StringName in GameState.medicines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var text := _label("%s ×%d　%s" % [Vitality.medicine_name(id), GameState.medicines[id], Vitality.medicine_effect(id)], 18)
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


## 纸面上的字：默认墨色。
## 长句自动换行并占满一行（右边宣纸页不宽，长的属性行、说明会撑出画面）。
func _label(text: String, font_size := 22, color := UiKit.INK) -> Label:
	var l := UiKit.label(text, font_size, color)
	if text.length() > 22:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## 中间的大立绘、竖写的名字、品级印和身份印；没招到的压暗。
func _show_portrait(hero: UnitData, owned: bool, star: int) -> void:
	_portrait.texture = hero.portrait if hero.portrait != null else hero.bust
	_portrait.modulate = Color.WHITE if owned else Color(0.35, 0.33, 0.32)
	_portrait_name.text = UiKit.vertical_text(hero.display_name)
	for c in _portrait_marks.get_children():
		c.queue_free()
	if _is_protagonist(hero):
		var s := UiKit.seal_label("统领", 18, true, UiKit.INDIGO)
		s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_portrait_marks.add_child(s)
		return
	var tier := UiKit.seal_label(UiKit.TIER_NAMES[hero.tier], 22, false, TIER_INK[hero.tier])
	tier.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_portrait_marks.add_child(tier)
	var seal := IdentitySeal.make(hero.rarity, 36)
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_portrait_marks.add_child(seal)


func _wrapped(text: String, color: Color) -> Label:
	var l := _label(text, 17, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## 主修按钮：显示现在练的那门（就是统领上阵放的绝招），点开换。
func _martial_button(main: bool) -> Button:
	var m := GameState.martial(GameState.martial_main) if main else null
	var text := "%s：%s" % ["主修" if main else "副修", m.display_name if m != null else "空"]
	if main:
		text = "武学：%s %s" % [m.display_name, "第%d重" % GameState.martial_level(m.id)] if m != null else "武学：空"
	var button := UiKit.button(text, Vector2(220, 50), 19)
	button.add_theme_color_override("font_color", UiKit.ACCENT if m != null else UiKit.TEXT_DIM)
	button.pressed.connect(_open_martials)
	return button


## 武学：列出学会的每一门，花修为修炼、点按钮换主修。别的职业的武学标「外门」（威力七成）。
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
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)
	var my_role := GameState.protagonist_role()
	v.add_child(_label("武学：主修的那门就是统领上阵放的绝招。修为 %d　境界「%s」最多修到第 %d 重" % [GameState.xiuwei, Renown.realm_name(GameState.realm), GameState.martial_cap()], 22, UiKit.INDIGO))
	v.add_child(_label("统领是%s：主修别的职业的武学（外门）也行，但威力只有七成。修为靠打仗、野外打坐攒。" % UiKit.ROLE_NAMES[my_role], 16, DIM))
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
		name_row.add_child(_label(m.display_name, 24))
		var state := "主修中" if id == GameState.martial_main else ""
		name_row.add_child(_label(state, 18, UiKit.INDIGO))
		name_row.add_child(_label(m.source, 16, DIM))
		var lv := GameState.martial_level(id)
		var sk := m.skill_at(lv)
		var outer := "（外门，威力七成）" if m.role != my_role else ""
		info.add_child(_label("%s%s · 第 %d 重　「%s」%s" % [UiKit.ROLE_NAMES[m.role], outer, lv, sk.display_name if sk != null else "", _area_text(sk) if sk != null else ""], 17))
		if lv < MartialData.MAX_LEVEL and lv >= GameState.martial_cap():
			info.add_child(_label("境界不够：升到下一阶境界才能接着修（主角页「投名状」）", 16, DIM))
		elif lv < MartialData.MAX_LEVEL:
			info.add_child(_label("修到第 %d 重：%s（修为 %d）" % [lv + 1, MartialData.level_text(lv + 1), MartialData.level_cost(lv)], 16, GOLD_INK))
		var train := UiKit.button("修炼", Vector2(90, 46), 20)
		train.disabled = not GameState.can_train(id)
		train.pressed.connect(func() -> void:
			if GameState.train_martial(id):
				close.call()
				_done("「%s」修到了第 %d 重" % [m.display_name, GameState.martial_level(id)]))
		row.add_child(train)
		var flavor := _label(m.flavor, 16, DIM)
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(flavor)
		var as_main := UiKit.button("主修", Vector2(90, 46), 20)
		as_main.disabled = id == GameState.martial_main
		as_main.pressed.connect(func() -> void:
			GameState.set_martial_main(id)
			close.call())
		row.add_child(as_main)
	if GameState.martials.size() < 2:
		list.add_child(_label("武学从奇遇和好汉列传里学：比如路上遇到的卖艺汉子、落难书生，林冲列传完结时林冲也会传授枪法。", 18, DIM))
	var back := UiKit.button("返回", Vector2(160, 50), 22)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	v.add_child(back)


## 技能书：按原著故事线用好汉将魂合成；行囊里的技能书统领可以研读，学会书里的武学。
func _open_books() -> void:
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
	panel.custom_minimum_size = Vector2(1080, 620)
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)
	v.add_child(_label("技能书：用一段故事里每位好汉的将魂合成（不用招到他们，也不会少人）。残页 %d 张，一张顶一个缺的将魂" % GameState.pages, 20, UiKit.INDIGO))
	v.add_child(_label("合成的书放进行囊：可以给好汉装进秘籍栏，也可以让统领研读，学会书里的武学（书就用掉了）", 16, DIM))
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
	overlay.set_meta("close_on_back", close)
	var name_of := func(id: StringName) -> String: return GameDB.hero(id).display_name if GameDB.hero(id) != null else String(id)
	var books := GameDB.mijis.values().filter(func(m: MijiData) -> bool: return m.is_book())
	books.sort_custom(func(a: MijiData, b: MijiData) -> bool: return a.quality > b.quality)
	for mj: MijiData in books:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		info.add_child(head)
		head.add_child(_label("《%s》" % mj.display_name, 22, UiKit.QUALITY_INK[mini(mj.quality, EquipData.Quality.MING)]))
		head.add_child(_label("%s · 故事「%s」" % [mj.quality_name(), mj.story], 17, DIM))
		var owned_count := GameState.scrolls.filter(func(sc: Dictionary) -> bool: return sc["id"] == mj.id).size()
		if owned_count > 0:
			head.add_child(_label("行囊里有 %d 本" % owned_count, 17, GOLD_INK))
		info.add_child(_wrapped("将魂：%s　还缺 %d 个" % [Books.progress_text(mj, GameState.souls, name_of), Books.missing(mj, GameState.souls)], UiKit.INK))
		info.add_child(_wrapped("装进秘籍栏：%s" % mj.summary(), DIM))
		if mj.martial != null:
			var sk := mj.martial.skill
			info.add_child(_wrapped("统领研读：学会武学「%s」（%s）——%s" % [mj.martial.display_name, UiKit.ROLE_NAMES[mj.martial.role], sk.description if sk != null else ""], DIM))
		var buttons := VBoxContainer.new()
		buttons.add_theme_constant_override("separation", 6)
		row.add_child(buttons)
		var craft := UiKit.button("合成", Vector2(96, 44), 20)
		craft.disabled = not Books.can_craft(mj, GameState.souls, GameState.pages)
		craft.pressed.connect(func() -> void:
			if GameState.craft_book(mj):
				close.call()
				_done("合成了《%s》，放进了行囊" % mj.display_name))
		buttons.add_child(craft)
		if mj.martial != null and owned_count > 0:
			var study := UiKit.button("研读", Vector2(96, 44), 20)
			study.disabled = mj.martial.id in GameState.martials
			study.tooltip_text = "统领已经会了" if study.disabled else "统领学会「%s」，这本书用掉" % mj.martial.display_name
			study.pressed.connect(func() -> void:
				for sc in GameState.scrolls:
					if sc["id"] == mj.id:
						if GameState.study_book(sc["uid"]):
							close.call()
							_done("统领研读《%s》，学会了「%s」，可以在武学里主修" % [mj.display_name, mj.martial.display_name])
						return)
			buttons.add_child(study)
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
	# 装备格：木匣子，金边
	var button := UiKit.button(text, Vector2(104, 50), 17)
	UiKit.skin(button, UiKit.kit_box(&"slot"))
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
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)
	v.add_child(_label("给%s挑%s" % [hero.display_name, EquipData.SLOT_NAMES[slot]], 28, GOLD_INK))
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
		list.add_child(_label("还没有%s。%s" % [EquipData.SLOT_NAMES[slot], where], 20, DIM))
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
		name_row.add_child(_label(data.display_name, 24, UiKit.QUALITY_INK[data.quality]))
		name_row.add_child(_label(data.quality_name(), 17, UiKit.QUALITY_INK[data.quality]))
		name_row.add_child(_label(data.summary(), 18))
		var holder: StringName = it["holder"]
		if holder != &"" and holder != hero.id:
			name_row.add_child(_label("（%s 穿着）" % _holder_name(holder), 17, DIM))
		if not data.effects.is_empty():
			info.add_child(_label(data.effects_text(), 16, DIM))
		if data.owner != &"":
			var mine := data.owner == hero.id
			info.add_child(_label("%s的%s：装在他身上绝招再强化一次%s" % [GameDB.hero(data.owner).display_name, data.quality_name(), "（正是本人）" if mine else ""], 16, GOLD_INK if mine else DIM))
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
	var button := UiKit.button("秘籍：%s" % (slot_name if slot_name != "" else "空"), Vector2(150, 50), 17)
	button.clip_text = true
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
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)
	v.add_child(_label("给%s挑秘籍：每人一格，被动、追击、开局三类" % hero.display_name, 26, GOLD_INK))
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
		name_row.add_child(_label(title, 22, color))
		if note != "":
			name_row.add_child(_label(note, 16, DIM))
		var desc := _label(line, 17)
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
		row_for.call("《%s》" % data.display_name, UiKit.QUALITY_INK[mini(data.quality, EquipData.Quality.MING)], data.summary(), note, holder == hero.id, func(wearing: bool) -> void:
			if wearing:
				GameState.unequip_scroll(hero.id)
			else:
				GameState.equip_scroll(hero.id, uid))
	if list.get_child_count() == 0:
		list.add_child(_label("还没有秘籍。和好汉结义时他会传授独门秘籍；悬赏、宝箱会给，集市也有卖凡品。", 20, DIM))
	var back := UiKit.button("返回", Vector2(160, 50), 22)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	v.add_child(back)


func _holder_name(id: StringName) -> String:
	if id == GameState.PROTAGONIST_ID:
		return GameState.player_name
	var h := GameDB.hero(id)
	return h.display_name if h != null else String(id)


## 招式的范围小字：「（穿透）」，单人不写。
func _area_text(sk: SkillData) -> String:
	var a := sk.effective_area()
	return "" if a == SkillData.Area.SINGLE else "（%s）" % SkillData.AREA_NAMES[a]


func _is_protagonist(hero: UnitData) -> bool:
	return hero.id == GameState.PROTAGONIST_ID


func _owned(hero: UnitData) -> bool:
	return _is_protagonist(hero) or GameState.owns(hero.id)


func _done(text: String) -> void:
	_notice.text = text
	_refresh_list()
	_show_detail()


## 「经验 120 / 300（比统领低 5 级，经验 ×1.5）」：只有上场的好汉拿经验。
static func _exp_text(id: StringName) -> String:
	var lv := GameState.level_of(id)
	var out := "满级" if lv >= GameState.MAX_LEVEL else "经验 %d / %d" % [GameState.exp_of(id), GameState.exp_to_next(lv)]
	var k := GameState.catch_up_mult(id)
	if k > 1.0:
		out += "（比统领低 %d 级，经验 ×%.1f）" % [GameState.level - lv, k]
	if not id in GameState.team_ids:
		out += "　出战才长经验"
	return out


## 这个等级下的属性，和战斗里的算法一致。
static func _at(base: int, level: int, unit: UnitData = null) -> int:
	return roundi(base * pow(Roles.level_growth(unit) if unit != null else BattleUnit.LEVEL_GROWTH, level - 1))




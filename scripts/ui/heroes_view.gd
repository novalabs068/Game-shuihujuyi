class_name HeroesView
extends Control
## 好汉：左边是名单，右边是选中好汉的详情；在这里升星、把将魂化成义气、用义气换将魂、用将魂招募。

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
var _yiqi_label: Label
var _notice: Label


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
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	detail_margin.add_child(_detail)

	_notice = UiKit.label("", 20, UiKit.GOLD)
	v.add_child(_notice)

	var heroes := GameDB.heroes.duplicate()
	heroes.sort_custom(func(a: UnitData, b: UnitData) -> bool:
		if GameState.owns(a.id) != GameState.owns(b.id):
			return GameState.owns(a.id)
		if a.tier != b.tier:
			return a.tier < b.tier
		return a.sort_order < b.sort_order)
	for hero: UnitData in heroes:
		_list.add_child(_make_row(hero))
	_selected = heroes[0] if not heroes.is_empty() and GameState.owns(heroes[0].id) else null
	_refresh_list()
	_show_detail()


func _make_row(hero: UnitData) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	h.add_child(UiKit.unit_picture(hero, ROW_HEIGHT - 8, false, true))
	var name := UiKit.label(hero.display_name, 24)
	name.custom_minimum_size.x = 96
	h.add_child(name)
	h.add_child(UiKit.label(UiKit.TIER_NAMES[hero.tier], 22, UiKit.TIER_COLORS[hero.tier]))
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
		var owned := GameState.owns(hero.id)
		row.visible = owned or _show_all
		row.modulate = Color.WHITE if owned else Color(0.5, 0.5, 0.5)
		var picked := hero == _selected
		row.add_theme_stylebox_override("panel", UiKit.box(UiKit.role_color(hero), UiKit.ACCENT if picked else UiKit.TIER_COLORS[hero.tier], 4 if picked else 1, 8))
		var right: Label = row.find_child("Right", true, false)
		if owned:
			right.text = _star_text(GameState.star_of(hero.id), Stars.max_stars(hero)) + ("　可升星" if GameState.can_star_up(hero) else "")
		else:
			right.text = "将魂 %d/%d" % [GameState.souls_of(hero.id), Stars.RECRUIT_SOULS]


func _show_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	if _selected == null:
		_detail.add_child(UiKit.label("还没有招募到好汉。去大地图点「招募」，用聚义令到聚义厅招人。", 22, UiKit.TEXT_DIM))
		return
	var hero := _selected
	var owned := GameState.owns(hero.id)
	var star := GameState.star_of(hero.id)
	var effective := Stars.apply(hero, star)

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
	name_row.add_child(UiKit.label(hero.display_name, 34))
	name_row.add_child(UiKit.label(hero.nickname, 22, UiKit.rarity_color(hero)))
	info.add_child(UiKit.label("%s级 · %s · %s" % [UiKit.TIER_NAMES[hero.tier], UiKit.RARITY_NAMES[hero.rarity], UiKit.ROLE_NAMES[hero.role]], 20, UiKit.TIER_COLORS[hero.tier]))
	if owned:
		info.add_child(UiKit.label(_star_text(star, Stars.max_stars(hero)), 26, UiKit.GOLD))
		var lv := GameState.level
		info.add_child(UiKit.label("%d 级　生命 %d　攻击 %d　防御 %d　速度 %d" % [lv, _at(effective.base_hp, lv), _at(effective.base_atk, lv), _at(effective.base_def, lv), _at(effective.base_spd, lv)], 20))
		if star > 1:
			info.add_child(UiKit.label("星级加成：生命、攻击、防御 +%d%%" % roundi(Stars.STAT_BONUS * (star - 1) * 100), 17, UiKit.TEXT_DIM))
	else:
		info.add_child(UiKit.label("未招募", 26, UiKit.TEXT_DIM))

	_detail.add_child(UiKit.label("「%s」" % effective.skill.display_name, 24))
	var desc := UiKit.label(effective.skill.description, 18, UiKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(desc)
	if star < Stars.SKILL_UP_STAR and Stars.max_stars(hero) >= Stars.SKILL_UP_STAR:
		_detail.add_child(UiKit.label("%d 星时强化：%s" % [Stars.SKILL_UP_STAR, Stars.upgrade_text(hero.skill)], 17, UiKit.TEXT_DIM))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(spacer)

	var souls := GameState.souls_of(hero.id)
	if owned:
		var need := "已满星" if star >= Stars.max_stars(hero) else "升下一星需要 %d" % Stars.cost(star)
		_detail.add_child(UiKit.label("将魂 %d（%s）" % [souls, need], 20))
	else:
		_detail.add_child(UiKit.label("将魂 %d / %d，攒够了就能直接招募" % [souls, Stars.RECRUIT_SOULS], 20))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_detail.add_child(buttons)
	if owned:
		var up := UiKit.button("升星", Vector2(150, 56), 24)
		up.disabled = not GameState.can_star_up(hero)
		up.pressed.connect(func() -> void:
			if GameState.star_up(hero):
				_done("%s 升到 %d 星！" % [hero.display_name, GameState.star_of(hero.id)]))
		buttons.add_child(up)
	else:
		var join := UiKit.button("招募", Vector2(150, 56), 24)
		join.disabled = souls < Stars.RECRUIT_SOULS
		join.pressed.connect(func() -> void:
			if GameState.recruit_with_souls(hero):
				_done("%s 加入了！" % hero.display_name))
		buttons.add_child(join)
	var price := Stars.soul_price(hero) * SOUL_STEP
	var buy := UiKit.button("义气 %d 换 %d 将魂" % [price, SOUL_STEP], Vector2(220, 56), 20)
	buy.disabled = GameState.yiqi < price
	buy.pressed.connect(func() -> void:
		if GameState.buy_souls(hero, SOUL_STEP):
			_done("换来 %s 的将魂 %d 个" % [hero.display_name, SOUL_STEP]))
	buttons.add_child(buy)
	var melt := UiKit.button("%d 将魂化为义气" % SOUL_STEP, Vector2(200, 56), 20)
	melt.disabled = souls < SOUL_STEP
	melt.pressed.connect(func() -> void:
		if GameState.souls_to_yiqi(hero.id, SOUL_STEP):
			_done("%d 个将魂化成了 %d 点义气" % [SOUL_STEP, SOUL_STEP * Stars.YIQI_PER_SOUL]))
	buttons.add_child(melt)


func _done(text: String) -> void:
	_notice.text = text
	_refresh_list()
	_show_detail()


## 当前队伍等级下的属性，和战斗里的算法一致。
static func _at(base: int, level: int) -> int:
	return roundi(base * pow(BattleUnit.LEVEL_GROWTH, level - 1))


static func _star_text(star: int, max_star: int) -> String:
	return "★".repeat(star) + "☆".repeat(max_star - star)

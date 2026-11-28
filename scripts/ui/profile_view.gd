class_name ProfileView
extends Control
## 主角页：立绘和出身、等级和家当、境界和名望（立名之战、统领天赋、号令）、主修武学、坐骑、江湖履历。
## 换武学和装备在「好汉」页主角那里做，这里有按钮直接过去。

signal back_requested
signal heroes_requested
## 去打立名之战（main 接着开打）
signal battle_requested(stage: StageData, bonus: Dictionary)

const SECTION_GAP := 14
## 右边宣纸页的三个页签
const TABS: Array[String] = ["境界", "武学", "履历"]
## 左边挂轴的位置和宽
const SCROLL_RECT := Rect2(40, 16, 380, 690)

static var _tab := 0

## 纸面上的字色
const INK := UiKit.INK
const DIM := UiKit.INK_DIM


func _ready() -> void:
	UiKit.backdrop(self)
	_build_scroll()

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.position = Vector2(464, 18)
	add_child(head)
	var title := UiKit.brush_label("统领", 44, Color("e9c979"))
	title.custom_minimum_size.x = 110
	head.add_child(title)
	for i in TABS.size():
		var tab := UiKit.tab_button(TABS[i])
		tab.size_flags_vertical = Control.SIZE_SHRINK_END
		UiKit.set_tab_on(tab, i == _tab)
		tab.pressed.connect(func() -> void:
			_tab = i
			_rebuild())
		head.add_child(tab)

	var back := UiKit.back_button()
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -74
	back.offset_right = -20
	back.offset_top = 14
	back.pressed.connect(func() -> void: back_requested.emit())

	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", UiKit.panel_box())
	page.position = Vector2(452, 70)
	page.size = Vector2(800, 636)
	add_child(page)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	scroll.add_child(right)
	match _tab:
		0:
			_add_level(right)
			_add_realm(right)
		1:
			_add_commander(right)
		2:
			_add_record(right)


## 左边的立轴：上下木轴、石青锦缎天头地头，宣纸上是立绘，右边竖写名字、盖出身印，底下一段出身。
func _build_scroll() -> void:
	var me := GameState.protagonist()
	var origin := GameState.origin()
	var r := SCROLL_RECT
	var brocade: Texture2D = load("res://art/ui/result_brocade.png")
	var paper_tex: Texture2D = load("res://art/ui/result_paper.png")
	var top_band := 34.0
	var bottom_band := 44.0
	var paper_h := r.size.y - top_band - bottom_band - 36
	var y := r.position.y + 16
	_band(brocade, Rect2(r.position.x, y, r.size.x, top_band))
	var paper := TextureRect.new()
	paper.texture = paper_tex
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.position = Vector2(r.position.x, y + top_band)
	paper.size = Vector2(r.size.x, paper_h)
	paper.clip_contents = true
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paper)
	_band(brocade, Rect2(r.position.x, y + top_band + paper_h, r.size.x, bottom_band))
	_rod(Rect2(r.position.x + 6, r.position.y, r.size.x - 12, 16))
	_rod(Rect2(r.position.x - 2, y + top_band + paper_h + bottom_band, r.size.x + 4, 20))

	var pic := UiKit.picture(me.portrait if me.portrait != null else me.bust, int(paper_h - 10))
	pic.position = Vector2(-40, 14)
	pic.size = Vector2(paper_h - 10, paper_h - 10)
	paper.add_child(pic)
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 10)
	name_col.position = Vector2(r.size.x - 74, 20)
	paper.add_child(name_col)
	var name := UiKit.brush_label(UiKit.vertical_text(me.display_name), 56, INK)
	name.add_theme_constant_override("line_spacing", -14)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_col.add_child(name)
	var seal := UiKit.seal_label(origin.display_name, 18, true)
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_col.add_child(seal)
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 2)
	var fade := StyleBoxFlat.new()
	fade.bg_color = Color(UiKit.PAPER, 0.92)
	fade.set_content_margin_all(10)
	var foot_panel := PanelContainer.new()
	foot_panel.add_theme_stylebox_override("panel", fade)
	foot_panel.add_child(foot)
	foot_panel.position = Vector2(0, paper_h - 96)
	foot_panel.size = Vector2(r.size.x, 96)
	paper.add_child(foot_panel)
	foot.add_child(UiKit.brush_label("%s · 出身%s · %s" % [UiKit.ROLE_NAMES[me.role], origin.display_name, "女" if GameState.gender == GameState.GENDER_FEMALE else "男"], 22, UiKit.INDIGO))
	var desc := UiKit.label(origin.description, 14, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(desc)
	UiKit.ignore_mouse(paper)


## 一段平铺的锦缎。
func _band(tex: Texture2D, rect: Rect2) -> void:
	var t := TextureRect.new()
	t.texture = tex
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	var edge := ColorRect.new()
	edge.color = UiKit.GILT
	edge.position = rect.position
	edge.size = Vector2(rect.size.x, 2)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge)
	var edge2 := edge.duplicate() as ColorRect
	edge2.position.y = rect.end.y - 2
	add_child(edge2)


## 一根木轴，两头包金。
func _rod(rect: Rect2) -> void:
	var rod := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color("6a4429")
	s.border_color = Color("3a2414")
	s.set_border_width_all(2)
	s.set_corner_radius_all(int(rect.size.y / 2))
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 4
	rod.add_theme_stylebox_override("panel", s)
	rod.position = rect.position
	rod.size = rect.size
	rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rod)
	for x: float in [rect.position.x - 12, rect.end.x - 8]:
		var cap := Panel.new()
		var c := StyleBoxFlat.new()
		c.bg_color = Color("c9a25a")
		c.border_color = Color("8c6a2e")
		c.set_border_width_all(2)
		c.set_corner_radius_all(6)
		cap.add_theme_stylebox_override("panel", c)
		cap.position = Vector2(x, rect.position.y - 3)
		cap.size = Vector2(20, rect.size.y + 6)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cap)


## 等级、经验、家当。
func _add_level(right: VBoxContainer) -> void:
	var lv := GameState.level
	var need := GameState.exp_to_next(lv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	right.add_child(row)
	row.add_child(UiKit.brush_label("%s级" % UiKit.cn_number(lv), 34, INK))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(UiKit.label("经验 %d / %d" % [GameState.experience, need], 15, DIM))
	var bar := ProgressBar.new()
	bar.max_value = need
	bar.value = GameState.experience
	bar.custom_minimum_size = Vector2(0, 10)
	UiKit.style_bar(bar, INK)
	col.add_child(bar)
	var purse := HBoxContainer.new()
	purse.add_theme_constant_override("separation", 26)
	right.add_child(purse)
	purse.add_child(UiKit.amount_row(UiKit.coin_icon(18), "银两 %d" % GameState.silver, 17, INK))
	purse.add_child(UiKit.amount_row(UiKit.token_icon(22), "聚义令 %d" % GameState.tokens, 17, INK))
	purse.add_child(UiKit.label("修为 %d" % GameState.xiuwei, 17, UiKit.INDIGO))
	purse.add_child(UiKit.label("义气 %d" % GameState.yiqi, 17, UiKit.CINNABAR))


## 统领：和好汉一起上阵，主修武学决定绝招（职业由出身定）；坐骑。
func _add_commander(right: VBoxContainer) -> void:
	var me := GameState.protagonist()
	var main := GameState.martial(GameState.martial_main)
	right.add_child(_line("主修", "%s 第 %d 重 · %s%s" % [main.display_name, GameState.martial_level(main.id), UiKit.ROLE_NAMES[main.role], "（外门，威力七成）" if main.role != me.role else ""] if main != null else "（无）"))
	var learned := UiKit.label("已学会 %d 门武学，在「好汉」页换主修、花修为修炼（现在最多修到第 %d 重）" % [GameState.martials.size(), GameState.martial_cap()], 15, DIM)
	learned.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(learned)
	var mount := GameState.mount()
	right.add_child(_line("坐骑", "%s · %s　%s" % [mount.display_name, mount.quality_name(), mount.summary()] if mount != null else "（无，集市有马卖）"))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(gap)
	var adjust := UiKit.plaque_button("换武学装备", Vector2(210, 58), false, 26)
	adjust.size_flags_horizontal = Control.SIZE_SHRINK_END
	adjust.pressed.connect(func() -> void: heroes_requested.emit())
	right.add_child(adjust)


## 江湖履历。
func _add_record(right: VBoxContainer) -> void:
	var map: WorldMapData = GameDB.maps[GameState.DEFAULT_MAP]
	var visited := map.locations.filter(func(l: LocationData) -> bool: return l.id == GameState.location_id or GameState.has_flag("visited_" + String(l.id))).size()
	var bounties := GameDB.bounties.filter(func(b: BountyData) -> bool: return GameState.has_flag("bounty_" + String(b.id))).size()
	var stories := GameDB.stories.filter(func(s: StoryData) -> bool: return GameState.story_done(s)).size()
	var minutes := int(GameState.record["play_seconds"]) / 60
	var lines := [
		["招募", "好汉 %d / %d 位" % [GameState.owned.size(), GameDB.heroes.size()]],
		["行旅", "走过的地方 %d / %d 处" % [visited, map.locations.size()]],
		["悬赏", "揭下 %d / %d 张" % [bounties, GameDB.bounties.size()]],
		["列传", "完成 %d / %d 段" % [stories, GameDB.stories.size()]],
		["战绩", "打赢 %d 场（其中街头巷尾的小怪 %d 只）" % [GameState.record["wins"], GameState.record["roamers"]]],
		["擂台", "最高第 %d / %d 关" % [Arena.best(), Arena.round_count()]],
		["光阴", "闯荡江湖 %d 小时 %d 分" % [minutes / 60, minutes % 60]],
	]
	for l: Array in lines:
		right.add_child(_line(l[0], l[1]))


## 境界：现在第几阶、名望进度、立名之战按钮、统领天赋、号令（点了换带哪一个）。
func _add_realm(right: VBoxContainer) -> void:
	var realm := GameState.realm
	var renown := GameState.renown()
	_section(right, "境界 · %s" % Renown.realm_name(realm))
	if Renown.next_threshold(realm) >= 0:
		var step := HBoxContainer.new()
		step.add_theme_constant_override("separation", 14)
		step.add_child(UiKit.brush_label(Renown.realm_name(realm), 32, INK))
		step.add_child(UiKit.brush_label("→", 26, UiKit.GILT))
		step.add_child(UiKit.brush_label(Renown.realm_name(realm + 1), 32, UiKit.CINNABAR))
		right.add_child(step)
	var need := Renown.next_threshold(realm)
	if need < 0:
		right.add_child(UiKit.label("江湖名望 %d　已到最高境界" % renown, 17, INK))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		right.add_child(row)
		var text := UiKit.label("江湖名望 %d / %d　下一阶「%s」" % [renown, need, Renown.realm_name(realm + 1)], 17, INK)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var trial := UiKit.plaque_button("立名之战", Vector2(186, 58), GameState.can_try_trial(), 28)
		trial.disabled = not GameState.can_try_trial()
		trial.tooltip_text = "对手 %d 级，都是精英；打赢升到「%s」" % [Renown.TRIALS[realm][1], Renown.realm_name(realm + 1)]
		trial.pressed.connect(func() -> void:
			battle_requested.emit(Renown.trial_stage(realm + 1), Renown.trial_bonus(realm + 1)))
		row.add_child(trial)
		var bar := ProgressBar.new()
		bar.max_value = need
		bar.value = mini(renown, need)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		UiKit.style_bar(bar, UiKit.CINNABAR)
		right.add_child(bar)
		var hint := "名望够了，去打立名之战（对手 %d 级精英，开打前回满血）" % Renown.TRIALS[realm][1] if GameState.can_try_trial() else "招好汉、打列传、揭悬赏、做小悬赏、打头目、上擂台、遇奇遇都会涨名望"
		var hint_label := UiKit.label(hint, 15, DIM)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(hint_label)
	right.add_child(_line("属性", "统领生命、攻击、防御、法抗 +%d%%（每阶 +%d%%）" % [roundi(Renown.STAT_PER_REALM * realm * 100), roundi(Renown.STAT_PER_REALM * 100)]))
	var talent := Renown.role_talent(GameState.protagonist_role())
	var rank := Renown.talent_rank(realm)
	var talent_text := "「%s」%s" % [talent.display_name, talent.describe(maxi(rank, 1))]
	if rank == 0:
		talent_text += "（%s解锁）" % Renown.realm_name(Renown.TALENT_REALM)
	elif rank == 1:
		talent_text += "（%s强化）" % Renown.realm_name(Renown.TALENT_ENHANCE_REALM)
	right.add_child(_line("天赋", talent_text))
	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 10)
	right.add_child(cmd_row)
	var head := UiKit.brush_label("号令", 24, UiKit.INDIGO)
	head.custom_minimum_size.x = 56
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cmd_row.add_child(head)
	var chosen := GameState.battle_command()
	for id: StringName in Commands.ALL:
		var unlocked := realm >= Commands.unlock_realm(id)
		# 带着的号令是一方朱印，没带的是铜扣，没解锁的褪色
		var b := UiKit.seal_button(Commands.display_name(id), 66, 21) if id == chosen else UiKit.copper_button(Commands.display_name(id), 66, 21)
		b.disabled = not unlocked
		b.tooltip_text = Commands.describe(id) + ("" if unlocked else "（%s解锁）" % Renown.realm_name(Commands.unlock_realm(id)))
		b.pressed.connect(func() -> void:
			GameState.set_command(id)
			_rebuild())
		cmd_row.add_child(b)
	var cmd_text := "带「%s」上阵：%s。每场一次，不占出手" % [Commands.display_name(chosen), Commands.describe(chosen)] if chosen != &"" else "%s解锁第一个号令「擂鼓」" % Renown.realm_name(Commands.unlock_realm(Commands.LEIGU))
	var cmd_label := UiKit.label(cmd_text, 15, DIM)
	cmd_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(cmd_label)


## 换了号令：整页重画。
func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_ready()


func _section(parent: Control, title: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = SECTION_GAP
	parent.add_child(gap)
	var line := ColorRect.new()
	line.color = Color(UiKit.GILT, 0.6)
	line.custom_minimum_size.y = 1
	parent.add_child(line)
	parent.add_child(UiKit.brush_label(title, 28, INK))


func _line(head: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var h := UiKit.brush_label(head, 24, UiKit.INDIGO)
	h.custom_minimum_size.x = 56
	row.add_child(h)
	var t := UiKit.label(text, 17, INK)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	return row

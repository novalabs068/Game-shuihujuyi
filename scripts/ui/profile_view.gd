class_name ProfileView
extends Control
## 主角页：立绘和出身、等级和家当、境界和名望（立名之战、统领天赋、号令）、主修武学、坐骑、江湖履历。
## 换武学和装备在「好汉」页主角那里做，这里有按钮直接过去。

signal back_requested
signal heroes_requested
## 去打立名之战（main 接着开打）
signal battle_requested(stage: StageData, bonus: Dictionary)

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
	var from := UiKit.label("%s · 出身%s · %s" % [UiKit.ROLE_NAMES[me.role], origin.display_name, "女" if GameState.gender == GameState.GENDER_FEMALE else "男"], 22, UiKit.ACCENT)
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
	right.add_child(UiKit.label("银两 %d　修为 %d　聚义令 %d　义气 %d" % [GameState.silver, GameState.xiuwei, GameState.tokens, GameState.yiqi], 20, UiKit.TEXT_DIM))

	_add_realm(right)

	# 统领：和好汉一起上阵，主修武学决定绝招（职业由出身定）
	_section(right, "统领")
	var main := GameState.martial(GameState.martial_main)
	right.add_child(_line("主修", "%s 第 %d 重 · %s%s" % [main.display_name, GameState.martial_level(main.id), UiKit.ROLE_NAMES[main.role], "（外门，威力七成）" if main.role != me.role else ""] if main != null else "（无）"))
	right.add_child(UiKit.label("已学会 %d 门武学，在「好汉」页换主修、花修为修炼（现在最多修到第 %d 重）" % [GameState.martials.size(), GameState.martial_cap()], 16, UiKit.TEXT_DIM))
	var mount := GameState.mount()
	right.add_child(_line("坐骑", "%s · %s　%s" % [mount.display_name, mount.quality_name(), mount.summary()] if mount != null else "（无，集市有马卖）"))

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


## 境界：现在第几阶、名望进度、立名之战按钮、统领天赋、号令（点了换带哪一个）。
func _add_realm(right: VBoxContainer) -> void:
	var realm := GameState.realm
	var renown := GameState.renown()
	_section(right, "境界 · %s" % Renown.realm_name(realm))
	var need := Renown.next_threshold(realm)
	if need < 0:
		right.add_child(UiKit.label("江湖名望 %d　已到最高境界" % renown, 20))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		right.add_child(row)
		var text := UiKit.label("江湖名望 %d / %d　下一阶「%s」" % [renown, need, Renown.realm_name(realm + 1)], 20)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var trial := UiKit.button("立名之战", Vector2(150, 46), 20)
		trial.disabled = not GameState.can_try_trial()
		trial.tooltip_text = "对手 %d 级，都是精英；打赢升到「%s」" % [Renown.TRIALS[realm][1], Renown.realm_name(realm + 1)]
		trial.pressed.connect(func() -> void:
			battle_requested.emit(Renown.trial_stage(realm + 1), Renown.trial_bonus(realm + 1)))
		row.add_child(trial)
		var bar := ProgressBar.new()
		bar.max_value = need
		bar.value = mini(renown, need)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.add_theme_stylebox_override("background", UiKit.box(UiKit.PANEL_LIGHT, Color(0, 0, 0, 0), 0, 4))
		bar.add_theme_stylebox_override("fill", UiKit.box(UiKit.BOSS, Color(0, 0, 0, 0), 0, 4))
		right.add_child(bar)
		var hint := "名望够了，去打立名之战（对手 %d 级精英，开打前回满血）" % Renown.TRIALS[realm][1] if GameState.can_try_trial() else "招好汉、打列传、揭悬赏、做小悬赏、打头目、上擂台、遇奇遇都会涨名望"
		right.add_child(UiKit.label(hint, 16, UiKit.TEXT_DIM))
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
	var head := UiKit.label("号令", 20, UiKit.ACCENT)
	head.custom_minimum_size.x = 56
	cmd_row.add_child(head)
	var chosen := GameState.battle_command()
	for id: StringName in Commands.ALL:
		var unlocked := realm >= Commands.unlock_realm(id)
		var b := UiKit.button(Commands.display_name(id), Vector2(96, 42), 18)
		b.disabled = not unlocked
		b.tooltip_text = Commands.describe(id) + ("" if unlocked else "（%s解锁）" % Renown.realm_name(Commands.unlock_realm(id)))
		if id == chosen:
			b.add_theme_stylebox_override("normal", UiKit.box(UiKit.PANEL_LIGHT, UiKit.GOLD, 3, 6))
		b.pressed.connect(func() -> void:
			GameState.set_command(id)
			_rebuild())
		cmd_row.add_child(b)
	var cmd_text := "带「%s」上阵：%s。每场一次，不占出手" % [Commands.display_name(chosen), Commands.describe(chosen)] if chosen != &"" else "%s解锁第一个号令「擂鼓」" % Renown.realm_name(Commands.unlock_realm(Commands.LEIGU))
	var cmd_label := UiKit.label(cmd_text, 16, UiKit.TEXT_DIM)
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

extends Control
## 游戏入口：在开始界面、创建角色、江湖大地图、地点场景、编队、战斗之间切换画面。

## 统领不上阵：一个好汉都没有的时候打不了仗
const NO_TEAM_TEXT := "身边还没有好汉随行，统领一个人上不了阵。先去聚义厅招募，再在「编队」里选人。"

var _screen: Control


## 在大地图上按返回键：这么多秒内再按一次才退出
const QUIT_CONFIRM_SECONDS := 2.0

var _quit_armed_at := -100.0


func _ready() -> void:
	theme = UiKit.make_theme()
	_show_title()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


## 电脑上按 Esc 等同手机返回键，方便调试。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


## 手机返回键：先关最上面的弹窗；再退回上一层；在大地图和开始界面连按两次退出。
## 战斗和列传里不响应，免得误触丢了进度（里面有「撤退」「离开」按钮）。
func _go_back() -> void:
	if _screen == null:
		return
	for i in range(_screen.get_child_count() - 1, -1, -1):
		var child := _screen.get_child(i)
		if child is SettingsPanel or child is MarketPanel or child is ArenaPanel or child is BountyBoard:
			child.closed.emit()
			return
		if child.has_meta("close_on_back"):
			(child.get_meta("close_on_back") as Callable).call()
			return
	if _screen is BattleView or _screen is StoryView:
		return
	if _screen is WorldMapView or _screen is TitleScreen:
		_ask_quit()
	elif _screen.has_method("go_back"):
		_screen.call("go_back")
	elif _screen.has_signal("back_requested"):
		_screen.emit_signal("back_requested")
	else:
		_show_map()


func _ask_quit() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _quit_armed_at <= QUIT_CONFIRM_SECONDS:
		get_tree().quit()
		return
	_quit_armed_at = now
	var toast := UiKit.label("再按一次返回键退出游戏", 24, UiKit.GOLD)
	toast.add_theme_constant_override("outline_size", 8)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.z_index = 50
	add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.position.y -= 120
	var t := toast.create_tween()
	t.tween_interval(QUIT_CONFIRM_SECONDS - 0.4)
	t.tween_property(toast, "modulate:a", 0.0, 0.4)
	t.tween_callback(toast.queue_free)


func _show_title() -> void:
	var screen := TitleScreen.new()
	screen.new_game_requested.connect(_show_character_create)
	screen.continue_requested.connect(_show_map)
	_set_screen(screen)


func _show_character_create() -> void:
	var screen := CharacterCreate.new()
	screen.back_requested.connect(_show_title)
	screen.created.connect(func(player_name: String, origin: OriginData) -> void:
		GameState.new_game(player_name, origin)
		_show_map())
	_set_screen(screen)


func _show_map(resume_destination: StringName = &"", resume_progress := 0.0, notice := "", focus_location: StringName = &"") -> void:
	var screen := WorldMapView.new()
	screen.notice = notice
	screen.focus_location = focus_location
	screen.map = GameDB.maps[GameState.DEFAULT_MAP]
	screen.resume_destination = resume_destination
	screen.resume_progress = resume_progress
	screen.battle_requested.connect(_start_battle)
	screen.team_requested.connect(_show_team_select)
	screen.scene_requested.connect(_show_scene)
	screen.recruit_requested.connect(_show_recruit)
	screen.heroes_requested.connect(_show_heroes)
	screen.story_requested.connect(_start_story)
	screen.jianghu_requested.connect(_show_jianghu)
	screen.profile_requested.connect(_show_profile)
	screen.restart_requested.connect(func() -> void:
		GameState.delete_save()
		_show_title())
	_set_screen(screen)


## 换画面时换配乐：大地图「江湖」、场景按场景配、战斗「战斗」、列传「列传」；菜单页不换曲。
func _play_music_for(screen: Control) -> void:
	if screen is WorldMapView or screen is TitleScreen or screen is CharacterCreate:
		Music.play(&"jianghu")
	elif screen is LocationView:
		Music.play((screen as LocationView).scene_data.music)
	elif screen is BattleView:
		Music.play(&"zhandou")
	elif screen is StoryView:
		Music.play(&"liezhuan")


func _show_profile() -> void:
	var screen := ProfileView.new()
	screen.back_requested.connect(_show_map)
	screen.heroes_requested.connect(_show_heroes)
	_set_screen(screen)


func _show_jianghu() -> void:
	var screen := JiangHuView.new()
	screen.back_requested.connect(_show_map)
	screen.heroes_requested.connect(_show_heroes)
	screen.travel_requested.connect(func(id: StringName) -> void: _show_map(&"", 0.0, "", id))
	_set_screen(screen)


## 演一段列传。start_at 非 0 表示打完仗回来，接着往下演。
func _start_story(story: StoryData, start_at := 0) -> void:
	var screen := StoryView.new()
	screen.story = story
	screen.start_at = start_at
	screen.quit_requested.connect(_show_map)
	screen.battle_requested.connect(_start_story_battle.bind(story))
	screen.finished.connect(_finish_story.bind(story))
	_set_screen(screen)


## 列传里的一仗：赢了拿普通战斗的经验银两，接着演；输了回大地图，这一段下次从头来。
func _start_story_battle(stage: StageData, resume_at: int, story: StoryData) -> void:
	if GameState.team().is_empty():
		_show_map(&"", 0.0, NO_TEAM_TEXT)
		return
	var screen := BattleView.new()
	screen.stage = stage
	screen.team = GameState.battle_team()
	screen.hero_level = GameState.level
	# 在剧本里打仗前最后换的那张背景下打（五台山、瓦罐寺这些不是大地图上的地点）
	var where := StoryScript.background_before(StoryScript.load_file(story.script_path), resume_at)
	if where == "":
		where = String(story.location)
	screen.background = _battle_background(StringName(where))
	screen.place = where
	screen.start_hp = GameState.vitality.duplicate()
	screen.retry_requested.connect(_start_story_battle.bind(stage, resume_at, story))
	screen.exit_requested.connect(func() -> void:
		GameState.record_battle(screen.model)
		GameState.save_game()
		_show_map())
	screen.finished.connect(func(won: bool) -> void:
		GameState.record_battle(screen.model)
		if not won:
			GameState.save_game()
			_show_map(&"", 0.0, "「%s」没能打赢，下次从这一段开头再来。" % story.title)
			return
		var r: Dictionary = Encounters.rewards(screen.model)
		GameState.add_rewards(r["exp"], r["silver"])
		GameState.record_win()
		GameState.save_game()
		_start_story(story, resume_at))
	_set_screen(screen)


## 「林冲、花荣重伤」这样的提示；没人重伤返回空。
func _wounded_text() -> String:
	var names := PackedStringArray()
	for u in GameState.team():
		if Vitality.is_wounded(GameState.vitality_of(u.id)):
			names.append(u.display_name)
	return "" if names.is_empty() else "%s重伤，记得歇脚或用药" % "、".join(names)


## 战场背景：这一带的水墨画（art/story/<地点>），还没画的用江湖大地图。
func _battle_background(where: StringName) -> Texture2D:
	var path := StoryScript.background_path(String(where))
	return load(path) if path != "" else GameDB.maps[GameState.DEFAULT_MAP].texture


## 列传演完：发奖励、记标记，回大地图。
func _finish_story(story: StoryData) -> void:
	GameState.set_flag(story.flag())
	var hero := GameDB.hero(story.hero)
	var parts := PackedStringArray(["「%s列传·%s」完成。" % [hero.display_name, story.title]])
	var gained := Rewards.grant(story.tokens, story.silver, 0)
	if gained != "":
		parts.append(gained)
	if story.souls > 0:
		GameState.souls[story.hero] = GameState.souls_of(story.hero) + story.souls
		parts.append("%s将魂 +%d" % [hero.display_name, story.souls])
	var bond_up := GameState.add_bond(story.hero, Bonds.STORY_POINTS)
	parts.append("与%s的羁绊 +%d" % [hero.display_name, Bonds.STORY_POINTS])
	if bond_up != "":
		parts.append(bond_up)
	var mingqi := GameState.claim_mingqi()
	if mingqi != "":
		parts.append(mingqi)
	var learned := Rewards.learn(story.martial)
	if learned != "":
		parts.append("%s传授了%s" % [hero.display_name, learned.trim_prefix("学会")])
	GameState.save_game()
	_show_map(&"", 0.0, "　".join(parts))


func _show_heroes() -> void:
	var screen := HeroesView.new()
	screen.back_requested.connect(_show_map)
	_set_screen(screen)


func _show_recruit() -> void:
	var screen := RecruitView.new()
	screen.back_requested.connect(_show_map)
	_set_screen(screen)


func _show_scene(scene_id: String, notice := "") -> void:
	var screen := LocationView.new()
	screen.scene_data = GameDB.scenes[scene_id]
	screen.notice = notice
	screen.exit_requested.connect(_show_map)
	screen.scene_requested.connect(_show_scene)
	screen.battle_requested.connect(func(stage: StageData, bonus: Dictionary) -> void:
		_start_battle(stage, &"", 0.0, bonus, scene_id))
	_set_screen(screen)


func _show_team_select() -> void:
	var screen := TeamSelect.new()
	screen.start_requested.connect(func(heroes: Array[UnitData]) -> void:
		GameState.set_heroes(heroes)
		GameState.save_game()
		_show_map())
	_set_screen(screen)


## destination 非空表示这是赶路时的遭遇战：赢了接着走完，输了或撤退就留在原地。
## bonus 是打赢后额外的奖励（悬赏、奇遇、支线）：tokens、silver、experience、flag、text。
## return_scene 非空时，打完回到这个地点场景，否则回大地图。
func _start_battle(stage: StageData, destination: StringName, progress: float, bonus := {}, return_scene := "") -> void:
	if GameState.team().is_empty():
		if return_scene != "":
			_show_scene(return_scene, NO_TEAM_TEXT)
		else:
			_show_map(&"", 0.0, NO_TEAM_TEXT)
		return
	var screen := BattleView.new()
	screen.stage = stage if bonus.has("arena_round") else GameState.prepare_stage(stage)
	screen.team = GameState.battle_team()
	screen.hero_level = GameState.level
	var where := destination if destination != &"" else GameState.location_id
	if return_scene != "":
		var sd: SceneData = GameDB.scenes[return_scene]
		where = sd.battle_bg if sd.battle_bg != &"" else sd.region
	screen.background = _battle_background(where)
	screen.place = String(where)
	# 擂台比武开打前回满、打完不记伤；别的仗血量都接着上一仗
	var arena := bonus.has("arena_round")
	if not arena:
		screen.start_hp = GameState.vitality.duplicate()
	screen.retry_requested.connect(_start_battle.bind(stage, destination, progress, bonus, return_scene))
	var leave := func(notice: String) -> void:
		if return_scene != "":
			_show_scene(return_scene, notice)
		else:
			_show_map(&"", 0.0, notice)
	screen.exit_requested.connect(func() -> void:
		if not arena:
			GameState.record_battle(screen.model)
			GameState.save_game()
		leave.call(""))
	screen.finished.connect(func(won: bool) -> void:
		if not arena:
			GameState.record_battle(screen.model)
		GameState.finish_roamer(won)
		var bond_text := GameState.record_win() if won else ""
		var notice := ""
		if won:
			var r: Dictionary = Encounters.rewards(screen.model)
			var ups := GameState.add_rewards(r["exp"], r["silver"])
			var parts := PackedStringArray()
			if bonus.has("text"):
				parts.append(String(bonus["text"]).replace("{name}", GameState.player_name))
			# 悬赏给指定品质的装备；普通遇敌有机会掉一件凡品
			var drop: EquipData = null
			if bonus.has("equip_quality"):
				drop = Equipment.random_of(GameDB.equipment.values(), bonus["equip_quality"], screen.model.rng)
			elif bonus.is_empty() and screen.model.rng.randf() < Equipment.ENCOUNTER_DROP_CHANCE:
				drop = Equipment.random_of(GameDB.equipment.values(), EquipData.Quality.FAN, screen.model.rng)
			var extra := Rewards.grant(bonus.get("tokens", 0), bonus.get("silver", 0), bonus.get("experience", 0), drop, bonus.get("medicine", &""))
			if extra != "":
				parts.append(extra)
			# 秘籍：乙甲等悬赏、擂台指定关给；普通遇敌偶尔掉一本凡品
			var mj: MijiData = null
			if bonus.has("miji_quality"):
				mj = Miji.random_of(GameDB.mijis.values(), bonus["miji_quality"], screen.model.rng)
			elif bonus.is_empty() and screen.model.rng.randf() < Miji.ENCOUNTER_DROP_CHANCE:
				mj = Miji.random_of(GameDB.mijis.values(), MijiData.Quality.FAN, screen.model.rng)
			var scroll_text := Rewards.grant_scroll(mj)
			if scroll_text != "":
				parts.append(scroll_text)
			GameState.set_flag(bonus.get("flag", ""))
			if bonus.has("arena_round"):
				GameState.record["arena"] = maxi(Arena.best(), bonus["arena_round"])
			var mingqi := GameState.claim_mingqi()
			if mingqi != "":
				parts.append(mingqi)
			var job_text := OddJobs.on_battle_won(stage)
			if job_text != "":
				parts.append(job_text)
			if ups > 0:
				parts.append("升到 %d 级！" % GameState.level)
			if bond_text != "":
				parts.append(bond_text)
			var hurt := _wounded_text()
			if hurt != "" and not arena:
				parts.append(hurt)
			notice = "　".join(parts)
			GameState.save_game()
		elif not won:
			notice = "败下阵来，全队都受了重伤。先歇歇脚、吃点药再走。"
			GameState.save_game()
		if won and destination != &"":
			_show_map(destination, progress, notice)
		else:
			leave.call(notice))
	_set_screen(screen)


func _set_screen(screen: Control) -> void:
	_play_music_for(screen)
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

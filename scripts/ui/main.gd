extends Control
## 游戏入口：在开始界面、创建角色、江湖大地图、地点场景、编队、战斗之间切换画面。

var _screen: Control


func _ready() -> void:
	theme = UiKit.make_theme()
	_show_title()


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


func _show_map(resume_destination: StringName = &"", resume_progress := 0.0, notice := "") -> void:
	var screen := WorldMapView.new()
	screen.notice = notice
	screen.map = GameDB.maps[GameState.DEFAULT_MAP]
	screen.resume_destination = resume_destination
	screen.resume_progress = resume_progress
	screen.battle_requested.connect(_start_battle)
	screen.team_requested.connect(_show_team_select)
	screen.scene_requested.connect(_show_scene)
	screen.recruit_requested.connect(_show_recruit)
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
	var screen := BattleView.new()
	screen.stage = stage
	screen.team = GameState.team()
	screen.hero_level = GameState.level
	screen.retry_requested.connect(_start_battle.bind(stage, destination, progress, bonus, return_scene))
	var leave := func(notice: String) -> void:
		if return_scene != "":
			_show_scene(return_scene, notice)
		else:
			_show_map(&"", 0.0, notice)
	screen.exit_requested.connect(leave.bind(""))
	screen.finished.connect(func(won: bool) -> void:
		var notice := ""
		if won:
			var r: Dictionary = Encounters.rewards(screen.model)
			var ups := GameState.add_rewards(r["exp"], r["silver"])
			var parts := PackedStringArray()
			if bonus.has("text"):
				parts.append(String(bonus["text"]).replace("{name}", GameState.player_name))
			var extra := Rewards.grant(bonus.get("tokens", 0), bonus.get("silver", 0), bonus.get("experience", 0))
			if extra != "":
				parts.append(extra)
			GameState.set_flag(bonus.get("flag", ""))
			if ups > 0:
				parts.append("升到 %d 级！" % GameState.level)
			notice = "　".join(parts)
			GameState.save_game()
		if won and destination != &"":
			_show_map(destination, progress, notice)
		else:
			leave.call(notice))
	_set_screen(screen)


func _set_screen(screen: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

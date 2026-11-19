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


func _show_map(resume_destination: StringName = &"", resume_progress := 0.0) -> void:
	var screen := WorldMapView.new()
	screen.map = GameDB.maps[GameState.DEFAULT_MAP]
	screen.resume_destination = resume_destination
	screen.resume_progress = resume_progress
	screen.battle_requested.connect(_start_battle)
	screen.team_requested.connect(_show_team_select)
	screen.scene_requested.connect(_show_scene)
	_set_screen(screen)


func _show_scene(scene_id: String) -> void:
	var screen := LocationView.new()
	screen.scene_data = GameDB.scenes[scene_id]
	screen.exit_requested.connect(_show_map)
	_set_screen(screen)


func _show_team_select() -> void:
	var screen := TeamSelect.new()
	screen.start_requested.connect(func(heroes: Array[UnitData]) -> void:
		GameState.set_heroes(heroes)
		GameState.save_game()
		_show_map())
	_set_screen(screen)


## destination 非空表示这是赶路时的遭遇战：赢了接着走完，输了或撤退就留在原地。
func _start_battle(stage: StageData, destination: StringName, progress: float) -> void:
	var screen := BattleView.new()
	screen.stage = stage
	screen.team = GameState.team()
	screen.hero_level = stage.recommended_level
	screen.retry_requested.connect(_start_battle.bind(stage, destination, progress))
	screen.exit_requested.connect(_show_map)
	screen.finished.connect(func(won: bool) -> void:
		if won and destination == &"":
			GameState.set_flag("clear_" + stage.id)
			GameState.save_game()
		if won and destination != &"":
			_show_map(destination, progress)
		else:
			_show_map())
	_set_screen(screen)


func _set_screen(screen: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

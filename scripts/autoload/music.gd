extends Node
## 背景音乐（自动加载为 Music）：play(曲名) 换曲时两首交叉淡入淡出，同一首在放就不打断。
## 曲子在 audio/music/<曲名>.ogg，由 tools/music/compose.py 生成；开关存在 user://settings.cfg。

const SETTINGS_PATH := "user://settings.cfg"
const FADE := 1.2
const VOLUME_DB := -6.0
const SILENT_DB := -60.0

var enabled := true:
	set(value):
		enabled = value
		_save_settings()
		if enabled:
			var track := _current
			_current = &""
			play(track)
		else:
			_fade_out(_players[_active])

var _players: Array[AudioStreamPlayer] = []
## 每个播放器正在跑的淡入淡出；复用播放器前要先停掉，不然上一次「淡出后停止」会把新曲子停了
var _fades: Array[Tween] = [null, null]
var _active := 0
var _current: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		enabled = cfg.get_value("audio", "music", true)


func play(track: StringName) -> void:
	if track == &"" or track == _current:
		return
	_current = track
	if not enabled:
		return
	var path := "res://audio/music/%s.ogg" % track
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var old := _players[_active]
	_active = 1 - _active
	var new := _players[_active]
	_kill_fade(_active)
	new.stream = stream
	new.volume_db = SILENT_DB
	new.play()
	_fades[_active] = create_tween()
	_fades[_active].tween_property(new, "volume_db", VOLUME_DB, FADE)
	_fade_out(old)


func _exit_tree() -> void:
	# 退出时放开曲子，免得引擎报「资源没释放」
	for i in _players.size():
		_kill_fade(i)
		_players[i].stop()
		_players[i].stream = null


func current() -> StringName:
	return _current


func _fade_out(p: AudioStreamPlayer) -> void:
	if not p.playing:
		return
	var i := _players.find(p)
	_kill_fade(i)
	_fades[i] = create_tween()
	_fades[i].tween_property(p, "volume_db", SILENT_DB, FADE)
	_fades[i].tween_callback(p.stop)


func _kill_fade(i: int) -> void:
	if _fades[i] != null and _fades[i].is_valid():
		_fades[i].kill()
	_fades[i] = null


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music", enabled)
	cfg.save(SETTINGS_PATH)

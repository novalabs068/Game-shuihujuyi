extends Node
## 背景音乐（自动加载为 Music）：play(曲名) 换曲时两首交叉淡入淡出，同一首在放就不打断。
## 曲子在 audio/music/<曲名>.ogg（tools/music/compose.py 合成）；一个曲名下有 <曲名>_1、_2……几首的
## （战斗配乐，真录音，作者见设置页的鸣谢），每次切到这个曲名时随机挑一首。开关和音量存在设置里（Prefs）。

const FADE := 1.2
const VOLUME_DB := -6.0
const SILENT_DB := -60.0

var enabled := true:
	set(value):
		enabled = value
		Prefs.set_value("audio", "music", enabled)
		if enabled:
			var track := _current
			_current = &""
			play(track)
		else:
			_fade_out(_players[_active])

## 音量（0～1），在 VOLUME_DB 的基础上调
var volume := 0.8:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		Prefs.set_value("audio", "volume", volume)
		if enabled and _players.size() == 2 and _players[_active].playing:
			_kill_fade(_active)
			_players[_active].volume_db = _target_db()

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
	enabled = Prefs.get_value("audio", "music", true)
	volume = Prefs.get_value("audio", "volume", 0.8)


## 曲名对应的文件：有 <曲名>_1、_2……的随机挑一首，否则就是 <曲名>.ogg；都没有返回空。
func _pick(track: StringName) -> String:
	var variants: Array[String] = []
	for i in range(1, 10):
		var path := "res://audio/music/%s_%d.ogg" % [track, i]
		if not ResourceLoader.exists(path):
			break
		variants.append(path)
	if not variants.is_empty():
		return variants.pick_random()
	var single := "res://audio/music/%s.ogg" % track
	return single if ResourceLoader.exists(single) else ""


func play(track: StringName) -> void:
	if track == &"" or track == _current:
		return
	_current = track
	if not enabled:
		return
	var path := _pick(track)
	if path == "":
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
	_fades[_active].tween_property(new, "volume_db", _target_db(), FADE)
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


func _target_db() -> float:
	return VOLUME_DB + linear_to_db(maxf(volume, 0.001)) if volume > 0.0 else SILENT_DB

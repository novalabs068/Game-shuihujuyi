extends Node
## 音效（自动加载为 Sfx）：play(名字) 放 audio/sfx/<名字>.ogg，几个声音可以同时响。
## 音效由 tools/music/real_sfx.py 用真实录音（Kenney、Freesound，都是 CC0）叠出来；开关和音量存在设置里（Prefs），和背景音乐分开。

const POOL := 8
const BASE_DB := -4.0

var enabled := true:
	set(value):
		enabled = value
		Prefs.set_value("audio", "sfx", enabled)
## 音量（0～1）
var volume := 0.8:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		Prefs.set_value("audio", "sfx_volume", volume)

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary[StringName, AudioStream] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	enabled = Prefs.get_value("audio", "sfx", true)
	volume = Prefs.get_value("audio", "sfx_volume", 0.8)


## 放一个音效；pitch_jitter 让连续的同一个声音（刀光、翻牌）每次略有不同；pitch 整体升降调（招募时一声比一声高，像上升的音阶）。
func play(name: StringName, volume_db := 0.0, pitch_jitter := 0.0, pitch := 1.0) -> void:
	if not enabled or volume <= 0.0:
		return
	var stream := _stream(name)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = stream
	p.volume_db = BASE_DB + volume_db + linear_to_db(volume)
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.play()


func _stream(name: StringName) -> AudioStream:
	if not _cache.has(name):
		var path := "res://audio/sfx/%s.ogg" % name
		_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[name]


func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null
	_cache.clear()

class_name Prefs
## 玩家设置的读写（user://settings.cfg）：音乐开关和音量、战斗默认 2 倍速。和存档分开，重开不清。

const PATH := "user://settings.cfg"


static func get_value(section: String, key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return default
	return cfg.get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(section, key, value)
	cfg.save(PATH)

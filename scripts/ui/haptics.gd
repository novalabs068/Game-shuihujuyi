class_name Haptics
## 手机震动：轻、中、强三档（招募时三玉轻震、四玉中震、五玉强震）。设置里能关（Prefs 的 general/vibrate，默认开）。
## 电脑上 Input.vibrate_handheld 什么都不做。安卓要在导出设置里开 VIBRATE 权限（export_presets.cfg 的 permissions/vibrate）。

enum Level { LIGHT, MEDIUM, STRONG }
## 每档震多少毫秒、多大力度（0～1，安卓 8.0 以上才分力度）
const DURATION_MS: Array[int] = [25, 60, 160]
const AMPLITUDE: Array[float] = [0.3, 0.6, 1.0]


static func enabled() -> bool:
	return Prefs.get_value("general", "vibrate", true)


static func set_enabled(on: bool) -> void:
	Prefs.set_value("general", "vibrate", on)


static func pulse(level: Level) -> void:
	if not enabled():
		return
	Input.vibrate_handheld(DURATION_MS[level], AMPLITUDE[level])

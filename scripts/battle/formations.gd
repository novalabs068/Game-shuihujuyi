class_name Formations
## 阵法：一张格子图。规定我方 4 人站哪 4 格，每格（阵位）有名字和加成；格子还写了宜站什么职业，
## 放对了这一格的数值加成再多一半。每个阵有一格是阵眼：阵眼上没人就摆不成阵，阵眼上的人倒下就破阵，
## 全部阵法加成消失。纯规则，不碰画面。

## 阵位上宜站的职业站对了，数值加成 ×这么多
const SUITED_BONUS := 1.5
## 不限职业的阵位
const ANY := -1

## id → {name, desc, cond（解锁条件：剧情标记；"arena:N" 是擂台打到第 N 关；空 = 一开始就有）, unlock（解锁说明）,
##        eye（阵眼是第几个阵位）, cells: [[格子 Vector2i(排, 路), 阵位名, 加成, 宜站职业], ...]}
## 加成的键：atk 攻击、def 防御和法抗、spd 速度、taken 受到的伤害、heal 治疗量、control 控制多几回合、
## tail 击首尾应（蛇头挨打时蛇尾追击，数值是伤害倍数）、horn 月角夹击（敌人近战打中路时两角各反击一下，数值是伤害倍数）
const ALL := {
	&"yu_lin": {
		"name": "鱼鳞阵", "desc": "三前一后，守：三路都有人挡，鱼头减伤、两鳞加防、鱼尾多治疗。怕刺客和穿透",
		"cond": "", "unlock": "", "eye": 1,
		"cells": [
			[Vector2i(0, 0), "鳞", {"def": 0.15}, ANY],
			[Vector2i(0, 1), "鱼头", {"taken": -0.2}, UnitData.Role.WARRIOR],
			[Vector2i(0, 2), "鳞", {"def": 0.15}, ANY],
			[Vector2i(1, 1), "鱼尾", {"heal": 0.2}, UnitData.Role.HEALER],
		],
	},
	&"chang_she": {
		"name": "长蛇阵", "desc": "斜贯一线，攻：蛇头攻击 +25%、多挨打 15%；蛇头挨打时蛇尾追击一次",
		"cond": "story_lin_chong_4", "unlock": "林冲列传完结", "eye": 0,
		"cells": [
			[Vector2i(0, 0), "蛇头", {"atk": 0.25, "taken": 0.15}, UnitData.Role.WARRIOR],
			[Vector2i(0, 1), "蛇身", {"taken": -0.1}, ANY],
			[Vector2i(1, 1), "蛇身", {"taken": -0.1}, ANY],
			[Vector2i(1, 2), "蛇尾", {"tail": 0.6}, UnitData.Role.ARCHER],
		],
	},
	&"ba_gua": {
		"name": "八卦阵", "desc": "一前三后，控：开战敌方全体攻击 -20%（3 回合），太极上的人控制多 1 回合",
		"cond": "sworn_wu_yong", "unlock": "和吴用结义", "eye": 2,
		"cells": [
			[Vector2i(0, 1), "乾", {"def": 0.15}, UnitData.Role.WARRIOR],
			[Vector2i(1, 0), "坎", {"atk": 0.1}, ANY],
			[Vector2i(1, 1), "太极", {"control": 1}, UnitData.Role.TAOIST],
			[Vector2i(1, 2), "离", {"heal": 0.15}, UnitData.Role.HEALER],
		],
	},
	&"yan_yue": {
		"name": "偃月阵", "desc": "两角前出，护主：月心受到伤害 -25%，两角攻击 +15%；敌人近战打中路时两角夹击",
		"cond": "arena:6", "unlock": "擂台打过第 6 关", "eye": 2,
		"cells": [
			[Vector2i(0, 0), "月角", {"atk": 0.15, "horn": 0.5}, UnitData.Role.WARRIOR],
			[Vector2i(0, 2), "月角", {"atk": 0.15, "horn": 0.5}, UnitData.Role.WARRIOR],
			[Vector2i(1, 1), "月心", {"taken": -0.25}, ANY],
			[Vector2i(1, 2), "月背", {"def": 0.15}, ANY],
		],
	},
	&"hun_tian": {
		"name": "混天阵", "desc": "虚中两翼，快：阵上的人速度 +10%，开战全队怒气 +20；敌方中路的近战第一回合攻击 -30%",
		"cond": "arena:10", "unlock": "擂台打过第 10 关", "eye": 1,
		"cells": [
			[Vector2i(0, 0), "左翼", {"spd": 0.1}, UnitData.Role.ASSASSIN],
			[Vector2i(0, 2), "右翼", {"spd": 0.1}, UnitData.Role.WARRIOR],
			[Vector2i(1, 0), "左翼", {"spd": 0.1}, ANY],
			[Vector2i(1, 2), "右翼", {"spd": 0.1}, ANY],
		],
	},
}
const DEFAULT := &"yu_lin"
## 八卦阵：开战敌方全体减攻
const BA_GUA_WEAKEN := 0.2
const BA_GUA_TURNS := 3
## 混天阵：开战全队怒气，敌方中路近战减攻
const HUN_TIAN_RAGE := 20
const HUN_TIAN_WEAKEN := 0.3


static func display_name(id: StringName) -> String:
	return ALL[id]["name"] if ALL.has(id) else ""


static func description(id: StringName) -> String:
	return ALL[id]["desc"] if ALL.has(id) else ""


static func unlock_text(id: StringName) -> String:
	return ALL[id]["unlock"]


static func unlock_condition(id: StringName) -> String:
	return ALL[id]["cond"]


## 阵位的格子（按顺序）。没有这个阵返回空。
static func cells(id: StringName) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if ALL.has(id):
		for c: Array in ALL[id]["cells"]:
			out.append(c[0])
	return out


static func eye_cell(id: StringName) -> Vector2i:
	return ALL[id]["cells"][ALL[id]["eye"]][0]


## 这一格在阵里叫什么（不是阵位返回空）。
static func slot_name(id: StringName, cell: Vector2i) -> String:
	if ALL.has(id):
		for c: Array in ALL[id]["cells"]:
			if c[0] == cell:
				return c[1]
	return ""


## 阵位宜站的职业（ANY 不限；不是阵位也返回 ANY）。
static func suited_role(id: StringName, cell: Vector2i) -> int:
	if ALL.has(id):
		for c: Array in ALL[id]["cells"]:
			if c[0] == cell:
				return c[3]
	return ANY


## 「鱼头：受到伤害 -20%（宜战士）」
static func slot_text(id: StringName, cell: Vector2i) -> String:
	if not ALL.has(id):
		return ""
	for c: Array in ALL[id]["cells"]:
		if c[0] == cell:
			var parts := PackedStringArray()
			for k: String in c[2]:
				parts.append(_mod_text(k, c[2][k]))
			var tail := "（宜%s）" % UnitData.ROLE_NAMES[c[3]] if c[3] != ANY else ""
			var eye := "阵眼 · " if c == ALL[id]["cells"][ALL[id]["eye"]] else ""
			return "%s%s：%s%s" % [eye, c[1], "，".join(parts), tail]
	return ""


static func _mod_text(k: String, v: Variant) -> String:
	match k:
		"atk": return "攻击 +%d%%" % roundi(v * 100)
		"def": return "防御、法抗 +%d%%" % roundi(v * 100)
		"spd": return "速度 +%d%%" % roundi(v * 100)
		"taken": return "受到伤害 %s%d%%" % ["+" if v > 0 else "-", roundi(absf(v) * 100)]
		"heal": return "治疗量 +%d%%" % roundi(v * 100)
		"control": return "控制多 %d 回合" % v
		"tail": return "蛇头挨打时追击（%d%%）" % roundi(v * 100)
		"horn": return "夹击中路来犯的近战（%d%%）" % roundi(v * 100)
	return ""


## 开战时按站位布阵：站在阵位上的人拿到这一格的加成（宜站的职业站对了数值 ×1.5），阵眼做标记。
## 阵眼上没人就摆不成阵。返回给准备回合看的一句话（没摆成返回空）。player_units 已经站好了格子。
static func apply(id: StringName, player_units: Array[BattleUnit], enemies: Array[BattleUnit]) -> String:
	if not ALL.has(id) or player_units.is_empty():
		return ""
	var by_cell := {}
	for u in player_units:
		by_cell[u.cell()] = u
	if not by_cell.has(eye_cell(id)):
		return ""
	var on := PackedStringArray()
	for c: Array in ALL[id]["cells"]:
		var u: BattleUnit = by_cell.get(c[0])
		if u == null:
			continue
		var k := SUITED_BONUS if c[3] != ANY and u.data.role == c[3] else 1.0
		for key: String in c[2]:
			var v: Variant = c[2][key]
			# 加的数值按宜站放大；多挨打（正的 taken）不放大
			u.formation_mods[key] = v if key == "control" or (key == "taken" and v > 0) else v * k
		on.append("%s·%s%s" % [c[1], u.display_name(), "（宜）" if k > 1.0 else ""])
	by_cell[eye_cell(id)].formation_eye = true
	match id:
		&"ba_gua":
			for e in enemies:
				e.add_buff(BattleUnit.Buff.new("八卦阵", -BA_GUA_WEAKEN, 0.0, BA_GUA_TURNS))
		&"hun_tian":
			for u in player_units:
				u.add_rage(HUN_TIAN_RAGE)
			for e in enemies:
				if e.lane == 1 and e.is_melee():
					e.add_buff(BattleUnit.Buff.new("混天阵", -HUN_TIAN_WEAKEN, 0.0, 1))
	return "「%s」%s" % [display_name(id), "　".join(on)]


## 破阵：阵眼倒下，全队的阵法加成清空。
static func break_formation(player_units: Array[BattleUnit]) -> void:
	for u in player_units:
		u.formation_mods.clear()
		u.formation_eye = false

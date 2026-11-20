class_name EquipData
extends Resource
## 一件装备（模板）。属性加成是百分比，到后期也不失效；没有强化和打造，拿到什么就是什么。

enum Slot { WEAPON, ARMOR, CHARM }
enum Quality { FAN, LIANG, JING }

const SLOT_NAMES: Array[String] = ["兵器", "护具", "饰物"]
const QUALITY_NAMES: Array[String] = ["凡品", "良品", "精品"]
## 卖给集市的价钱；凡品也能在集市按 BUY_PRICE 买到
const SELL_PRICES: Array[int] = [20, 60, 120]
const BUY_PRICE := 40
## 特效：名字和说明
const EFFECTS := {
	&"armor_break": ["破甲", "普攻打铁甲敌人不减半"],
	&"swift": ["疾风", "开战时速度 +20%，持续 2 回合"],
	&"regen": ["回春", "每次轮到自己回复 2% 生命"],
	&"nimble": ["机变", "技能冷却 -1 回合"],
	&"keen": ["会心", "暴击率 +15%"],
}

@export var id: StringName
@export var display_name: String
@export var slot: Slot
@export var quality: Quality
@export_multiline var flavor: String
@export var hp_pct := 0.0
@export var atk_pct := 0.0
@export var def_pct := 0.0
@export var spd_pct := 0.0
@export var effects: Array[StringName] = []


func sell_price() -> int:
	return SELL_PRICES[quality]


## 「攻击 +12%　破甲」这样的一行说明。
func summary() -> String:
	var parts := PackedStringArray()
	for pair in [["生命", hp_pct], ["攻击", atk_pct], ["防御", def_pct], ["速度", spd_pct]]:
		if pair[1] > 0.0:
			parts.append("%s +%d%%" % [pair[0], roundi(pair[1] * 100)])
	for e in effects:
		parts.append(EFFECTS[e][0])
	return "　".join(parts)


func effects_text() -> String:
	var lines := PackedStringArray()
	for e in effects:
		lines.append("%s：%s" % EFFECTS[e])
	return "\n".join(lines)

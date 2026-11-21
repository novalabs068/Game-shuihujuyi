class_name EquipData
extends Resource
## 一件装备（模板）。属性加成是百分比，到后期也不失效；没有强化和打造，拿到什么就是什么。

enum Slot { WEAPON, ARMOR, CHARM, MOUNT }
## 名器：出自原著、全游戏只有一件，不随机掉落、不能卖；装在原主人（owner）身上时绝招再强化一次
enum Quality { FAN, LIANG, JING, MING }

const SLOT_NAMES: Array[String] = ["兵器", "护具", "饰物", "坐骑"]
const QUALITY_NAMES: Array[String] = ["凡品", "良品", "精品", "名器"]
## 卖给集市的价钱；凡品也能在集市按 BUY_PRICE 买到（坐骑按 MOUNT_PRICE）
const SELL_PRICES: Array[int] = [20, 60, 120, 0]
const BUY_PRICE := 40
const MOUNT_PRICE := 200
## 特效：名字和说明
const EFFECTS := {
	&"armor_break": ["破甲", "普攻打铁甲敌人不减半"],
	&"swift": ["疾风", "开战时速度 +20%，持续 2 回合"],
	&"regen": ["回春", "每次轮到自己回复 2% 生命"],
	&"nimble": ["机变", "技能冷却 -1 回合"],
	&"keen": ["会心", "暴击率 +15%"],
	&"pursuit": ["追击", "普攻后 25% 再追一下，60% 伤害"],
	&"pursuit_axe": ["连斧", "普攻后 35% 再砍一斧，90% 伤害"],
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

@export_group("坐骑")
## 主角骑着它在江湖大地图上赶路快多少（0.3 = 快 30%）、路上遇敌的概率少多少（0.2 = 少两成）
@export var travel_speed := 0.0
@export var encounter_cut := 0.0

@export_group("名器")
## 原主人（好汉 id）：装在他身上时绝招再强化一次
@export var owner: StringName
## 从哪里得到：一个标记（列传 story_…、悬赏 bounty_…、宝箱 chest_<场景>_<宝箱>），或 arena:<关数>
@export var source: String
## 给玩家看的出处，比如「林冲列传完结」
@export var source_text: String


func buy_price() -> int:
	return MOUNT_PRICE if slot == Slot.MOUNT else BUY_PRICE


func can_sell() -> bool:
	return quality != Quality.MING


## 名马也算名器，只是叫法不同。
func quality_name() -> String:
	return "名马" if quality == Quality.MING and slot == Slot.MOUNT else QUALITY_NAMES[quality]


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
	if travel_speed > 0.0:
		parts.append("赶路 +%d%%" % roundi(travel_speed * 100))
	if encounter_cut > 0.0:
		parts.append("遇敌 -%d%%" % roundi(encounter_cut * 100))
	return "　".join(parts)


func effects_text() -> String:
	var lines := PackedStringArray()
	for e in effects:
		lines.append("%s：%s" % EFFECTS[e])
	return "\n".join(lines)

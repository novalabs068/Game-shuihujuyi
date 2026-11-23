class_name Vitality
## 气血：战斗里剩多少血会带到下一仗（按百分比记）。纯规则，存档里的数据在 GameState.vitality。
## 倒下的人「重伤」，下一仗只剩一成血；打输了全队一成血；赶路每段回一点；药按固定点数回血；
## 客栈按伤势收钱回满；野外歇脚要打坐真实的 5 分钟（关掉游戏也算），一小时只能歇一次。

## 重伤、战败后剩的血
const WOUNDED := 0.1
## 赶路每走完一段路回多少；队里有「神医」天赋的人时翻倍
const ROAD_REGEN := 0.1
const ROAD_REGEN_HEALER := 0.2
## 野外歇脚：打坐多少秒（真实时间）、歇完回多少、隔多少秒才能再歇（从上次歇完算）。被打退的小怪也会回来
const CAMP_SECONDS := 300
const CAMP_REGEN := 0.5
const CAMP_COOLDOWN := 3600
## 客栈：按伤势收钱，每人每少一整条血收「队伍等级 × INN_PER_LEVEL」两；最少 INN_MIN
const INN_PER_LEVEL := 5
const INN_MIN := 20
## 药：id → [名字, 说明, 回多少点气血, 全队？, 集市价钱]。回的是固定点数，不是比例：
## 前期一份金疮药能回大半条血，到后期血条长了就得换高档的药。价钱不随等级变。
const MEDICINES := {
	&"zhi_xue_cao": ["止血草", "嚼碎了敷上，止住血。", 300, false, 15],
	&"jin_chuang_yao": ["金疮药", "江湖上最常见的刀伤药。", 800, false, 40],
	&"hui_chun_san": ["回春散", "冲水服下，大家分着喝。", 600, true, 90],
	&"xu_ming_gao": ["续命膏", "吊命的膏药，重伤也能救回来。", 2000, false, 110],
	&"huan_hun_dan": ["九转还魂丹", "道观里炼的灵丹，一颗顶半条命。", 6000, false, 250],
}


## 打完一仗后我方每个人的剩余气血：活着的按血量比例，倒下的重伤；输了全队重伤。
static func after_battle(model: BattleModel) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	var lost := model.result == BattleModel.Result.LOSE
	for u in model.units:
		if u.side != BattleUnit.Side.PLAYER:
			continue
		out[u.data.id] = WOUNDED if lost or not u.is_alive() else maxf(u.hp_ratio(), WOUNDED)
	return out


## 开战时按记下的气血扣血（至少 1 点）；没记的就是满血。
static func apply_start(model: BattleModel, ratios: Dictionary) -> void:
	for u in model.units:
		if u.side == BattleUnit.Side.PLAYER and ratios.has(u.data.id):
			u.hp = clampi(roundi(u.max_hp * float(ratios[u.data.id])), 1, u.max_hp)


## 赶路一段：每人回一点。
static func road_regen(ratios: Dictionary, has_healer: bool) -> void:
	var k := ROAD_REGEN_HEALER if has_healer else ROAD_REGEN
	for id in ratios:
		ratios[id] = minf(float(ratios[id]) + k, 1.0)


static func is_wounded(ratio: float) -> bool:
	return ratio <= WOUNDED + 0.001


## 客栈住一晚的价钱：ratios 是每人剩的气血（没记的就是满血），按大家一共少了多少血算，取整到 5 两。
static func rest_price(level: int, ratios: Dictionary) -> int:
	var missing := 0.0
	for id in ratios:
		missing += 1.0 - float(ratios[id])
	var price := missing * level * INN_PER_LEVEL
	return maxi(INN_MIN, roundi(price / 5.0) * 5)


static func medicine_name(id: StringName) -> String:
	return MEDICINES[id][0]


static func medicine_heal(id: StringName) -> int:
	return MEDICINES[id][2]


static func medicine_for_team(id: StringName) -> bool:
	return MEDICINES[id][3]


static func medicine_price(id: StringName) -> int:
	return MEDICINES[id][4]


## 「一人回复 800 点气血」「全队每人回复 600 点气血」。
static func medicine_effect(id: StringName) -> String:
	return ("全队每人回复 %d 点气血" if medicine_for_team(id) else "一人回复 %d 点气血") % medicine_heal(id)

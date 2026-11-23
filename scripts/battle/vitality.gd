class_name Vitality
## 气血：战斗里剩多少血会带到下一仗（按百分比记）。纯规则，存档里的数据在 GameState.vitality。
## 倒下的人「重伤」，下一仗只剩一成血；打输了全队一成血；赶路每段回一点，金疮药之类的药也能回；
## 客栈按伤势收钱回满，野外歇脚吃一份干粮回一截。

## 重伤、战败后剩的血
const WOUNDED := 0.1
## 赶路每走完一段路回多少；队里有「神医」天赋的人时翻倍
const ROAD_REGEN := 0.1
const ROAD_REGEN_HEALER := 0.2
## 在野外随地歇一宿回多少：要吃一份干粮，被打退的小怪也会回来
const CAMP_REGEN := 0.3
## 干粮的价钱：底价 + 每级队伍等级加一点；开新档送几份
const RATION_BASE_PRICE := 10
const RATION_PRICE_PER_LEVEL := 2
const STARTING_RATIONS := 3
## 客栈：按伤势收钱，每人每少一整条血收「队伍等级 × INN_PER_LEVEL」两；最少 INN_MIN
const INN_PER_LEVEL := 5
const INN_MIN := 20
## 药价随队伍等级涨：每级多 LEVEL_PRICE_RATE 倍底价
const LEVEL_PRICE_RATE := 0.1

## 药：id → [名字, 说明, 回多少（比例）, 全队？, 集市价钱]
const MEDICINES := {
	&"jin_chuang_yao": ["金疮药", "敷在伤口上，一人回复 40% 气血。", 0.4, false, 30],
	&"hui_chun_san": ["回春散", "冲水服下，全队回复 25% 气血。", 0.25, true, 60],
	&"xu_ming_gao": ["续命膏", "吊命的膏药，一人气血回满，重伤也能救回来。", 1.0, false, 90],
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


static func ration_price(level: int) -> int:
	return RATION_BASE_PRICE + level * RATION_PRICE_PER_LEVEL


static func medicine_name(id: StringName) -> String:
	return MEDICINES[id][0]


static func medicine_heal(id: StringName) -> float:
	return MEDICINES[id][2]


static func medicine_for_team(id: StringName) -> bool:
	return MEDICINES[id][3]


## 药价：底价随队伍等级涨，取整到 5 两。
static func medicine_price(id: StringName, level := 1) -> int:
	var base: int = MEDICINES[id][4]
	return roundi(base * (1.0 + LEVEL_PRICE_RATE * (level - 1)) / 5.0) * 5

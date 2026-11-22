class_name Vitality
## 气血：战斗里剩多少血会带到下一仗（按百分比记）。纯规则，存档里的数据在 GameState.vitality。
## 倒下的人「重伤」，下一仗只剩一成血；打输了全队一成血；赶路每段回一点，歇脚回满，金疮药之类的药也能回。

## 重伤、战败后剩的血
const WOUNDED := 0.1
## 赶路每走完一段路回多少；队里有「神医」天赋的人时翻倍
const ROAD_REGEN := 0.1
const ROAD_REGEN_HEALER := 0.2
## 在野外随地歇一宿回多少（不花钱，但被打退的小怪会回来）
const CAMP_REGEN := 0.35
## 歇脚：每一级队伍等级要多少银两（最少 REST_MIN）
const REST_PER_LEVEL := 2
const REST_MIN := 10

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


static func rest_price(level: int) -> int:
	return maxi(REST_MIN, level * REST_PER_LEVEL)


static func medicine_name(id: StringName) -> String:
	return MEDICINES[id][0]


static func medicine_heal(id: StringName) -> float:
	return MEDICINES[id][2]


static func medicine_for_team(id: StringName) -> bool:
	return MEDICINES[id][3]


static func medicine_price(id: StringName) -> int:
	return MEDICINES[id][4]

class_name Encounters
## 生成赶路时的遭遇战，结算战斗奖励。纯规则，不碰画面。

## 一场遭遇战里出现一个精英的概率
const ELITE_CHANCE := 0.15
const ELITE_HP_BONUS := 0.3
const ELITE_TRAITS: Array[StringName] = [&"iron", &"berserk"]
const ELITE_PREFIX := {&"iron": "铁甲·", &"berserk": "狂暴·"}
const EXP_PER_LEVEL := 15
const SILVER_PER_LEVEL := 3


## 按地点的遭遇组合生成一场战斗：随机挑一个组合，敌人等级在地区区间内贴近队伍等级，偶尔把一个敌人换成精英。
static func build(loc: LocationData, party_level: int, rng: RandomNumberGenerator) -> StageData:
	return build_from(loc.encounter_groups, loc.level_min, loc.level_max, party_level, rng)


## 从 groups 里挑一个组合生成一场战斗。bonus 是额外加的等级（场景深处的小怪更强），
## 加上之后可以超出地区的等级上限。
static func build_from(groups: Array[StageData], level_min: int, level_max: int, party_level: int, rng: RandomNumberGenerator, bonus := 0) -> StageData:
	if groups.is_empty():
		return null
	var template: StageData = groups[rng.randi_range(0, groups.size() - 1)]
	var stage := StageData.new()
	stage.id = "encounter_%s" % template.id
	stage.title = template.title
	stage.star_round_limit = template.star_round_limit
	stage.enemy_level = clampi(clampi(party_level, level_min, level_max) + rng.randi_range(0, 1), level_min, level_max) + bonus
	stage.recommended_level = stage.enemy_level
	var enemies: Array[UnitData] = template.enemies.duplicate()
	if rng.randf() < ELITE_CHANCE:
		var i := rng.randi_range(0, enemies.size() - 1)
		enemies[i] = make_elite(enemies[i], ELITE_TRAITS[rng.randi_range(0, ELITE_TRAITS.size() - 1)])
	stage.enemies = enemies
	return stage


static func make_elite(base: UnitData, elite_trait: StringName) -> UnitData:
	var elite := base.duplicate()
	elite.elite_trait = elite_trait
	elite.display_name = String(ELITE_PREFIX[elite_trait]) + base.display_name
	elite.base_hp = roundi(base.base_hp * (1.0 + ELITE_HP_BONUS))
	return elite


## 打赢后的经验和银两：按每个敌人的等级算，精英加倍。
static func rewards(model: BattleModel) -> Dictionary:
	var gained_exp := 0
	var gained_silver := 0
	if model.result != BattleModel.Result.WIN:
		return {"exp": 0, "silver": 0}
	for u in model.units:
		if u.side != BattleUnit.Side.ENEMY:
			continue
		var mult := 2 if u.data.elite_trait != &"" else 1
		gained_exp += u.level * EXP_PER_LEVEL * mult
		gained_silver += u.level * SILVER_PER_LEVEL * mult
	return {"exp": gained_exp, "silver": gained_silver}

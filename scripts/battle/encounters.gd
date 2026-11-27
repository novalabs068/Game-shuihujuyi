class_name Encounters
## 生成赶路时的遭遇战，结算战斗奖励。纯规则，不碰画面。

## 一场遭遇战里出现一个精英的概率：一星地区 15%，危险度每高一颗星多 10%
const ELITE_CHANCE := 0.15
const ELITE_CHANCE_PER_DANGER := 0.1
## 危险度每高一颗星，敌人生命、攻击多 15%（后期地区的小怪不再是换了等级的泼皮）
const POWER_PER_DANGER := 0.2
## 危险度达到这么高的地区，敌人等级不封顶：至少是队伍等级 - LEVEL_FOLLOW_GAP
const LEVEL_FOLLOW_DANGER := 3
const LEVEL_FOLLOW_GAP := 6
## 头目跟着队伍的养成变强：队伍因养成（勾玉、羁绊、装备）变强了多少倍，头目就跟上这么多比例
const BOSS_GROWTH_SHARE := 1.3
const ELITE_HP_BONUS := 0.3
const ELITE_TRAITS: Array[StringName] = [&"iron", &"berserk"]
const ELITE_PREFIX := {&"iron": "铁甲·", &"berserk": "狂暴·"}
## 每个敌人给的经验、银两 = 它的等级 × 这个数（精英加倍）
const EXP_PER_LEVEL := 5
const SILVER_PER_LEVEL := 0.8


## 按地点的遭遇组合生成一场战斗：随机挑一个组合，敌人等级在地区区间内贴近队伍等级，偶尔把一个敌人换成精英。
static func build(loc: LocationData, party_level: int, rng: RandomNumberGenerator) -> StageData:
	return build_from(loc.encounter_groups, loc.level_min, loc.level_max, party_level, rng, 0, loc.danger)


## 从 groups 里挑一个组合生成一场战斗。bonus 是额外加的等级（场景深处的小怪更强），
## 加上之后可以超出地区的等级上限。danger 是地区危险度（1～4），决定敌人强度、精英概率和等级是否跟着队伍走。
static func build_from(groups: Array[StageData], level_min: int, level_max: int, party_level: int, rng: RandomNumberGenerator, bonus := 0, danger := 1) -> StageData:
	if groups.is_empty():
		return null
	var template: StageData = groups[rng.randi_range(0, groups.size() - 1)]
	var stage := StageData.new()
	stage.id = "encounter_%s" % template.id
	stage.title = template.title
	stage.star_round_limit = template.star_round_limit
	stage.enemy_level = clampi(clampi(party_level, level_min, level_max) + rng.randi_range(0, 1), level_min, level_max)
	if danger >= LEVEL_FOLLOW_DANGER:
		stage.enemy_level = maxi(stage.enemy_level, party_level - LEVEL_FOLLOW_GAP + rng.randi_range(0, 1))
	stage.enemy_level += bonus
	stage.recommended_level = stage.enemy_level
	stage.enemy_power = power_of(danger)
	var enemies: Array[UnitData] = template.enemies.duplicate()
	if rng.randf() < elite_chance(danger):
		var i := rng.randi_range(0, enemies.size() - 1)
		enemies[i] = make_elite(enemies[i], ELITE_TRAITS[rng.randi_range(0, ELITE_TRAITS.size() - 1)])
	stage.enemies = enemies
	return stage


## 头目的强度倍数。raw 是队伍不带养成的样子，effective 是带上勾玉、羁绊、装备之后的样子（同一顺序）。
## 养成的强度按每人「生命 × 攻击 × 防御」的立方根算，取全队平均。
static func boss_power(raw: Array[UnitData], effective: Array[UnitData]) -> float:
	if raw.is_empty():
		return 1.0
	var total := 0.0
	for i in raw.size():
		var a := raw[i]
		var b := effective[i]
		total += pow(float(b.base_hp * b.base_atk * b.base_def) / (a.base_hp * a.base_atk * a.base_def), 1.0 / 3.0)
	var growth := total / raw.size()
	return 1.0 + BOSS_GROWTH_SHARE * maxf(growth - 1.0, 0.0)


static func power_of(danger: int) -> float:
	return 1.0 + POWER_PER_DANGER * (maxi(danger, 1) - 1)


static func elite_chance(danger: int) -> float:
	return ELITE_CHANCE + ELITE_CHANCE_PER_DANGER * (maxi(danger, 1) - 1)


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
		if u.side != BattleUnit.Side.ENEMY or u.reinforcement or u.is_summon():
			continue
		var mult := 2 if u.data.elite_trait != &"" else 1
		gained_exp += u.level * EXP_PER_LEVEL * mult
		gained_silver += roundi(u.level * SILVER_PER_LEVEL) * mult
	return {"exp": gained_exp, "silver": gained_silver}

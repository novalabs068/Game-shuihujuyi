class_name Gacha
## 抽卡规则（见设计文档「好汉卡牌与招募」）。纯规则，状态从外面传进来，方便测试。

## 甲、乙、丙、丁的概率（百分比）
const RATES: Array[int] = [3, 12, 35, 50]
## 这么多抽内必出一个甲
const PITY_JIA := 50
## 重复抽到时给的将魂
const DUPLICATE_SOULS := 10
## 多抽一次抽几张（五连，参考三国志战略版）；五连保底一个乙或以上
const MULTI := 5


## 抽 count 次。pulls_since_jia 是距上次出甲已经抽了几次；返回 {"heroes": [...], "pulls_since_jia": 新值}。
## 五连（count >= MULTI）时保证至少一个乙或以上；guarantee_jia 时保证至少一个甲（新手第一次五连）。
static func pull(pool: Array[UnitData], count: int, pulls_since_jia: int, rng: RandomNumberGenerator, guarantee_jia := false) -> Dictionary:
	var tiers: Array[int] = []
	var since := pulls_since_jia
	for i in count:
		since += 1
		var tier := UnitData.Tier.JIA if since >= PITY_JIA else _roll_tier(rng)
		tiers.append(tier)
		if tier == UnitData.Tier.JIA:
			since = 0
	if count >= MULTI and tiers.min() > UnitData.Tier.YI:
		tiers[count - 1] = UnitData.Tier.YI
	if guarantee_jia and not UnitData.Tier.JIA in tiers:
		tiers[count - 1] = UnitData.Tier.JIA
		since = 0
	var heroes: Array[UnitData] = []
	for t in tiers:
		heroes.append(_pick(pool, t, rng))
	return {"heroes": heroes, "pulls_since_jia": since}


static func _roll_tier(rng: RandomNumberGenerator) -> UnitData.Tier:
	var r := rng.randi_range(1, 100)
	var acc := 0
	for i in RATES.size():
		acc += RATES[i]
		if r <= acc:
			return i as UnitData.Tier
	return UnitData.Tier.DING


## 从卡池里挑一个该品级的人；这个品级没人时，先往低一级找，再往高一级找。
static func _pick(pool: Array[UnitData], tier: int, rng: RandomNumberGenerator) -> UnitData:
	var order: Array[int] = [tier]
	for d in range(1, 4):
		order.append(tier + d)
		order.append(tier - d)
	for t in order:
		if t < 0 or t > UnitData.Tier.DING:
			continue
		var candidates := pool.filter(func(h: UnitData) -> bool: return h.tier == t)
		if not candidates.is_empty():
			return candidates[rng.randi_range(0, candidates.size() - 1)]
	return null

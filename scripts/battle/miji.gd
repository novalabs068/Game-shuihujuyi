class_name Miji
## 把秘籍的效果算进战斗数据，以及掉落规则。

## 遭遇战、宝箱掉秘籍的概率（宝箱掉良品，遭遇战掉凡品）
const CHEST_DROP_CHANCE := 0.25
const ENCOUNTER_DROP_CHANCE := 0.04


## 带上秘籍的战斗数据（返回复制，不改原数据）；属性、特效类的这里就算进去，其他的战斗里结算。
static func apply(unit: UnitData, m: MijiData) -> UnitData:
	if m == null:
		return unit
	var out: UnitData = unit.duplicate(true)
	out.miji_effect = m.effect
	Stars.apply_passive(out, m.effect, 1)
	return out


## 从 all 里随机挑一本指定品质的（绝品不随机掉）。
static func random_of(all: Array, quality: MijiData.Quality, rng: RandomNumberGenerator) -> MijiData:
	var pool := all.filter(func(m: MijiData) -> bool: return m.quality == quality)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]

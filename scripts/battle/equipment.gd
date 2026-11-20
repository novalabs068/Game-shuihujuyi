class_name Equipment
## 把装备加成算进战斗数据，以及掉落规则。

## 路上遇敌打赢后掉一件凡品的概率
const ENCOUNTER_DROP_CHANCE := 0.15
const SWIFT_BONUS := 0.2
const SWIFT_TURNS := 2
const REGEN_RATIO := 0.02
const KEEN_CRIT := 0.15


## 带上装备加成的战斗数据（返回复制，不改原数据）。
static func apply(unit: UnitData, gear: Array[EquipData]) -> UnitData:
	if gear.is_empty():
		return unit
	var out: UnitData = unit.duplicate(true)
	var hp := 1.0
	var atk := 1.0
	var def := 1.0
	var spd := 1.0
	var effects: Array[StringName] = []
	for g in gear:
		hp += g.hp_pct
		atk += g.atk_pct
		def += g.def_pct
		spd += g.spd_pct
		for e in g.effects:
			if not e in effects:
				effects.append(e)
	out.base_hp = roundi(unit.base_hp * hp)
	out.base_atk = roundi(unit.base_atk * atk)
	out.base_def = roundi(unit.base_def * def)
	out.base_spd = roundi(unit.base_spd * spd)
	out.gear_effects = effects
	return out


## 从 all（全部装备模板）里随机挑一件指定品质的。
static func random_of(all: Array, quality: EquipData.Quality, rng: RandomNumberGenerator) -> EquipData:
	var pool := all.filter(func(e: EquipData) -> bool: return e.quality == quality)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]

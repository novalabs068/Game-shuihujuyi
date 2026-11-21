class_name Stars
## 升星和义气的规则（见设计文档「养成与组合技」「重复卡和用不上的卡的去处」）。纯规则，数值是初稿。

## 界面上用勾玉表示：甲 5 颗、乙 4 颗、丙 3 颗、丁 2 颗，刚抽到时全是空心，每升一星点亮一颗。
## 内部星级从 1 起（1 = 一颗都没点亮），所以星级上限 = 勾玉数 + 1。
const MAX_STARS: Array[int] = [6, 5, 4, 3]
## 每点亮一颗勾玉，生命、攻击、防御 +10%；速度不加，免得打乱出手顺序
const STAT_BONUS := 0.10
## 到这个星级（点亮 2 颗勾玉）时主动技强化一次
const SKILL_UP_STAR := 3
const SKILL_UP_RATIO := 1.25
## 没招到的好汉攒够这么多将魂可以直接招募
const RECRUIT_SOULS := 30
## 1 个将魂化成多少义气；用义气换 1 个将魂的价格（按品级甲乙丙丁）
const YIQI_PER_SOUL := 1
const SOUL_PRICE: Array[int] = [5, 3, 2, 1]


static func max_stars(hero: UnitData) -> int:
	return MAX_STARS[hero.tier]


## 点亮了几颗勾玉。
static func lit(star: int) -> int:
	return star - 1


## 从 star 星升到下一星（再点亮一颗勾玉）要多少将魂：20、40、60、80、100。
static func cost(star: int) -> int:
	return 20 * star


## 天赋档次：一颗勾玉都没点亮时 0（未解锁），点亮了 1，全部点亮 2（强化）。
static func talent_rank(hero: UnitData, star: int) -> int:
	if hero.talent == null or lit(star) < 1:
		return 0
	return 2 if star >= max_stars(hero) else 1


## 带上星级和天赋加成的战斗数据：star 为 1 时原样返回，否则返回一份复制。
static func apply(hero: UnitData, star: int) -> UnitData:
	if star <= 1:
		return hero
	var out: UnitData = hero.duplicate(true)
	var k := 1.0 + STAT_BONUS * (star - 1)
	out.base_hp = roundi(hero.base_hp * k)
	out.base_atk = roundi(hero.base_atk * k)
	out.base_def = roundi(hero.base_def * k)
	if star >= SKILL_UP_STAR and hero.skill != null:
		out.skill = upgraded_skill(hero.skill)
	out.talent_rank = talent_rank(hero, star)
	if out.talent_rank > 0:
		_apply_talent(out)
	return out


## 改数据就能生效的天赋（属性、特效、绝招伤害）在这里算；战斗里才起作用的由 BattleModel 结算。
static func _apply_talent(out: UnitData) -> void:
	apply_passive(out, out.talent, out.talent_rank)


## 一条被动（天赋或秘籍）里改数据就能生效的部分：属性、特效、绝招伤害。out 要是复制出来的。
static func apply_passive(out: UnitData, t: TalentData, rank: int) -> void:
	var v := t.value(rank)
	match t.kind:
		&"stat":
			for stat in t.stats:
				var key := "base_" + String(stat)
				out.set(key, roundi(out.get(key) * (1.0 + v)))
		&"effect":
			if not t.effect in out.gear_effects:
				out.gear_effects.append(t.effect)
		&"skill_power":
			if out.skill != null:
				out.skill = out.skill.duplicate()
				out.skill.power *= 1.0 + v
	if rank >= 2 and t.kind in TalentData.FLAT_KINDS:
		out.base_atk = roundi(out.base_atk * (1.0 + TalentData.FLAT_ENHANCE_ATK))


## 3 星强化后的主动技：伤害类加倍率，控制和增益类多 1 回合，治疗加量，偷东西减冷却。
static func upgraded_skill(skill: SkillData) -> SkillData:
	var s: SkillData = skill.duplicate()
	match skill.effect:
		SkillData.Effect.TAUNT, SkillData.Effect.STUN, SkillData.Effect.STUN_ALL, SkillData.Effect.WEAKEN_ALL, SkillData.Effect.TEAM_ATK, SkillData.Effect.TEAM_HASTE:
			s.turns += 1
		SkillData.Effect.HEAL:
			s.amount *= SKILL_UP_RATIO
		SkillData.Effect.STEAL:
			s.cooldown = maxi(s.cooldown - 1, 1)
		_:
			s.power *= SKILL_UP_RATIO
	s.description = "%s（点亮 %d 颗勾玉强化：%s）" % [skill.description, lit(SKILL_UP_STAR), upgrade_text(skill)]
	return s


static func upgrade_text(skill: SkillData) -> String:
	match skill.effect:
		SkillData.Effect.TAUNT, SkillData.Effect.STUN, SkillData.Effect.STUN_ALL, SkillData.Effect.WEAKEN_ALL, SkillData.Effect.TEAM_ATK, SkillData.Effect.TEAM_HASTE:
			return "持续 +1 回合"
		SkillData.Effect.HEAL:
			return "回复量 ×1.25"
		SkillData.Effect.STEAL:
			return "冷却 -1 回合"
	return "伤害 ×1.25"


static func soul_price(hero: UnitData) -> int:
	return SOUL_PRICE[hero.tier]

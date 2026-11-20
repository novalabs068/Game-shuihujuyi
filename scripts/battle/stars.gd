class_name Stars
## 升星和义气的规则（见设计文档「养成与组合技」「重复卡和用不上的卡的去处」）。纯规则，数值是初稿。

## 甲、乙、丙、丁的星数上限
const MAX_STARS: Array[int] = [10, 8, 5, 3]
## 每升 1 星生命、攻击、防御 +5%；速度不加，免得打乱出手顺序
const STAT_BONUS := 0.05
## 到这个星数时主动技强化一次
const SKILL_UP_STAR := 3
const SKILL_UP_RATIO := 1.25
## 没招到的好汉攒够这么多将魂可以直接招募
const RECRUIT_SOULS := 30
## 1 个将魂化成多少义气；用义气换 1 个将魂的价格（按品级甲乙丙丁）
const YIQI_PER_SOUL := 1
const SOUL_PRICE: Array[int] = [5, 3, 2, 1]


static func max_stars(hero: UnitData) -> int:
	return MAX_STARS[hero.tier]


## 从 star 星升到下一星要多少将魂。
static func cost(star: int) -> int:
	return 10 * star


## 带上星级加成的战斗数据：star 为 1 时原样返回，否则返回一份复制。
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
	return out


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
	s.description = "%s（%d 星强化：%s）" % [skill.description, SKILL_UP_STAR, upgrade_text(skill)]
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

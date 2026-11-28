class_name Leveling
## 等级和经验的规则：统领和每位好汉各算各的，一套升级曲线。纯规则，状态在 GameState。

## 等级上限（统领和好汉一样；好汉可以比统领高）
const MAX_LEVEL := 99
## 好汉比统领每低 1 级，打仗多拿这么多经验（新招的好汉从 1 级练起，好追上来），最多 CATCH_UP_MAX 倍
const CATCH_UP_PER_LEVEL := 0.1
const CATCH_UP_MAX := 3.0


## 从 at_level 升到下一级需要的经验。
## 一场仗（三个同级敌人）给 15 × 等级 的经验：早期一两场升一级，60 级左右要三场，越往后越慢。
static func exp_to_next(at_level: int) -> int:
	return 20 + 15 * at_level + at_level * at_level / 2


## 从 at_level 级、已攒 at_exp 经验，再加 gained 经验以后是 [几级, 这一级攒了多少]。到顶以后经验清零。
static func gain_exp(at_level: int, at_exp: int, gained: int) -> Array[int]:
	var lv := at_level
	var xp := at_exp + gained
	while lv < MAX_LEVEL and xp >= exp_to_next(lv):
		xp -= exp_to_next(lv)
		lv += 1
	if lv >= MAX_LEVEL:
		xp = 0
	return [lv, xp]


## 好汉拿经验的倍数：比统领低几级就多拿几成，最多 CATCH_UP_MAX 倍；和统领同级或更高拿原样。
static func catch_up_mult(hero_level: int, lead_level: int) -> float:
	var gap := lead_level - hero_level
	if gap <= 0:
		return 1.0
	return minf(1.0 + CATCH_UP_PER_LEVEL * gap, CATCH_UP_MAX)

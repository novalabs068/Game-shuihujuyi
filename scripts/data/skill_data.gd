class_name SkillData
extends Resource
## 好汉或敌人的一个主动技能。具体效果由 BattleModel 按 effect 结算。

enum Effect {
	DAMAGE,      ## 单体伤害：power 倍
	EXECUTE,     ## 单体伤害：power 倍，目标血量低于 30% 时翻倍
	MULTI_HIT,   ## 对同一目标连击 hits 次，每次 power 倍
	SURE_CRIT,   ## 必中必暴击的单体伤害
	TAUNT,       ## 嘲讽全体敌人 turns 回合，自身减伤 amount
	TEAM_HASTE,  ## 全队速度 +amount、怒气 +rage_gain，持续 turns 回合
	STUN,        ## 单体眩晕 turns 回合
	STEAL,       ## 偷取目标 1 个增益，并立刻再行动一次
	HEAL,        ## 全队恢复 amount 比例的生命，并解除眩晕
	BACKSTAB,    ## 敌人用：无视嘲讽，打血量比例最低的好汉，power 倍
}

@export var display_name: String
@export_multiline var description: String
@export var effect: Effect
@export var power := 1.0
@export var hits := 1
@export var turns := 0
@export var amount := 0.0
@export var rage_gain := 0
@export var cooldown := 3


## 出手前是否需要玩家选一个敌人。
func needs_enemy_target() -> bool:
	return effect in [Effect.DAMAGE, Effect.EXECUTE, Effect.MULTI_HIT, Effect.SURE_CRIT, Effect.STUN, Effect.STEAL]

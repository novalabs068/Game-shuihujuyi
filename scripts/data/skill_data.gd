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
	GUARD_STRIKE, ## 单体 power 倍伤害，同时全队获得施放者 amount 比例生命的护盾
	PIERCE,      ## 单体 power 倍伤害，无视防御
	ALL_FOES,    ## 敌方全体各受 power 倍伤害
	CRIPPLE,     ## 单体 power 倍伤害，目标速度 -amount，持续 turns 回合
	WEAKEN_ALL,  ## 敌方全体攻击 -amount，持续 turns 回合
	TEAM_ATK,    ## 全队攻击 +amount，持续 turns 回合
	STUN_ALL,    ## 敌方全体眩晕 turns 回合
	ALL_FOES_SLOW,  ## 敌方全体各受 power 倍伤害，速度 -amount，持续 turns 回合
	ALL_FOES_RAGE,  ## 敌方全体各受 power 倍伤害；自己怒气越高越疼，满怒时 ×(1+amount)。不消耗怒气
	ALL_FOES_BURN,  ## 敌方全体各受 power 倍伤害，并灼烧 turns 回合：每次轮到时掉施放者攻击 amount 倍的血（无视防御）
	ALL_FOES_MULTI, ## 敌方全体连打 hits 轮，每轮各受 power 倍伤害
	DISARM,      ## 单体 power 倍伤害（0 就不打），并缴械 turns 回合：不能普攻
	SILENCE,     ## 单体 power 倍伤害（0 就不打），并计穷 turns 回合：不能放绝招和组合技
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
	return effect in [Effect.DAMAGE, Effect.EXECUTE, Effect.MULTI_HIT, Effect.SURE_CRIT, Effect.STUN, Effect.STEAL, Effect.GUARD_STRIKE, Effect.PIERCE, Effect.CRIPPLE, Effect.DISARM, Effect.SILENCE]

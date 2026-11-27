class_name TalentData
extends Resource
## 好汉的天赋：一条被动。点亮第 1 颗勾玉时解锁，勾玉全亮时再强化一次（数值 ×1.5）。
## kind 决定怎么起作用（见 KINDS）；text 里的 {x} 换成当前数值。

const ENHANCE := 1.5
## 没有数值可加的天赋（特效、首击必暴、全队回春），全亮时改为攻击 +10%
const FLAT_ENHANCE_ATK := 0.1
const FLAT_KINDS: Array[StringName] = [&"effect", &"first_crit", &"team_regen", &"open_silence"]
## 在准备回合生效、要亮出来的种类
const OPENING_KINDS: Array[StringName] = [&"rage_start", &"team_rage_start", &"team_atk", &"team_haste_open", &"team_regen", &"team_guard_open", &"open_silence", &"open_weaken"]


## 给玩家看的类型：追击、开局或被动。
func category() -> String:
	if kind == &"pursuit":
		return "追击"
	if kind in OPENING_KINDS:
		return "开局"
	return "被动"
## 数值是怒气点数（0～100），不是百分比
const RAGE_KINDS: Array[StringName] = [&"rage_start", &"team_rage_start"]
const KINDS := {
	&"stat": "stats 里列的几项属性各 +amount",
	&"effect": "装备特效 effect（EquipData.EFFECTS 的键）",
	&"skill_power": "绝招伤害 +amount",
	&"crit_haste": "每次暴击后速度 +amount，最多叠 CRIT_HASTE_STACKS 层",
	&"boss_slayer": "打头目伤害 +amount",
	&"tough": "受到的伤害 -amount",
	&"first_crit": "每场第一次出手必暴击",
	&"bloodlust": "生命低于一半时攻击 +amount",
	&"rage_start": "开战时自己怒气 +amount",
	&"team_atk": "全队攻击 +amount，整场有效",
	&"team_rage_start": "开战时全队怒气 +amount",
	&"team_haste_open": "开战时全队速度 +amount，持续 2 回合",
	&"team_regen": "全队每次轮到自己回复 2% 生命",
	&"low_hp_crit": "生命低于一半时暴击率 +amount",
	&"team_guard_open": "开战时全队受到的伤害 -amount，持续 2 回合",
	&"open_silence": "开战时让敌方攻击最高的一人计穷 2 回合",
	&"open_weaken": "开战时敌方全体攻击 -amount，持续 2 回合",
	&"cleanse_regen": "每次轮到自己回复 amount 比例的生命，并解除一种控制",
	&"anti_counter": "被克制时受到的伤害 -amount",
	&"formation_boost": "在场时全队的阵法加成（攻、防、速、减伤、治疗、反击）再 +amount",
	&"pursuit": "追击：普攻后有 chance 的机会追加一下，pursuit_kind 决定追加什么，amount 是伤害倍数（减速时是减速比例）",
}
const CRIT_HASTE_STACKS := 3

@export var display_name: String
@export var kind: StringName
@export var amount := 0.0
## kind 为 stat 时加哪几项：hp、atk、def、spd
@export var stats: Array[StringName] = []
## kind 为 effect 时的特效
@export var effect: StringName
@export var text: String
## kind 为 pursuit 时：触发几率，和追加什么（见 Pursuit.KINDS）
@export var chance := 0.0
@export var pursuit_kind: StringName


## rank：0 未解锁，1 解锁，2 强化。
func value(rank: int) -> float:
	return amount * (ENHANCE if rank >= 2 else 1.0)


func describe(rank: int) -> String:
	var v := value(maxi(rank, 1))
	var x := ("%d" % roundi(v)) if kind in RAGE_KINDS else ("%d%%" % roundi(v * 100))
	var out := text.replace("{x}", x)
	if rank >= 2 and kind in FLAT_KINDS:
		out += "；攻击 +%d%%" % roundi(FLAT_ENHANCE_ATK * 100)
	return out

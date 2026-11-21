class_name Pursuit
extends RefCounted
## 追击：普攻命中后按几率追加一下。来源有天赋、装备特效（以后还有秘籍）。
## 一次普攻最多触发一个追击：按来源顺序掷骰，第一个成功的生效。纯规则，不碰画面。

## 追加什么：hit 再打同一个目标、snipe 绕开嘲讽打血最少的敌人、slow 让目标减速、stun 眩晕、expose 露出破绽
const KINDS: Array[StringName] = [&"hit", &"snipe", &"slow", &"stun", &"expose"]
## 减速类追击持续的回合
const SLOW_TURNS := 2
## 装备特效 → [名字, 几率, 追加什么, 倍数]
const GEAR := {
	&"pursuit": ["追击", 0.25, &"hit", 0.6],
	&"pursuit_axe": ["连斧", 0.35, &"hit", 0.9],
}

var name: String
var chance: float
var kind: StringName
var power: float


func _init(p_name: String, p_chance: float, p_kind: StringName, p_power: float) -> void:
	name = p_name
	chance = p_chance
	kind = p_kind
	power = p_power


## 这个人身上的全部追击来源：天赋、秘籍在前，装备在后。
static func sources_for(unit: BattleUnit) -> Array[Pursuit]:
	var out: Array[Pursuit] = []
	for p in unit.passives():
		var t: TalentData = p[0]
		if t.kind == &"pursuit":
			out.append(Pursuit.new(t.display_name, t.chance, t.pursuit_kind, t.value(p[1])))
	for effect: StringName in GEAR:
		if unit.has_gear(effect):
			var g: Array = GEAR[effect]
			out.append(Pursuit.new(g[0], g[1], g[2], g[3]))
	return out

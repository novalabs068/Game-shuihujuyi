class_name BattleStats
extends RefCounted
## 一场仗的统计：每个人打了多少、挨了多少、治了多少……总数和按回合分开的数都记。纯数据，BattleModel 结算时往里记。

## 每个人总数的项目（键 → 显示名），顺序就是统计表的列
const TOTALS := {
	"dealt": "输出", "taken": "承伤", "healed": "治疗", "shielded": "护盾",
	"crits": "暴击", "pursuits": "追击", "kills": "击倒", "controls": "控制",
	"attacks": "普攻", "skills": "绝招", "combos": "组合技",
}
## 按回合记的项目
const PER_ROUND := {"dealt": "输出", "taken": "承伤", "healed": "治疗"}

var _rows: Dictionary = {}
var rounds := 1


func of(u: BattleUnit) -> Dictionary:
	if not _rows.has(u):
		var row := {}
		for key: String in TOTALS:
			row[key] = 0
		for key: String in PER_ROUND:
			row["round_" + key] = {}
		_rows[u] = row
	return _rows[u]


func total(u: BattleUnit, key: String) -> int:
	return of(u)[key]


## 第 r 回合这个人某一项是多少。
func at_round(u: BattleUnit, key: String, r: int) -> int:
	return of(u)["round_" + key].get(r, 0)


func add(u: BattleUnit, key: String, amount := 1, round := 0) -> void:
	if u == null or amount == 0:
		return
	var row := of(u)
	row[key] += amount
	if PER_ROUND.has(key) and round > 0:
		row["round_" + key][round] = row["round_" + key].get(round, 0) + amount
		rounds = maxi(rounds, round)


## 一下伤害：打人的记输出（暴击、追击另记次数），挨打的记承伤。
func damage(attacker: BattleUnit, target: BattleUnit, amount: int, round: int, crit := false, pursuit := false) -> void:
	add(attacker, "dealt", amount, round)
	add(target, "taken", amount, round)
	if crit:
		add(attacker, "crits")
	if pursuit:
		add(attacker, "pursuits")

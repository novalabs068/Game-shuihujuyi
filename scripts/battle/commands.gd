class_name Commands
## 号令：统领专属的第二招。开战前选好带哪一个，每场仗能用一次，不占出手（用完统领接着行动）。
## 随境界解锁（见 Renown）。效果在 BattleModel.use_command 里结算。纯规则，数值是初稿。

## 擂鼓：全队攻击 +ATK_BONUS、怒气 +RAGE，持续 TURNS 回合
const LEIGU := &"leigu"
const LEIGU_ATK := 0.15
const LEIGU_RAGE := 20
const LEIGU_TURNS := 2
## 列阵：全队获得自身生命 SHIELD 比例的护盾
const LIEZHEN := &"liezhen"
const LIEZHEN_SHIELD := 0.15
## 鸣金：全队回复 HEAL 比例的生命，并解除眩晕、缴械、计穷、灼烧
const MINGJIN := &"mingjin"
const MINGJIN_HEAL := 0.2

## 号令 id → [名字, 第几阶境界解锁]，按解锁顺序
const ALL := {
	LEIGU: ["擂鼓", 2],
	LIEZHEN: ["列阵", 3],
	MINGJIN: ["鸣金", 5],
}


static func display_name(id: StringName) -> String:
	return ALL[id][0] if ALL.has(id) else ""


static func unlock_realm(id: StringName) -> int:
	return ALL[id][1] if ALL.has(id) else 99


static func describe(id: StringName) -> String:
	match id:
		LEIGU:
			return "全队攻击 +%d%%，怒气 +%d，持续 %d 回合" % [roundi(LEIGU_ATK * 100), LEIGU_RAGE, LEIGU_TURNS]
		LIEZHEN:
			return "全队获得自身 %d%% 生命的护盾" % roundi(LIEZHEN_SHIELD * 100)
		MINGJIN:
			return "全队回复 %d%% 生命，解除眩晕、缴械、计穷和灼烧" % roundi(MINGJIN_HEAL * 100)
	return ""


## 这一阶境界已经解锁的号令（按解锁顺序）。
static func unlocked(realm: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in ALL:
		if realm >= unlock_realm(id):
			out.append(id)
	return out

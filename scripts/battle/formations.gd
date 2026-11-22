class_name Formations
## 阵法：一队选一个，开战时在准备回合生效。纯规则，不碰画面。

## id → [名字, 说明, 解锁条件（剧情标记；"arena:N" 是擂台打到第 N 关；空 = 一开始就有）, 解锁说明]
const ALL := {
	&"yu_lin": ["鱼鳞阵", "主将以外的两位防御 +20%", "", ""],
	&"chang_she": ["长蛇阵", "主将攻击 +25%、受到的伤害 +15%；另两位受到的伤害 -10%", "story_lin_chong_4", "林冲列传完结"],
	&"ba_gua": ["八卦阵", "敌方全体攻击 -20%，持续 3 回合", "sworn_wu_yong", "和吴用结义"],
	&"yan_yue": ["偃月阵", "主将受到的伤害 -25%；另两位攻击 +15%", "arena:6", "擂台打过第 6 关"],
	&"hun_tian": ["混天阵", "全队速度 +10%，开战怒气 +20", "arena:10", "擂台打过第 10 关"],
}
const DEFAULT := &"yu_lin"


static func display_name(id: StringName) -> String:
	return ALL[id][0] if ALL.has(id) else ""


static func description(id: StringName) -> String:
	return ALL[id][1] if ALL.has(id) else ""


static func unlock_text(id: StringName) -> String:
	return ALL[id][3]


static func unlock_condition(id: StringName) -> String:
	return ALL[id][2]


## 开战时按阵法改队伍。player_units 第一个是主将（编队时排第一的好汉）。返回给准备回合看的一句话（没有阵法返回空）。
static func apply(id: StringName, player_units: Array[BattleUnit], enemies: Array[BattleUnit]) -> String:
	if not ALL.has(id) or player_units.is_empty():
		return ""
	var lead := player_units[0]
	var heroes := player_units.slice(1)
	match id:
		&"yu_lin":
			for u in heroes:
				u.scale_def(1.2)
		&"chang_she":
			lead.add_buff(BattleUnit.Buff.new("长蛇阵", 0.25, 0.0, BattleModel.WHOLE_BATTLE))
			lead.taken_mult *= 1.15
			for u in heroes:
				u.taken_mult *= 0.9
		&"ba_gua":
			for e in enemies:
				e.add_buff(BattleUnit.Buff.new("八卦阵", -0.2, 0.0, 3))
		&"yan_yue":
			lead.taken_mult *= 0.75
			for u in heroes:
				u.add_buff(BattleUnit.Buff.new("偃月阵", 0.15, 0.0, BattleModel.WHOLE_BATTLE))
		&"hun_tian":
			for u in player_units:
				u.add_buff(BattleUnit.Buff.new("混天阵", 0.0, 0.1, BattleModel.WHOLE_BATTLE))
				u.add_rage(20)
	return "「%s」：%s" % [display_name(id), description(id)]

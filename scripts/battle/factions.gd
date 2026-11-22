class_name Factions
## 山头：出战的好汉里有两位（或三位）出自同一个山头时，全队得到一条加成。纯规则，不碰画面。

## 山头 → [名字, 好汉, 加成说明]
const ALL := {
	&"er_long_shan": ["二龙山", [&"lu_zhishen", &"yang_zhi", &"wu_song", &"cao_zheng", &"zhang_qing", &"sun_erniang", &"shi_en"], "全队生命 +8%"],
	&"liang_shan_yuan_lao": ["梁山元老", [&"lin_chong", &"du_qian", &"song_wan", &"zhu_gui"], "全队防御 +8%"],
	&"qi_xing": ["七星聚义", [&"wu_yong", &"bai_sheng"], "全队开战怒气 +20"],
	&"qing_feng_shan": ["清风山", [&"hua_rong", &"qin_ming"], "全队暴击率 +8%"],
	&"xiang_jiang": ["朝廷降将", [&"huyan_zhuo", &"ling_zhen"], "全队攻击 +8%"],
	&"jian_kang": ["建康府", [&"an_daoquan", &"wang_dingliu"], "全队每次轮到自己回复 2% 生命"],
}
const BONUS := 0.08
const RAGE := 20


## 这位好汉的山头（没有返回空）。
static func of(hero_id: StringName) -> StringName:
	for f: StringName in ALL:
		if hero_id in ALL[f][1]:
			return f
	return &""


## 至少两位好汉同出的山头，没有为空。
static func shared(hero_ids: Array[StringName]) -> StringName:
	var count := {}
	for id in hero_ids:
		var f := of(id)
		if f != &"":
			count[f] = int(count.get(f, 0)) + 1
	for f: StringName in count:
		if count[f] >= 2:
			return f
	return &""


static func display_name(f: StringName) -> String:
	return ALL[f][0] if ALL.has(f) else ""


static func bonus_text(f: StringName) -> String:
	return ALL[f][2] if ALL.has(f) else ""


## 开战时给全队加上山头加成，返回给准备回合看的一句话。
static func apply(f: StringName, player_units: Array[BattleUnit]) -> String:
	if not ALL.has(f):
		return ""
	for u in player_units:
		match f:
			&"er_long_shan":
				u.scale_hp(1.0 + BONUS)
			&"liang_shan_yuan_lao":
				u.scale_def(1.0 + BONUS)
			&"qi_xing":
				u.add_rage(RAGE)
			&"qing_feng_shan":
				u.crit_bonus += BONUS
			&"xiang_jiang":
				u.add_buff(BattleUnit.Buff.new(display_name(f), BONUS, 0.0, BattleModel.WHOLE_BATTLE))
			&"jian_kang":
				if not &"regen" in u.extra_effects:
					u.extra_effects.append(&"regen")
	var members := player_units.filter(func(u: BattleUnit) -> bool: return of(u.data.id) == f).map(func(u: BattleUnit) -> String: return u.display_name())
	return "%s同出%s：%s" % ["、".join(members), display_name(f), bonus_text(f)]

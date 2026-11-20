class_name Arena
## 擂台：10 关，一关比一关强。只能挑战打过的下一关；打过的关可以再打（只拿普通战斗的经验银两）。
## 每关第一次打赢有额外奖励；最高关数记在 GameState.record["arena"]。

## 每关：[敌人 id（data/enemies 下的文件名）, 敌人等级]
const ROUNDS := [
	[["po_pi", "po_pi"], 3],
	[["po_pi_tou", "po_pi"], 5],
	[["gao_fu_jia_ding", "gao_fu_jia_ding", "gao_fu_jia_ding"], 7],
	[["xun_jie_ya_yi", "xun_jie_ya_yi"], 9],
	[["lin_zhong_qiang_ren", "shan_zei_tou_mu"], 11],
	[["ma_zei", "ma_zei", "ma_zei"], 13],
	[["guan_bing_gong_shou", "qin_bing", "guan_bing_gong_shou"], 15],
	[["dao_mu_zei", "ye_lang", "ye_lang"], 17],
	[["shui_kou", "shan_zei_tou_mu", "shui_kou"], 19],
	[["lin_zhong_qiang_ren", "lei_tai_jiao_tou", "lin_zhong_qiang_ren"], 21],
]
## 从这一关起，上台的都是精英（铁甲、狂暴轮着来）：擂台上没有庸手
const ELITE_FROM := 3
## 第一次打赢的奖励：聚义令（按关），第 5 关给良品、第 10 关给精品
const FIRST_TOKENS := {3: 2, 6: 2, 9: 2, 10: 5}
const FIRST_SILVER_PER_ROUND := 30
const FIRST_EQUIP := {5: EquipData.Quality.LIANG, 10: EquipData.Quality.JING}


static func round_count() -> int:
	return ROUNDS.size()


static func best() -> int:
	return int(GameState.record.get("arena", 0))


## 第 n 关（从 1 数）的战斗。
static func stage(n: int) -> StageData:
	var spec: Array = ROUNDS[n - 1]
	var st := StageData.new()
	st.id = "arena_%d" % n
	st.title = "擂台第 %d 关" % n
	var ids: Array = spec[0]
	for i in ids.size():
		var e: UnitData = load("res://data/enemies/%s.tres" % ids[i])
		if n >= ELITE_FROM and not e.is_boss:
			e = Encounters.make_elite(e, Encounters.ELITE_TRAITS[(n + i) % Encounters.ELITE_TRAITS.size()])
		st.enemies.append(e)
	st.enemy_level = spec[1]
	st.recommended_level = spec[1]
	return st


## 交给 main 的额外奖励（第一次打赢才有），以及「打赢了记最高关数」。
static func battle_bonus(n: int) -> Dictionary:
	var bonus := {"arena_round": n, "text": "擂台第 %d 关胜！" % n}
	if n > best():
		bonus["silver"] = n * FIRST_SILVER_PER_ROUND
		bonus["tokens"] = FIRST_TOKENS.get(n, 0)
		if FIRST_EQUIP.has(n):
			bonus["equip_quality"] = FIRST_EQUIP[n]
		bonus["text"] = "擂台第 %d 关，首次打赢！" % n
	return bonus


static func first_reward_text(n: int) -> String:
	var parts := PackedStringArray(["银两 %d" % (n * FIRST_SILVER_PER_ROUND)])
	if FIRST_TOKENS.has(n):
		parts.append("聚义令 %d" % FIRST_TOKENS[n])
	if FIRST_EQUIP.has(n):
		parts.append("%s装备一件" % EquipData.QUALITY_NAMES[FIRST_EQUIP[n]])
	return "、".join(parts)

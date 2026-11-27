class_name Renown
## 统领的成长线：江湖名望 → 五阶境界（见方案页「统领之路」）。纯规则，不碰画面。
##
## 名望不单独记数，按存档里已经做过的事现算（招到几位好汉、打完几章列传、揭了几张悬赏……），
## 所以旧存档读进来自动就有名望。名望够了不会自动升阶，要打赢一场「立名之战」才升（境界存在 GameState.realm）。
## 每升一阶：统领属性 +10%、武学能多修两重，并解锁统领天赋、号令等。数值是初稿。

## 名望来源（每件事给多少）
const PER_HERO := 20
const PER_STORY := 30
## 大悬赏按等级：丙、乙、甲
const PER_BOUNTY: Array[int] = [15, 25, 40]
const PER_ODD_JOB := 3
## 每个头目第一次被打败（标记 boss_<敌人 id>）
const PER_BOSS := 25
## 擂台每打过一关
const PER_ARENA := 20
## 每个打完的奇遇（只发生一次的那种，标记 event_<id>）
const PER_EVENT := 10

## 境界：名字和要多少名望才能去打立名之战（第 0 阶是开局）
const NAMES: Array[String] = ["无名", "初露锋芒", "小有名气", "名动一方", "威震江湖", "名震天下"]
const THRESHOLDS: Array[int] = [0, 100, 300, 600, 1000, 1500]
const MAX_REALM := 5
## 每阶统领生命、攻击、防御、法抗 +10%（速度、敏捷不加，免得打乱出手顺序）；五阶 +50%，和甲品好汉勾玉全亮一样
const STAT_PER_REALM := 0.10
## 每阶武学最多修到第几重
const MARTIAL_CAP: Array[int] = [4, 6, 8, 10, 10, 10]
## 统领天赋：一阶解锁，四阶强化（和好汉的天赋一样 ×1.5）
const TALENT_REALM := 1
const TALENT_ENHANCE_REALM := 4

## 立名之战：要升到第 n 阶打的那一仗（n 从 1 数）：[敌人 id, 敌人等级]。上台的都是精英
const TRIALS := [
	[["po_pi_tou", "po_pi", "po_pi"], 12],
	[["xun_jie_ya_yi", "gao_fu_jia_ding", "xun_jie_ya_yi"], 24],
	[["shan_zei_tou_mu", "ma_zei", "ma_zei"], 36],
	[["qin_bing", "lei_tai_jiao_tou", "guan_bing_gong_shou"], 50],
	[["shui_kou", "jiang_men_shen", "shan_zei_tou_mu"], 64],
]
## 立名之战第一次打赢给的银两（按阶）
const TRIAL_SILVER := 200


## 按已经做过的事算名望。counts 的键：heroes、stories、bounties（[丙, 乙, 甲] 各几张）、odd_jobs、bosses、arena、events。
static func compute(counts: Dictionary) -> int:
	var total := 0
	total += int(counts.get("heroes", 0)) * PER_HERO
	total += int(counts.get("stories", 0)) * PER_STORY
	var bounties: Array = counts.get("bounties", [0, 0, 0])
	for g in mini(bounties.size(), PER_BOUNTY.size()):
		total += int(bounties[g]) * PER_BOUNTY[g]
	total += int(counts.get("odd_jobs", 0)) * PER_ODD_JOB
	total += int(counts.get("bosses", 0)) * PER_BOSS
	total += int(counts.get("arena", 0)) * PER_ARENA
	total += int(counts.get("events", 0)) * PER_EVENT
	return total


static func realm_name(realm: int) -> String:
	return NAMES[clampi(realm, 0, MAX_REALM)]


## 这一阶统领属性的倍数（第 0 阶 1.0，五阶 1.5）。
static func stat_mult(realm: int) -> float:
	return 1.0 + STAT_PER_REALM * clampi(realm, 0, MAX_REALM)


static func martial_cap(realm: int) -> int:
	return MARTIAL_CAP[clampi(realm, 0, MAX_REALM)]


## 统领天赋档次：0 未解锁，1 解锁，2 强化（和 TalentData.value 的 rank 一样）。
static func talent_rank(realm: int) -> int:
	if realm >= TALENT_ENHANCE_REALM:
		return 2
	if realm >= TALENT_REALM:
		return 1
	return 0


## 升到下一阶要多少名望；已经满阶返回 -1。
static func next_threshold(realm: int) -> int:
	return THRESHOLDS[realm + 1] if realm < MAX_REALM else -1


## 名望够不够去打下一阶的立名之战。
static func can_try(realm: int, renown: int) -> bool:
	return realm < MAX_REALM and renown >= THRESHOLDS[realm + 1]


## 升到第 n 阶（从 1 数）的立名之战。
static func trial_stage(n: int) -> StageData:
	var spec: Array = TRIALS[n - 1]
	var st := StageData.new()
	st.id = "trial_%d" % n
	st.title = "立名之战 · %s" % NAMES[n]
	var ids: Array = spec[0]
	for i in ids.size():
		var e: UnitData = load("res://data/enemies/%s.tres" % ids[i])
		if not e.is_boss:
			e = Encounters.make_elite(e, Encounters.ELITE_TRAITS[(n + i) % Encounters.ELITE_TRAITS.size()])
		st.enemies.append(e)
	st.enemy_level = spec[1]
	st.recommended_level = spec[1]
	return st


## 交给 main 的额外奖励：打赢了升阶（main 看 "trial" 这个键）。
static func trial_bonus(n: int) -> Dictionary:
	return {"trial": n, "silver": TRIAL_SILVER * n, "text": "立名之战胜！江湖上从此都知道{name}这号人物了。"}


## 统领天赋：每个职业一条（一阶解锁、四阶强化）。用好汉天赋现成的种类（见 TalentData.KINDS）。
static func role_talent(role: UnitData.Role) -> TalentData:
	var t := TalentData.new()
	match role:
		UnitData.Role.WARRIOR:
			t.display_name = "护镖"
			t.kind = &"team_guard_open"
			t.amount = 0.15
			t.text = "开战时全队受到的伤害 -{x}，持续 2 回合"
		UnitData.Role.ASSASSIN:
			t.display_name = "趁虚"
			t.kind = &"first_crit"
			t.text = "每场第一次出手必定暴击"
		UnitData.Role.ARCHER:
			t.display_name = "压阵"
			t.kind = &"pursuit"
			t.chance = 0.2
			t.pursuit_kind = &"snipe"
			t.amount = 0.8
			t.text = "普攻后 20% 几率再射一箭，绕开嘲讽打血最少的敌人，{x} 伤害"
		UnitData.Role.TAOIST:
			t.display_name = "聚气"
			t.kind = &"team_rage_start"
			t.amount = 20
			t.text = "开战时全队怒气 +{x}"
		_:
			t.display_name = "妙手"
			t.kind = &"team_regen"
			t.text = "全队每次轮到自己回复 2% 生命"
	return t

extends Node
## 存档：主角（名字、出身）、随行好汉、剧情标记、所在地点（自动加载为 GameState）。
## 存在手机本地 user://save.json。

const SAVE_PATH := "user://save.json"
## 版本不同的旧存档不兼容，当作没有存档
const SAVE_VERSION := 2
## 队伍是统领（主角）+ 最多这么多位好汉，四人一起上场
const MAX_HEROES := 3
## 新开局送的聚义令，够两次五连
const STARTING_TOKENS := 10
const DEFAULT_MAP := "ch1"
const PROTAGONIST_ID := &"protagonist"
const GENDER_MALE := &"male"
const GENDER_FEMALE := &"female"
## 别人称呼统领：台词里的占位词按性别换（例：「{name}{兄弟}」→ 女统领「韩青妹子」）
const ADDRESS_WORDS := {
	"{兄弟}": {GENDER_MALE: "兄弟", GENDER_FEMALE: "妹子"},
	"{后生}": {GENDER_MALE: "后生", GENDER_FEMALE: "姑娘"},
}
const GENDERS: Array[StringName] = [GENDER_MALE, GENDER_FEMALE]
## 修为：野外歇脚打坐歇完得多少（按统领等级）
const CAMP_XIUWEI_PER_LEVEL := 12
## 等级上限（规则在 Leveling）
const MAX_LEVEL := Leveling.MAX_LEVEL
## 存档里的等级是哪一套：旧存档（1～30 级）读档时换算成 1～99 级
const LEVEL_SCALE := 99

var player_name := ""
var origin_id: StringName = &""
## 统领的性别：只换立绘、小人和别人怎么称呼（属性不分男女）。旧存档没有这一项，算男
var gender: StringName = GENDER_MALE
## 统领的境界（见 Renown）：名望够了纳了投名状才升一阶
var realm := 0
## 修为：修炼武学用（打仗、野外打坐得来）
var xiuwei := 0
## 开战带哪一个号令（见 Commands）；空 = 自动带最后解锁的那个
var command: StringName = &""
var team_ids: Array[StringName] = []
var flags: Dictionary[String, bool] = {}
var location_id: StringName = &""
## 现在在哪张场景里（地点的场景或者野外路图）；游戏以它为家，打完仗、看完菜单都回这里
var scene_id := ""
## 统领的等级和经验；敌人强弱、歇脚价钱这些都按统领等级算
var level := 1
var experience := 0
## 每位好汉自己的等级和经验：只有上场的好汉拿经验。没记的就是 1 级（新招的从 1 级练起）
var hero_levels: Dictionary[StringName, int] = {}
var hero_exp: Dictionary[StringName, int] = {}
var silver := 0
## 聚义令：抽卡用，只能靠闯荡获得
var tokens := 0
## 已招募的好汉、每位好汉攒下的将魂（重复抽到时得到，M3 升星用）、距上次抽出甲级已经抽了几次
var owned: Array[StringName] = []
var souls: Dictionary[StringName, int] = {}
var pulls_since_jia := 0
## 每位好汉的星数（没记的就是 1 星）、通用货币义气（将魂化来，可换指定好汉的将魂）
var stars: Dictionary[StringName, int] = {}
var yiqi := 0
## 残页：合成技能书时顶缺的将魂（见 Books）
var pages := 0
## 主角和每位好汉的羁绊点数（见 Bonds）
var bonds: Dictionary[StringName, int] = {}
## 气血：没回满的人剩多少（0～1，见 Vitality）；没记的就是满血
var vitality: Dictionary[StringName, float] = {}
## 身上带的药：id → 数量
var medicines: Dictionary[StringName, int] = {}
## 野外歇脚：正在歇的 {"scene": 场景, "cell": [x, y], "started": 开始的时刻}（没在歇就是空），上次歇完的时刻。
## 时刻都是真实时间（秒），关掉游戏也照算
var camp: Dictionary = {}
var last_camp_done := 0
## 背包里的装备：每件 {"uid": 编号, "id": 模板 id, "holder": 装备在谁身上（空 = 没装备）}
var items: Array[Dictionary] = []
## 主角学会的武学和主修（主修那门就是统领在战斗里放的绝招；职业由出身定）、每门修到第几重
var martials: Array[StringName] = []
var martial_main: StringName = &""
var martial_levels: Dictionary[StringName, int] = {}
## 布阵：统领和每位好汉站哪一格（Vector2i(排, 路)，见 Grid）；没记的人开战时按阵法、按职业自动摆
var positions: Dictionary[StringName, Vector2i] = {}
## 老存档里的副修武学。主角改当统领后不再用，读档时清空
var martial_side: StringName = &""
## 秘籍：每本一条 {uid, id, holder}，holder 为空就是没人装。和装备共用编号
var scrolls: Array[Dictionary] = []
## 选用的阵法（Formations 的 id）
var formation: StringName = Formations.DEFAULT
## 江湖履历：打赢几场、其中游荡小怪几只、闯荡了多少秒（主角页显示）
var record: Dictionary = {"wins": 0, "roamers": 0, "play_seconds": 0.0, "arena": 0, "odd_jobs": 0, "city_jobs": 0}
## 小悬赏：{地区 id: [{enemy, name, need, have, silver, exp, tokens}, ...]}，见 OddJobs
var jobs: Dictionary = {}
## 地图左上「指引」正在追踪的一件事（江湖榜某一行的 kind、text、detail、location）；空 = 默认追踪「上梁山」（境界）
var tracked: Dictionary = {}
## 城中悬赏：{地区 id: {"day", "stock", "job"}}，见 CityJobs
var city_jobs: Dictionary = {}
## 甲马：身上有几张；集市哪天买了几张 {"day", "bought"}；戴宗写到了哪天（见 Jiama）
var jiama := 0
var jiama_shop: Dictionary = {}
var jiama_dai_day := 0
var _next_uid := 1

## 场景里的临时状态（不存档）：{场景 id: {"cleared": 打败的小怪序号, "cell": 打完仗回来站的格子}}。
## 离开场景就清掉，再进来小怪会重新出现
var scene_memory: Dictionary = {}
## 正在打的场景小怪 [场景 id, 序号]；打赢了记进 scene_memory
var pending_roamer: Array = []

var _protagonist: UnitData


func _ready() -> void:
	load_game()


func _process(delta: float) -> void:
	if player_name != "":
		record["play_seconds"] += delta


## 打赢一场就记一笔，同场的好汉羁绊各涨一点（main 在战斗结算时调用）。返回羁绊升级的提示。
func record_win() -> String:
	record["wins"] += 1
	var parts := PackedStringArray()
	for id in team_ids:
		var up := add_bond(id, Bonds.BATTLE_POINTS)
		if up != "":
			parts.append(up)
	return "　".join(parts)


func bond_of(id: StringName) -> int:
	return bonds.get(id, 0)


func sworn(id: StringName) -> bool:
	return has_flag("sworn_" + String(id))


func can_swear(id: StringName) -> bool:
	return owns(id) and not sworn(id) and Bonds.level(bond_of(id)) >= Bonds.SWEAR_LEVEL


## 和羁绊到了知己的好汉结义：他传授一本独门秘籍。
func swear(id: StringName) -> bool:
	if not can_swear(id):
		return false
	set_flag("sworn_" + String(id))
	_teach_miji(id)
	save_game()
	return true


## 结义兄弟传授的秘籍；返回「林冲传授了秘籍《豹子头枪诀》」，已经传过或没有就返回空。
func _teach_miji(id: StringName) -> String:
	var mj := GameDB.miji_of_hero(id)
	if mj == null or has_flag("miji_" + String(id)):
		return ""
	set_flag("miji_" + String(id))
	add_scroll(mj.id)
	return "%s传授了秘籍《%s》" % [GameDB.hero(id).display_name, mj.display_name]


## 结义时传授的那句话（界面用）。
func taught_text(id: StringName) -> String:
	var mj := GameDB.miji_of_hero(id)
	return "%s传授了独门秘籍《%s》：%s" % [GameDB.hero(id).display_name, mj.display_name, mj.summary()] if mj != null else ""


# --- 秘籍 ---

func add_scroll(id: StringName) -> int:
	var uid := _next_uid
	_next_uid += 1
	scrolls.append({"uid": uid, "id": id, "holder": &""})
	return uid


func scroll(uid: int) -> Dictionary:
	for sc in scrolls:
		if sc["uid"] == uid:
			return sc
	return {}


static func scroll_data(sc: Dictionary) -> MijiData:
	return GameDB.mijis.get(sc["id"])


## 某人秘籍栏里的那本（没有返回空字典）。
func scroll_of(holder: StringName) -> Dictionary:
	for sc in scrolls:
		if sc["holder"] == holder:
			return sc
	return {}


## 给 holder 装上这本：他原来那本卸下；这本原来在别人身上就拿过来。
func equip_scroll(holder: StringName, uid: int) -> void:
	var sc := scroll(uid)
	if sc.is_empty():
		return
	var old := scroll_of(holder)
	if not old.is_empty():
		old["holder"] = &""
	sc["holder"] = holder
	save_game()


func unequip_scroll(holder: StringName) -> void:
	var sc := scroll_of(holder)
	if not sc.is_empty():
		sc["holder"] = &""
	save_game()


## 秘籍栏里写的是什么：「《豹子头枪诀》」或空。
func scroll_slot_name(holder: StringName) -> String:
	var sc := scroll_of(holder)
	return "《%s》" % scroll_data(sc).display_name if not sc.is_empty() else ""


# --- 阵法 ---

func formation_unlocked(id: StringName) -> bool:
	var cond := Formations.unlock_condition(id)
	return cond == "" or _source_done(cond)


## 能用的阵法（按 Formations.ALL 的顺序）。
func unlocked_formations() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in Formations.ALL:
		if formation_unlocked(id):
			out.append(id)
	return out


func set_formation(id: StringName) -> void:
	if formation_unlocked(id):
		formation = id
		save_game()


## 现在出战用的阵法（选的那个没解锁就用默认的）。
func current_formation() -> StringName:
	return formation if formation_unlocked(formation) else Formations.DEFAULT


# --- 技能书 ---

## 合成技能书：每位故事里的好汉扣将魂，不够的用残页顶。成功返回 true，书进行囊。
func craft_book(mj: MijiData) -> bool:
	if not Books.can_craft(mj, souls, pages):
		return false
	var need := Books.souls_per_hero(mj)
	var short := 0
	for id in mj.recipe:
		var use := mini(souls_of(id), need)
		souls[id] = souls_of(id) - use
		short += need - use
	pages -= short
	add_scroll(mj.id)
	save_game()
	return true


## 统领研读一本技能书：学会书里的武学，书用掉。已经会了返回 false。
func study_book(uid: int) -> bool:
	var sc := scroll(uid)
	if sc.is_empty():
		return false
	var mj := scroll_data(sc)
	if mj == null or mj.martial == null or mj.martial.id in martials:
		return false
	scrolls.erase(sc)
	learn_martial(mj.martial)
	save_game()
	return true


func buy_scroll(mj: MijiData) -> bool:
	if mj.quality != MijiData.Quality.FAN or silver < MijiData.FAN_PRICE:
		return false
	silver -= MijiData.FAN_PRICE
	add_scroll(mj.id)
	save_game()
	return true


## 战斗里能用的组合技：好汉之间的，加上和结义兄弟的「结义同心」。
func combos() -> Array[ComboData]:
	var out: Array[ComboData] = GameDB.combos.duplicate()
	for id in owned:
		if sworn(id):
			out.append(Bonds.sworn_combo(GameDB.hero(id), PROTAGONIST_ID))
	return out


## 涨羁绊；升了一级时返回「与林冲的羁绊升到了相熟」，否则返回空。
func add_bond(id: StringName, points: int) -> String:
	if id == PROTAGONIST_ID or not owns(id):
		return ""
	var before := Bonds.level(bond_of(id))
	bonds[id] = bond_of(id) + points
	var after := Bonds.level(bond_of(id))
	if after == before:
		return ""
	return "与%s的羁绊升到了「%s」" % [GameDB.hero(id).display_name, Bonds.NAMES[after]]


## 开新档：起名、选出身，从出身的开局地点出发。
func new_game(p_name: String, origin: OriginData, p_gender: StringName = GENDER_MALE) -> void:
	reset()
	player_name = p_name
	origin_id = origin.id
	gender = p_gender if p_gender in GENDERS else GENDER_MALE
	location_id = origin.start_location
	tokens = STARTING_TOKENS
	_learn_origin_martial()
	set_flag("tut_on")
	_protagonist = null
	save_game()


func origin() -> OriginData:
	return GameDB.origins.get(origin_id)


## 主角的战斗数据：出身模板的一份复制，名字换成玩家起的名字。
## 职业由出身定死（开局选的）；主修别的职业的武学也行，但绝招威力打折（MartialData.FOREIGN_POWER）。
## 属性：这个职业甲品范围的中间值 × 境界倍数；境界到了再带上统领天赋。女统领换女版的立绘和小人。
func protagonist() -> UnitData:
	if _protagonist == null:
		var o := origin()
		if o == null:
			return null
		_protagonist = o.unit.duplicate(true)
		_protagonist.id = PROTAGONIST_ID
		_protagonist.display_name = player_name
		_protagonist.rarity = UnitData.Rarity.PROTAGONIST
		if gender == GENDER_FEMALE:
			o.apply_female_art(_protagonist)
		var main := martial(martial_main)
		if main != null:
			_protagonist.skill = main.skill_at(mini(martial_level(main.id), MartialData.MAX_LEVEL))
			if main.role != _protagonist.role:
				_protagonist.skill = MartialData.foreign(_protagonist.skill)
		var st := Roles.protagonist_stats(_protagonist.role)
		var k := Renown.stat_mult(realm)
		_protagonist.base_hp = roundi(st[0] * k)
		_protagonist.base_atk = roundi(st[1] * k)
		_protagonist.base_def = roundi(st[2] * k)
		_protagonist.base_res = roundi(st[3] * k)
		_protagonist.base_spd = st[4]
		_protagonist.base_agi = st[5]
		var rank := Renown.talent_rank(realm)
		if rank > 0:
			_protagonist.talent = Renown.role_talent(_protagonist.role)
			_protagonist.talent_rank = rank
			Stars.apply_passive(_protagonist, _protagonist.talent, rank)
		else:
			_protagonist.talent = null
			_protagonist.talent_rank = 0
	return _protagonist


## 统领的职业（出身定的）。
func protagonist_role() -> UnitData.Role:
	var o := origin()
	return o.unit.role if o != null else UnitData.Role.WARRIOR


## 统领打坐时的像素小人（女统领用女版）。
func sit_sprite() -> Texture2D:
	var o := origin()
	if o == null:
		return null
	if gender == GENDER_FEMALE and o.sit_sprite_female != null:
		return o.sit_sprite_female
	return o.sit_sprite


## 台词、旁白里的占位词：{name} 换成统领的名字，{兄弟}、{后生} 按性别换（见 ADDRESS_WORDS）。
func fill_text(text: String) -> String:
	var out := text.replace("{name}", player_name)
	for key: String in ADDRESS_WORDS:
		out = out.replace(key, ADDRESS_WORDS[key][gender if gender in GENDERS else GENDER_MALE])
	return out


# --- 名望和境界 ---

## 江湖名望：按已经做过的事现算（见 Renown.compute）。
func renown() -> int:
	var bounties := [0, 0, 0]
	for b: BountyData in GameDB.bounties:
		if has_flag("bounty_" + String(b.id)):
			bounties[int(b.grade)] += 1
	var stories := GameDB.stories.filter(func(s: StoryData) -> bool: return story_done(s)).size()
	var bosses := 0
	var events := 0
	for f: String in flags:
		if f.begins_with("boss_"):
			bosses += 1
		elif f.begins_with("event_"):
			events += 1
	return Renown.compute({
		"heroes": owned.size(),
		"stories": stories,
		"bounties": bounties,
		"odd_jobs": int(record.get("odd_jobs", 0)),
		"city_jobs": int(record.get("city_jobs", 0)),
		"bosses": bosses,
		"arena": Arena.best(),
		"events": events,
	})


## 名望够了，可以去纳下一阶的投名状。
func can_try_trial() -> bool:
	return Renown.can_try(realm, renown())


## 打赢第 n 阶的投名状：升到这一阶。返回提示。
func pass_trial(n: int) -> String:
	if n != realm + 1 or n > Renown.MAX_REALM:
		return ""
	realm = n
	_protagonist = null
	var parts := PackedStringArray(["境界升到「%s」：统领属性 +%d%%，武学最多修到第 %d 重" % [Renown.realm_name(n), roundi(Renown.STAT_PER_REALM * n * 100), Renown.martial_cap(n)]])
	if n == Renown.TALENT_REALM:
		parts.append("领悟统领天赋「%s」" % Renown.role_talent(protagonist_role()).display_name)
	elif n == Renown.TALENT_ENHANCE_REALM:
		parts.append("统领天赋「%s」强化" % Renown.role_talent(protagonist_role()).display_name)
	for id in Commands.unlocked(n):
		if Commands.unlock_realm(id) == n:
			parts.append("学会号令「%s」" % Commands.display_name(id))
	save_game()
	return "　".join(parts)


## 这一仗带哪个号令：选过且已解锁的就用它，否则带最后解锁的那个；还没解锁返回空。
func battle_command() -> StringName:
	var list := Commands.unlocked(realm)
	if list.is_empty():
		return &""
	return command if command in list else list.back()


func set_command(id: StringName) -> void:
	if id in Commands.unlocked(realm):
		command = id
		save_game()


func heroes() -> Array[UnitData]:
	var out: Array[UnitData] = []
	for id in team_ids:
		var hero := GameDB.hero(id)
		if hero != null and id in owned:
			out.append(hero)
	return out


func owns(id: StringName) -> bool:
	return id in owned


## 用聚义令招募 count 次（1 或 Gacha.MULTI）。返回每一抽的结果 [{hero, is_new}]；聚义令不够时返回空。
## 队伍没满时，新招到的好汉按品级从高到低自动补进去；第一次五连保证出一个甲（旗子沿用旧名 first_ten_pull，旧存档抽过十连的不再送）。
func recruit(count: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if tokens < count:
		return results
	tokens -= count
	var first_ten := count >= Gacha.MULTI and not has_flag("first_ten_pull")
	if count >= Gacha.MULTI:
		set_flag("first_ten_pull")
	var outcome := Gacha.pull(GameDB.heroes, count, pulls_since_jia, rng, first_ten)
	pulls_since_jia = outcome["pulls_since_jia"]
	var drawn: Array[UnitData] = []
	drawn.assign(outcome["heroes"])
	var newcomers: Array[UnitData] = []
	for hero in drawn:
		var is_new := not owns(hero.id)
		if is_new:
			owned.append(hero.id)
			newcomers.append(hero)
		else:
			souls[hero.id] = souls.get(hero.id, 0) + Gacha.DUPLICATE_SOULS
		results.append({"hero": hero, "is_new": is_new})
	newcomers.sort_custom(func(a: UnitData, b: UnitData) -> bool: return a.tier < b.tier)
	for hero in newcomers:
		if team_ids.size() < MAX_HEROES:
			team_ids.append(hero.id)
	save_game()
	return results


func star_of(id: StringName) -> int:
	var star: int = stars.get(id, 1)
	# 旧存档按以前的上限（10/8/5/3 星）升过的，压到现在的上限
	var hero := GameDB.hero(id)
	return mini(star, Stars.max_stars(hero)) if hero != null else star


func souls_of(id: StringName) -> int:
	return souls.get(id, 0)


func can_star_up(hero: UnitData) -> bool:
	var star := star_of(hero.id)
	return owns(hero.id) and star < Stars.max_stars(hero) and souls_of(hero.id) >= Stars.cost(star)


## 消耗将魂升 1 星，成功返回 true。
func star_up(hero: UnitData) -> bool:
	if not can_star_up(hero):
		return false
	souls[hero.id] = souls_of(hero.id) - Stars.cost(star_of(hero.id))
	stars[hero.id] = star_of(hero.id) + 1
	save_game()
	return true


## 把 count 个将魂化成义气。
func souls_to_yiqi(id: StringName, count: int) -> bool:
	if count <= 0 or souls_of(id) < count:
		return false
	souls[id] = souls_of(id) - count
	yiqi += count * Stars.YIQI_PER_SOUL
	save_game()
	return true


## 用义气换 count 个指定好汉的将魂（没招到的也能换，攒够了直接招募）。
func buy_souls(hero: UnitData, count: int) -> bool:
	var price := Stars.soul_price(hero) * count
	if count <= 0 or yiqi < price:
		return false
	yiqi -= price
	souls[hero.id] = souls_of(hero.id) + count
	save_game()
	return true


## 没招到的好汉，用将魂直接招募。
func recruit_with_souls(hero: UnitData) -> bool:
	if owns(hero.id) or souls_of(hero.id) < Stars.RECRUIT_SOULS:
		return false
	souls[hero.id] = souls_of(hero.id) - Stars.RECRUIT_SOULS
	owned.append(hero.id)
	if team_ids.size() < MAX_HEROES:
		team_ids.append(hero.id)
	save_game()
	return true


## 这个人现在等级下的生命上限（带上勾玉、羁绊、装备、秘籍），药按它折算比例。统领也算。
func max_hp_of(id: StringName) -> int:
	var unit := battle_data(id)
	if unit == null:
		return 1
	return maxi(1, roundi(unit.base_hp * pow(Roles.level_growth(unit), level_of(id) - 1)))


## 这个人的等级：统领看 level，好汉看自己的（没记的是 1 级）。
func level_of(id: StringName) -> int:
	if id == PROTAGONIST_ID:
		return level
	return hero_levels.get(id, 1)


## 这个人当前这一级攒了多少经验。
func exp_of(id: StringName) -> int:
	if id == PROTAGONIST_ID:
		return experience
	return hero_exp.get(id, 0)


## 这个人拿经验的倍数：好汉比统领低就多拿（见 Leveling.catch_up_mult），统领拿原样。
func catch_up_mult(id: StringName) -> float:
	if id == PROTAGONIST_ID:
		return 1.0
	return Leveling.catch_up_mult(level_of(id), level)


## 出战队伍每人的等级（和 team() 一一对应），开战时交给 BattleModel。
func team_levels() -> Array[int]:
	var out: Array[int] = []
	for u in team():
		out.append(level_of(u.id))
	return out


## 一个人上战场的数据：好汉带上星级、羁绊，统领用主修武学；都再带上装备和秘籍。
func battle_data(id: StringName) -> UnitData:
	var unit: UnitData
	if id == PROTAGONIST_ID:
		unit = protagonist()
	else:
		var hero := GameDB.hero(id)
		if hero == null:
			return null
		unit = Bonds.apply(Stars.apply(hero, star_of(id)), bond_of(id))
	if unit == null:
		return null
	unit = Equipment.apply(unit, effective_gear(id))
	var sc := scroll_of(id)
	return Miji.apply(unit, scroll_data(sc) if not sc.is_empty() else null)


## 战斗用的队伍：统领在前，然后是出战的好汉（都带上星级、羁绊、装备、秘籍）。
func battle_team(_unused := true) -> Array[UnitData]:
	var out: Array[UnitData] = []
	for u in team():
		var unit := battle_data(u.id)
		if unit != null:
			out.append(unit)
	return out


## 开战时每人站的格子（和 battle_team 一一对应）；没布过阵的是 Grid.NONE，按阵法、职业自动摆。
func placement() -> Array:
	var auto := _arranged(current_formation())
	var out := []
	for u in team():
		out.append(positions.get(u.id, auto.get(u.id, Grid.NONE)))
	return out


## 按阵法的阵位一键布阵：阵位宜站什么职业就先挑那个职业的人，剩下的按顺序；阵位不够的按职业自动摆。
func arrange_by_formation(id: StringName) -> void:
	positions.clear()
	var put := _arranged(id)
	for uid: StringName in put:
		positions[uid] = put[uid]
	save_game()


## 按阵位算出的站位（不存）：id → 格子。阵眼先挑人；宜站的职业优先，其次宜站这一排的，剩下的按职业找空格。
func _arranged(id: StringName) -> Dictionary:
	var members := team()
	var cells := Formations.cells(id)
	if not cells.is_empty():
		cells.erase(Formations.eye_cell(id))
		cells.push_front(Formations.eye_cell(id))
	var left: Array[UnitData] = members.duplicate()
	var put := {}
	# 三轮：宜站的职业 → 宜站这一排的 → 阵眼不能空，谁都行
	for pass_i in 3:
		for c in cells:
			if put.values().has(c):
				continue
			var want := Formations.suited_role(id, c)
			for u in left:
				var ok := (want != Formations.ANY and u.role == want) if pass_i == 0 else (Roles.home_row(u.role) == c.x if pass_i == 1 else c == Formations.eye_cell(id))
				if ok:
					put[u.id] = c
					left.erase(u)
					break
	# 剩下的人（阵位不够时）按职业找空格
	var taken := {}
	for c: Vector2i in put.values():
		taken[c] = true
	for u in left:
		var home := Roles.home_row(u.role)
		for r in [home, 1 - home]:
			if put.has(u.id):
				break
			for l in Grid.LANE_ORDER:
				var c := Vector2i(r, l)
				if not taken.has(c):
					put[u.id] = c
					taken[c] = true
					break
	return put


## 把 id 挪到格子 c；那格原来有人就和他换位。
func move_to_cell(id: StringName, c: Vector2i) -> void:
	var team_ids_all: Array[StringName] = []
	for u in team():
		team_ids_all.append(u.id)
	# 先把没记过格子的人按当前的样子补上，免得换位时丢人
	var current := current_cells()
	for uid in team_ids_all:
		positions[uid] = current[uid]
	for uid in team_ids_all:
		if uid != id and positions[uid] == c:
			positions[uid] = positions[id]
	positions[id] = c
	save_game()


## 队伍现在每人站哪一格（没布过阵的按开战时的规则算出来）：id → Vector2i。
func current_cells() -> Dictionary:
	var stage := StageData.new()
	var m := BattleModel.new(stage, team(), 1, [], 1, current_formation(), placement())
	var out := {}
	for u in m.units:
		out[u.data.id] = u.cell()
	return out


## 开打前的关卡：头目按队伍的养成程度加强（复制一份，不改原关卡）。
func prepare_stage(stage: StageData) -> StageData:
	var st: StageData = stage.duplicate()
	st.boss_power = Encounters.boss_power(team(), battle_team())
	return st


## 算属性时用的「装备」：身上的装备。
func effective_gear(holder: StringName) -> Array[EquipData]:
	return gear_of(holder)


# --- 武学 ---

func martial(id: StringName) -> MartialData:
	return GameDB.martials.get(id)


## 学会一门武学，已经会了返回 false。学会的第一门直接主修。
func learn_martial(m: MartialData) -> bool:
	if m == null or m.id in martials:
		return false
	martials.append(m.id)
	if martial_main == &"":
		martial_main = m.id
		_protagonist = null
	save_game()
	return true


## 第几重（学会就是第 1 重）。
func martial_level(id: StringName) -> int:
	return clampi(martial_levels.get(id, 1), 1, MartialData.MAX_LEVEL)


## 武学现在最多能修到第几重（受境界限制）。
func martial_cap() -> int:
	return Renown.martial_cap(realm)


func can_train(id: StringName) -> bool:
	var lv := martial_level(id)
	return id in martials and lv < martial_cap() and xiuwei >= MartialData.level_cost(lv)


## 花修为把这门武学修上一重。
func train_martial(id: StringName) -> bool:
	if not can_train(id):
		return false
	xiuwei -= MartialData.level_cost(martial_level(id))
	martial_levels[id] = martial_level(id) + 1
	_protagonist = null
	save_game()
	return true


## 换主修（统领的绝招跟着换；职业不变，别的职业的武学威力打折）。
func set_martial_main(id: StringName) -> void:
	if not id in martials or id == martial_main:
		return
	martial_main = id
	_protagonist = null
	save_game()


func _learn_origin_martial() -> void:
	var o := origin()
	if o != null and o.martial != null and not o.martial.id in martials:
		martials.append(o.martial.id)
		if martial_main == &"":
			martial_main = o.martial.id
		_protagonist = null


# --- 场景小怪 ---

func scene_state(scene_id: String) -> Dictionary:
	if not scene_memory.has(scene_id):
		scene_memory[scene_id] = {"cleared": [], "cell": null}
	return scene_memory[scene_id]


## 一场仗打完：如果是场景小怪，赢了就记下它已被打败。
func finish_roamer(won: bool) -> void:
	if won and pending_roamer.size() == 2:
		scene_state(pending_roamer[0])["cleared"].append(pending_roamer[1])
		record["roamers"] += 1
	pending_roamer = []


# --- 城中悬赏（规则见 CityJobs） ---

## 这个地方眼下的城中悬赏状态（先换天、再补贴一张）；会改 city_jobs，不存档。
func city_entry(region: StringName) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var e := CityJobs.accrue(city_jobs.get(String(region), {}), CityJobs.today())
	e = CityJobs.post_next(e, OddJobs.enemy_pool(region), rng)
	city_jobs[String(region)] = e
	return e


## 去过的地方（江湖榜、聚义令指引列出来用）。
func visited_regions() -> Array[StringName]:
	var out: Array[StringName] = []
	for loc: LocationData in GameDB.maps[DEFAULT_MAP].locations:
		if has_flag("visited_" + String(loc.id)) or loc.id == location_id:
			out.append(loc.id)
	return out


## 打赢一场后调用：有这种敌人的城中悬赏进度 +1，够数的发赏、贴下一张。返回给玩家看的一句话。
func city_on_battle_won(stage: StageData) -> String:
	var ids := stage.enemies.map(func(e: UnitData) -> String: return String(e.id))
	var done := PackedStringArray()
	for region: String in city_jobs.keys():
		var e: Dictionary = city_jobs[region]
		var job: Dictionary = e.get("job", {})
		if job.is_empty() or not job["enemy"] in ids:
			continue
		job["have"] = int(job["have"]) + 1
		if job["have"] >= job["need"]:
			var gained := Rewards.grant(job["tokens"], job["silver"], job["exp"])
			record["city_jobs"] = int(record.get("city_jobs", 0)) + 1
			done.append("城中悬赏「打败%s %d 拨」完成：%s" % [job["name"], job["need"], gained])
			e["job"] = {}
			city_jobs[region] = e
			city_entry(StringName(region))
	return "　".join(done)


# --- 甲马（规则见 Jiama） ---

## 招到了戴宗：按天补他写的甲马（几天不来就攒着，身上最多 Jiama.MAX_CARRY 张）。返回提示，没多就是空。
func jiama_daily() -> String:
	if not owns(Jiama.WRITER):
		return ""
	var r := Jiama.dai_write(jiama, jiama_dai_day, CityJobs.today())
	jiama = r[0]
	jiama_dai_day = r[1]
	if r[2] <= 0:
		return ""
	return "戴宗写好甲马 ×%d" % r[2]


## 集市今天还能买几张甲马。
func jiama_shop_left() -> int:
	return Jiama.shop_left(jiama_shop, CityJobs.today(), jiama)


func buy_jiama() -> bool:
	if jiama_shop_left() <= 0 or silver < Jiama.PRICE:
		return false
	var today := CityJobs.today()
	var bought := int(jiama_shop.get("bought", 0)) if int(jiama_shop.get("day", -1)) == today else 0
	jiama_shop = {"day": today, "bought": bought + 1}
	silver -= Jiama.PRICE
	jiama += 1
	save_game()
	return true


## 拴一张甲马，去一个去过的地方（不是眼下这里）。成功了由 main 切到那里的场景。
func use_jiama(location: StringName) -> bool:
	if jiama <= 0 or location == location_id or not has_flag("visited_" + String(location)):
		return false
	jiama -= 1
	save_game()
	return true


# --- 列传 ---

func story_done(story: StoryData) -> bool:
	return has_flag(story.flag())


## 能玩的列传：招到了这位好汉、前一段打完了、这一段还没打。
func story_available(story: StoryData) -> bool:
	if not owns(story.hero) or story_done(story):
		return false
	for s in GameDB.stories:
		if s.hero == story.hero and s.order < story.order and not story_done(s):
			return false
	return true


## 某位好汉的列传：[已完成段数, 总段数]
func story_progress(hero_id: StringName) -> Array[int]:
	var done := 0
	var total := 0
	for s in GameDB.stories:
		if s.hero == hero_id:
			total += 1
			if story_done(s):
				done += 1
	return [done, total]


# --- 装备 ---

## 出处已经达成、还没拿到的名器发给玩家（列传完结、悬赏揭下、宝箱打开、擂台打到第几关）。
## 每件只发一次（标记 mingqi_<id>）。返回提示，没有新的返回空。
func claim_mingqi() -> String:
	var parts := PackedStringArray()
	for e: EquipData in GameDB.equipment.values():
		if e.quality != EquipData.Quality.MING or e.source == "" or has_flag("mingqi_" + String(e.id)):
			continue
		if _source_done(e.source):
			set_flag("mingqi_" + String(e.id))
			add_item(e.id)
			parts.append("得到%s「%s」" % [e.quality_name(), e.display_name])
	return "　".join(parts)


func _source_done(source: String) -> bool:
	if source.begins_with("arena:"):
		return Arena.best() >= int(source.get_slice(":", 1))
	return has_flag(source)


## 主角的坐骑（决定在大地图上赶路多快、遇敌多少），没有返回 null。
func mount() -> EquipData:
	for g in gear_of(PROTAGONIST_ID):
		if g.slot == EquipData.Slot.MOUNT:
			return g
	return null


## 放进背包，返回这件的编号。
func add_item(id: StringName) -> int:
	var uid := _next_uid
	_next_uid += 1
	items.append({"uid": uid, "id": id, "holder": &""})
	return uid


func item(uid: int) -> Dictionary:
	for it in items:
		if it["uid"] == uid:
			return it
	return {}


static func item_data(it: Dictionary) -> EquipData:
	return GameDB.equipment.get(it["id"])


## 某人身上的装备（按栏位顺序）。
func gear_of(holder: StringName) -> Array[EquipData]:
	var out: Array[EquipData] = []
	for it in items:
		if it["holder"] == holder:
			out.append(item_data(it))
	out.sort_custom(func(a: EquipData, b: EquipData) -> bool: return a.slot < b.slot)
	return out


## 某人某个栏位上的那件（没有就返回空字典）。
func equipped(holder: StringName, slot: EquipData.Slot) -> Dictionary:
	for it in items:
		if it["holder"] == holder and item_data(it).slot == slot:
			return it
	return {}


## 给 holder 穿上这件：同一栏位原来那件卸下；这件原来在别人身上就从那人身上拿过来。
func equip(holder: StringName, uid: int) -> void:
	var it := item(uid)
	if it.is_empty() or (holder == PROTAGONIST_ID and item_data(it).slot != EquipData.Slot.MOUNT):
		return
	var old := equipped(holder, item_data(it).slot)
	if not old.is_empty():
		old["holder"] = &""
	it["holder"] = holder
	save_game()


func unequip(uid: int) -> void:
	var it := item(uid)
	if not it.is_empty():
		it["holder"] = &""
		save_game()


## 卖给集市，返回得到的银两。
func sell_item(uid: int) -> int:
	var it := item(uid)
	if it.is_empty():
		return 0
	if not item_data(it).can_sell():
		return 0
	var price := item_data(it).sell_price()
	items.erase(it)
	silver += price
	save_game()
	return price


func buy_item(data: EquipData) -> bool:
	if silver < data.buy_price():
		return false
	silver -= data.buy_price()
	add_item(data.id)
	save_game()
	return true


## 出战队伍：统领（主角）在前，加上最多三位好汉，四人一起上场。还没开新档（没有出身）时只有好汉。
func team() -> Array[UnitData]:
	var out: Array[UnitData] = []
	var me := protagonist()
	if me != null:
		out.append(me)
	out.append_array(heroes())
	return out


func set_heroes(list: Array[UnitData]) -> void:
	team_ids.clear()
	for h in list.slice(0, MAX_HEROES):
		team_ids.append(h.id)


## 从 at_level 升到下一级需要的经验（见 Leveling）。
static func exp_to_next(at_level: int) -> int:
	return Leveling.exp_to_next(at_level)


## 旧存档（最高 30 级）的等级换算到 1～99 级。
static func rescale_old_level(old: int) -> int:
	return clampi(roundi(1 + (old - 1) * 98.0 / 29.0), 1, MAX_LEVEL)


## 加银两，统领和出战的好汉每人各加一份经验（好汉按 catch_up_mult 多拿）。
## 返回升级的提示，升到同一级的并成一句（「统领、林冲升到 12 级！」），没人升级返回空。升了级的人气血回满。
func add_rewards(gained_exp: int, gained_silver: int) -> PackedStringArray:
	silver += gained_silver
	var texts := PackedStringArray()
	if gained_exp <= 0:
		return texts
	var risen := {}  # 升到几级 → [谁, ...]
	var ids: Array[StringName] = [PROTAGONIST_ID]
	for hero in heroes():
		ids.append(hero.id)
	for id in ids:
		var gained := roundi(gained_exp * catch_up_mult(id))
		var grown := Leveling.gain_exp(level_of(id), exp_of(id), gained)
		var ups: int = grown[0] - level_of(id)
		if id == PROTAGONIST_ID:
			level = grown[0]
			experience = grown[1]
		else:
			hero_levels[id] = grown[0]
			hero_exp[id] = grown[1]
		if ups > 0:
			vitality.erase(id)
			var who := "统领" if id == PROTAGONIST_ID else GameDB.hero(id).display_name
			if not risen.has(grown[0]):
				risen[grown[0]] = PackedStringArray()
			risen[grown[0]].append(who)
	for lv: int in risen:
		texts.append("%s升到 %d 级！" % ["、".join(risen[lv]), lv])
	return texts



# --- 气血和药 ---

func vitality_of(id: StringName) -> float:
	return vitality.get(id, 1.0)


## 打完一仗（赢、输、撤退都算）记下我方每人剩的气血。擂台不算（main 不调这里）。
func record_battle(model: BattleModel) -> void:
	var after := Vitality.after_battle(model)
	for id in after:
		_set_vitality(id, after[id])


func _set_vitality(id: StringName, ratio: float) -> void:
	if ratio >= 0.999:
		vitality.erase(id)
	else:
		vitality[id] = ratio


## 队里有人带「神医」这类全队回春的天赋，赶路回血翻倍。
func has_healer() -> bool:
	for u in battle_team():
		if u.talent != null and u.talent_rank > 0 and u.talent.kind == &"team_regen":
			return true
	return false


## 走完一段路：每人回一点气血。
func road_regen() -> void:
	Vitality.road_regen(vitality, has_healer())
	for id in vitality.keys():
		_set_vitality(id, vitality[id])


## 在有店的地方歇脚：按伤势花银两，全队回满。
func rest_price() -> int:
	return Vitality.rest_price(level, vitality)


func rest() -> bool:
	var price := rest_price()
	if vitality.is_empty() or silver < price:
		return false
	silver -= price
	vitality.clear()
	save_game()
	return true


# --- 野外歇脚（真实时间） ---

static func now() -> int:
	return int(Time.get_unix_time_from_system())


## 还要等几秒才能再歇（0 = 现在就能歇）。
func camp_cooldown_left() -> int:
	return maxi(0, last_camp_done + Vitality.CAMP_COOLDOWN - now())


func start_camp(scene_id: String, cell: Vector2i) -> void:
	camp = {"scene": scene_id, "cell": [cell.x, cell.y], "started": now()}
	save_game()


## 这一次歇脚还要打坐几秒（0 = 歇好了）。
func camp_time_left() -> int:
	if camp.is_empty():
		return 0
	return maxi(0, int(camp["started"]) + Vitality.CAMP_SECONDS - now())


## 中途起身：不回血，也不算歇过。
func cancel_camp() -> void:
	camp = {}
	save_game()


## 歇好了：每人回 Vitality.CAMP_REGEN，记下歇完的时刻。
func finish_camp() -> void:
	camp = {}
	last_camp_done = now()
	xiuwei += camp_xiuwei()
	camp_rest()


## 歇完一次打坐得多少修为。
func camp_xiuwei() -> int:
	return CAMP_XIUWEI_PER_LEVEL * level


## 每人回 Vitality.CAMP_REGEN。
func camp_rest() -> bool:
	for id in vitality:
		vitality[id] = minf(vitality[id] + Vitality.CAMP_REGEN, 1.0)
	save_game()
	return true


func buy_medicine(id: StringName) -> bool:
	var price := Vitality.medicine_price(id)
	if silver < price:
		return false
	silver -= price
	medicines[id] = medicines.get(id, 0) + 1
	save_game()
	return true


## 用一份药：全队药不看 target，单人药用在 target 身上。
func use_medicine(id: StringName, target: StringName) -> bool:
	if medicines.get(id, 0) <= 0:
		return false
	var heal := Vitality.medicine_heal(id)
	if Vitality.medicine_for_team(id):
		if vitality.is_empty():
			return false
		for k in vitality.keys():
			_set_vitality(k, vitality[k] + float(heal) / max_hp_of(k))
	else:
		if vitality_of(target) >= 0.999:
			return false
		_set_vitality(target, minf(vitality_of(target) + float(heal) / max_hp_of(target), 1.0))
	medicines[id] -= 1
	if medicines[id] <= 0:
		medicines.erase(id)
	save_game()
	return true


## 主角现在所在的场景（存档里没有就用所在地点的场景）。
func home_scene() -> String:
	if scene_id != "" and GameDB.scenes.has(scene_id):
		return scene_id
	var loc := GameDB.maps[DEFAULT_MAP].location(location_id)
	return loc.scene_id if loc != null else ""


## 走进一张场景：记下位置。是某个地点的场景就算到了那个地点——第一次来给聚义令、讲那里的事；
## 从野外路上走过来的，路上缓过一口气（气血回一点）。返回要给玩家看的提示（没有就是空）。
func enter_scene(id: String) -> String:
	var previous := scene_id
	scene_id = id
	var parts := PackedStringArray()
	for loc: LocationData in GameDB.maps[DEFAULT_MAP].locations:
		if loc.scene_id != id:
			continue
		location_id = loc.id
		if previous != id and previous.begins_with("road_"):
			road_regen()
		var visit_flag := "visited_" + String(loc.id)
		if not has_flag(visit_flag):
			set_flag(visit_flag)
			tokens += WorldMapView.FIRST_VISIT_TOKENS
			parts.append("初到%s，聚义令 +%d" % [loc.display_name, WorldMapView.FIRST_VISIT_TOKENS])
		var written := jiama_daily()
		if written != "":
			parts.append(written)
		if loc.arrive_flag != "" and not has_flag(loc.arrive_flag):
			set_flag(loc.arrive_flag)
			if loc.arrive_text != "":
				parts.append(loc.arrive_text)
	save_game()
	return "　".join(parts)


func has_flag(flag: String) -> bool:
	if flag == "":
		return true
	var on: bool = flags.get(flag, false)
	return on


func set_flag(flag: String) -> void:
	if flag != "":
		flags[flag] = true


func reset() -> void:
	player_name = ""
	origin_id = &""
	gender = GENDER_MALE
	realm = 0
	xiuwei = 0
	command = &""
	team_ids.clear()
	owned.clear()
	souls.clear()
	pulls_since_jia = 0
	stars.clear()
	yiqi = 0
	pages = 0
	bonds.clear()
	vitality.clear()
	medicines.clear()
	camp = {}
	last_camp_done = 0
	scene_id = ""
	items.clear()
	scrolls.clear()
	formation = Formations.DEFAULT
	_next_uid = 1
	martials.clear()
	martial_main = &""
	martial_side = &""
	martial_levels.clear()
	positions.clear()
	record = {"wins": 0, "roamers": 0, "play_seconds": 0.0, "arena": 0, "odd_jobs": 0, "city_jobs": 0}
	jobs = {}
	tracked = {}
	city_jobs = {}
	jiama = 0
	jiama_shop = {}
	jiama_dai_day = 0
	flags.clear()
	location_id = GameDB.maps[DEFAULT_MAP].start_location
	level = 1
	experience = 0
	hero_levels.clear()
	hero_exp.clear()
	silver = 0
	tokens = 0
	_protagonist = null


## 新手引导走到第几步（0 = 不用引导，老存档和走完的都是 0）：
## 1 招募 → 2 编队 → 3 打一仗 → 4 看「好汉」页 → 5 看「江湖榜」。
func tutorial_step() -> int:
	if not has_flag("tut_on") or has_flag("tut_done"):
		return 0
	if owned.is_empty():
		return 1
	if team_ids.size() <= 1:
		return 2
	if record["wins"] == 0:
		return 3
	if not has_flag("tut_heroes"):
		return 4
	if not has_flag("tut_jianghu"):
		return 5
	return 0


## 引导里要求看的页面看过了，或者玩家点了「跳过引导」。
func mark_tutorial(flag: String) -> void:
	if tutorial_step() == 0 or has_flag(flag):
		return
	set_flag(flag)
	save_game()


## 清空存档：内存里的进度清掉，存档文件删掉（设置里的「重新开始」）。
func delete_save() -> void:
	reset()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func has_save() -> bool:
	return player_name != "" and origin() != null


func save_game() -> void:
	var team_names: Array[String] = []
	for id in team_ids:
		team_names.append(String(id))
	var data := {
		"version": SAVE_VERSION,
		"name": player_name,
		"origin": String(origin_id),
		"gender": String(gender),
		"realm": realm,
		"xiuwei": xiuwei,
		"command": String(command),
		"team": team_names,
		"flags": flags.keys(),
		"location": String(location_id),
		"level": level,
		"exp": experience,
		"hero_levels": _ids_to_json(hero_levels),
		"hero_exp": _ids_to_json(hero_exp),
		"silver": silver,
		"tokens": tokens,
		"owned": owned.map(func(id: StringName) -> String: return String(id)),
		"souls": _ids_to_json(souls),
		"pulls_since_jia": pulls_since_jia,
		"stars": _ids_to_json(stars),
		"bonds": _ids_to_json(bonds),
		"vitality": _floats_to_json(vitality),
		"medicines": _ids_to_json(medicines),
		"camp": camp,
		"scene": scene_id,
		"level_scale": LEVEL_SCALE,
		"last_camp_done": last_camp_done,
		"yiqi": yiqi,
		"pages": pages,
		"record": record,
		"jobs": jobs,
		"tracked": tracked,
		"city_jobs": city_jobs,
		"jiama": jiama,
		"jiama_shop": jiama_shop,
		"jiama_dai_day": jiama_dai_day,
		"martials": martials.map(func(id: StringName) -> String: return String(id)),
		"martial_main": String(martial_main),
		"martial_side": String(martial_side),
		"martial_levels": _ids_to_json(martial_levels),
		"positions": _cells_to_json(positions),
		"items": items.map(func(it: Dictionary) -> Dictionary: return {"uid": it["uid"], "id": String(it["id"]), "holder": String(it["holder"])}),
		"formation": String(formation),
		"scrolls": scrolls.map(func(sc: Dictionary) -> Dictionary: return {"uid": sc["uid"], "id": String(sc["id"]), "holder": String(sc["holder"])}),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("存档失败：%s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_game() -> void:
	reset()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_warning("存档损坏，已重新开始")
		return
	var data: Dictionary = parsed
	var version: int = data.get("version", 0)
	if version != SAVE_VERSION:
		return
	player_name = data.get("name", "")
	origin_id = StringName(data.get("origin", ""))
	gender = StringName(data.get("gender", String(GENDER_MALE)))
	if not gender in GENDERS:
		gender = GENDER_MALE
	realm = clampi(int(data.get("realm", 0)), 0, Renown.MAX_REALM)
	xiuwei = maxi(0, int(data.get("xiuwei", 0)))
	command = StringName(data.get("command", ""))
	var saved_team: Array = data.get("team", [])
	team_ids.clear()
	for id: String in saved_team:
		team_ids.append(StringName(id))
	var saved_flags: Array = data.get("flags", [])
	for flag: String in saved_flags:
		flags[flag] = true
	var saved_location: String = data.get("location", "")
	if saved_location != "":
		location_id = StringName(saved_location)
	level = data.get("level", 1)
	experience = data.get("exp", 0)
	# 1～30 级时代的旧存档：等级换算过来，经验从头攒
	if int(data.get("level_scale", 30)) != LEVEL_SCALE:
		level = rescale_old_level(level)
		experience = 0
	silver = data.get("silver", 0)
	tokens = data.get("tokens", 0)
	var saved_owned: Array = data.get("owned", saved_team)
	for id: String in saved_owned:
		owned.append(StringName(id))
	# 好汉各自的等级：以前全队共用一个等级的旧存档，已招到的好汉都从统领现在的等级起
	if data.has("hero_levels"):
		var saved_hero_levels: Dictionary = data["hero_levels"]
		for id: String in saved_hero_levels:
			hero_levels[StringName(id)] = clampi(int(saved_hero_levels[id]), 1, MAX_LEVEL)
		var saved_hero_exp: Dictionary = data.get("hero_exp", {})
		for id: String in saved_hero_exp:
			hero_exp[StringName(id)] = maxi(0, int(saved_hero_exp[id]))
	else:
		for id in owned:
			hero_levels[id] = level
	var saved_souls: Dictionary = data.get("souls", {})
	for id: String in saved_souls:
		souls[StringName(id)] = int(saved_souls[id])
	pulls_since_jia = data.get("pulls_since_jia", 0)
	var saved_stars: Dictionary = data.get("stars", {})
	for id: String in saved_stars:
		stars[StringName(id)] = int(saved_stars[id])
	var saved_vitality: Dictionary = data.get("vitality", {})
	for id: String in saved_vitality:
		vitality[StringName(id)] = float(saved_vitality[id])
	camp = data.get("camp", {})
	scene_id = data.get("scene", "")
	last_camp_done = int(data.get("last_camp_done", 0))
	# 老存档里已经下架的药名不认
	var saved_medicines: Dictionary = data.get("medicines", {})
	for id: String in saved_medicines:
		if Vitality.MEDICINES.has(StringName(id)):
			medicines[StringName(id)] = int(saved_medicines[id])
	var saved_bonds: Dictionary = data.get("bonds", {})
	for id: String in saved_bonds:
		bonds[StringName(id)] = int(saved_bonds[id])
	yiqi = data.get("yiqi", 0)
	pages = int(data.get("pages", 0))
	var saved_record: Dictionary = data.get("record", {})
	for key in record:
		record[key] = saved_record.get(key, record[key])
	jobs = data.get("jobs", {})
	tracked = data.get("tracked", {})
	city_jobs = data.get("city_jobs", {})
	jiama = int(data.get("jiama", 0))
	jiama_shop = data.get("jiama_shop", {})
	jiama_dai_day = int(data.get("jiama_dai_day", 0))
	var saved_martials: Array = data.get("martials", [])
	for id: String in saved_martials:
		if GameDB.martials.has(StringName(id)):
			martials.append(StringName(id))
	martial_main = StringName(data.get("martial_main", ""))
	martial_side = StringName(data.get("martial_side", ""))
	if not martial_main in martials:
		martial_main = &""
	if not martial_side in martials:
		martial_side = &""
	# 有武学之前的旧存档：补上出身自带的那门
	_learn_origin_martial()
	var saved_items: Array = data.get("items", [])
	for it: Dictionary in saved_items:
		if GameDB.equipment.has(StringName(it.get("id", ""))):
			var uid := int(it["uid"])
			items.append({"uid": uid, "id": StringName(it["id"]), "holder": StringName(it.get("holder", ""))})
			_next_uid = maxi(_next_uid, uid + 1)
	var saved_formation := StringName(data.get("formation", ""))
	if Formations.ALL.has(saved_formation):
		formation = saved_formation
	var saved_scrolls: Array = data.get("scrolls", [])
	for sc: Dictionary in saved_scrolls:
		if GameDB.mijis.has(StringName(sc.get("id", ""))):
			var uid := int(sc["uid"])
			scrolls.append({"uid": uid, "id": StringName(sc["id"]), "holder": StringName(sc.get("holder", ""))})
			_next_uid = maxi(_next_uid, uid + 1)
	# 副修作废（统领只看主修）
	martial_side = &""
	var saved_levels: Dictionary = data.get("martial_levels", {})
	for id: String in saved_levels:
		if StringName(id) in martials:
			martial_levels[StringName(id)] = clampi(int(saved_levels[id]), 1, MartialData.MAX_LEVEL)
	var saved_positions: Dictionary = data.get("positions", {})
	for id: String in saved_positions:
		var c: Array = saved_positions[id]
		var cell := Vector2i(int(c[0]), int(c[1])) if c.size() == 2 else Grid.NONE
		if Grid.valid(cell):
			positions[StringName(id)] = cell
	# 有名器之前的旧存档：已经打完的列传、揭下的悬赏、开过的宝箱，补发对应的名器
	claim_mingqi()
	# 有秘籍之前就结义了的兄弟：补传秘籍
	for id in owned:
		if sworn(id):
			_teach_miji(id)


func _cells_to_json(values: Dictionary[StringName, Vector2i]) -> Dictionary:
	var out := {}
	for id in values:
		out[String(id)] = [values[id].x, values[id].y]
	return out


func _floats_to_json(values: Dictionary[StringName, float]) -> Dictionary:
	var out := {}
	for id in values:
		out[String(id)] = values[id]
	return out


func _ids_to_json(values: Dictionary[StringName, int]) -> Dictionary:
	var out := {}
	for id in values:
		out[String(id)] = values[id]
	return out

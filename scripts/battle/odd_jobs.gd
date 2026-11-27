class_name OddJobs
## 小悬赏（可以一直做的差事）：每个地区的告示栏上同时贴 3 张「打败 N 拨某种敌人」，
## 不用接，打赢一场里有这种敌人的仗就算一拨；够数了当场发赏，再换一张新的。
## 不按天刷新（设计上不做逼人上线的机制）。

const PER_REGION := 3
const NEED_MIN := 2
const NEED_MAX := 4
const SILVER_PER_KILL := 12
const EXP_PER_KILL := 30
## 每张小悬赏有这么大概率另外给 1 枚聚义令
const TOKEN_CHANCE := 0.35


## 某个地区能遇到的敌人（地区遇敌表 + 属于这个地区的场景里的小怪），去重。
static func enemy_pool(region: StringName) -> Array[UnitData]:
	var loc: LocationData = GameDB.maps[GameState.DEFAULT_MAP].location(region)
	var groups: Array[StageData] = []
	if loc != null:
		groups.append_array(loc.encounter_groups)
	for sd: SceneData in GameDB.scenes.values():
		if sd.region == region:
			groups.append_array(sd.roam_groups)
	var out: Array[UnitData] = []
	var seen: Array[StringName] = []
	for g in groups:
		for e in g.enemies:
			if not e.id in seen:
				seen.append(e.id)
				out.append(e)
	return out


## 这个地区眼下的 3 张小悬赏；不够就补新的。
static func jobs_for(region: StringName) -> Array:
	var jobs: Array = GameState.jobs.get(String(region), [])
	var pool := enemy_pool(region)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while jobs.size() < PER_REGION and not pool.is_empty():
		jobs.append(_make(pool, jobs, rng))
	GameState.jobs[String(region)] = jobs
	return jobs


static func _make(pool: Array[UnitData], existing: Array, rng: RandomNumberGenerator) -> Dictionary:
	# 尽量不和已有的几张重样
	var taken := existing.map(func(j: Dictionary) -> String: return j["enemy"])
	var choices := pool.filter(func(e: UnitData) -> bool: return not String(e.id) in taken)
	if choices.is_empty():
		choices = pool
	var enemy: UnitData = choices[rng.randi_range(0, choices.size() - 1)]
	var need := rng.randi_range(NEED_MIN, NEED_MAX)
	return {
		"enemy": String(enemy.id), "name": enemy.display_name, "need": need, "have": 0,
		"silver": need * SILVER_PER_KILL, "exp": need * EXP_PER_KILL,
		"tokens": 1 if rng.randf() < TOKEN_CHANCE else 0,
	}


## 打赢一场后调用：有这种敌人的小悬赏进度 +1，够数的发赏并换新。返回给玩家看的一句话（没完成的就是空）。
static func on_battle_won(stage: StageData) -> String:
	var ids := stage.enemies.map(func(e: UnitData) -> String: return String(e.id))
	var done := PackedStringArray()
	for region in GameState.jobs.keys():
		var jobs: Array = GameState.jobs[region]
		for i in jobs.size():
			var job: Dictionary = jobs[i]
			if not job["enemy"] in ids:
				continue
			job["have"] += 1
			if job["have"] >= job["need"]:
				var gained := Rewards.grant(job["tokens"], job["silver"], job["exp"])
				GameState.record["odd_jobs"] = int(GameState.record.get("odd_jobs", 0)) + 1
				done.append("小悬赏「打败%s %d 拨」完成：%s" % [job["name"], job["need"], gained])
				jobs[i] = {}
		GameState.jobs[region] = jobs.filter(func(j: Dictionary) -> bool: return not j.is_empty())
		if (GameState.jobs[region] as Array).size() < PER_REGION:
			jobs_for(StringName(region))
	return "　".join(done)


static func describe(job: Dictionary) -> String:
	return "打败%s %d 拨（%d / %d）" % [job["name"], job["need"], job["have"], job["need"]]


static func reward_text(job: Dictionary) -> String:
	var parts := PackedStringArray(["银两 %d" % job["silver"], "经验 %d" % job["exp"]])
	if job["tokens"] > 0:
		parts.append("聚义令 %d" % job["tokens"])
	return "、".join(parts)

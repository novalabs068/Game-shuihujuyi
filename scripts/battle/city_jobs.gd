class_name CityJobs
## 城中悬赏：每个地方的告示栏每天贴一张，必给聚义令。
## 几天不玩就攒着，不过期，最多攒 MAX_STOCK 张（正在做的那张也算），所以不玩也不吃亏、不逼人每天上线。
## 换天按手机的本地日期，离线也照算。
## 一张城中悬赏 = 「在这一带打败 N 拨某种敌人」，不用接，打赢就算（和小悬赏一样）；做完了，攒着的下一张马上贴出来。
##
## 纯规则（不碰 GameState，方便测试）；读写存档的部分在 GameState 的「城中悬赏」一节。
## 存档 GameState.city_jobs：{地区 id: {"day": 上次算到哪天, "stock": 攒着几张, "job": 正在贴的那张（没有就是空）}}

## 每天每个地方贴几张
const PER_DAY := 1
## 最多攒几张（含正在贴的那张）
const MAX_STOCK := 7
## 每张给的聚义令（随机，含两头）
const TOKENS_MIN := 2
const TOKENS_MAX := 3
## 要打几拨
const NEED_MIN := 3
const NEED_MAX := 5
## 银两、经验按打几拨算，是小悬赏的两倍
const SILVER_PER_KILL := 24
const EXP_PER_KILL := 60


## 今天是第几天（本地日期，从 1970-01-01 数）。
static func today() -> int:
	var bias_minutes: int = Time.get_time_zone_from_system().get("bias", 0)
	return int(floor((Time.get_unix_time_from_system() + bias_minutes * 60) / 86400.0))


## 换天：从上次算到的那天到 day，每天多攒 PER_DAY 张，连正在贴的不超过 MAX_STOCK。没来过的地方给一张。纯函数。
static func accrue(entry: Dictionary, day: int) -> Dictionary:
	if entry.is_empty():
		return {"day": day, "stock": PER_DAY, "job": {}}
	var out := entry.duplicate(true)
	var active := 0 if (out.get("job", {}) as Dictionary).is_empty() else 1
	var gained := maxi(0, day - int(out.get("day", day))) * PER_DAY
	out["stock"] = clampi(int(out.get("stock", 0)) + gained, 0, MAX_STOCK - active)
	out["day"] = maxi(day, int(out.get("day", day)))
	return out


## 没在贴的、又攒着的，就贴一张新的（敌人从 pool 里挑）。纯函数。
static func post_next(entry: Dictionary, pool: Array[UnitData], rng: RandomNumberGenerator) -> Dictionary:
	var out := entry.duplicate(true)
	if not (out.get("job", {}) as Dictionary).is_empty() or int(out.get("stock", 0)) <= 0 or pool.is_empty():
		return out
	var enemy: UnitData = pool[rng.randi_range(0, pool.size() - 1)]
	var need := rng.randi_range(NEED_MIN, NEED_MAX)
	out["job"] = {
		"enemy": String(enemy.id), "name": enemy.display_name, "need": need, "have": 0,
		"silver": need * SILVER_PER_KILL, "exp": need * EXP_PER_KILL,
		"tokens": rng.randi_range(TOKENS_MIN, TOKENS_MAX),
	}
	out["stock"] = int(out["stock"]) - 1
	return out


static func reward_text(job: Dictionary) -> String:
	return "聚义令 %d、银两 %d、经验 %d" % [job["tokens"], job["silver"], job["exp"]]

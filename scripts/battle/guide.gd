class_name Guide
## 指引的规则（纯规则，不碰 GameState，方便测试）：从江湖榜的事里挑推荐、算「上梁山」的进度和下一步。
## 地图上怎么显示、追踪哪一条见 GuideTrack。

## 默认追踪的那条叫什么（小印上的字）
const DEFAULT_SEAL := "上梁山"
## 推荐时各种事的先后，越靠前越先推荐（养成不在地图上，不推荐）
const KIND_ORDER: Array[String] = ["列传", "悬赏", "城中悬赏", "擂台", "初到", "支线", "宝箱", "差事"]
## 能涨名望的事（「上梁山」的下一步只从这些里挑；宝箱、初到给聚义令，不涨名望）
const RENOWN_KINDS: Array[String] = ["列传", "悬赏", "城中悬赏", "擂台", "支线", "差事"]
## 推荐的事最多比统领高几级（再高就打不过了）
const LEVEL_SLACK := 3


## 从江湖榜的事里挑最合适的几件：先按种类（列传、悬赏优先），同类里等级离统领最近的先。
## 太难的（比统领高 LEVEL_SLACK 级以上）和没有地点的不挑。
static func recommended(items: Array[Dictionary], count: int, level: int, kinds: Array[String] = KIND_ORDER) -> Array[Dictionary]:
	var fit: Array[Dictionary] = []
	for it in items:
		# 没有地点的（还没招到人的列传预告、养成）不是能马上去做的事，不推荐
		if kinds.has(it["kind"]) and it["location"] != &"" and int(it["level"]) <= level + LEVEL_SLACK:
			fit.append(it)
	fit.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := KIND_ORDER.find(a["kind"])
		var kb := KIND_ORDER.find(b["kind"])
		if ka != kb:
			return ka < kb
		return absi(int(a["level"]) - level) < absi(int(b["level"]) - level))
	return fit.slice(0, count)


## 「上梁山」这一条：境界从哪阶到哪阶、名望进度、下一步做什么。
## 返回 {seal, title, next, progress（0～1）, progress_text, location}。
static func default_info(realm: int, renown: int, todo: Array[Dictionary], level: int) -> Dictionary:
	var info := {"seal": DEFAULT_SEAL, "progress": 1.0, "progress_text": "", "location": &""}
	if realm >= Renown.MAX_REALM:
		info["title"] = "已经「%s」" % Renown.realm_name(realm)
		info["next"] = "江湖上人人都知道你了。去江湖榜的「江湖年表」看看，后面还有什么大事。"
		return info
	var need := Renown.next_threshold(realm)
	info["title"] = "%s → %s" % [Renown.realm_name(realm), Renown.realm_name(realm + 1)]
	info["progress"] = clampf(float(renown) / need, 0.0, 1.0)
	info["progress_text"] = "%d/%d" % [mini(renown, need), need]
	if Renown.can_try(realm, renown):
		info["next"] = "名望够了！去主角页纳「投名状」（对手 %d 级），赢了就升「%s」。" % [Renown.TRIALS[realm][1], Renown.realm_name(realm + 1)]
		return info
	var pick := recommended(todo, 1, level, RENOWN_KINDS)
	if pick.is_empty():
		info["next"] = "再攒 %d 名望：招好汉、揭悬赏、打列传、打头目都涨名望。" % (need - renown)
	else:
		info["next"] = "再攒 %d 名望。眼下合适：%s" % [need - renown, pick[0]["text"]]
		info["location"] = pick[0]["location"]
	return info

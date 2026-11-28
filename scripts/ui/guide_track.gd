class_name GuideTrack
## 地图左上的「指引」：默认追踪「上梁山」（攒名望、纳投名状升境界），也可以在江湖榜上改追踪别的事。
## 游戏没有主线，指引只是提示、不挡路：收起来、不照着做都不影响任何玩法。

## 正在追踪的那一条：追踪的事还在江湖榜上就是它，做完了（或没追踪）就回到「上梁山」。
static func current() -> Dictionary:
	var todo := JiangHuView.todo_items()
	var t := GameState.tracked
	if not t.is_empty():
		for it in todo:
			if it["kind"] == t.get("kind") and it["text"] == t.get("text"):
				return {"seal": it["kind"], "title": it["text"], "next": it["detail"], "progress": -1.0, "progress_text": "", "location": it["location"]}
		GameState.tracked = {}
	return Guide.default_info(GameState.realm, GameState.renown(), todo, GameState.level)


## 某一行是不是正在追踪。
static func is_tracked(item: Dictionary) -> bool:
	return GameState.tracked.get("kind") == item["kind"] and GameState.tracked.get("text") == item["text"]


## 追踪这一行；传空字典 = 回到默认的「上梁山」。
static func track(item: Dictionary) -> void:
	GameState.tracked = {} if item.is_empty() else {"kind": item["kind"], "text": item["text"]}
	GameState.save_game()

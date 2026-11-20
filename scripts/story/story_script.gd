class_name StoryScript
## 列传剧本的解析。一行一句，不用改代码就能加剧情：
##
##   # 注释
##   @bg 背景名            换背景（art/story/<背景名>.jpg 或 .png，没有图时用大地图垫底）
##   @show left 林冲的id   在左边 / 右边站一个人：好汉 id、敌人 id（data/enemies 下的文件名）、me 是主角、none 是清空
##   @battle 关卡名         打一仗（和剧本同目录的 <关卡名>.tres），赢了接着往下演，输了可以重打
##   ? 选项文字 > 标签      连着几行就是一组选项（最多 3 个），选了跳到对应的标签
##   * 标签                跳转的落点
##   @goto 标签            跳到标签
##   林冲：台词            「说话人：台词」；没有冒号的是旁白；「我」是主角；台词里的 {name} 换成主角的名字

## 解析成一串指令：{"op": "say"/"bg"/"show"/"battle"/"choice"/"label"/"goto", ...}
static func parse(text: String) -> Array[Dictionary]:
	var ops: Array[Dictionary] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("@"):
			var parts := line.substr(1).split(" ", false)
			match parts[0]:
				"bg":
					ops.append({"op": "bg", "key": parts[1]})
				"show":
					ops.append({"op": "show", "side": parts[1], "id": parts[2]})
				"battle":
					ops.append({"op": "battle", "stage": parts[1]})
				"goto":
					ops.append({"op": "goto", "label": parts[1]})
				_:
					push_error("剧本里不认识的指令：" + line)
		elif line.begins_with("?"):
			var pair := line.substr(1).split(">")
			var option := {"text": pair[0].strip_edges(), "label": pair[1].strip_edges()}
			if not ops.is_empty() and ops[-1]["op"] == "choice":
				ops[-1]["options"].append(option)
			else:
				ops.append({"op": "choice", "options": [option]})
		elif line.begins_with("*"):
			ops.append({"op": "label", "name": line.substr(1).strip_edges()})
		else:
			var colon := line.find("：")
			if colon > 0 and colon <= 6:
				ops.append({"op": "say", "speaker": line.substr(0, colon), "text": line.substr(colon + 1)})
			else:
				ops.append({"op": "say", "speaker": "", "text": line})
	return ops


static func load_file(path: String) -> Array[Dictionary]:
	return parse(FileAccess.get_file_as_string(path))


## 背景图路径（水墨背景存成 jpg，渐变压色会有色带）；没有图时返回空，用大地图垫底。
static func background_path(key: String) -> String:
	for ext in ["jpg", "png"]:
		var path := "res://art/story/%s.%s" % [key, ext]
		if ResourceLoader.exists(path):
			return path
	return ""


## 标签在第几条指令。
static func find_label(ops: Array[Dictionary], label: String) -> int:
	for i in ops.size():
		if ops[i]["op"] == "label" and ops[i]["name"] == label:
			return i
	return -1

class_name Rewards
## 把奖励加进存档，返回给玩家看的一句话（比如「聚义令 +3　银两 +20」）。

static func grant(tokens: int, silver: int, experience: int, equipment: EquipData = null, medicine := &"", medicine_count := 1) -> String:
	var parts := PackedStringArray()
	if medicine != &"" and Vitality.MEDICINES.has(medicine):
		GameState.medicines[medicine] = GameState.medicines.get(medicine, 0) + medicine_count
		parts.append("%s ×%d" % [Vitality.medicine_name(medicine), medicine_count])
	if equipment != null:
		GameState.add_item(equipment.id)
		parts.append("得到%s「%s」" % [equipment.quality_name(), equipment.display_name])
	if tokens != 0:
		GameState.tokens += tokens
		parts.append("聚义令 %+d" % tokens)
	if silver != 0:
		GameState.silver = maxi(GameState.silver + silver, 0)
		parts.append("银两 %+d" % silver)
	if experience != 0:
		var ups := GameState.add_rewards(experience, 0)
		parts.append("经验 %+d" % experience)
		if ups > 0:
			parts.append("升到 %d 级！" % GameState.level)
	return "　".join(parts)


## 得到一本秘籍，返回给玩家看的一句话。
static func grant_scroll(mj: MijiData) -> String:
	if mj == null:
		return ""
	GameState.add_scroll(mj.id)
	return "得到%s秘籍《%s》" % [mj.quality_name(), mj.display_name]


## 选项能不能选：银两够不够；教武学的选项，已经会了就不能再选。
static func affordable(choice: EventChoice) -> bool:
	if choice.martial != null and choice.martial.id in GameState.martials:
		return false
	return GameState.silver >= choice.cost_silver


## 学一门武学，返回给玩家看的一句话（已经会了返回空）。
static func learn(m: MartialData) -> String:
	if m == null or not GameState.learn_martial(m):
		return ""
	return "学会武学「%s」（在「好汉」页主角那里换主修，或放进秘籍栏）" % m.display_name


## 选了一个不打仗的选项：扣银两、给奖励、设标记，返回奖励说明。
static func apply_choice(choice: EventChoice) -> String:
	GameState.set_flag(choice.flag)
	var parts := PackedStringArray()
	var gained := grant(choice.tokens, choice.silver - choice.cost_silver, choice.experience)
	if gained != "":
		parts.append(gained)
	var learned := learn(choice.martial)
	if learned != "":
		parts.append(learned)
	return "　".join(parts)

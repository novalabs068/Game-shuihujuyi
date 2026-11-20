class_name Rewards
## 把奖励加进存档，返回给玩家看的一句话（比如「聚义令 +3　银两 +20」）。

static func grant(tokens: int, silver: int, experience: int, equipment: EquipData = null) -> String:
	var parts := PackedStringArray()
	if equipment != null:
		GameState.add_item(equipment.id)
		parts.append("得到%s「%s」" % [EquipData.QUALITY_NAMES[equipment.quality], equipment.display_name])
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


## 选项能不能选（银两够不够）。
static func affordable(choice: EventChoice) -> bool:
	return GameState.silver >= choice.cost_silver


## 选了一个不打仗的选项：扣银两、给奖励、设标记，返回奖励说明。
static func apply_choice(choice: EventChoice) -> String:
	GameState.set_flag(choice.flag)
	return grant(choice.tokens, choice.silver - choice.cost_silver, choice.experience)

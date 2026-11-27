class_name Books
## 技能书：按原著的一段故事，用这段故事里每一位好汉的将魂合成（不消耗已经招到的好汉）。
## 故事里人越多书越好：2～3 人良品、4～6 人精品、7 人以上绝品。缺的将魂可以用残页顶。纯规则。

## 每位好汉要几个将魂（按书的品质：凡、良、精、绝）
const SOULS_PER_HERO: Array[int] = [3, 5, 8, 10]
## 残页：宝箱、悬赏、遭遇战、擂台掉，一张顶一个缺的将魂
const CHEST_PAGES := 2
const ENCOUNTER_PAGE_CHANCE := 0.08
## 悬赏按等级给几张（丙、乙、甲）
const BOUNTY_PAGES: Array[int] = [0, 3, 6]


static func souls_per_hero(mj: MijiData) -> int:
	return SOULS_PER_HERO[mj.quality]


## 还缺多少个将魂（每人不够的部分加起来）。souls 是 id → 有几个。
static func missing(mj: MijiData, souls: Dictionary) -> int:
	var need := souls_per_hero(mj)
	var total := 0
	for id in mj.recipe:
		total += maxi(0, need - int(souls.get(id, 0)))
	return total


static func can_craft(mj: MijiData, souls: Dictionary, pages: int) -> bool:
	return mj.is_book() and missing(mj, souls) <= pages


## 「鲁智深 3/10、杨志 10/10……」
static func progress_text(mj: MijiData, souls: Dictionary, name_of: Callable) -> String:
	var need := souls_per_hero(mj)
	var parts := PackedStringArray()
	for id in mj.recipe:
		parts.append("%s %d/%d" % [name_of.call(id), mini(int(souls.get(id, 0)), need), need])
	return "、".join(parts)

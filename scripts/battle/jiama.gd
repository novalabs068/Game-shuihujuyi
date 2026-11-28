class_name Jiama
## 甲马（原著里戴宗拴在腿上作神行法的纸马）：用一张，从大地图上直接去一个去过的地方，不用走野外路。
## 来源：集市每天限买 SHOP_PER_DAY 张；招到戴宗后他每天写 DAI_PER_DAY 张，几天不来就攒着。
## 身上最多带 MAX_CARRY 张（买的、戴宗写的都算），满了就不再攒。换天按手机本地日期（CityJobs.today）。
## 纯规则（不碰 GameState，方便测试）；读写存档的部分在 GameState 的「甲马」一节。

## 身上最多带几张
const MAX_CARRY := 15
## 集市每天限买几张
const SHOP_PER_DAY := 5
## 集市一张多少银两
const PRICE := 30
## 戴宗每天写几张
const DAI_PER_DAY := 5
## 写甲马的好汉
const WRITER := &"dai_zong"


## 戴宗写甲马：从上次算到的那天到 today，每天写 DAI_PER_DAY 张；第一次（last_day = 0）当天就写一份。
## 返回 [新的张数, 算到哪天, 这次多了几张]。身上满了就不多写。
static func dai_write(count: int, last_day: int, today: int) -> Array[int]:
	var days := 1 if last_day <= 0 else maxi(0, today - last_day)
	var after := mini(MAX_CARRY, count + days * DAI_PER_DAY)
	var gained := maxi(0, after - count)
	return [maxi(count, after), maxi(today, last_day), gained]


## 集市今天还能买几张：shop = {"day": 哪天, "bought": 那天买了几张}；也不能超过身上的上限。
static func shop_left(shop: Dictionary, today: int, count: int) -> int:
	var bought := int(shop.get("bought", 0)) if int(shop.get("day", -1)) == today else 0
	return maxi(0, mini(SHOP_PER_DAY - bought, MAX_CARRY - count))

class_name Volumes
## 江湖年表的规则：哪一卷开了、哪一卷还是传闻。纯规则，不碰画面，也不碰 GameState（方便测试）。

## 年表上一卷的状态
enum State { ACTIVE, LOCKED, RUMOR, FAR }

const STATE_NAMES := {
	State.ACTIVE: "正在发生",
	State.LOCKED: "等你扬名",
	State.RUMOR: "尚未发生",
	State.FAR: "远方传闻",
}


## 按统领境界算这一卷的状态：能玩且境界够 → 正在发生；能玩但境界不够 → 等你扬名；
## 还没开发的原著大事 → 尚未发生；外传 → 远方传闻。
static func state_of(vol: VolumeData, realm: int) -> State:
	if vol.status == VolumeData.Status.OPEN:
		return State.ACTIVE if realm >= vol.realm_gate else State.LOCKED
	return State.FAR if vol.status == VolumeData.Status.FAR else State.RUMOR


## 按年表先后排好。
static func sorted(list: Array) -> Array[VolumeData]:
	var out: Array[VolumeData] = []
	for v in list:
		out.append(v as VolumeData)
	out.sort_custom(func(a: VolumeData, b: VolumeData) -> bool: return a.order < b.order)
	return out


## 眼下正在发生的、最靠后的那一卷（年表默认停在这里），一卷都没有返回 null。
static func current(list: Array[VolumeData], realm: int) -> VolumeData:
	var out: VolumeData = null
	for v in list:
		if state_of(v, realm) == State.ACTIVE:
			out = v
	return out

extends RefCounted
## 房间配方：一间屋子“是什么样的地方”。room.gd 按配方从实体库（props.gd）里挑东西、摆放、打光、配声音。
##
## 字段：
##   sizes    适用的房间："big"（15 米见方）/ "small"（5 米见方）
##   weight   被挑中的相对概率
##   dread    不安程度 0～1：血迹多少、灯闪不闪、东西歪不歪、有没有变异
##   tags     实体气质的权重，例如 {"clinical": 3}：带 clinical 标签的实体权重 3
##   focal    屋子正中的焦点实体（可空）
##   rows     沿墙排成一排的实体（可空），例如病房的床
##   hang     墙上挂东西的密度（每段墙几件）
##   floor    地上散放东西的密度（每 10 平方米几件）
##   ceiling  吊顶的实体和数量
##   lining   内衬："plain" 土墙 / "tiles" 瓷砖墙裙和地面
##   light    灯："fluor" 日光灯 / "bulb" 吊灯泡 / "red" 暗红灯 / "oculus" 天光 / "surgical" 手术灯 / "warm" 暖光
##   sound    背景声："buzz" / "hum" / "tick" / "drip" / ""
##   normal   看起来正常的屋子（不加血、不加变异，但总有一处不对劲）

const ALL := [
	{"id": "ward", "sizes": ["big"], "weight": 2.0, "dread": 0.55,
		"tags": {"clinical": 3.0, "domestic": 0.3}, "focal": "", "rows": "bed",
		"hang": 0.3, "floor": 0.4, "ceiling": {"sheet": 2}, "lining": "tiles", "light": "fluor", "sound": "buzz"},
	{"id": "surgery", "sizes": ["big", "small"], "weight": 2.0, "dread": 0.9,
		"tags": {"clinical": 3.0}, "focal": "optable", "rows": "",
		"hang": 0.2, "floor": 0.5, "ceiling": {"chains": 1}, "lining": "tiles", "light": "surgical", "sound": "drip"},
	{"id": "shrine", "sizes": ["big", "small"], "weight": 1.5, "dread": 0.6,
		"tags": {"ritual": 3.0, "cell": 0.5}, "focal": "altar", "rows": "",
		"hang": 0.3, "floor": 0.5, "ceiling": {"chains": 2}, "lining": "plain", "light": "oculus", "sound": "hum"},
	{"id": "clocks", "sizes": ["big", "small"], "weight": 1.2, "dread": 0.35,
		"tags": {"clocks": 4.0, "domestic": 0.5}, "focal": "", "rows": "",
		"hang": 2.2, "floor": 0.15, "ceiling": {}, "lining": "plain", "light": "bulb", "sound": "tick"},
	{"id": "cell", "sizes": ["small", "big"], "weight": 2.5, "dread": 0.85,
		"tags": {"cell": 3.0}, "focal": "", "rows": "",
		"hang": 0.1, "floor": 0.8, "ceiling": {"chains": 2}, "lining": "plain", "light": "red", "sound": "drip"},
	{"id": "storage", "sizes": ["small", "big"], "weight": 1.5, "dread": 0.35,
		"tags": {"storage": 3.0, "clinical": 0.5}, "focal": "", "rows": "",
		"hang": 0.1, "floor": 1.2, "ceiling": {"sheet": 1}, "lining": "plain", "light": "bulb", "sound": ""},
	{"id": "bath", "sizes": ["small", "big"], "weight": 1.2, "dread": 0.75,
		"tags": {"clinical": 1.0}, "focal": "", "rows": "bathtub",
		"hang": 0.3, "floor": 0.3, "ceiling": {}, "lining": "tiles", "light": "fluor", "sound": "drip"},
	{"id": "parlor", "sizes": ["small", "big"], "weight": 1.6, "dread": 0.0, "normal": true,
		"tags": {"domestic": 3.0}, "focal": "table", "rows": "",
		"hang": 0.8, "floor": 0.3, "ceiling": {}, "lining": "plain", "light": "warm", "sound": "tick"},
]


static func pick(rng: RandomNumberGenerator, small: bool) -> Dictionary:
	var size := "small" if small else "big"
	var total := 0.0
	for r: Dictionary in ALL:
		if size in r["sizes"]:
			total += r["weight"]
	var x := rng.randf() * total
	for r: Dictionary in ALL:
		if size in r["sizes"]:
			x -= r["weight"]
			if x <= 0.0:
				return r
	return ALL[0]

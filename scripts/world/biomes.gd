class_name Biomes
extends RefCounted
## 场景（地域）配置。每段路程切换一次地域，按《水浒传》林冲上梁山前后的故事排布。

## 每个地域持续的路程（米）。
const LENGTH := 700.0
## 第一个地域固定为山神庙，之后在其余地域间循环。
const ORDER := ["snow", "forest", "huangni", "jingyang", "liangshan"]

const DATA := {
	"snow": {
		"name": "山神庙",
		"chapter": "第十回  林教头风雪山神庙  陆虞候火烧草料场",
		"sky_top": Color("#2f3b57"), "sky_horizon": Color("#aab6c8"),
		"fog": Color("#bcc6d4"), "fog_begin": 30.0, "fog_end": 100.0,
		"sun": Color("#d6e2ff"), "sun_energy": 0.85,
		"ambient": Color("#93a3bd"), "ambient_energy": 0.9,
		"ground": Color("#e6ecf2"), "road": Color("#7c838d"), "road_line": Color("#5d636c"),
		"curb": Color("#9aa1aa"), "leaf": Color("#355b45"), "trunk": Color("#4a3426"),
		"water": false, "particles": "snow",
		"props": {"pine": 5, "bare_tree": 3, "rock": 2, "lantern": 1, "hut": 1, "temple_wall": 1},
		"high_text": "缉拿要犯", "wall_text": "此路不通",
	},
	"forest": {
		"name": "野猪林",
		"chapter": "第八回  林教头刺配沧州道  鲁智深大闹野猪林",
		"sky_top": Color("#3d5a4c"), "sky_horizon": Color("#9fb79a"),
		"fog": Color("#86a083"), "fog_begin": 22.0, "fog_end": 90.0,
		"sun": Color("#f2f0d0"), "sun_energy": 0.8,
		"ambient": Color("#7d9479"), "ambient_energy": 0.85,
		"ground": Color("#3e5a33"), "road": Color("#6d5a40"), "road_line": Color("#57472f"),
		"curb": Color("#56604a"), "leaf": Color("#24452c"), "trunk": Color("#3b2a1c"),
		"water": false, "particles": "",
		"props": {"pine": 6, "round_tree": 3, "rock": 2, "bush": 3},
		"high_text": "野猪林", "wall_text": "林深莫入",
	},
	"huangni": {
		"name": "黄泥冈",
		"chapter": "第十六回  杨志押送金银担  吴用智取生辰纲",
		"sky_top": Color("#3f7fc4"), "sky_horizon": Color("#f0d8a6"),
		"fog": Color("#e6cd98"), "fog_begin": 35.0, "fog_end": 110.0,
		"sun": Color("#fff0c8"), "sun_energy": 1.1,
		"ambient": Color("#d7b98a"), "ambient_energy": 0.8,
		"ground": Color("#c49450"), "road": Color("#a47a43"), "road_line": Color("#8a6334"),
		"curb": Color("#8c6a3a"), "leaf": Color("#5d7a3a"), "trunk": Color("#5a3d22"),
		"water": false, "particles": "",
		"props": {"pine": 2, "rock": 4, "date_tree": 3, "wine_flag": 1, "hut": 1},
		"high_text": "生辰纲", "wall_text": "此路不通",
	},
	"jingyang": {
		"name": "景阳冈",
		"chapter": "第二十三回  横海郡柴进留宾  景阳冈武松打虎",
		"sky_top": Color("#4f6fa6"), "sky_horizon": Color("#f2c49c"),
		"fog": Color("#d9a888"), "fog_begin": 30.0, "fog_end": 100.0,
		"sun": Color("#ffd2a0"), "sun_energy": 1.0,
		"ambient": Color("#c99b82"), "ambient_energy": 0.85,
		"ground": Color("#8c6b3d"), "road": Color("#8a8070"), "road_line": Color("#6e6556"),
		"curb": Color("#77705f"), "leaf": Color("#c2542b"), "trunk": Color("#4a3020"),
		"water": false, "particles": "leaves",
		"props": {"round_tree": 5, "pine": 2, "rock": 3, "tiger_sign": 1, "wine_flag": 1},
		"high_text": "三碗不过冈", "wall_text": "冈上有虎",
	},
	"liangshan": {
		"name": "水泊梁山",
		"chapter": "第十一回  朱贵水亭施号箭  林冲雪夜上梁山",
		"sky_top": Color("#4f86bd"), "sky_horizon": Color("#cfe3ea"),
		"fog": Color("#b3ced6"), "fog_begin": 35.0, "fog_end": 110.0,
		"sun": Color("#fff6e0"), "sun_energy": 1.0,
		"ambient": Color("#a9c3cc"), "ambient_energy": 0.9,
		"ground": Color("#5e7d48"), "road": Color("#8a5a32"), "road_line": Color("#5c3a1e"),
		"curb": Color("#6b4426"), "leaf": Color("#4f7a3a"), "trunk": Color("#4a3020"),
		"water": true, "water_color": Color("#3f7c8c"), "particles": "",
		"props": {"reeds": 6, "boat": 1, "banner": 2, "stilt_hut": 1},
		"high_text": "替天行道", "wall_text": "",
	},
}


static func id_for_path(path: float) -> String:
	var idx := int(floor(path / LENGTH))
	if idx <= 0:
		return ORDER[0]
	return ORDER[1 + (idx - 1) % (ORDER.size() - 1)]


static func get_data(id: String) -> Dictionary:
	return DATA[id]


## 某地域第一次出现时的路程位置，用于调试 / 截图时直接跳到该地域。
static func first_path_of(id: String) -> float:
	return ORDER.find(id) * LENGTH

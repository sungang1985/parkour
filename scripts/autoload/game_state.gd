extends Node
## 全局状态（自动加载）：存档、好汉数据、字体与输入映射。

signal coins_changed(total: int)
signal hero_changed(hero_id: String)

const DEFAULT_SAVE_PATH := "user://save.cfg"

## 可选好汉。数值只做轻度差异化，人人都能跑完全程。
const HEROES := [
	{
		"id": "linchong", "name": "林冲", "title": "豹子头", "cost": 0,
		"desc": "八十万禁军枪棒教头。风雪山神庙一夜，被逼上梁山。",
		"perk": "身手均衡，无特殊加成",
		"robe": Color("#22304f"), "trim": Color("#c9a04a"), "pants": Color("#1b1b22"),
		"skin": Color("#e9c39b"), "hair": Color("#151212"),
		"hat": "futou", "weapon": "spear", "bulk": 1.0, "beard": true,
		"jump_mult": 1.0, "magnet_mult": 1.0, "boost_mult": 1.0,
		"start_shield": false, "break_jars": false,
	},
	{
		"id": "wusong", "name": "武松", "title": "行者", "cost": 600,
		"desc": "景阳冈上三拳打死吊睛白额大虫的打虎英雄。",
		"perk": "开局自带护心镜",
		"robe": Color("#3a2a20"), "trim": Color("#d8b25a"), "pants": Color("#211814"),
		"skin": Color("#dcae84"), "hair": Color("#120f0e"),
		"hat": "hoop", "weapon": "blades", "bulk": 1.05,
		"jump_mult": 1.0, "magnet_mult": 1.0, "boost_mult": 1.0,
		"start_shield": true, "break_jars": false,
	},
	{
		"id": "luzhishen", "name": "鲁智深", "title": "花和尚", "cost": 1500,
		"desc": "倒拔垂杨柳、大闹野猪林，一条禅杖护得兄弟周全。",
		"perk": "撞碎酒坛不会绊倒",
		"robe": Color("#b5651d"), "trim": Color("#7a2e12"), "pants": Color("#4a2d18"),
		"skin": Color("#e0b088"), "hair": Color("#e0b088"),
		"hat": "bald", "weapon": "staff", "bulk": 1.2,
		"jump_mult": 1.0, "magnet_mult": 1.0, "boost_mult": 1.0,
		"start_shield": false, "break_jars": true,
	},
	{
		"id": "yanqing", "name": "燕青", "title": "浪子", "cost": 2500,
		"desc": "身手轻捷、相扑天下无对的风流浪子。",
		"perk": "跳得更高，聚宝盆持续更久",
		"robe": Color("#e8e4da"), "trim": Color("#3d7ea6"), "pants": Color("#2e3c4a"),
		"skin": Color("#f0cfae"), "hair": Color("#151212"),
		"hat": "bun", "weapon": "none", "bulk": 0.95,
		"jump_mult": 1.15, "magnet_mult": 1.6, "boost_mult": 1.0,
		"start_shield": false, "break_jars": false,
	},
	{
		"id": "daizong", "name": "戴宗", "title": "神行太保", "cost": 4000,
		"desc": "腿绑甲马、日行八百里的神行太保。",
		"perk": "神行甲马持续时间翻倍",
		"robe": Color("#4d6b3c"), "trim": Color("#e3c04c"), "pants": Color("#2a3322"),
		"skin": Color("#e3b991"), "hair": Color("#151212"),
		"hat": "futou", "weapon": "none", "bulk": 1.0, "talismans": true,
		"jump_mult": 1.0, "magnet_mult": 1.0, "boost_mult": 2.0,
		"start_shield": false, "break_jars": false,
	},
]

var save_path := DEFAULT_SAVE_PATH
var best_score := 0
var best_distance := 0
var total_coins := 0
var total_runs := 0
var unlocked: Array[String] = ["linchong"]
var selected_hero := "linchong"
var music_on := true
var sfx_on := true

var font_title: Font
var font_body: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input_map()
	font_title = load("res://assets/fonts/MaShanZheng-Subset.ttf")
	font_body = load("res://assets/fonts/NotoSansSC-Subset.ttf")
	font_title.fallbacks = [font_body]
	load_game()


func _setup_input_map() -> void:
	var map := {
		"move_left": [KEY_LEFT, KEY_A],
		"move_right": [KEY_RIGHT, KEY_D],
		"jump": [KEY_UP, KEY_W, KEY_SPACE],
		"slide": [KEY_DOWN, KEY_S],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action: String in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func hero_data(id: String) -> Dictionary:
	for h: Dictionary in HEROES:
		if h["id"] == id:
			return h
	return HEROES[0]


func hero_index(id: String) -> int:
	for i in HEROES.size():
		if HEROES[i]["id"] == id:
			return i
	return 0


func current_hero() -> Dictionary:
	return hero_data(selected_hero)


func is_unlocked(id: String) -> bool:
	return id in unlocked


func select_hero(id: String) -> void:
	if is_unlocked(id) and id != selected_hero:
		selected_hero = id
		save_game()
		hero_changed.emit(id)


## 用铜钱解锁好汉，成功后自动出战。
func try_unlock(id: String) -> bool:
	if is_unlocked(id):
		return true
	var cost: int = hero_data(id)["cost"]
	if total_coins < cost:
		return false
	total_coins -= cost
	unlocked.append(id)
	coins_changed.emit(total_coins)
	select_hero(id)
	save_game()
	return true


func spend_coins(amount: int) -> bool:
	if amount > total_coins:
		return false
	total_coins -= amount
	coins_changed.emit(total_coins)
	save_game()
	return true


## 结算一局，返回是否刷新最高分。续命后再次结算时 count_run 为 false。
func submit_run(score: int, distance: int, coins: int, count_run := true) -> bool:
	if count_run:
		total_runs += 1
	total_coins += coins
	var record := score > best_score
	best_score = maxi(best_score, score)
	best_distance = maxi(best_distance, distance)
	coins_changed.emit(total_coins)
	save_game()
	return record


func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "best_score", best_score)
	cfg.set_value("progress", "best_distance", best_distance)
	cfg.set_value("progress", "total_coins", total_coins)
	cfg.set_value("progress", "total_runs", total_runs)
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "selected_hero", selected_hero)
	cfg.set_value("settings", "music_on", music_on)
	cfg.set_value("settings", "sfx_on", sfx_on)
	cfg.save(save_path)


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	best_score = cfg.get_value("progress", "best_score", 0)
	best_distance = cfg.get_value("progress", "best_distance", 0)
	total_coins = cfg.get_value("progress", "total_coins", 0)
	total_runs = cfg.get_value("progress", "total_runs", 0)
	unlocked.clear()
	for id in cfg.get_value("progress", "unlocked", ["linchong"]):
		unlocked.append(str(id))
	if not "linchong" in unlocked:
		unlocked.append("linchong")
	selected_hero = cfg.get_value("progress", "selected_hero", "linchong")
	if not is_unlocked(selected_hero):
		selected_hero = "linchong"
	music_on = cfg.get_value("settings", "music_on", true)
	sfx_on = cfg.get_value("settings", "sfx_on", true)


## 测试用：重置为全新存档（不写盘）。
func reset_progress() -> void:
	best_score = 0
	best_distance = 0
	total_coins = 0
	total_runs = 0
	unlocked = ["linchong"]
	selected_hero = "linchong"

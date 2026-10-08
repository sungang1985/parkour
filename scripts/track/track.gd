class_name Track
extends Node3D
## 无尽赛道生成器。
##
## 赛道由 12 米一段的直路和路口拼成。玩家只会朝 北 / 东 / 西 三个方向跑（永不向南），
## 向北时遇到 T 字路口（左右都可转），向东 / 西时遇到 L 形弯（只能转回北），
## 因此赛道永远不会和自己相交。生成器最多生成到下一个路口为止，
## 玩家转弯后才继续向所选方向生成；路口两侧先放两段无障碍的“预览路”。

signal biome_changed(id: String)

const CHUNK_LEN := 12.0
const JUNCTION := ChunkBuilder.ROAD_W
const SPAWN_AHEAD := 140.0
const KEEP_BEHIND := 30.0
const STUB_CHUNKS := 2
const SAFE_START := 40.0
const BASE_SPEED := 11.0
const MAX_SPEED := 27.0

var rng := RandomNumberGenerator.new()
## 调试：只影响地域选择的路程偏移，可直接从某个地域开跑。
var biome_offset := 0.0

var cursor := Vector3.ZERO
var heading := 0
var gen_path := 0.0
var leg_left := 0
var blocked := false
var safe_until := 0.0
var last_hazard_path := -100.0
var last_power_path := 0.0
var coin_lane := 1
var serial := 0
var current_biome := ""
var player_path := 0.0

## 已生成的节点：{node, end_path}，按路程排序。
var chunks: Array[Dictionary] = []
## 尚未通过的路口：{id, center, heading, allowed, path_center, stubs, node}
var junctions: Array[Dictionary] = []
## 前方障碍登记表（供自动驾驶 / 续命清场使用）：{path, lane, kind, node, junction_id}
var hazards: Array[Dictionary] = []


static func dir_of(h: int) -> Vector3:
	match posmod(h, 4):
		0:
			return Vector3(0, 0, -1)
		1:
			return Vector3(1, 0, 0)
		2:
			return Vector3(0, 0, 1)
		_:
			return Vector3(-1, 0, 0)


static func yaw_of(h: int) -> float:
	return -h * PI * 0.5


## 速度随路程平滑上升，约 4 公里后接近上限。
static func speed_at(path: float) -> float:
	return BASE_SPEED + (MAX_SPEED - BASE_SPEED) * (1.0 - exp(-maxf(path, 0.0) / 2200.0))


static func difficulty(path: float) -> float:
	return clampf(path / 2500.0, 0.0, 1.0)


func biome_id_at(path: float) -> String:
	return Biomes.id_for_path(path + biome_offset)


func reset(seed_value := -1) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	cursor = Vector3.ZERO
	heading = 0
	gen_path = 0.0
	leg_left = 7
	blocked = false
	safe_until = SAFE_START
	last_hazard_path = -100.0
	last_power_path = 0.0
	coin_lane = 1
	serial = 0
	current_biome = ""
	player_path = 0.0
	chunks.clear()
	junctions.clear()
	hazards.clear()
	var start := Node3D.new()
	start.name = "Start"
	add_child(start)
	ChunkBuilder.build_start(start, Biomes.get_data(biome_id_at(0.0)))
	chunks.append({"node": start, "end_path": 0.0})
	update(0.0)


func update(p_player_path: float) -> void:
	player_path = p_player_path
	var bid := biome_id_at(player_path)
	if bid != current_biome:
		current_biome = bid
		biome_changed.emit(bid)
	while not blocked and gen_path - player_path < SPAWN_AHEAD:
		if leg_left > 0:
			_spawn_straight(leg_left == 1)
			leg_left -= 1
		else:
			_spawn_junction()
	while chunks.size() > 1 and chunks[0]["end_path"] < player_path - KEEP_BEHIND:
		var c: Dictionary = chunks.pop_front()
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	while not hazards.is_empty() and (hazards[0]["path"] < player_path - 4.0 or not is_instance_valid(hazards[0]["node"])):
		hazards.pop_front()


func next_junction() -> Dictionary:
	return junctions[0] if not junctions.is_empty() else {}


## 玩家在路口转向 t（-1 左 / 1 右）后调用：删掉另一侧预览路，继续沿新方向生成。
func on_player_turned(j: Dictionary, t: int) -> void:
	var stubs: Dictionary = j["stubs"]
	for k: int in stubs:
		if k != t and is_instance_valid(stubs[k]["node"]):
			stubs[k]["node"].queue_free()
	var stub: Dictionary = stubs[t]
	var stub_end_path: float = j["path_center"] + JUNCTION * 0.5 + STUB_CHUNKS * CHUNK_LEN
	chunks.append({"node": stub["node"], "end_path": stub_end_path})
	var jid: int = j["id"]
	hazards = hazards.filter(func(h: Dictionary) -> bool: return h.get("junction_id", -1) != jid)
	junctions.erase(j)
	cursor = stub["end"]
	heading = stub["heading"]
	gen_path = stub_end_path
	leg_left = rng.randi_range(5, 9) if heading == 0 else rng.randi_range(3, 6)
	safe_until = gen_path
	blocked = false
	update(player_path)


## 续命：清掉玩家前方一段路上的障碍。
func clear_hazards_ahead(from_path: float, dist: float) -> void:
	for h: Dictionary in hazards:
		if h["kind"] == Obstacle.Kind.WALL:
			continue
		if h["path"] >= from_path - 2.0 and h["path"] <= from_path + dist and is_instance_valid(h["node"]):
			h["node"].smash()


# ---------------------------------------------------------------- 生成

func _new_node(pos: Vector3, h: int) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw_of(h)
	add_child(n)
	return n


func _spawn_straight(last_of_leg: bool) -> void:
	var bid := biome_id_at(gen_path + CHUNK_LEN * 0.5)
	var b := Biomes.get_data(bid)
	var node := _new_node(cursor, heading)
	var rows := _plan_rows(last_of_leg)
	var gaps: Array = []
	for r: Dictionary in rows:
		if r["full"] and r["lanes"][0] == Obstacle.Kind.GAP:
			gaps.append(r["d"])
	ChunkBuilder.build_road(node, b, CHUNK_LEN, gaps, rng, serial)
	if gen_path > 0.0 and biome_id_at(gen_path - CHUNK_LEN * 0.5) != bid:
		Props.archway(node, Vector3(0, 0, -1.0), 0.0, ChunkBuilder.ROAD_W + 1.2, b["name"])
	for r: Dictionary in rows:
		if r["full"]:
			_make_obstacle(node, b, r["lanes"][0], -1, r["d"])
		else:
			for lane in 3:
				if r["lanes"][lane] >= 0:
					_make_obstacle(node, b, r["lanes"][lane], lane, r["d"])
	_place_coins(node, rows)
	_maybe_powerup(node, rows)
	chunks.append({"node": node, "end_path": gen_path + CHUNK_LEN})
	cursor += dir_of(heading) * CHUNK_LEN
	gen_path += CHUNK_LEN
	serial += 1


func _spawn_junction() -> void:
	var b := Biomes.get_data(biome_id_at(gen_path))
	var node := _new_node(cursor, heading)
	var allowed: Array = []
	match heading:
		0:
			allowed = [-1, 1]
		1:
			allowed = [-1]
		_:
			allowed = [1]
	ChunkBuilder.build_junction(node, b, allowed, serial)
	var center := cursor + dir_of(heading) * JUNCTION * 0.5
	var path_center := gen_path + JUNCTION * 0.5
	var jid := serial
	var wall := Obstacle.new()
	wall.position = Vector3(0, 0, -JUNCTION - 0.6)
	node.add_child(wall)
	wall.setup(Obstacle.Kind.WALL, -1, Vector3(JUNCTION + 2.0, 4.0, 1.0), Vector3(0, 1.5, 0))
	hazards.append({"path": gen_path + JUNCTION + 0.1, "lane": -1, "kind": Obstacle.Kind.WALL,
		"node": wall, "junction_id": jid})
	var stubs := {}
	var stub_biome := Biomes.get_data(biome_id_at(path_center + JUNCTION))
	for t: int in allowed:
		var h2 := posmod(heading + t, 4)
		var start := center + dir_of(h2) * JUNCTION * 0.5
		var stub := _new_node(start, h2)
		for i in STUB_CHUNKS:
			var seg := Node3D.new()
			seg.position = Vector3(0, 0, -i * CHUNK_LEN)
			stub.add_child(seg)
			ChunkBuilder.build_road(seg, stub_biome, CHUNK_LEN, [], rng, serial + 1 + i)
		_coin_line(stub, 1, CHUNK_LEN + 1.5, CHUNK_LEN * 2.0 - 1.0)
		stubs[t] = {"node": stub, "end": start + dir_of(h2) * STUB_CHUNKS * CHUNK_LEN, "heading": h2}
	junctions.append({"id": jid, "center": center, "heading": heading, "allowed": allowed,
		"path_center": path_center, "stubs": stubs, "node": node})
	chunks.append({"node": node, "end_path": path_center + JUNCTION * 0.5})
	gen_path = path_center + JUNCTION * 0.5
	blocked = true
	serial += 3


## 规划本段的障碍行。每段有两个槽位（距段首 3 米、9 米），间距随速度拉开。
func _plan_rows(last_of_leg: bool) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if last_of_leg:
		return rows  # 路口前留出转弯的空间
	for d: float in [3.0, 9.0]:
		var p: float = gen_path + d
		if p < safe_until:
			continue
		var spd := speed_at(p)
		if p - last_hazard_path < maxf(11.0, spd * 0.95):
			continue
		if rng.randf() > lerpf(0.5, 0.85, difficulty(p)):
			continue
		var row := _pick_row(p)
		row["d"] = d
		rows.append(row)
		last_hazard_path = p
	return rows


func _pick_row(p: float) -> Dictionary:
	var diff := difficulty(p)
	var weights := {
		"low": 3.0, "high": 3.0, "block1": 3.0, "jars": 2.0,
		"gap": 2.0 if p > 150.0 else 0.0,
		"block2": lerpf(0.8, 3.5, diff) if p > 100.0 else 0.0,
		"mixed": lerpf(0.5, 4.0, diff) if p > 300.0 else 0.0,
	}
	var K := Obstacle.Kind
	var lanes := [-1, -1, -1]
	match ChunkBuilder._pick(weights, rng):
		"low":
			return {"full": true, "lanes": [K.LOW, K.LOW, K.LOW]}
		"high":
			return {"full": true, "lanes": [K.HIGH, K.HIGH, K.HIGH]}
		"gap":
			return {"full": true, "lanes": [K.GAP, K.GAP, K.GAP]}
		"block1":
			lanes[rng.randi_range(0, 2)] = K.BLOCK
		"block2":
			lanes = [K.BLOCK, K.BLOCK, K.BLOCK]
			lanes[rng.randi_range(0, 2)] = -1
		"jars":
			lanes[rng.randi_range(0, 2)] = K.JARS
			if rng.randf() < 0.4:
				lanes[rng.randi_range(0, 2)] = K.JARS
		"mixed":
			var pool := [K.LOW, K.HIGH, K.BLOCK, K.JARS]
			for i in 3:
				lanes[i] = pool[rng.randi_range(0, pool.size() - 1)]
			if lanes.count(K.BLOCK) >= 2:
				var open := rng.randi_range(0, 2)
				lanes[open] = [K.LOW, K.HIGH][rng.randi_range(0, 1)]
	return {"full": false, "lanes": lanes}


func _make_obstacle(node: Node3D, b: Dictionary, kind: int, lane: int, d: float) -> void:
	var o := Obstacle.new()
	var width := ChunkBuilder.ROAD_W if lane < 0 else ChunkBuilder.LANE_W - 0.2
	o.position = Vector3(0.0 if lane < 0 else ChunkBuilder.lane_x(lane), 0, -d)
	node.add_child(o)
	match kind:
		Obstacle.Kind.LOW:
			o.setup(kind, lane, Vector3(width, 0.9, 0.7), Vector3(0, 0.45, 0))
			if b["name"] == "野猪林" and rng.randf() < 0.6:
				Props.fallen_log(o, width, b["trunk"])
			else:
				Props.barricade(o, width)
		Obstacle.Kind.HIGH:
			o.setup(kind, lane, Vector3(width, 1.3, 0.5), Vector3(0, 1.8, 0))
			var text: String = b["high_text"] if lane < 0 else String(b["high_text"]).left(2)
			Props.banner_gate(o, width, text, Color("#7a1f18") if b["name"] != "水泊梁山" else Color("#b8862e"))
		Obstacle.Kind.BLOCK:
			o.setup(kind, lane, Vector3(width - 0.1, 3.2, 2.2), Vector3(0, 1.6, 0))
			match b["name"]:
				"黄泥冈", "水泊梁山":
					Props.cart(o)
				"野猪林", "景阳冈":
					if rng.randf() < 0.5:
						Props.boulder(o, Color("#7d776c"))
					else:
						Props.shield_guard(o)
				_:
					Props.shield_guard(o)
		Obstacle.Kind.GAP:
			o.setup(kind, -1, Vector3(ChunkBuilder.ROAD_W, 0.7, ChunkBuilder.GAP_LEN - 0.6), Vector3(0, -0.2, 0))
		Obstacle.Kind.JARS:
			o.setup(kind, lane, Vector3(width - 0.3, 0.8, 0.8), Vector3(0, 0.4, 0))
			Props.jars(o, width)
	hazards.append({"path": gen_path + d, "lane": lane, "kind": kind, "node": o})


func _make_pickup(node: Node3D, kind: String, pos: Vector3) -> void:
	var pk := Pickup.new()
	pk.position = pos
	node.add_child(pk)
	pk.setup(kind)


func _coin_line(node: Node3D, lane: int, from_d: float, to_d: float) -> void:
	var d := from_d
	while d <= to_d:
		_make_pickup(node, "coin", Vector3(ChunkBuilder.lane_x(lane), 0.7, -d))
		d += 1.5


## 铜钱沿一条道排布；遇到障碍时绕开（镖车）或拱成弧线（拒马 / 断路 / 酒坛）或压低（横幅）。
func _place_coins(node: Node3D, rows: Array[Dictionary]) -> void:
	if rng.randf() > 0.65:
		return
	var K := Obstacle.Kind
	var blocked_lanes := []
	for r: Dictionary in rows:
		for lane in 3:
			if r["lanes"][lane] == K.BLOCK:
				blocked_lanes.append(lane)
	if coin_lane in blocked_lanes or rng.randf() < 0.25:
		var options := [0, 1, 2].filter(func(l: int) -> bool: return not l in blocked_lanes)
		if options.is_empty():
			return
		coin_lane = options[rng.randi_range(0, options.size() - 1)]
	var x := ChunkBuilder.lane_x(coin_lane)
	var d := 0.75
	while d < CHUNK_LEN:
		var y := 0.7
		var skip := false
		for r: Dictionary in rows:
			var k: int = r["lanes"][coin_lane]
			var dz := absf(d - r["d"])
			if k == K.BLOCK and dz < 2.2:
				skip = true
			elif (k == K.LOW or k == K.GAP or k == K.JARS) and dz < 2.8:
				y = 0.7 + 1.1 * (1.0 - pow(dz / 2.8, 2.0))
			elif k == K.HIGH and dz < 1.2:
				y = 0.45
		if not skip and gen_path + d > 8.0:  # 出生点正前方留空，主菜单画面更干净
			_make_pickup(node, "coin", Vector3(x, y, -d))
		d += 1.5


func _maybe_powerup(node: Node3D, rows: Array[Dictionary]) -> void:
	var p := gen_path + 6.0
	if p < 120.0 or p - last_power_path < 160.0 or rng.randf() > 0.1:
		return
	var free := []
	for lane in 3:
		if lane == coin_lane:
			continue
		var ok := true
		for r: Dictionary in rows:
			if r["lanes"][lane] >= 0 and absf(r["d"] - 6.0) < 2.5:
				ok = false
		if ok:
			free.append(lane)
	if free.is_empty():
		return
	var kind := ChunkBuilder._pick({"boost": 2.0, "shield": 2.0, "magnet": 3.0, "double": 2.0}, rng)
	_make_pickup(node, kind, Vector3(ChunkBuilder.lane_x(free[rng.randi_range(0, free.size() - 1)]), 1.1, -6.0))
	last_power_path = p

class_name ChunkBuilder
extends RefCounted
## 赛道几何：路面、路肩、地面 / 水面、路边装饰、路口与起点山神庙。
## 坐标约定同 Props：局部 -Z 为前进方向，路面中心线在 x = 0，路面顶面 y = 0。

const LANE_W := 2.5
const ROAD_W := 7.5
const HALF_W := 3.75
const GAP_LEN := 3.0


static func lane_x(lane: int) -> float:
	return (lane - 1) * LANE_W


## 一段直路。gaps 为断路中心距本段起点的距离列表。
static func build_road(node: Node3D, b: Dictionary, length: float, gaps: Array,
		rng: RandomNumberGenerator, serial: int, decorate := true) -> void:
	var water: bool = b["water"]
	var segs: Array = []
	var start := 0.0
	var sorted_gaps := gaps.duplicate()
	sorted_gaps.sort()
	for g: float in sorted_gaps:
		segs.append(Vector2(start, g - GAP_LEN * 0.5))
		start = g + GAP_LEN * 0.5
	segs.append(Vector2(start, length))
	for s: Vector2 in segs:
		var seg_len := s.y - s.x
		if seg_len <= 0.01:
			continue
		var zc := -(s.x + s.y) * 0.5
		if water:
			Props.part(node, "box", Vector3(ROAD_W, 0.2, seg_len), Vector3(0, -0.1, zc), b["road"])
		else:
			Props.part(node, "box", Vector3(ROAD_W, 0.5, seg_len), Vector3(0, -0.25, zc), b["road"])

	# 石板缝 / 木板缝：给速度感一个参照。
	var step := 2.0 if water else 3.0
	var d := step
	while d < length - 0.01:
		var in_gap := false
		for g: float in gaps:
			if absf(d - g) < GAP_LEN * 0.5 + 0.1:
				in_gap = true
		if not in_gap:
			Props.part(node, "box", Vector3(ROAD_W - 0.1, 0.02, 0.09), Vector3(0, 0.005, -d), b["road_line"])
		d += step

	var ground_y := -0.32 - (serial % 5) * 0.004
	if water:
		Props.water(node, Vector3(130.0, 0.2, length), Vector3(0, -0.85, -length * 0.5), b["water_color"])
		for side: float in [-1.0, 1.0]:
			for pd: float in [1.5, 7.5]:
				Props.part(node, "cyl", Vector3(0.28, 1.6, 0.28), Vector3(side * (HALF_W - 0.1), -0.7, -pd), Props.DARK_WOOD)
				Props.part(node, "box", Vector3(0.14, 0.55, 0.14), Vector3(side * (HALF_W + 0.05), 0.27, -pd), Props.DARK_WOOD)
			Props.part(node, "box", Vector3(0.08, 0.08, length), Vector3(side * (HALF_W + 0.05), 0.5, -length * 0.5), Color("#c9b48a"))
	else:
		for side: float in [-1.0, 1.0]:
			Props.part(node, "box", Vector3(0.35, 0.3, length), Vector3(side * (HALF_W + 0.17), 0.05, -length * 0.5), b["curb"])
			Props.part(node, "box", Vector3(60.0, 0.4, length), Vector3(side * (HALF_W + 30.3), ground_y, -length * 0.5), b["ground"])
		for g: float in gaps:
			Props.part(node, "box", Vector3(ROAD_W, 3.0, GAP_LEN), Vector3(0, -2.0, -g), Color("#17110c"))

	if decorate:
		_decorate(node, b, length, rng)


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in weights:
		total += weights[k]
	var r := rng.randf() * total
	for k: String in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[0]


static func _decorate(node: Node3D, b: Dictionary, length: float, rng: RandomNumberGenerator) -> void:
	for side: float in [-1.0, 1.0]:
		var d := rng.randf_range(3.0, 5.0)
		while d < length - 2.5:
			place_prop(node, _pick(b["props"], rng), b, side, d, rng)
			d += rng.randf_range(4.0, 7.0)
		# 远景层：大树 / 远山，增加纵深。
		if rng.randf() < 0.6:
			var far_d := rng.randf_range(3.0, length - 2.5)
			var far_x := side * (HALF_W + rng.randf_range(13.0, 24.0))
			if b["water"]:
				Props.reeds(node, Vector3(far_x, -0.7, -far_d), 1.6)
			elif b["props"].has("pine"):
				Props.pine(node, Vector3(far_x, 0, -far_d), rng.randf_range(1.6, 2.4), b["leaf"].darkened(0.15), b["trunk"], b["particles"] == "snow")
			else:
				Props.round_tree(node, Vector3(far_x, 0, -far_d), rng.randf_range(1.5, 2.2), b["leaf"].darkened(0.1), b["trunk"])


static func place_prop(node: Node3D, kind: String, b: Dictionary, side: float, d: float, rng: RandomNumberGenerator) -> void:
	var snowy: bool = b["particles"] == "snow"
	var near := Vector3(side * (HALF_W + rng.randf_range(2.4, 9.0)), 0, -d)
	match kind:
		"pine":
			Props.pine(node, near, rng.randf_range(0.8, 1.4), b["leaf"], b["trunk"], snowy)
		"round_tree":
			Props.round_tree(node, near, rng.randf_range(0.8, 1.3), b["leaf"], b["trunk"])
		"date_tree":
			Props.date_tree(node, near, rng.randf_range(0.8, 1.2), b["leaf"], b["trunk"])
		"bare_tree":
			Props.bare_tree(node, near, rng.randf_range(0.8, 1.2), b["trunk"])
		"rock":
			Props.rock(node, near, rng.randf_range(0.6, 1.5), b["curb"].darkened(0.15))
		"bush":
			Props.bush(node, near, rng.randf_range(0.7, 1.2), b["leaf"].lightened(0.08))
		"lantern":
			Props.lantern(node, Vector3(side * (HALF_W + 1.0), 0, -d))
		"hut":
			Props.hut(node, Vector3(side * (HALF_W + rng.randf_range(5.5, 9.0)), 0, -d), -side * PI * 0.5, snowy)
		"temple_wall":
			Props.temple_wall(node, Vector3(side * (HALF_W + 2.2), 0, -d), PI * 0.5, 5.0)
		"wine_flag":
			var text := "三碗不过冈" if b["name"] == "景阳冈" else "酒"
			Props.wine_flag(node, Vector3(side * (HALF_W + 1.3), 0, -d), -side * 0.45, text)
		"tiger_sign":
			Props.sign_board(node, Vector3(side * (HALF_W + 1.4), 0, -d), -side * 0.5, "冈上有虎")
		"reeds":
			Props.reeds(node, Vector3(side * (HALF_W + rng.randf_range(0.9, 8.0)), -0.7, -d), rng.randf_range(0.9, 1.4))
		"boat":
			Props.boat(node, Vector3(side * (HALF_W + rng.randf_range(4.0, 10.0)), -0.65, -d), rng.randf() * TAU)
		"banner":
			Props.banner(node, Vector3(side * (HALF_W + 0.9), -0.7, -d), -side * 0.45)
		"stilt_hut":
			Props.stilt_hut(node, Vector3(side * (HALF_W + rng.randf_range(7.0, 11.0)), -0.7, -d), -side * PI * 0.5)


## 路口平台。allowed 为可转方向（-1 左 / 1 右），其余方向用墙或水面封住。
static func build_junction(node: Node3D, b: Dictionary, allowed: Array, serial: int) -> void:
	var water: bool = b["water"]
	var zc := -HALF_W
	if water:
		Props.part(node, "box", Vector3(ROAD_W, 0.2, ROAD_W), Vector3(0, -0.1, zc), b["road"])
		Props.water(node, Vector3(130.0, 0.2, 130.0), Vector3(0, -0.86, zc), b["water_color"])
		for x: float in [-2.5, 0.0, 2.5]:
			Props.part(node, "cyl", Vector3(0.3, 1.6, 0.3), Vector3(x, -0.2, -ROAD_W - 0.4), Props.DARK_WOOD)
		Props.boat(node, Vector3(1.5, -0.65, -ROAD_W - 4.0), 1.2)
	else:
		Props.part(node, "box", Vector3(ROAD_W, 0.5, ROAD_W), Vector3(0, -0.25, zc), b["road"])
		Props.part(node, "box", Vector3(130.0, 0.4, 130.0), Vector3(0, -0.34 - (serial % 5) * 0.004, zc), b["ground"])
		Props.temple_wall(node, Vector3(0, 0, -ROAD_W - 0.9), 0.0, ROAD_W + 3.0)
		Props.label(node, b["wall_text"], Vector3(0, 1.3, -ROAD_W - 0.55), 96, Color("#f3e3c3"), Color(0, 0, 0, 0.6))
	for side: int in [-1, 1]:
		if not side in allowed:
			if water:
				for pz: float in [-1.5, -4.0, -6.5]:
					Props.part(node, "cyl", Vector3(0.3, 1.6, 0.3), Vector3(side * (HALF_W + 0.3), -0.2, pz), Props.DARK_WOOD)
			else:
				Props.temple_wall(node, Vector3(side * (HALF_W + 0.9), 0, zc), PI * 0.5, ROAD_W + 1.8)
	Props.lantern(node, Vector3(-(HALF_W + 1.0), 0, 0.6))
	Props.lantern(node, Vector3(HALF_W + 1.0, 0, 0.6))


## 起点：被大火吞没的草料场与山神庙（位于出发点身后）。
static func build_start(node: Node3D, b: Dictionary) -> void:
	var length := 26.0
	Props.part(node, "box", Vector3(ROAD_W, 0.5, length), Vector3(0, -0.25, length * 0.5), b["road"])
	for side: float in [-1.0, 1.0]:
		Props.part(node, "box", Vector3(0.35, 0.3, length), Vector3(side * (HALF_W + 0.17), 0.05, length * 0.5), b["curb"])
		Props.part(node, "box", Vector3(60.0, 0.4, length + 20.0), Vector3(side * (HALF_W + 30.3), -0.33, length * 0.5), b["ground"])
	Props.part(node, "box", Vector3(130.0, 0.4, 40.0), Vector3(0, -0.35, length + 20.0), b["ground"])
	var arch := Props.archway(node, Vector3(0, 0, 9.0), PI, ROAD_W + 1.2, "山神庙")
	arch.name = "Archway"
	# 山神庙正殿
	var hall := Props.group(node, Vector3(0, 0, 19.0), PI)
	Props.part(hall, "box", Vector3(9.0, 0.6, 6.0), Vector3(0, 0.3, 0), Color("#8a8070"))
	for x: float in [-3.6, -1.2, 1.2, 3.6]:
		Props.part(hall, "cyl", Vector3(0.45, 3.4, 0.45), Vector3(x, 2.3, -2.4), Props.RED)
	Props.part(hall, "box", Vector3(8.2, 3.4, 4.2), Vector3(0, 2.3, 0.4), Color("#9c3b2c"))
	Props.part(hall, "prism", Vector3(10.4, 2.2, 7.0), Vector3(0, 5.1, 0), Color("#eef2f6"))
	Props.part(hall, "box", Vector3(2.4, 0.8, 0.1), Vector3(0, 3.7, -1.75), Color("#1f3d7a"))
	Props.label(hall, "山神庙", Vector3(0, 3.7, -1.85), 56, Props.GOLD, Color(0, 0, 0, 0.5), Vector3(0, PI, 0))
	# 燃烧的草料堆
	for p: Vector3 in [Vector3(-8.0, 0, 6.0), Vector3(8.5, 0, 9.0), Vector3(-10.0, 0, 14.0)]:
		Props.part(node, "cone", Vector3(3.2, 2.6, 3.2), p + Vector3(0, 1.3, 0), Color("#a07a2c"))
		node.add_child(make_fire(p + Vector3(0, 1.4, 0), 1.0))
	for i in 6:
		Props.pine(node, Vector3(-HALF_W - 4.0 - i * 2.5, 0, 16.0 + (i % 2) * 4.0), 1.2, b["leaf"], b["trunk"], true)
		Props.pine(node, Vector3(HALF_W + 4.0 + i * 2.5, 0, 15.0 + (i % 2) * 4.0), 1.1, b["leaf"], b["trunk"], true)


static func make_fire(pos: Vector3, s: float) -> CPUParticles3D:
	var fire := CPUParticles3D.new()
	fire.position = pos
	fire.amount = 36
	fire.lifetime = 0.9
	fire.preprocess = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.6 * s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = m
	fire.mesh = quad
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 1.0 * s
	fire.direction = Vector3.UP
	fire.spread = 15.0
	fire.gravity = Vector3(0, 2.0, 0)
	fire.initial_velocity_min = 1.5 * s
	fire.initial_velocity_max = 3.0 * s
	fire.scale_amount_min = 0.8
	fire.scale_amount_max = 1.8
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.3, 0.9))
	ramp.set_color(1, Color(0.8, 0.15, 0.05, 0.0))
	ramp.add_point(0.45, Color(1.0, 0.45, 0.1, 0.8))
	fire.color_ramp = ramp
	return fire

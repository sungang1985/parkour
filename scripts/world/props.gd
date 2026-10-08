class_name Props
extends RefCounted
## 低多边形道具工厂：所有场景物件都由基础几何体拼成，网格和材质全局共享，
## 无需任何美术素材即可运行。之后可以逐个替换成 glTF 模型。
##
## 约定：道具的局部坐标 -Z 为前进方向，+X 为右侧，Y 向上，原点在地面。

static var _mats := {}
static var _meshes := {}

const WOOD := Color("#6b4426")
const DARK_WOOD := Color("#3d2616")
const RED := Color("#a3271f")
const ROOF := Color("#3b3d45")
const PLASTER := Color("#d9cfba")
const GOLD := Color("#e0b04a")
const IRON := Color("#4b4f57")
const CLOTH_YELLOW := Color("#e7c14f")


static func mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


static func unit_mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	match kind:
		"box":
			mesh = BoxMesh.new()
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 8
			c.rings = 1
			mesh = c
		"disc":
			var d := CylinderMesh.new()
			d.top_radius = 0.5
			d.bottom_radius = 0.5
			d.height = 1.0
			d.radial_segments = 16
			d.rings = 1
			mesh = d
		"cone":
			var k := CylinderMesh.new()
			k.top_radius = 0.0
			k.bottom_radius = 0.5
			k.height = 1.0
			k.radial_segments = 8
			k.rings = 1
			mesh = k
		"bowl":
			var b := CylinderMesh.new()
			b.top_radius = 0.5
			b.bottom_radius = 0.3
			b.height = 1.0
			b.radial_segments = 12
			b.rings = 1
			mesh = b
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 10
			s.rings = 6
			mesh = s
		"prism":
			mesh = PrismMesh.new()
		"torus":
			var t := TorusMesh.new()
			t.inner_radius = 0.38
			t.outer_radius = 0.5
			t.rings = 16
			t.ring_segments = 6
			mesh = t
		"quad":
			var q := QuadMesh.new()
			q.size = Vector2.ONE
			mesh = q
		_:
			push_error("未知网格类型: %s" % kind)
			mesh = BoxMesh.new()
	_meshes[kind] = mesh
	return mesh


## 添加一个基础几何体。size 为缩放（单位网格均为 1 米）。
static func part(parent: Node3D, kind: String, size: Vector3, pos: Vector3, color: Color,
		rot := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_mesh(kind)
	mi.material_override = mat(color, emission)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = rot
	mi.scale = size
	parent.add_child(mi)
	return mi


static func group(parent: Node3D, pos := Vector3.ZERO, yaw := 0.0, s := 1.0) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = yaw
	g.scale = Vector3.ONE * s
	parent.add_child(g)
	return g


static func label(parent: Node3D, text: String, pos: Vector3, font_size := 64,
		color := Color.WHITE, outline := Color(0, 0, 0, 0.8), rot := Vector3.ZERO,
		pixel := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = GameState.font_title
	l.font_size = font_size
	l.outline_size = maxi(4, font_size >> 3)
	l.pixel_size = pixel
	l.modulate = color
	l.outline_modulate = outline
	l.position = pos
	l.rotation = rot
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	return l


## 竖排文字（每个字一行）。
static func vertical(text: String) -> String:
	return "\n".join(text.split(""))


# ---------------------------------------------------------------- 植物与地形

static func pine(parent: Node3D, pos: Vector3, s: float, leaf: Color, trunk: Color, snowy := false) -> void:
	var g := group(parent, pos, 0.0, s)
	part(g, "cyl", Vector3(0.35, 1.6, 0.35), Vector3(0, 0.8, 0), trunk)
	for i in 3:
		var r := 1.7 - i * 0.45
		var c := leaf.lerp(Color.WHITE, 0.55) if snowy and i == 2 else leaf
		part(g, "cone", Vector3(r * 2.0, 1.7, r * 2.0), Vector3(0, 1.9 + i * 0.95, 0), c)
	if snowy:
		part(g, "cone", Vector3(1.4, 0.5, 1.4), Vector3(0, 2.25, 0), Color("#f4f7fa"))


static func round_tree(parent: Node3D, pos: Vector3, s: float, leaf: Color, trunk: Color) -> void:
	var g := group(parent, pos, randf() * TAU, s)
	part(g, "cyl", Vector3(0.4, 2.2, 0.4), Vector3(0, 1.1, 0), trunk)
	part(g, "sphere", Vector3(3.0, 2.4, 3.0), Vector3(0, 3.0, 0), leaf)
	part(g, "sphere", Vector3(2.0, 1.7, 2.0), Vector3(0.9, 3.9, 0.3), leaf.lightened(0.12))
	part(g, "sphere", Vector3(1.8, 1.5, 1.8), Vector3(-0.8, 3.6, -0.5), leaf.darkened(0.1))


static func date_tree(parent: Node3D, pos: Vector3, s: float, leaf: Color, trunk: Color) -> void:
	var g := group(parent, pos, randf() * TAU, s)
	part(g, "cyl", Vector3(0.3, 2.6, 0.3), Vector3(0, 1.3, 0), trunk, Vector3(0, 0, 0.12))
	part(g, "sphere", Vector3(2.4, 1.2, 2.4), Vector3(0.2, 2.9, 0), leaf)


static func bare_tree(parent: Node3D, pos: Vector3, s: float, trunk: Color) -> void:
	var g := group(parent, pos, randf() * TAU, s)
	part(g, "cyl", Vector3(0.35, 3.2, 0.35), Vector3(0, 1.6, 0), trunk)
	part(g, "cyl", Vector3(0.18, 1.6, 0.18), Vector3(0.45, 2.7, 0), trunk, Vector3(0, 0, -0.7))
	part(g, "cyl", Vector3(0.15, 1.4, 0.15), Vector3(-0.4, 3.0, 0.1), trunk, Vector3(0.2, 0, 0.8))
	part(g, "cyl", Vector3(0.12, 1.1, 0.12), Vector3(0.1, 3.4, -0.35), trunk, Vector3(-0.7, 0, 0))
	part(g, "box", Vector3(0.9, 0.12, 0.5), Vector3(0.75, 3.25, 0), Color("#f4f7fa"), Vector3(0, 0, -0.7))


static func rock(parent: Node3D, pos: Vector3, s: float, color: Color) -> void:
	part(parent, "sphere", Vector3(1.6, 1.0, 1.3) * s, pos + Vector3(0, 0.3 * s, 0), color,
		Vector3(randf() * 0.4, randf() * TAU, randf() * 0.3))


static func bush(parent: Node3D, pos: Vector3, s: float, leaf: Color) -> void:
	part(parent, "sphere", Vector3(1.6, 1.0, 1.6) * s, pos + Vector3(0, 0.4 * s, 0), leaf)
	part(parent, "sphere", Vector3(1.0, 0.8, 1.0) * s, pos + Vector3(0.6, 0.35, 0.3) * s, leaf.lightened(0.1))


static func reeds(parent: Node3D, pos: Vector3, s: float) -> void:
	var g := group(parent, pos, randf() * TAU, s)
	for i in 6:
		var h := randf_range(1.2, 2.2)
		var off := Vector3(randf_range(-0.6, 0.6), h * 0.5 - 0.4, randf_range(-0.6, 0.6))
		var tilt := Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
		part(g, "box", Vector3(0.06, h, 0.06), off, Color("#9fae5a"), tilt)
		if i % 2 == 0:
			part(g, "cyl", Vector3(0.12, 0.35, 0.12), off + Vector3(0, h * 0.5, 0), Color("#6b4a2a"), tilt)


static func water(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	part(parent, "box", size, pos, color)


# ---------------------------------------------------------------- 建筑与器物

static func hut(parent: Node3D, pos: Vector3, yaw: float, snowy := false) -> void:
	var g := group(parent, pos, yaw)
	part(g, "box", Vector3(4.0, 2.4, 3.4), Vector3(0, 1.2, 0), PLASTER)
	part(g, "box", Vector3(4.2, 0.3, 3.6), Vector3(0, 0.15, 0), Color("#7a7062"))
	part(g, "prism", Vector3(4.9, 1.5, 4.1), Vector3(0, 3.15, 0), Color("#eef2f6") if snowy else ROOF)
	part(g, "box", Vector3(0.9, 1.6, 0.1), Vector3(0, 0.95, 1.71), DARK_WOOD)
	part(g, "box", Vector3(0.12, 2.4, 0.12), Vector3(-2.0, 1.2, 1.7), RED)
	part(g, "box", Vector3(0.12, 2.4, 0.12), Vector3(2.0, 1.2, 1.7), RED)


static func stilt_hut(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var g := group(parent, pos, yaw)
	for x: float in [-1.6, 1.6]:
		for z: float in [-1.2, 1.2]:
			part(g, "cyl", Vector3(0.2, 2.2, 0.2), Vector3(x, 0.0, z), DARK_WOOD)
	part(g, "box", Vector3(4.0, 0.2, 3.2), Vector3(0, 1.0, 0), WOOD)
	part(g, "box", Vector3(3.6, 1.8, 2.8), Vector3(0, 2.0, 0), Color("#b8a27e"))
	part(g, "prism", Vector3(4.4, 1.3, 3.6), Vector3(0, 3.55, 0), Color("#8f7a4a"))


static func temple_wall(parent: Node3D, pos: Vector3, yaw: float, length := 8.0) -> void:
	var g := group(parent, pos, yaw)
	part(g, "box", Vector3(length, 2.4, 0.6), Vector3(0, 1.2, 0), Color("#9c3b2c"))
	part(g, "box", Vector3(length + 0.4, 0.3, 1.0), Vector3(0, 2.55, 0), ROOF)
	part(g, "prism", Vector3(length + 0.4, 0.4, 1.0), Vector3(0, 2.9, 0), ROOF, Vector3(0, 0, 0))


static func lantern(parent: Node3D, pos: Vector3) -> void:
	var g := group(parent, pos)
	part(g, "box", Vector3(0.12, 2.6, 0.12), Vector3(0, 1.3, 0), DARK_WOOD)
	part(g, "box", Vector3(0.7, 0.1, 0.1), Vector3(0.3, 2.55, 0), DARK_WOOD)
	part(g, "sphere", Vector3(0.45, 0.6, 0.45), Vector3(0.55, 2.15, 0), Color("#e0402a"), Vector3.ZERO, 1.6)


static func flag(parent: Node3D, pos: Vector3, yaw: float, text: String, cloth: Color,
		text_color := Color("#1d1d1d"), height := 4.6) -> void:
	var g := group(parent, pos, yaw)
	part(g, "cyl", Vector3(0.14, height, 0.14), Vector3(0, height * 0.5, 0), DARK_WOOD)
	var rows := text.length()
	var cloth_h := maxf(1.2, rows * 0.55 + 0.3)
	var top := height - 0.25
	part(g, "box", Vector3(0.9, cloth_h, 0.05), Vector3(0.52, top - cloth_h * 0.5, 0), cloth)
	part(g, "box", Vector3(0.95, 0.1, 0.07), Vector3(0.52, top, 0), RED)
	label(g, vertical(text), Vector3(0.52, top - cloth_h * 0.5, 0.04), 52, text_color,
		Color(0, 0, 0, 0))


static func wine_flag(parent: Node3D, pos: Vector3, yaw: float, text := "酒") -> void:
	flag(parent, pos, yaw, text, Color("#e9e2cf"), Color("#1f3d7a"), 4.2)


static func banner(parent: Node3D, pos: Vector3, yaw: float) -> void:
	flag(parent, pos, yaw, "替天行道", CLOTH_YELLOW, Color("#a3271f"), 6.0)


static func sign_board(parent: Node3D, pos: Vector3, yaw: float, text: String) -> void:
	var g := group(parent, pos, yaw)
	part(g, "box", Vector3(0.15, 1.6, 0.15), Vector3(0, 0.8, 0), DARK_WOOD)
	var w := maxf(1.8, text.length() * 0.48 + 0.3)
	part(g, "box", Vector3(w, 0.8, 0.1), Vector3(0, 1.75, 0), Color("#d8c39a"))
	label(g, text, Vector3(0, 1.75, 0.06), 44, Color("#3a1f12"), Color(0, 0, 0, 0))


static func boat(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var g := group(parent, pos, yaw)
	part(g, "box", Vector3(1.4, 0.4, 4.0), Vector3(0, 0.0, 0), WOOD)
	part(g, "prism", Vector3(1.4, 0.5, 1.0), Vector3(0, 0.0, -2.4), WOOD, Vector3(-PI / 2, 0, 0))
	part(g, "box", Vector3(1.2, 0.08, 1.6), Vector3(0, 1.0, 0.4), Color("#4e3b22"))
	for x: float in [-0.55, 0.55]:
		part(g, "box", Vector3(0.06, 0.8, 0.06), Vector3(x, 0.6, 0.4), DARK_WOOD)


## 牌坊：两根红柱、横额和屋顶。width 为柱间距。
static func archway(parent: Node3D, pos: Vector3, yaw: float, width: float, text: String) -> Node3D:
	var g := group(parent, pos, yaw)
	var hx := width * 0.5
	for x: float in [-hx, hx]:
		part(g, "cyl", Vector3(0.5, 5.0, 0.5), Vector3(x, 2.5, 0), RED)
		part(g, "box", Vector3(0.8, 0.5, 0.8), Vector3(x, 0.25, 0), Color("#8a8070"))
	part(g, "box", Vector3(width + 1.0, 0.45, 0.5), Vector3(0, 4.6, 0), RED)
	part(g, "box", Vector3(width * 0.45, 0.9, 0.12), Vector3(0, 5.25, 0.2), Color("#1f3d7a"))
	label(g, text, Vector3(0, 5.25, 0.28), 72, GOLD, Color(0, 0, 0, 0.6))
	part(g, "box", Vector3(width + 2.0, 0.3, 1.4), Vector3(0, 5.85, 0), ROOF)
	part(g, "prism", Vector3(width + 1.6, 0.7, 1.4), Vector3(0, 6.35, 0), ROOF)
	return g


# ---------------------------------------------------------------- 障碍物外观

## 拒马：横木加交叉尖桩。
static func barricade(parent: Node3D, width: float) -> void:
	part(parent, "cyl", Vector3(0.22, width, 0.22), Vector3(0, 0.5, 0), WOOD, Vector3(0, 0, PI / 2))
	var count := maxi(2, int(width / 0.9))
	for i in count:
		var x := -width * 0.5 + (i + 0.5) * width / count
		part(parent, "cyl", Vector3(0.13, 1.3, 0.13), Vector3(x, 0.5, 0), Color("#8a6038"), Vector3(0.75, 0, 0))
		part(parent, "cyl", Vector3(0.13, 1.3, 0.13), Vector3(x, 0.5, 0), Color("#8a6038"), Vector3(-0.75, 0, 0))
		part(parent, "cone", Vector3(0.14, 0.25, 0.14), Vector3(x, 0.98, 0.48), Color("#d9c7a3"), Vector3(0.75, 0, 0))
		part(parent, "cone", Vector3(0.14, 0.25, 0.14), Vector3(x, 0.98, -0.48), Color("#d9c7a3"), Vector3(-0.75, 0, 0))


## 倒木：横在路上的树干。
static func fallen_log(parent: Node3D, width: float, trunk: Color) -> void:
	part(parent, "cyl", Vector3(0.75, width + 0.6, 0.75), Vector3(0, 0.38, 0), trunk, Vector3(0, 0, PI / 2))
	part(parent, "cyl", Vector3(0.25, 1.2, 0.25), Vector3(width * 0.2, 0.75, 0.1), trunk, Vector3(0, 0, -0.6))


## 酒坛：一摞会被撞碎的坛子。
static func jars(parent: Node3D, width: float) -> void:
	var count := 3 if width > 2.0 else 2
	for i in count:
		var x := -width * 0.35 + i * (width * 0.7 / maxf(1, count - 1))
		part(parent, "sphere", Vector3(0.75, 0.8, 0.75), Vector3(x, 0.4, randf_range(-0.15, 0.15)), Color("#6e4424"))
		part(parent, "cyl", Vector3(0.34, 0.14, 0.34), Vector3(x, 0.83, 0), Color("#4a2c16"))
		part(parent, "box", Vector3(0.4, 0.06, 0.4), Vector3(x, 0.9, 0), RED)
	label(parent, "酒", Vector3(0, 0.45, 0.42), 48, Color("#f3e3c3"), Color(0, 0, 0, 0))


## 横幅门：需要翻滚通过。下沿高度 1.15 米。
static func banner_gate(parent: Node3D, width: float, text: String, high_obstacle: Color) -> void:
	var hx := width * 0.5 + 0.35
	for x: float in [-hx, hx]:
		part(parent, "cyl", Vector3(0.28, 3.4, 0.28), Vector3(x, 1.7, 0), DARK_WOOD)
	part(parent, "cyl", Vector3(0.22, width + 1.2, 0.22), Vector3(0, 2.45, 0), DARK_WOOD, Vector3(0, 0, PI / 2))
	part(parent, "box", Vector3(width - 0.3, 1.15, 0.06), Vector3(0, 1.75, 0), high_obstacle)
	var font_size := int(minf(0.8, (width - 0.7) / maxf(1.0, text.length())) * 100.0)
	label(parent, text, Vector3(0, 1.75, 0.05), font_size, Color("#f7ecd2"), Color(0, 0, 0, 0.5))
	label(parent, text, Vector3(0, 1.75, -0.05), font_size, Color("#f7ecd2"), Color(0, 0, 0, 0.5), Vector3(0, PI, 0))


## 镖车：一条道上的大型阻挡物。
static func cart(parent: Node3D) -> void:
	part(parent, "box", Vector3(1.8, 1.1, 2.6), Vector3(0, 1.05, 0), WOOD)
	part(parent, "box", Vector3(1.9, 0.5, 2.4), Vector3(0, 1.85, 0), RED)
	for x: float in [-1.0, 1.0]:
		for z: float in [-0.8, 0.8]:
			part(parent, "cyl", Vector3(1.0, 0.18, 1.0), Vector3(x, 0.5, z), DARK_WOOD, Vector3(0, 0, PI / 2))
	part(parent, "cyl", Vector3(0.06, 1.8, 0.06), Vector3(0.7, 2.9, 0.9), DARK_WOOD)
	part(parent, "box", Vector3(0.6, 0.5, 0.04), Vector3(1.0, 3.5, 0.9), CLOTH_YELLOW)
	label(parent, "镖", Vector3(1.0, 3.5, 0.93), 40, RED, Color(0, 0, 0, 0))


## 巨石：一条道上的阻挡物。
static func boulder(parent: Node3D, color: Color) -> void:
	part(parent, "sphere", Vector3(2.1, 2.4, 2.0), Vector3(0, 1.1, 0), color, Vector3(0.2, randf() * TAU, 0.1))
	part(parent, "sphere", Vector3(1.0, 0.9, 1.0), Vector3(0.7, 0.4, 0.5), color.darkened(0.15))


## 官兵盾阵：持盾站岗的官兵。
static func shield_guard(parent: Node3D) -> void:
	var g := group(parent, Vector3.ZERO, PI)
	part(g, "box", Vector3(0.36, 0.85, 0.36), Vector3(-0.15, 0.42, 0), Color("#2b2b30"))
	part(g, "box", Vector3(0.36, 0.85, 0.36), Vector3(0.15, 0.42, 0), Color("#2b2b30"))
	part(g, "box", Vector3(0.8, 0.9, 0.45), Vector3(0, 1.3, 0), Color("#9a2a1f"))
	part(g, "box", Vector3(0.84, 0.5, 0.5), Vector3(0, 1.45, 0), IRON)
	part(g, "sphere", Vector3(0.42, 0.45, 0.42), Vector3(0, 2.0, 0), Color("#e2b48c"))
	part(g, "cone", Vector3(0.55, 0.45, 0.55), Vector3(0, 2.35, 0), IRON)
	part(g, "sphere", Vector3(0.14, 0.14, 0.14), Vector3(0, 2.6, 0), RED)
	part(g, "cyl", Vector3(1.4, 0.1, 1.4), Vector3(0, 1.2, -0.45), Color("#7a4a22"), Vector3(PI / 2, 0, 0))
	part(g, "sphere", Vector3(0.35, 0.35, 0.15), Vector3(0, 1.2, -0.52), GOLD)
	part(g, "cyl", Vector3(0.06, 3.0, 0.06), Vector3(0.55, 1.6, 0), DARK_WOOD)
	part(g, "cone", Vector3(0.12, 0.35, 0.12), Vector3(0.55, 3.2, 0), Color("#c8ccd2"))


# ---------------------------------------------------------------- 收集物外观

## 铜钱：外圆内方。
static func coin(parent: Node3D) -> void:
	part(parent, "disc", Vector3(0.7, 0.08, 0.7), Vector3.ZERO, Color("#d9a33a"), Vector3(PI / 2, 0, 0), 0.35)
	part(parent, "box", Vector3(0.2, 0.2, 0.1), Vector3.ZERO, Color("#3a2510"))


static func powerup_visual(parent: Node3D, kind: String) -> void:
	match kind:
		"boost":
			part(parent, "box", Vector3(0.7, 0.95, 0.05), Vector3.ZERO, CLOTH_YELLOW, Vector3.ZERO, 0.4)
			label(parent, "神行", Vector3(0, 0, 0.04), 44, RED, Color(0, 0, 0, 0))
		"shield":
			part(parent, "disc", Vector3(0.9, 0.1, 0.9), Vector3.ZERO, Color("#b8893a"), Vector3(PI / 2, 0, 0), 0.4)
			part(parent, "disc", Vector3(0.6, 0.12, 0.6), Vector3.ZERO, Color("#e8d6a0"), Vector3(PI / 2, 0, 0), 0.6)
			label(parent, "护", Vector3(0, 0, 0.08), 44, Color("#7a2e12"), Color(0, 0, 0, 0))
		"magnet":
			part(parent, "bowl", Vector3(0.9, 0.45, 0.9), Vector3(0, -0.15, 0), GOLD, Vector3.ZERO, 0.4)
			part(parent, "sphere", Vector3(0.35, 0.25, 0.25), Vector3(-0.15, 0.15, 0), Color("#f4d36a"), Vector3.ZERO, 0.8)
			part(parent, "sphere", Vector3(0.35, 0.25, 0.25), Vector3(0.18, 0.12, 0.05), Color("#f4d36a"), Vector3.ZERO, 0.8)
			label(parent, "宝", Vector3(0, -0.15, 0.47), 40, RED, Color(0, 0, 0, 0))
		"double":
			part(parent, "box", Vector3(0.05, 1.1, 0.05), Vector3(-0.35, 0, 0), DARK_WOOD)
			part(parent, "box", Vector3(0.65, 0.7, 0.04), Vector3(0, 0.15, 0), RED, Vector3.ZERO, 0.4)
			label(parent, "双", Vector3(0, 0.15, 0.04), 44, CLOTH_YELLOW, Color(0, 0, 0, 0))
	part(parent, "sphere", Vector3(1.3, 1.3, 1.3), Vector3.ZERO, Color(1.0, 0.85, 0.4, 0.18), Vector3.ZERO, 0.6)

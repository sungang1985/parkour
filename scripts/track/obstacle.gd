class_name Obstacle
extends Area3D
## 障碍物碰撞体。外观由 Props 生成后作为子节点挂在下面。

enum Kind {
	LOW,    ## 低矮障碍（拒马、倒木）：跳过
	HIGH,   ## 高处横幅：翻滚通过
	BLOCK,  ## 整条道阻挡（镖车、巨石、官兵）：换道
	GAP,    ## 断路 / 断桥：跳过，否则坠落
	JARS,   ## 酒坛：撞到会绊一跤（不致命）
	WALL,   ## 路口尽头的墙或水面：必须转弯
}

const LAYER := 2

var kind: Kind = Kind.LOW
## 所在车道 0..2；-1 表示横跨整条路。
var lane := -1
## 已被撞碎 / 失效。
var consumed := false


func setup(p_kind: Kind, p_lane: int, shape_size: Vector3, shape_center: Vector3) -> void:
	kind = p_kind
	lane = p_lane
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = shape_size
	cs.shape = box
	cs.position = shape_center
	add_child(cs)


func is_lethal() -> bool:
	return kind != Kind.JARS


## 撞碎：缩小消失（神行 / 护心镜 / 鲁智深撞坛子时使用）。
func smash() -> void:
	if consumed:
		return
	consumed = true
	set_deferred("monitorable", false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.4, 0.05, 1.4), 0.18)
	tw.tween_callback(queue_free)

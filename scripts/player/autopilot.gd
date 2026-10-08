class_name Autopilot
extends Node
## 自动驾驶：读取赛道的障碍登记表做出操作。用于自动化测试，也可当作演示模式。

@export var player: Player
@export var track: Track

var enabled := false
var rng := RandomNumberGenerator.new()
var _lane_cooldown := 0.0


func _physics_process(delta: float) -> void:
	if not enabled or player == null or player.state != Player.State.RUNNING:
		return
	_lane_cooldown -= delta
	var spd := maxf(player.speed, Track.BASE_SPEED)

	var j := track.next_junction()
	if not j.is_empty() and player.queued_turn == 0:
		var sj := player.dist_to_junction(j)
		if sj > -6.0 and sj < Player.TURN_LATE - 0.5:
			var allowed: Array = j["allowed"]
			var t: int = allowed[rng.randi_range(0, allowed.size() - 1)]
			player.command("left" if t < 0 else "right")
			return

	var rows := rows_ahead(spd * 1.3 + 6.0)
	if rows.is_empty():
		return
	var row: Dictionary = rows[0]
	var d: float = row["d"]
	var kind: int = row["lanes"][player.lane]

	var want := _best_lane(rows)
	if want != player.lane and d < spd * 1.1:
		if _lane_cooldown <= 0.0:
			player.command("left" if want < player.lane else "right")
			_lane_cooldown = 0.08
		return
	if absf(player.lateral - player.lane_x(player.lane)) > 0.4:
		return

	var air := Player.BASE_AIR_TIME * sqrt(Track.BASE_SPEED / spd)
	var roll := Player.BASE_ROLL_TIME * sqrt(Track.BASE_SPEED / spd)
	match kind:
		Obstacle.Kind.LOW, Obstacle.Kind.GAP, Obstacle.Kind.JARS:
			if d > 0.0 and d <= air * spd * 0.5 + 0.2:
				player.command("up")
		Obstacle.Kind.HIGH:
			if not player.rolling and d > 0.0 and d <= roll * spd * 0.3 + 0.7:
				player.command("down")


## 选择对最近一行最安全的车道：优先空道，其次可跳 / 可滚的道，同等时选离得近的。
func _best_lane(rows: Array) -> int:
	var best := player.lane
	var best_cost := 1e9
	for lane in 3:
		var cost := absf(lane - player.lane) * 0.6
		var k0: int = rows[0]["lanes"][lane]
		if k0 == Obstacle.Kind.BLOCK:
			continue
		# 中间车道被挡住时无法横穿过去
		var step := 1 if lane > player.lane else -1
		var path_ok := true
		var l := player.lane
		while l != lane:
			l += step
			if l != lane and rows[0]["lanes"][l] == Obstacle.Kind.BLOCK and rows[0]["d"] < 4.0:
				path_ok = false
		if not path_ok:
			continue
		if k0 == Obstacle.Kind.JARS:
			cost += 1.5
		elif k0 >= 0:
			cost += 1.0
		if rows.size() > 1 and rows[1]["lanes"][lane] == Obstacle.Kind.BLOCK:
			cost += 0.8
		if cost < best_cost:
			best_cost = cost
			best = lane
	return best


## 前方 look 米内的障碍，按行（同一路程位置）合并为 {d, lanes[3]}。
func rows_ahead(look: float) -> Array:
	var rows := []
	for h: Dictionary in track.hazards:
		var node = h["node"]
		if not is_instance_valid(node) or node.consumed:
			continue
		if h["kind"] == Obstacle.Kind.WALL:
			continue
		var d: float = h["path"] - player.path_dist
		if d < -0.9:
			continue
		if d > look:
			break
		if rows.is_empty() or absf(rows[-1]["d"] - d) > 0.3:
			rows.append({"d": d, "lanes": [-1, -1, -1]})
		var row: Dictionary = rows[-1]
		if h["lane"] < 0:
			row["lanes"] = [h["kind"], h["kind"], h["kind"]]
		else:
			row["lanes"][h["lane"]] = h["kind"]
	return rows

class_name CameraRig
extends Camera3D
## Match camera. PRO = behind the controlled player looking up-pitch (REMATCH-like),
## TV = broadcast side camera, CINE = goal replay / celebration orbit.

enum Mode { PRO, TV, CINE, TOP }

var mode := Mode.PRO
var m: MatchSim
var follow_id := -1
var _tgt := Vector3.ZERO
var _pos := Vector3.ZERO
var _yaw := 0.0
var _initialized := false
var shake := 0.0
var cine_center := Vector3.ZERO
var cine_t := 0.0
var zoom := 1.0


func setup(sim: MatchSim, pid: int) -> void:
	m = sim
	follow_id = pid
	near = 0.1
	far = 900.0
	fov = 52.0


## Horizontal forward/right used to map the stick to the world.
func control_axes() -> Array:
	var f := -global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.01:
		f = Vector3(1, 0, 0)
	f = f.normalized()
	var r := f.cross(Vector3.UP).normalized()
	return [f, r]


func snap() -> void:
	_initialized = false


func update_cam(dt: float, ball_pos: Vector3, focus_pos: Vector3, focus_team_side: int) -> void:
	var desired_pos := Vector3.ZERO
	var look := Vector3.ZERO
	var big := m.cfg.per_side >= 9
	match mode:
		Mode.PRO:
			var me := focus_pos
			var t := me.lerp(ball_pos, 0.35)
			t.y = 0.0
			var att := Vector3(focus_team_side, 0, 0)
			# yaw leans slightly toward the ball's side so it stays in view
			var to_ball := ball_pos - me
			to_ball.y = 0.0
			var desired_yaw := atan2(-att.z, att.x)
			if to_ball.length() > 2.0:
				var ang := att.signed_angle_to(to_ball.normalized(), Vector3.UP)
				desired_yaw += clampf(ang, -1.0, 1.0) * 0.28
			if not _initialized:
				_yaw = desired_yaw
			_yaw = lerp_angle(_yaw, desired_yaw, clampf(dt * 1.6, 0.0, 1.0))
			var fwd := Vector3(cos(_yaw), 0, -sin(_yaw))
			var dist := (10.5 if big else 8.2) * zoom
			var h := (6.8 if big else 5.4) * zoom
			desired_pos = t - fwd * dist + Vector3.UP * h
			look = t + fwd * 3.0 + Vector3.UP * 0.6
		Mode.TV:
			var hw := m.pitch.hw()
			var t2 := ball_pos.lerp(focus_pos, 0.25)
			var x := clampf(t2.x, -m.pitch.hl() * 0.8, m.pitch.hl() * 0.8)
			var back := (hw + (30.0 if big else 15.0)) * zoom
			var h2 := (24.0 if big else 13.5) * zoom
			desired_pos = Vector3(x * 0.92, h2, back)
			look = Vector3(x, 0.0, clampf(t2.z, -hw * 0.6, hw * 0.6) * 0.75)
		Mode.CINE:
			cine_t += dt
			var ang2 := cine_t * 0.35
			desired_pos = cine_center + Vector3(cos(ang2) * 7.0, 2.4, sin(ang2) * 7.0)
			look = cine_center + Vector3(0, 1.1, 0)
		Mode.TOP:
			desired_pos = Vector3(ball_pos.x * 0.5, m.pitch.length * 0.9, 0.01)
			look = Vector3(ball_pos.x * 0.5, 0, 0)
	if not _initialized:
		_pos = desired_pos
		_tgt = look
		_initialized = true
	var k := clampf(dt * (4.0 if mode != Mode.TV else 2.5), 0.0, 1.0)
	_pos = _pos.lerp(desired_pos, k)
	_tgt = _tgt.lerp(look, clampf(dt * 5.0, 0.0, 1.0))
	var sh := Vector3.ZERO
	if shake > 0.0:
		shake = maxf(shake - dt * 2.0, 0.0)
		sh = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.08
	global_position = _pos + sh
	if _pos.distance_to(_tgt) > 0.01:
		look_at(_tgt, Vector3.UP)
	fov = 40.0 if mode == Mode.TV else 52.0

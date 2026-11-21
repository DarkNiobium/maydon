class_name CameraRig
extends Camera3D
## Match camera. SHOULDER = REMATCH-style third person: mouse / right stick /
## touch-drag orbit, the screen centre is the aim. PRO = behind the player
## looking up-pitch, TV = broadcast, CINE = celebration orbit.

enum Mode { PRO, TV, CINE, TOP, SHOULDER }

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
# shoulder-cam state
var yaw := 0.0
var pitch := 0.22
var auto_follow := true
var manual_t := 99.0
var fov_kick := 0.0
var _sh_pos := Vector3.ZERO
const PITCH_MIN := -0.12
const PITCH_MAX := 0.75


func setup(sim: MatchSim, pid: int) -> void:
	m = sim
	follow_id = pid
	near = 0.1
	far = 900.0
	fov = 52.0


## Rotate the shoulder camera (radians).
func look_input(dyaw: float, dpitch: float) -> void:
	yaw -= dyaw
	pitch = clampf(pitch + dpitch, PITCH_MIN, PITCH_MAX)
	manual_t = 0.0


func face_dir() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


## Centre-of-screen aim ray (world): [origin, direction].
func aim_ray() -> Array:
	return [global_position, -global_transform.basis.z]


## Horizontal forward/right used to map the stick to the world.
func control_axes() -> Array:
	if mode == Mode.SHOULDER:
		var fw := face_dir()
		return [fw, fw.cross(Vector3.UP).normalized()]
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
			# stay inside the cage / stadium bowl so walls and fences never cover the view
			var lx := m.pitch.hl() - 0.6 + (m.pitch.runoff_x if not m.pitch.walls else 0.0)
			var lz := m.pitch.hw() - 0.6 + (m.pitch.runoff_z if not m.pitch.walls else 0.0)
			var over := maxf(absf(desired_pos.x) - lx, 0.0) + maxf(absf(desired_pos.z) - lz, 0.0)
			desired_pos.x = clampf(desired_pos.x, -lx, lx)
			desired_pos.z = clampf(desired_pos.z, -lz, lz)
			desired_pos.y += over * 0.5
		Mode.SHOULDER:
			manual_t += dt
			var me2 := focus_pos
			if not _initialized:
				yaw = atan2(0.0, float(focus_team_side)) if focus_team_side > 0 else PI
				_sh_pos = me2
			# auto-align behind the run direction when the player isn't steering the camera
			if auto_follow and manual_t > 1.4 and m.players.size() > follow_id and follow_id >= 0:
				var v: Vector3 = m.players[follow_id].vel
				if v.length() > 2.5:
					var vy := atan2(-v.z, v.x)
					yaw = lerp_angle(yaw, vy, clampf(dt * 0.9, 0.0, 1.0))
			_sh_pos = _sh_pos.lerp(me2, clampf(dt * 14.0, 0.0, 1.0))
			var pivot := _sh_pos + Vector3(0, 1.55, 0)
			var fwd2 := face_dir()
			var dir := (fwd2 * cos(pitch) - Vector3.UP * sin(pitch)).normalized()
			var right := fwd2.cross(Vector3.UP).normalized()
			var dist2 := (5.6 if big else 4.7) * zoom
			var cp := pivot - dir * dist2 + right * 0.32
			if cp.y < 0.35:
				cp.y = 0.35
			var lx2 := m.pitch.hl() - 0.5 + (m.pitch.runoff_x if not m.pitch.walls else 0.0)
			var lz2 := m.pitch.hw() - 0.5 + (m.pitch.runoff_z if not m.pitch.walls else 0.0)
			cp.x = clampf(cp.x, -lx2, lx2)
			cp.z = clampf(cp.z, -lz2, lz2)
			_pos = cp
			_tgt = pivot + dir * 12.0 + right * 0.32
			_initialized = true
			var sh2 := Vector3.ZERO
			if shake > 0.0:
				shake = maxf(shake - dt * 2.0, 0.0)
				sh2 = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.06
			global_position = _pos + sh2
			look_at(_tgt, Vector3.UP)
			fov = lerpf(fov, 70.0 + fov_kick, clampf(dt * 6.0, 0.0, 1.0))
			return
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
			var rad := 7.0 if cine_center.length() > 0.5 else m.pitch.width * 0.45
			var hh := 2.4 if cine_center.length() > 0.5 else m.pitch.width * 0.22
			desired_pos = cine_center + Vector3(cos(ang2) * rad, hh, sin(ang2) * rad)
			look = cine_center + Vector3(0, 1.1, 0)
			# never orbit through the cage walls / into the stands
			var clx := m.pitch.hl() - 0.8 + (m.pitch.runoff_x if not m.pitch.walls else 0.0)
			var clz := m.pitch.hw() - 0.8 + (m.pitch.runoff_z if not m.pitch.walls else 0.0)
			desired_pos.x = clampf(desired_pos.x, -clx, clx)
			desired_pos.z = clampf(desired_pos.z, -clz, clz)
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
	_update_dof(dt)


## Cinematic depth of field for the celebration orbit (crowd and far stands melt into bokeh,
## the scorer stays sharp). Off during play so nothing important is ever blurred.
var _dof_amt := 0.0
func _update_dof(dt: float) -> void:
	if int(Game.settings.get("quality", 1)) < 2:
		return
	var ca := attributes as CameraAttributesPractical
	if ca == null:
		ca = CameraAttributesPractical.new()
		attributes = ca
	var want := 1.0 if mode == Mode.CINE else 0.0
	_dof_amt = move_toward(_dof_amt, want, dt * 1.5)
	ca.dof_blur_far_enabled = _dof_amt > 0.01
	ca.dof_blur_near_enabled = _dof_amt > 0.01
	if _dof_amt <= 0.01:
		return
	var d := global_position.distance_to(cine_center + Vector3(0, 1.2, 0))
	ca.dof_blur_far_distance = d + 3.0
	ca.dof_blur_far_transition = 10.0
	ca.dof_blur_near_distance = maxf(d - 2.5, 0.3)
	ca.dof_blur_near_transition = 1.5
	ca.dof_blur_amount = 0.08 * _dof_amt

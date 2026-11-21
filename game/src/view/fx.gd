class_name MatchFx
extends Node3D
## Cheap, mobile-safe match effects: ball trail on hard strikes, turf flecks
## on kicks/slides, net ripple handled by sounds/camera.

var _trail: MeshInstance3D
var _im: ImmediateMesh
var _pts: Array[Vector3] = []
var _cam: Camera3D
var _flecks: CPUParticles3D
var _turf_col := Color(0.2, 0.42, 0.16)


func setup(cam: Camera3D, turf: bool) -> void:
	_cam = cam
	_turf_col = Color(0.16, 0.42, 0.18) if turf else Color(0.22, 0.4, 0.14)
	_im = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = m
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_flecks = CPUParticles3D.new()
	_flecks.emitting = false
	_flecks.one_shot = true
	_flecks.amount = 14
	_flecks.lifetime = 0.55
	_flecks.explosiveness = 0.95
	_flecks.direction = Vector3(0, 1, 0)
	_flecks.spread = 55.0
	_flecks.initial_velocity_min = 1.5
	_flecks.initial_velocity_max = 3.5
	_flecks.gravity = Vector3(0, -9.8, 0)
	_flecks.scale_amount_min = 0.5
	_flecks.scale_amount_max = 1.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.035, 0.035)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = _turf_col
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.material = fm
	_flecks.mesh = qm
	add_child(_flecks)


func flecks(at: Vector3, strength: float) -> void:
	_flecks.global_position = Vector3(at.x, 0.05, at.z)
	_flecks.initial_velocity_max = 2.0 + strength * 2.5
	_flecks.restart()
	_flecks.emitting = true


func update_trail(ball_pos: Vector3, speed: float) -> void:
	if speed > 15.0 and ball_pos.y > 0.15:
		_pts.push_front(ball_pos)
	elif not _pts.is_empty():
		_pts.pop_back()
	while _pts.size() > 14:
		_pts.pop_back()
	_im.clear_surfaces()
	if _pts.size() < 2 or _cam == null:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _pts.size()
	for i in n:
		var p := _pts[i]
		var nxt := _pts[mini(i + 1, n - 1)] if i < n - 1 else p + (p - _pts[i - 1])
		var fwd := (nxt - p).normalized()
		var to_cam := (_cam.global_position - p).normalized()
		var side := fwd.cross(to_cam).normalized()
		var k := 1.0 - float(i) / float(n)
		var w := 0.09 * k
		var col := Color(1.0, 1.0, 1.0, 0.35 * k)
		_im.surface_set_color(col)
		_im.surface_add_vertex(p + side * w)
		_im.surface_set_color(col)
		_im.surface_add_vertex(p - side * w)
	_im.surface_end()

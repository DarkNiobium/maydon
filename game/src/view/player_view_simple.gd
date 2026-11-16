class_name PlayerViewSimple
extends Node3D
## Lightweight procedural footballer (capsule rig with gait-driven limbs).
## Used until/when the skinned character isn't available, and for far LOD.

var pid := -1
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _hips: Node3D
var _legs := []      # [hip pivot, knee pivot]
var _arms := []
var _yaw := 0.0
var _lean := 0.0
var _last_pos := Vector3.ZERO


func _cap(r: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 3
	mi.mesh = cm
	mi.material_override = mat
	return mi


func _m(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	return m


func setup(p: Footballer, kit: Dictionary) -> void:
	pid = p.id
	var shirt: Color = kit.get("shirt", Color(0.8, 0.1, 0.1))
	var shorts: Color = kit.get("shorts", Color.WHITE)
	var socks: Color = kit.get("socks", shirt)
	var skin := Color(0.78, 0.6, 0.47).lerp(Color(0.42, 0.28, 0.2), float(p.id % 5) / 6.0)
	_hips = Node3D.new()
	_hips.position = Vector3(0, 0.95, 0)
	add_child(_hips)
	_torso = _cap(0.2, 0.62, _m(shirt))
	_torso.position = Vector3(0, 0.33, 0)
	_hips.add_child(_torso)
	_head = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.115
	sm.height = 0.25
	sm.radial_segments = 12
	sm.rings = 6
	_head.mesh = sm
	_head.material_override = _m(skin)
	_head.position = Vector3(0, 0.78, 0)
	_hips.add_child(_head)
	for s: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0, 0, 0.1 * s)
		_hips.add_child(hip)
		var thigh := _cap(0.085, 0.48, _m(shorts))
		thigh.position = Vector3(0, -0.22, 0)
		hip.add_child(thigh)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.46, 0)
		hip.add_child(knee)
		var shin := _cap(0.065, 0.5, _m(socks))
		shin.position = Vector3(0, -0.24, 0)
		knee.add_child(shin)
		var boot := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.24, 0.07, 0.09)
		boot.mesh = bm
		boot.material_override = _m(Color(0.08, 0.08, 0.08))
		boot.position = Vector3(0.05, -0.48, 0)
		knee.add_child(boot)
		_legs.append([hip, knee])
		var sh := Node3D.new()
		sh.position = Vector3(0, 0.56, 0.24 * s)
		_hips.add_child(sh)
		var arm := _cap(0.05, 0.6, _m(skin))
		arm.position = Vector3(0, -0.27, 0)
		sh.add_child(arm)
		_arms.append(sh)


func sync(p: Footballer, pos: Vector3, face: Vector3, dt: float) -> void:
	position = pos
	var tgt_yaw := atan2(-face.z, face.x)
	_yaw = lerp_angle(_yaw, tgt_yaw, clampf(dt * 18.0, 0.0, 1.0))
	rotation = Vector3(0, _yaw, 0)
	var sp := p.vel.length()
	var ph := p.gait * TAU
	var amp := clampf(sp / 8.0, 0.0, 1.0)
	_hips.position.y = 0.95 - absf(sin(ph)) * 0.04 * amp
	_hips.rotation = Vector3.ZERO
	var tgt_lean := clampf(sp / 9.0, 0.0, 1.0) * 0.25
	_lean = lerpf(_lean, tgt_lean, clampf(dt * 6.0, 0.0, 1.0))
	_hips.rotation.z = -_lean
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		var hip: Node3D = _legs[i][0]
		var knee: Node3D = _legs[i][1]
		var sw := sin(ph + (PI if i == 1 else 0.0))
		hip.rotation = Vector3(0, 0, sw * 0.75 * amp)
		knee.rotation = Vector3(0, 0, -maxf(0.0, -cos(ph + (PI if i == 1 else 0.0))) * 1.2 * amp - 0.05)
		var arm: Node3D = _arms[i]
		arm.rotation = Vector3(s * 0.12, 0, -sw * 0.6 * amp)
	_action_pose(p)


func _action_pose(p: Footballer) -> void:
	var t := p.act_t
	match p.action:
		Footballer.A.PASS, Footballer.A.SHOT, Footballer.A.LOB, Footballer.A.CHIP, Footballer.A.VOLLEY, Footballer.A.GK_KICK:
			var c := maxf(p.act_contact, 0.05)
			var k := t / c
			var hip: Node3D = _legs[1][0]
			var knee: Node3D = _legs[1][1]
			if k < 1.0:
				hip.rotation.z = lerpf(0.0, -0.9, k)
				knee.rotation.z = lerpf(0.0, -1.4, k)
			else:
				var f := clampf((t - c) / 0.25, 0.0, 1.0)
				hip.rotation.z = lerpf(-0.9, 1.3, minf(f * 2.0, 1.0)) * (1.0 - maxf(f - 0.5, 0.0))
				knee.rotation.z = lerpf(-1.4, 0.0, f)
		Footballer.A.SLIDE:
			_hips.position.y = 0.32
			_hips.rotation.z = 1.15
			(_legs[1][0] as Node3D).rotation.z = 1.2
		Footballer.A.GK_DIVE:
			var dir: Vector3 = p.act_data.get("dir", Vector3.RIGHT)
			var lat: float = p.act_data.get("lat", 0.0)
			var k2 := clampf((t - 0.05) / 0.4, 0.0, 1.0)
			var local := global_transform.basis.inverse() * dir
			var roll := -signf(local.z) * PI * 0.45 * k2 * clampf(lat / 1.5, 0.3, 1.0)
			_hips.rotation.x = roll
			_hips.position.y = lerpf(0.95, 0.35 + p.act_data.get("h", 0.5) * 0.4, k2)
			for arm in _arms:
				(arm as Node3D).rotation.z = PI * 0.9
		Footballer.A.FALL, Footballer.A.GETUP:
			var k3 := 1.0 if p.action == Footballer.A.FALL else 1.0 - clampf(t / 0.7, 0.0, 1.0)
			_hips.position.y = lerpf(0.95, 0.2, k3)
			_hips.rotation.z = lerpf(0.0, -1.4, k3)
		Footballer.A.CELEBRATE:
			for arm in _arms:
				(arm as Node3D).rotation.z = PI * 0.85
			(_arms[0] as Node3D).rotation.x = 0.4
			(_arms[1] as Node3D).rotation.x = -0.4
		Footballer.A.HEADER:
			var k4 := sin(clampf(t / 0.45, 0.0, 1.0) * PI)
			position.y += k4 * 0.4
			_hips.rotation.z = -0.3 * k4
		Footballer.A.THROW_IN, Footballer.A.GK_THROW:
			for arm in _arms:
				(arm as Node3D).rotation.z = PI * (0.95 if t < p.act_contact else 0.5)
		Footballer.A.TACKLE:
			var hip2: Node3D = _legs[1][0]
			hip2.rotation.z = 0.9 * sin(clampf(t / 0.35, 0.0, 1.0) * PI)
	if p.is_gk() and p.action == Footballer.A.NONE and p.vel.length() < 2.0:
		for arm in _arms:
			(arm as Node3D).rotation.z = 0.6

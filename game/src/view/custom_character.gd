class_name CustomCharacter
extends RefCounted
## The player's own customisable footballer (assets/chars/custom/base.glb):
## face/body morphs, hairstyle meshes, skin tone + facial-hair masks in a
## shader, gear toggles. Applies a Look dictionary to an instance.

const DIR := "res://assets/chars/custom/"
const SKIN_SHADER := preload("res://src/view/shaders/skin_custom.gdshader")
const HAIR_SHADER := preload("res://src/view/shaders/hair_tint.gdshader")
const EYE_SHADER := preload("res://src/view/shaders/eye_custom.gdshader")
const ACC_SHADER := preload("res://src/view/shaders/acc_tint.gdshader")

static var _scene: PackedScene
static var _checked := false
static var _tex_cache := {}


static func available() -> bool:
	if not _checked:
		_checked = true
		if ResourceLoader.exists(DIR + "base.glb"):
			_scene = load(DIR + "base.glb")
	return _scene != null


static func instantiate_look(look: Dictionary) -> Node3D:
	if not available():
		return null
	var inst: Node3D = _scene.instantiate()
	apply(inst, look)
	return inst


static func _tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var t: Texture2D = null
	for ext in [".png", ".jpg"]:
		if ResourceLoader.exists(DIR + name + ext):
			t = load(DIR + name + ext)
			break
	_tex_cache[name] = t
	return t


static func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


static var _spec := {}


static func _hair_spec(id: String) -> Dictionary:
	if _spec.is_empty():
		var f := FileAccess.open(DIR + "custom.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_spec = d
	return (_spec.get("hair", {}) as Dictionary).get(id, {})


static func apply(inst: Node3D, look: Dictionary) -> void:
	var meshes := []
	_meshes(inst, meshes)
	var morphs: Dictionary = look.get("morphs", {})
	var build: Dictionary = look.get("build", {})
	var hair: String = look.get("hair", "hair_short_fade")
	var boots := int(look.get("boots", 1))
	var acc: Dictionary = look.get("acc", {})
	var low_socks := str(look.get("socks", "high")) == "low"
	var skin := _skin_mat(look)
	var acc_col := Color.html(str(look.get("acc_color", "#f2f2f2")))
	for mi_v in meshes:
		var mi := mi_v as MeshInstance3D
		var lname := String(mi.name).to_lower()
		# morph targets (each mesh carries only the keys that move it)
		if mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			for i in am.get_blend_shape_count():
				var bn := String(am.get_blend_shape_name(i))
				var w := float(morphs.get(bn, build.get(bn, 0.0)))
				mi.set_blend_shape_value(i, clampf(w, 0.0, 1.0))
		# visibility
		if lname.begins_with("hair_"):
			mi.visible = lname == hair
		elif lname.begins_with("boots_"):
			mi.visible = lname == "boots_%d" % boots
		elif lname == "sleeves_long":
			mi.visible = str(look.get("sleeves", "short")) == "long"
		elif lname == "socks_low":
			mi.visible = low_socks
		elif lname.begins_with("acc_"):
			var key := lname.trim_prefix("acc_")
			if key.begins_with("wristband"):
				key = "wristbands"
			mi.visible = bool(acc.get(key, false))
		if lname == "kit":
			mi.set_instance_shader_parameter("hide_socks", low_socks)
		# materials
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			var mn: String = m.resource_name.to_lower() if m else ""
			var tex: Texture2D = (m as BaseMaterial3D).albedo_texture if m is BaseMaterial3D else null
			if mn.begins_with("skin") or lname == "body":
				mi.set_surface_override_material(s, skin)
			elif mn.begins_with("eye") or lname == "eyes":
				var em := ShaderMaterial.new()
				em.shader = EYE_SHADER
				em.set_shader_parameter("eye_tex", tex if tex else _tex("eye"))
				em.set_shader_parameter("eye_col", Color.html(str(look.get("eye_color", "#3b2416"))))
				mi.set_surface_override_material(s, em)
			elif lname.begins_with("hair_"):
				var hm := ShaderMaterial.new()
				hm.shader = HAIR_SHADER
				hm.set_shader_parameter("hair_tex", tex if tex else _tex(lname))
				hm.set_shader_parameter("hair_col", Color.html(str(look.get("hair_color", "#1d1611"))))
				mi.set_surface_override_material(s, hm)
			elif lname.begins_with("acc_"):
				var am2 := ShaderMaterial.new()
				am2.shader = ACC_SHADER
				am2.set_shader_parameter("acc_tex", tex if tex else _tex("acc"))
				am2.set_shader_parameter("tint", Color(0.12, 0.12, 0.13) if lname == "acc_gloves" else acc_col)
				mi.set_surface_override_material(s, am2)
	inst.scale = Vector3.ONE * lerpf(0.94, 1.06, float(look.get("height", 0.5)))


static func _skin_mat(look: Dictionary) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = SKIN_SHADER
	var light := _tex("skin_light")
	sm.set_shader_parameter("skin_light", light)
	sm.set_shader_parameter("skin_mid", _tex("skin_mid") if _tex("skin_mid") else light)
	sm.set_shader_parameter("skin_dark", _tex("skin_dark") if _tex("skin_dark") else light)
	var nt := _tex("skin_normal")
	if nt:
		sm.set_shader_parameter("skin_normal", nt)
		sm.set_shader_parameter("has_normal", true)
	# Look.skin_tone 0..1 → atlas blend 0..2
	sm.set_shader_parameter("tone", clampf(float(look.get("skin_tone", 0.45)), 0.0, 1.0) * 2.0)
	sm.set_shader_parameter("warmth", float(look.get("skin_warmth", 0.2)))
	var hc := Color.html(str(look.get("hair_color", "#1d1611")))
	sm.set_shader_parameter("hair_col", hc)
	var hair := str(look.get("hair", "hair_short_fade"))
	var hs := _hair_spec(hair)
	var scalp: Texture2D = null
	var strength := 0.0
	if hair == "bald":
		scalp = _tex("scalp_full")
		strength = 0.12
	elif not hs.is_empty():
		scalp = _tex(str(hs.get("scalp_mask", "scalp_full")))
		strength = float(hs.get("scalp_strength", 0.6))
	if scalp:
		sm.set_shader_parameter("scalp_mask", scalp)
		sm.set_shader_parameter("scalp_on", strength)
	var beard := str(look.get("beard", "none"))
	var bt := _tex(beard) if beard != "none" else null
	sm.set_shader_parameter("beard_on", 1.0 if bt else 0.0)
	if bt:
		sm.set_shader_parameter("beard_mask", bt)
	sm.set_shader_parameter("beard_col", Color.html(str(look.get("beard_color", look.get("hair_color", "#1d1611")))))
	var brow := _tex(str(look.get("brows", "brows_normal")))
	if brow:
		sm.set_shader_parameter("brow_mask", brow)
	sm.set_shader_parameter("brow_col", hc.darkened(0.15))
	var iris := _tex("iris_mask")
	if iris:
		sm.set_shader_parameter("iris_mask", iris)
	sm.set_shader_parameter("eye_col", Color.html(str(look.get("eye_color", "#3b2416"))))
	return sm

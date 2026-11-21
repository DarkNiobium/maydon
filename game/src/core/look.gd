class_name Look
extends RefCounted
## Player appearance data (saved in the profile) and helpers: defaults, random,
## presets and conversion from the selfie-AI answer.

const MORPHS := ["head_round", "head_square", "head_long", "jaw_wide", "jaw_narrow", "chin_out", "chin_in",
	"chin_wide", "cheekbones_high", "cheeks_full", "cheeks_hollow", "nose_wide", "nose_narrow", "nose_long",
	"nose_short", "nose_hump", "nose_flat", "eyes_big", "eyes_small", "eyes_wide", "eyes_close",
	"eyes_slant_up", "eyes_monolid", "brow_heavy", "brow_high", "lips_full", "lips_thin", "mouth_wide",
	"ears_big", "ears_out", "forehead_high", "face_mature"]

## Bipolar sliders: [label key, negative morph, positive morph]
const FACE_SLIDERS := [
	["S_HEAD", "head_round", "head_long"], ["S_HEAD_SQ", "", "head_square"],
	["S_JAW", "jaw_narrow", "jaw_wide"], ["S_CHIN", "chin_in", "chin_out"], ["S_CHIN_W", "", "chin_wide"],
	["S_CHEEKS", "cheeks_hollow", "cheeks_full"], ["S_CHEEKBONES", "", "cheekbones_high"],
	["S_NOSE_W", "nose_narrow", "nose_wide"], ["S_NOSE_L", "nose_short", "nose_long"], ["S_NOSE_B", "nose_flat", "nose_hump"],
	["S_EYES", "eyes_small", "eyes_big"], ["S_EYES_SP", "eyes_close", "eyes_wide"], ["S_EYES_SL", "", "eyes_slant_up"],
	["S_EYELID", "", "eyes_monolid"], ["S_BROW", "", "brow_heavy"], ["S_BROW_H", "", "brow_high"],
	["S_LIPS", "lips_thin", "lips_full"], ["S_MOUTH", "", "mouth_wide"], ["S_EARS", "", "ears_big"],
	["S_EARS_OUT", "", "ears_out"], ["S_FOREHEAD", "", "forehead_high"], ["S_AGE", "", "face_mature"],
]

const HAIR := ["bald", "hair_buzz", "hair_short_fade", "hair_crop", "hair_side_part", "hair_slick_back",
	"hair_quiff", "hair_curly", "hair_afro", "hair_man_bun", "hair_long", "hair_braids"]
const BEARD := ["none", "beard_stubble", "beard_short", "beard_full", "beard_goatee", "beard_mustache", "beard_chinstrap"]
const BROWS := ["brows_thin", "brows_normal", "brows_thick"]
const HAIR_COLORS := ["#0e0c0b", "#1d1611", "#3a271a", "#5a3a22", "#7a5230", "#a77a4a", "#c9a46b", "#e3cfa1",
	"#8a2f1a", "#b04a22", "#7f7f7f", "#d9d9d9", "#1e3a8a", "#b91c1c"]
const EYE_COLORS := ["#3b2416", "#5c3a21", "#7a5a2b", "#4f6b3a", "#5f7f8f", "#3b5f9e", "#2a2a2a"]
const ACC_COLORS := ["#f2f2f2", "#111111", "#1d4ed8", "#e11d48", "#16a34a", "#facc15", "#ff6a00"]
const BOOT_COLORS := ["#101010", "#f2f2f2", "#ff6a00", "#1d4ed8", "#e11d48", "#16a34a", "#facc15", "#a855f7", "#06b6d4"]


## Shop: gear that costs coins (everything else is free). Keys: kind:value.
const PRICES := {"boots:2": 300, "boots:3": 500, "boots:4": 800, "sleeves:long": 200, "socks:low": 150,
	"acc:headband": 150, "acc:wristbands": 150, "acc:armband": 200, "acc:gloves": 250}
const FREE_BOOT_COLORS := 3
const FREE_ACC_COLORS := 2


static func price(key: String) -> int:
	if key in owned():
		return 0
	if PRICES.has(key):
		return PRICES[key]
	if key.begins_with("bootcol:"):
		var i := BOOT_COLORS.find(key.trim_prefix("bootcol:"))
		return 120 if i >= FREE_BOOT_COLORS else 0
	if key.begins_with("acccol:"):
		var j := ACC_COLORS.find(key.trim_prefix("acccol:"))
		return 80 if j >= FREE_ACC_COLORS else 0
	return 0


static func owned() -> Array:
	return Game.profile.get("owned", [])


## Paid items worn by `l` that the player doesn't own yet.
static func unowned(l: Dictionary) -> Array:
	var keys := ["boots:%d" % int(l.get("boots", 1)), "bootcol:" + str(l.get("boot_color", "")),
		"sleeves:" + str(l.get("sleeves", "short")), "socks:" + str(l.get("socks", "high"))]
	var acc: Dictionary = l.get("acc", {})
	var any_acc := false
	for k in acc:
		if acc[k]:
			keys.append("acc:" + str(k))
			any_acc = true
	if any_acc:
		keys.append("acccol:" + str(l.get("acc_color", "")))
	var out := []
	for k in keys:
		if price(k) > 0:
			out.append(k)
	return out


static func strip_unowned(l: Dictionary) -> void:
	var d := default_look()
	for k in unowned(l):
		var kind: String = k.get_slice(":", 0)
		match kind:
			"boots": l["boots"] = d["boots"]
			"bootcol": l["boot_color"] = d["boot_color"]
			"sleeves": l["sleeves"] = d["sleeves"]
			"socks": l["socks"] = d["socks"]
			"acc": (l["acc"] as Dictionary)[k.get_slice(":", 1)] = false
			"acccol": l["acc_color"] = d["acc_color"]


static func default_look() -> Dictionary:
	return {"morphs": {}, "skin_tone": 0.45, "skin_warmth": 0.25, "hair": "hair_crop", "hair_color": "#1d1611",
		"beard": "none", "beard_color": "#1d1611", "brows": "brows_normal", "eye_color": "#3b2416",
		"height": 0.5, "build": {"body_muscular": 0.3, "body_heavy": 0.0, "body_slim": 0.0},
		"boots": 1, "boot_color": "#101010", "sleeves": "short", "socks": "high", "acc_color": "#f2f2f2",
		"acc": {"headband": false, "wristbands": false, "gloves": false, "armband": false}}


static func get_look() -> Dictionary:
	var l: Dictionary = Game.profile.get("look", {})
	var d := default_look()
	for k in l:
		d[k] = l[k]
	return d


static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var l := default_look()
	var m := {}
	for sl in FACE_SLIDERS:
		var v := clampf(rng.randfn(0.0, 0.32), -0.8, 0.8)
		if v < 0.0 and sl[1] != "":
			m[sl[1]] = -v
		elif v > 0.0:
			m[sl[2]] = v
	l["morphs"] = m
	l["skin_tone"] = clampf(rng.randfn(0.45, 0.22), 0.0, 1.0)
	l["skin_warmth"] = rng.randf_range(-0.2, 0.7)
	l["hair"] = HAIR[rng.randi_range(1, HAIR.size() - 1)]
	l["hair_color"] = HAIR_COLORS[rng.randi() % 6]
	l["beard"] = BEARD[rng.randi() % BEARD.size()] if rng.randf() < 0.55 else "none"
	l["beard_color"] = l["hair_color"]
	l["brows"] = BROWS[rng.randi() % 3]
	l["eye_color"] = EYE_COLORS[rng.randi() % 4]
	l["height"] = rng.randf_range(0.2, 0.8)
	var b := rng.randf()
	l["build"] = {"body_muscular": rng.randf_range(0.0, 0.7), "body_heavy": maxf(0.0, b - 0.75) * 2.0, "body_slim": maxf(0.0, 0.3 - b) * 2.0}
	l["boots"] = rng.randi_range(1, 4)
	l["boot_color"] = BOOT_COLORS[rng.randi() % BOOT_COLORS.size()]
	return l


## Map the selfie-AI JSON onto a look (keeps gear/height from `base`).
static func from_ai(ai: Dictionary, base: Dictionary) -> Dictionary:
	var l := base.duplicate(true)
	var m := {}
	var face: Dictionary = ai.get("face", {})
	for k in face:
		if k in MORPHS:
			m[k] = clampf(float(face[k]), 0.0, 1.0)
	l["morphs"] = m
	l["skin_tone"] = clampf(float(ai.get("skin_tone", l["skin_tone"])), 0.0, 1.0)
	l["skin_warmth"] = clampf(float(ai.get("skin_warmth", l["skin_warmth"])), -1.0, 1.0)
	if str(ai.get("hair_style", "")) in HAIR:
		l["hair"] = ai["hair_style"]
	if str(ai.get("beard", "")) in BEARD:
		l["beard"] = ai["beard"]
	for k in ["hair_color", "beard_color", "eye_color"]:
		var c := str(ai.get(k, ""))
		if c.begins_with("#") and c.length() == 7:
			l[k] = c
	var brows := str(ai.get("brows", "normal"))
	l["brows"] = "brows_" + brows if ("brows_" + brows) in BROWS else "brows_normal"
	match str(ai.get("build", "average")):
		"slim":
			l["build"] = {"body_muscular": 0.1, "body_heavy": 0.0, "body_slim": 0.6}
		"muscular":
			l["build"] = {"body_muscular": 0.8, "body_heavy": 0.0, "body_slim": 0.0}
		"heavy":
			l["build"] = {"body_muscular": 0.3, "body_heavy": 0.6, "body_slim": 0.0}
		_:
			l["build"] = {"body_muscular": 0.35, "body_heavy": 0.0, "body_slim": 0.0}
	var age := int(ai.get("age", 22))
	if age > 32:
		m["face_mature"] = maxf(float(m.get("face_mature", 0.0)), clampf((age - 30) / 25.0, 0.0, 0.8))
	return l


## Read a bipolar slider value (-1..1) from morphs.
static func slider_value(look: Dictionary, sl: Array) -> float:
	var m: Dictionary = look.get("morphs", {})
	var pos := float(m.get(sl[2], 0.0)) if sl[2] != "" else 0.0
	var neg := float(m.get(sl[1], 0.0)) if sl[1] != "" else 0.0
	return pos - neg


static func set_slider(look: Dictionary, sl: Array, v: float) -> void:
	var m: Dictionary = look.get("morphs", {})
	if sl[1] != "":
		m[sl[1]] = maxf(-v, 0.0)
	if sl[2] != "":
		m[sl[2]] = maxf(v, 0.0)
	look["morphs"] = m

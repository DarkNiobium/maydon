extends Node
## Global state: settings, player profile, save/load, scene switching.

const SAVE_PATH := "user://save.json"
const VERSION := 1

const KIT_PRESETS := [
	{"name": "Yashil", "shirt": Color(0.05, 0.55, 0.3), "shorts": Color(0.97, 0.97, 0.97), "socks": Color(0.05, 0.55, 0.3), "num": Color.WHITE, "pattern": 0},
	{"name": "Ko'k", "shirt": Color(0.07, 0.25, 0.7), "shorts": Color(0.07, 0.25, 0.7), "socks": Color(0.97, 0.97, 0.97), "num": Color.WHITE, "pattern": 1},
	{"name": "Qizil", "shirt": Color(0.78, 0.07, 0.1), "shorts": Color(0.1, 0.1, 0.12), "socks": Color(0.78, 0.07, 0.1), "num": Color.WHITE, "pattern": 0},
	{"name": "Oq", "shirt": Color(0.95, 0.95, 0.95), "shorts": Color(0.95, 0.95, 0.95), "socks": Color(0.95, 0.95, 0.95), "num": Color(0.1, 0.1, 0.2), "pattern": 2},
	{"name": "Qora", "shirt": Color(0.08, 0.08, 0.09), "shorts": Color(0.08, 0.08, 0.09), "socks": Color(0.08, 0.08, 0.09), "num": Color(1.0, 0.8, 0.2), "pattern": 3},
	{"name": "Sariq", "shirt": Color(1.0, 0.78, 0.1), "shorts": Color(0.06, 0.15, 0.4), "socks": Color(1.0, 0.78, 0.1), "num": Color(0.06, 0.15, 0.4), "pattern": 0},
	{"name": "Osmon", "shirt": Color(0.45, 0.72, 0.95), "shorts": Color(0.97, 0.97, 0.97), "socks": Color(0.45, 0.72, 0.95), "num": Color(0.05, 0.1, 0.3), "pattern": 1},
	{"name": "To'q qizil", "shirt": Color(0.45, 0.06, 0.16), "shorts": Color(0.45, 0.06, 0.16), "socks": Color(0.45, 0.06, 0.16), "num": Color(0.95, 0.8, 0.45), "pattern": 2},
	{"name": "Apelsin", "shirt": Color(0.98, 0.45, 0.08), "shorts": Color(0.1, 0.1, 0.1), "socks": Color(0.98, 0.45, 0.08), "num": Color(0.1, 0.1, 0.1), "pattern": 3},
	{"name": "Binafsha", "shirt": Color(0.35, 0.12, 0.6), "shorts": Color(0.97, 0.97, 0.97), "socks": Color(0.35, 0.12, 0.6), "num": Color.WHITE, "pattern": 1},
]

var settings := {
	"lang": "uz", "quality": -1, "camera": 0, "sfx": 0.0, "music": 0.0, "vibration": true,
	"btn_scale": 1.0, "btn_alpha": 0.8, "gk_assist": true, "aim_assist": 1.0,
	"difficulty": 1, "match_len": 240, "fps60": true, "mouse_sens": 0.5, "invert_y": false, "mode": 11,
}

var profile := {
	"name": "", "number": 10, "role": Footballer.Role.FWD, "face": 0, "skin": 1, "hair": 0,
	"boots": 0, "celebration": 0,
	"look": {},
	"xp": 0, "level": 1, "coins": 0,
	"career": {"matches": 0, "wins": 0, "draws": 0, "losses": 0, "goals": 0, "assists": 0,
		"motm": 0, "rating_sum": 0.0, "clean_sheets": 0, "saves": 0, "tackles": 0},
	"league": {},
	"unlocked": [],
	"tutorial_done": false,
	"created": false,
}

var next_match: MatchConfig = null
var next_match_meta := {}
var last_result := {}
var _fade: ColorRect


func _ready() -> void:
	load_game()
	if int(settings["quality"]) < 0:
		settings["quality"] = _detect_quality()
	TranslationServer.set_locale(settings["lang"])
	_apply_display()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var th := Theme.new()
	th.default_font = load("res://assets/fonts/Oswald.ttf")
	th.default_font_size = 28
	th.set_font_size("font_size", "LineEdit", 30)
	th.set_font_size("font_size", "SpinBox", 30)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	th.set_stylebox("normal", "LineEdit", sb)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.16, 0.86, 0.48)
	grab.set_corner_radius_all(6)
	grab.content_margin_top = 6
	grab.content_margin_bottom = 6
	th.set_stylebox("grabber_area", "HSlider", grab)
	th.set_stylebox("grabber_area_highlight", "HSlider", grab)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	th.set_stylebox("slider", "HSlider", track)
	get_tree().root.theme = th
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(_fade)


## Phone/tablet (native or mobile browser) vs. PC. Touch controls and phone-style
## assists only on phones; a touchscreen laptop is still a PC (mouse + keyboard).
static func is_phone() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


static func is_web() -> bool:
	return OS.has_feature("web")


func _detect_quality() -> int:
	if OS.has_feature("web"):
		return 0 if is_phone() else 1     # WebGL2: phones low, PC medium
	if OS.has_feature("mobile"):
		var name := RenderingServer.get_video_adapter_name().to_lower()
		if name.contains("adreno (tm) 6") or name.contains("adreno (tm) 7") or name.contains("mali-g7") or name.contains("immortalis") or name.contains("xclipse"):
			return 1
		return 0
	return 2


func _apply_display() -> void:
	Engine.max_fps = 60 if settings.get("fps60", true) else 30


func save_game() -> void:
	var data := {"v": VERSION, "settings": settings, "profile": profile}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var s: Dictionary = data.get("settings", {})
	for k in s:
		settings[k] = s[k]
	var p: Dictionary = data.get("profile", {})
	for k in p:
		profile[k] = p[k]


func set_lang(code: String) -> void:
	settings["lang"] = code
	TranslationServer.set_locale(code)
	save_game()


func goto(path: String) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.18)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(path))
	tw.tween_property(_fade, "color:a", 0.0, 0.25)


## Fixed team identities (blue vs orange) with realistic modern kits.
func team_kit(t: int) -> Dictionary:
	if t == 0:
		return {"name": "Blue", "shirt": Color(0.08, 0.32, 0.86), "shorts": Color(0.05, 0.12, 0.35), "socks": Color(0.08, 0.32, 0.86), "num": Color.WHITE, "pattern": 0}
	return {"name": "Orange", "shirt": Color(1.0, 0.42, 0.06), "shorts": Color(0.12, 0.12, 0.14), "socks": Color(1.0, 0.42, 0.06), "num": Color(0.08, 0.08, 0.1), "pattern": 0}


func kit(i: int) -> Dictionary:
	return KIT_PRESETS[clampi(i, 0, KIT_PRESETS.size() - 1)].duplicate()


## Pick an away kit that contrasts with `home`.
func contrasting_kit(home_idx: int, prefer: int) -> int:
	var hc: Color = KIT_PRESETS[home_idx]["shirt"]
	var best := prefer
	var bd := -1.0
	for i in KIT_PRESETS.size():
		if i == home_idx:
			continue
		var c: Color = KIT_PRESETS[i]["shirt"]
		var d := absf(c.get_luminance() - hc.get_luminance()) * 1.5 + Vector3(c.r - hc.r, c.g - hc.g, c.b - hc.b).length()
		if i == prefer:
			d += 0.4
		if d > bd:
			bd = d
			best = i
	return best


func player_name() -> String:
	var n: String = profile.get("name", "")
	return n if n != "" else "Siz"


func club_name() -> String:
	return "MAYDON"


## Quick match: Blue (you) vs Orange, REMATCH-style — no fake clubs.
func quick_match(per_side: int, role: int, difficulty: int, night := true) -> MatchConfig:
	var cfg := MatchConfig.new()
	cfg.per_side = per_side
	cfg.rules = MatchConfig.Rules.FULL if per_side >= 9 else MatchConfig.Rules.ARENA
	cfg.venue = "stadium" if per_side >= 9 else "arena"
	cfg.duration = float(settings["match_len"]) if per_side < 9 else float(settings["match_len"]) * 1.5
	cfg.difficulty = difficulty
	cfg.night = night
	cfg.seed = randi()
	cfg.team_names = [TranslationServer.translate("TEAM_BLUE"), TranslationServer.translate("TEAM_ORANGE")]
	cfg.team_short = [TranslationServer.translate("TEAM_BLUE_S"), TranslationServer.translate("TEAM_ORANGE_S")]
	cfg.kits = [team_kit(0), team_kit(1)]
	cfg.gk_kits = [{"shirt": Color(0.95, 0.85, 0.1), "shorts": Color(0.1, 0.1, 0.1), "socks": Color(0.95, 0.85, 0.1)},
		{"shirt": Color(0.2, 0.85, 0.35), "shorts": Color(0.1, 0.1, 0.1), "socks": Color(0.2, 0.85, 0.35)}]
	var lvl := 0.58 + float(profile.get("level", 1)) * 0.011
	cfg.team_strength = [0.62, [0.5, 0.6, 0.7, 0.8][clampi(difficulty, 0, 3)]]
	cfg.humans = [{"team": 0, "role": role, "idx": 0, "name": player_name(), "number": int(profile.get("number", 10)), "level": clampf(lvl, 0.55, 0.9)}]
	cfg.gk_assist = bool(settings.get("gk_assist", true))
	cfg.aim_assist = float(settings.get("aim_assist", 1.0))
	return cfg


func fade_flash() -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.12)
	tw.tween_property(_fade, "color:a", 0.0, 0.2)

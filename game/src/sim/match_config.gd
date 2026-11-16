class_name MatchConfig
extends RefCounted
## Everything needed to set up a match. Serializable to a Dictionary (network).

enum Rules { ARENA, FULL }

var per_side := 5
var rules := Rules.ARENA
var duration := 300.0            # real seconds of play (FULL: both halves)
var difficulty := 1              # 0 easy, 1 normal, 2 hard, 3 legend
var seed := 1
var venue := "arena"
var night := true
var formation := ["", ""]         # formation id per team ("" = default)
var team_names := ["", ""]
var team_short := ["", ""]
var kits := [{}, {}]              # {"shirt":Color, "shorts":Color, "socks":Color, "num":Color, "pattern":int}
var gk_kits := [{}, {}]
var humans := []                  # [{team:int, role:int, idx:int, name:String}] — one per human
var team_strength := [0.6, 0.6]   # average attribute level per team (AI teams)
var ai_only := false
var gk_assist := true             # human goalkeepers dive automatically
var aim_assist := 1.0             # 0..1
var auto_pass_power := true


func to_dict() -> Dictionary:
	return {
		"per_side": per_side, "rules": rules, "duration": duration,
		"difficulty": difficulty, "seed": seed, "venue": venue, "night": night,
		"formation": formation, "team_names": team_names, "team_short": team_short,
		"kits": _kits_out(kits), "gk_kits": _kits_out(gk_kits), "humans": humans,
		"team_strength": team_strength, "ai_only": ai_only, "gk_assist": gk_assist,
		"aim_assist": aim_assist,
	}


static func from_dict(d: Dictionary) -> MatchConfig:
	var c := MatchConfig.new()
	c.per_side = int(d.get("per_side", 5))
	c.rules = int(d.get("rules", 0))
	c.duration = float(d.get("duration", 300.0))
	c.difficulty = int(d.get("difficulty", 1))
	c.seed = int(d.get("seed", 1))
	c.venue = str(d.get("venue", "arena"))
	c.night = bool(d.get("night", true))
	c.formation = d.get("formation", ["", ""])
	c.team_names = d.get("team_names", ["", ""])
	c.team_short = d.get("team_short", ["", ""])
	c.kits = _kits_in(d.get("kits", [{}, {}]))
	c.gk_kits = _kits_in(d.get("gk_kits", [{}, {}]))
	c.humans = d.get("humans", [])
	c.team_strength = d.get("team_strength", [0.6, 0.6])
	c.ai_only = bool(d.get("ai_only", false))
	c.gk_assist = bool(d.get("gk_assist", true))
	c.aim_assist = float(d.get("aim_assist", 1.0))
	return c


static func _kits_out(k: Array) -> Array:
	var out := []
	for kit in k:
		var o := {}
		for key in kit:
			var v = kit[key]
			o[key] = v.to_html() if v is Color else v
		out.append(o)
	return out


static func _kits_in(k: Array) -> Array:
	var out := []
	for kit in k:
		var o := {}
		for key in kit:
			var v = kit[key]
			o[key] = Color.html(v) if v is String and key != "name" else v
		out.append(o)
	return out

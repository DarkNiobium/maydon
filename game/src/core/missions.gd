class_name Missions
extends RefCounted
## Daily missions: 3 per day (seeded by the date), progress from finished
## matches, coin + XP rewards claimed in the lobby.

const TEMPLATES := [
	{"id": "goals", "stat": "goals", "n": [1, 2, 3], "coins": 120, "label": "MS_GOALS"},
	{"id": "assists", "stat": "assists", "n": [1, 2], "coins": 120, "label": "MS_ASSISTS"},
	{"id": "passes", "stat": "passes_ok", "n": [10, 15, 25], "coins": 80, "label": "MS_PASSES"},
	{"id": "tackles", "stat": "tackles_won", "n": [3, 5, 8], "coins": 80, "label": "MS_TACKLES"},
	{"id": "shots", "stat": "on_target", "n": [2, 3, 5], "coins": 80, "label": "MS_SHOTS"},
	{"id": "win", "stat": "_win", "n": [1, 2], "coins": 150, "label": "MS_WIN"},
	{"id": "play", "stat": "_play", "n": [2, 3], "coins": 60, "label": "MS_PLAY"},
	{"id": "rating", "stat": "_rating7", "n": [1, 2], "coins": 100, "label": "MS_RATING"},
]


static func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


## Today's missions (regenerated when the day changes).
static func list() -> Array:
	var p: Dictionary = Game.profile
	var m: Dictionary = p.get("missions", {})
	var day := _today()
	if str(m.get("day", "")) != day:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(day + str(p.get("name", "")))
		var pool := range(TEMPLATES.size())
		var out := []
		for i in 3:
			var k: int = pool.pop_at(rng.randi() % pool.size())
			var t: Dictionary = TEMPLATES[k]
			var ns: Array = t["n"]
			var tier := rng.randi() % ns.size()
			out.append({"id": t["id"], "target": ns[tier], "prog": 0, "claimed": false,
				"coins": int(t["coins"] * (1.0 + tier * 0.5))})
		m = {"day": day, "list": out}
		p["missions"] = m
	return m["list"]


static func template(id: String) -> Dictionary:
	for t in TEMPLATES:
		if t["id"] == id:
			return t
	return {}


static func label(ms: Dictionary) -> String:
	var t := template(ms["id"])
	return TranslationServer.translate(t.get("label", "")).replace("{n}", str(int(ms["target"])))


static func claimable() -> int:
	var n := 0
	for ms in list():
		if int(ms["prog"]) >= int(ms["target"]) and not ms["claimed"]:
			n += 1
	return n


## Called after every finished match with the human's stats.
static func on_match(st: Dictionary, won: bool, rating: float) -> void:
	for ms in list():
		var t := template(ms["id"])
		var add := 0
		match str(t.get("stat", "")):
			"_win":
				add = 1 if won else 0
			"_play":
				add = 1
			"_rating7":
				add = 1 if rating >= 7.0 else 0
			var s:
				add = int(st.get(s, 0))
		ms["prog"] = mini(int(ms["prog"]) + add, int(ms["target"]))


static func claim(i: int) -> int:
	var l := list()
	if i < 0 or i >= l.size():
		return 0
	var ms: Dictionary = l[i]
	if ms["claimed"] or int(ms["prog"]) < int(ms["target"]):
		return 0
	ms["claimed"] = true
	var c := int(ms["coins"])
	Game.profile["coins"] = int(Game.profile.get("coins", 0)) + c
	Game.save_game()
	return c

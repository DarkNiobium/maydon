class_name League
extends RefCounted
## Season logic: Tashkent district league (5v5 arena) → national league of
## regions (11v11 stadium). Other matches are simulated with a Poisson model.

const TIER_NAMES := ["LEAGUE_TITLE", "REPUBLIC_TITLE"]


static func new_season(tier: int, season_no: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var names: Array = Names.DISTRICTS if tier == 0 else Names.REGIONS.slice(0, 12)
	var user_idx := int(Game.profile["club"].get("district", 0)) % names.size() if tier == 0 else 0
	var teams := []
	for i in names.size():
		var t := {"name": names[i], "short": str(names[i]).substr(0, 3).to_upper(), "user": i == user_idx,
			"strength": clampf(0.5 + tier * 0.1 + season_no * 0.015 + rng.randf_range(-0.07, 0.09), 0.4, 0.88),
			"kit": rng.randi() % Game.KIT_PRESETS.size(),
			"p": 0, "w": 0, "d": 0, "l": 0, "gf": 0, "ga": 0, "pts": 0}
		if t["user"]:
			t["name"] = Game.club_name()
			t["short"] = Game.club_short()
			t["kit"] = int(Game.profile["club"].get("kit", 0))
		teams.append(t)
	return {"tier": tier, "season": season_no, "teams": teams, "fixtures": _round_robin(teams.size()),
		"round": 0, "user": user_idx, "done": false, "history": []}


static func _round_robin(n: int) -> Array:
	var ids := range(n)
	var rounds := []
	for r in n - 1:
		var pairs := []
		for i in n / 2:
			var a: int = ids[i]
			var b: int = ids[n - 1 - i]
			pairs.append([a, b] if (r + i) % 2 == 0 else [b, a])
		rounds.append(pairs)
		# rotate all but the first
		var last: int = ids.pop_back()
		ids.insert(1, last)
	return rounds


static func user_fixture(lg: Dictionary) -> Array:
	var r := int(lg["round"])
	if r >= lg["fixtures"].size():
		return []
	var u := int(lg["user"])
	for pr in lg["fixtures"][r]:
		if int(pr[0]) == u or int(pr[1]) == u:
			return [int(pr[0]), int(pr[1])]
	return []


static func sim_score(sa: float, sb: float, per_side: int, rng: RandomNumberGenerator) -> Array:
	var base := 2.3 if per_side <= 5 else 1.35
	var la := base * exp((sa - sb) * 2.4) * 1.05
	var lb := base * exp((sb - sa) * 2.4)
	return [_poisson(la, rng), _poisson(lb, rng)]


static func _poisson(l: float, rng: RandomNumberGenerator) -> int:
	var L := exp(-l)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= L:
			break
		k += 1
	return k


static func record(lg: Dictionary, a: int, b: int, ga: int, gb: int) -> void:
	var ta: Dictionary = lg["teams"][a]
	var tb: Dictionary = lg["teams"][b]
	for t in [ta, tb]:
		for k in ["p", "w", "d", "l", "gf", "ga", "pts"]:
			t[k] = int(t[k])
	ta["p"] += 1
	tb["p"] += 1
	ta["gf"] += ga
	ta["ga"] += gb
	tb["gf"] += gb
	tb["ga"] += ga
	if ga > gb:
		ta["w"] += 1
		tb["l"] += 1
		ta["pts"] += 3
	elif gb > ga:
		tb["w"] += 1
		ta["l"] += 1
		tb["pts"] += 3
	else:
		ta["d"] += 1
		tb["d"] += 1
		ta["pts"] += 1
		tb["pts"] += 1


## Apply the user's result and simulate the rest of the round.
static func finish_round(lg: Dictionary, user_goals: int, opp_goals: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var per_side := 5 if lg["tier"] == 0 else 11
	var results := []
	var u := int(lg["user"])
	for pr in lg["fixtures"][int(lg["round"])]:
		var a: int = int(pr[0])
		var b: int = int(pr[1])
		var ga := 0
		var gb := 0
		if a == u:
			ga = user_goals
			gb = opp_goals
		elif b == u:
			ga = opp_goals
			gb = user_goals
		else:
			var sc := sim_score(lg["teams"][a]["strength"], lg["teams"][b]["strength"], per_side, rng)
			ga = sc[0]
			gb = sc[1]
		record(lg, a, b, ga, gb)
		results.append([a, b, ga, gb])
	lg["history"].append(results)
	lg["round"] = int(lg["round"]) + 1
	if int(lg["round"]) >= lg["fixtures"].size():
		lg["done"] = true
	return results


static func standings(lg: Dictionary) -> Array:
	var idx := range(lg["teams"].size())
	var teams: Array = lg["teams"]
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ta: Dictionary = teams[a]
		var tb: Dictionary = teams[b]
		if ta["pts"] != tb["pts"]:
			return ta["pts"] > tb["pts"]
		var gda: int = ta["gf"] - ta["ga"]
		var gdb: int = tb["gf"] - tb["ga"]
		if gda != gdb:
			return gda > gdb
		return ta["gf"] > tb["gf"])
	return idx


static func user_place(lg: Dictionary) -> int:
	return standings(lg).find(int(lg["user"])) + 1


## Build the MatchConfig for the user's next league match.
static func next_match_config(lg: Dictionary) -> MatchConfig:
	var pr := user_fixture(lg)
	if pr.is_empty():
		return null
	var home: bool = pr[0] == int(lg["user"])
	var opp: int = pr[1] if home else pr[0]
	var per_side := 5 if lg["tier"] == 0 else 11
	var role := int(Game.profile.get("role", Footballer.Role.FWD))
	var cfg := Game.quick_match(per_side, role, int(Game.settings.get("difficulty", 1)), int(lg["round"]) % 3 != 1)
	var ot: Dictionary = lg["teams"][opp]
	var ut: Dictionary = lg["teams"][int(lg["user"])]
	var away_kit := Game.contrasting_kit(int(ut["kit"]), int(ot["kit"]))
	cfg.team_names = [ut["name"], ot["name"]]
	cfg.team_short = [ut["short"], ot["short"]]
	cfg.kits = [Game.kit(int(ut["kit"])), Game.kit(away_kit)]
	var diff_off: float = [-0.08, 0.0, 0.07, 0.14][clampi(int(Game.settings.get("difficulty", 1)), 0, 3)]
	cfg.team_strength = [clampf(float(ut["strength"]) + 0.04, 0.45, 0.9), clampf(float(ot["strength"]) + diff_off, 0.4, 0.95)]
	return cfg


# ---------------------------------------------------------------------------
# Progression
# ---------------------------------------------------------------------------

static func xp_for_level(lvl: int) -> int:
	return 250 + lvl * 120


## Apply a finished match to the profile. Returns a summary for the results screen.
static func apply_result(res: Dictionary) -> Dictionary:
	var hid: int = res.get("human_id", -1)
	var out := {"xp": 0, "coins": 0, "level_up": false, "rating": 0.0, "motm": false}
	if hid < 0:
		return out
	var me: Dictionary = {}
	var best_r := -1.0
	var best_id := -1
	for r in res["ratings"]:
		if r["id"] == hid:
			me = r
		if r["rating"] > best_r:
			best_r = r["rating"]
			best_id = r["id"]
	var team: int = me.get("team", 0)
	var gf: int = res["score"][team]
	var ga: int = res["score"][1 - team]
	var st: Dictionary = me.get("stats", {})
	var rating: float = me.get("rating", 6.0)
	if bool(res.get("team_mode", false)):
		# the human controlled the whole team: credit team totals, average field rating
		var agg := {}
		var rs := 0.0
		var rn := 0
		for r in res["ratings"]:
			if int(r["team"]) != team:
				continue
			for k in (r["stats"] as Dictionary):
				if typeof(r["stats"][k]) in [TYPE_INT, TYPE_FLOAT]:
					agg[k] = agg.get(k, 0) + r["stats"][k]
			if int(r.get("role", 1)) != Footballer.Role.GK:
				rs += float(r["rating"])
				rn += 1
		st = agg
		rating = rs / maxf(rn, 1)
	var xp := 60 + int(rating * 12.0) + int(st.get("goals", 0)) * 25 + int(st.get("assists", 0)) * 18
	xp += 60 if gf > ga else (25 if gf == ga else 0)
	var motm := best_id == hid
	if motm:
		xp += 40
	var coins := xp / 3
	var p: Dictionary = Game.profile
	p["xp"] = int(p.get("xp", 0)) + xp
	p["coins"] = int(p.get("coins", 0)) + coins
	var lvl := int(p.get("level", 1))
	var leveled := false
	while int(p["xp"]) >= xp_for_level(lvl):
		p["xp"] = int(p["xp"]) - xp_for_level(lvl)
		lvl += 1
		leveled = true
	p["level"] = lvl
	var c: Dictionary = p["career"]
	c["matches"] = int(c.get("matches", 0)) + 1
	if gf > ga:
		c["wins"] = int(c.get("wins", 0)) + 1
	elif gf == ga:
		c["draws"] = int(c.get("draws", 0)) + 1
	else:
		c["losses"] = int(c.get("losses", 0)) + 1
	c["goals"] = int(c.get("goals", 0)) + int(st.get("goals", 0))
	c["assists"] = int(c.get("assists", 0)) + int(st.get("assists", 0))
	c["saves"] = int(c.get("saves", 0)) + int(st.get("saves", 0))
	c["tackles"] = int(c.get("tackles", 0)) + int(st.get("tackles_won", 0))
	c["rating_sum"] = float(c.get("rating_sum", 0.0)) + rating
	if motm:
		c["motm"] = int(c.get("motm", 0)) + 1
	if ga == 0 and int(me.get("role", 0)) in [Footballer.Role.GK, Footballer.Role.DEF]:
		c["clean_sheets"] = int(c.get("clean_sheets", 0)) + 1
	Missions.on_match(st, gf > ga, rating)
	Game.save_game()
	out = {"xp": xp, "coins": coins, "level_up": leveled, "rating": rating, "motm": motm,
		"level": lvl, "xp_now": int(p["xp"]), "xp_need": xp_for_level(lvl)}
	return out


## Overall rating shown on the player card (40..99).
static func overall() -> int:
	var lvl := int(Game.profile.get("level", 1))
	return clampi(58 + lvl * 2, 40, 99)

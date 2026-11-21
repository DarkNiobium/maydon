extends RefCounted
## Shared match configs for the trailer: the scan (headless) and the director
## (rendered) must build identical configs so the deterministic sim replays the same goals.

static func make(kind: String, seed: int) -> MatchConfig:
	var per := 5
	if kind.begins_with("stadium"):
		per = 11
	elif kind.begins_with("arena3"):
		per = 3
	var cfg := Game.quick_match(per, Footballer.Role.FWD, 2, not kind.ends_with("day"))
	cfg.night = not kind.ends_with("day")
	cfg.seed = seed
	cfg.humans = []
	cfg.duration = 600.0 if per >= 9 else 300.0
	cfg.difficulty = 2
	cfg.team_strength = [0.8, 0.8]
	cfg.team_names = ["BLUE", "ORANGE"]
	cfg.team_short = ["BLU", "ORG"]
	return cfg

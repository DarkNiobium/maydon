class_name Formations
extends RefCounted
## Slot layouts in normalized pitch space for a team attacking +X:
## x ∈ [-1, 1] (own goal line → opponent goal line), z ∈ [-1, 1] (+z = right).
## Each slot: role, defensive shape position, attacking shape position.

const R_GK := Footballer.Role.GK
const R_DEF := Footballer.Role.DEF
const R_MID := Footballer.Role.MID
const R_FWD := Footballer.Role.FWD

const DATA := {
	"3": [
		[R_GK, Vector2(-0.9, 0.0), Vector2(-0.78, 0.0)],
		[R_DEF, Vector2(-0.42, -0.22), Vector2(0.05, -0.45)],
		[R_FWD, Vector2(-0.12, 0.25), Vector2(0.52, 0.3)],
	],
	"5": [
		[R_GK, Vector2(-0.9, 0.0), Vector2(-0.75, 0.0)],
		[R_DEF, Vector2(-0.55, -0.38), Vector2(-0.08, -0.6)],
		[R_DEF, Vector2(-0.55, 0.38), Vector2(-0.08, 0.6)],
		[R_MID, Vector2(-0.28, 0.0), Vector2(0.3, 0.0)],
		[R_FWD, Vector2(-0.02, 0.0), Vector2(0.62, 0.08)],
	],
	"7": [
		[R_GK, Vector2(-0.92, 0.0), Vector2(-0.78, 0.0)],
		[R_DEF, Vector2(-0.6, -0.4), Vector2(-0.15, -0.55)],
		[R_DEF, Vector2(-0.62, 0.0), Vector2(-0.3, 0.0)],
		[R_DEF, Vector2(-0.6, 0.4), Vector2(-0.15, 0.55)],
		[R_MID, Vector2(-0.3, -0.45), Vector2(0.3, -0.7)],
		[R_MID, Vector2(-0.3, 0.45), Vector2(0.3, 0.7)],
		[R_FWD, Vector2(-0.05, 0.0), Vector2(0.65, 0.0)],
	],
	"4-3-3": [
		[R_GK, Vector2(-0.95, 0.0), Vector2(-0.82, 0.0)],
		[R_DEF, Vector2(-0.64, -0.66), Vector2(-0.05, -0.88)],
		[R_DEF, Vector2(-0.72, -0.24), Vector2(-0.34, -0.3)],
		[R_DEF, Vector2(-0.72, 0.24), Vector2(-0.34, 0.3)],
		[R_DEF, Vector2(-0.64, 0.66), Vector2(-0.05, 0.88)],
		[R_MID, Vector2(-0.5, 0.0), Vector2(0.02, 0.0)],
		[R_MID, Vector2(-0.38, -0.34), Vector2(0.25, -0.38)],
		[R_MID, Vector2(-0.38, 0.34), Vector2(0.25, 0.38)],
		[R_FWD, Vector2(-0.18, -0.68), Vector2(0.6, -0.78)],
		[R_FWD, Vector2(-0.1, 0.0), Vector2(0.72, 0.0)],
		[R_FWD, Vector2(-0.18, 0.68), Vector2(0.6, 0.78)],
	],
	"4-4-2": [
		[R_GK, Vector2(-0.95, 0.0), Vector2(-0.82, 0.0)],
		[R_DEF, Vector2(-0.64, -0.66), Vector2(-0.08, -0.86)],
		[R_DEF, Vector2(-0.72, -0.24), Vector2(-0.34, -0.3)],
		[R_DEF, Vector2(-0.72, 0.24), Vector2(-0.34, 0.3)],
		[R_DEF, Vector2(-0.64, 0.66), Vector2(-0.08, 0.86)],
		[R_MID, Vector2(-0.4, -0.66), Vector2(0.38, -0.8)],
		[R_MID, Vector2(-0.45, -0.2), Vector2(0.12, -0.22)],
		[R_MID, Vector2(-0.45, 0.2), Vector2(0.12, 0.22)],
		[R_MID, Vector2(-0.4, 0.66), Vector2(0.38, 0.8)],
		[R_FWD, Vector2(-0.12, -0.16), Vector2(0.7, -0.18)],
		[R_FWD, Vector2(-0.14, 0.16), Vector2(0.68, 0.2)],
	],
	"4-2-3-1": [
		[R_GK, Vector2(-0.95, 0.0), Vector2(-0.82, 0.0)],
		[R_DEF, Vector2(-0.64, -0.66), Vector2(-0.06, -0.86)],
		[R_DEF, Vector2(-0.72, -0.24), Vector2(-0.34, -0.3)],
		[R_DEF, Vector2(-0.72, 0.24), Vector2(-0.34, 0.3)],
		[R_DEF, Vector2(-0.64, 0.66), Vector2(-0.06, 0.86)],
		[R_MID, Vector2(-0.52, -0.18), Vector2(-0.02, -0.2)],
		[R_MID, Vector2(-0.52, 0.18), Vector2(-0.02, 0.2)],
		[R_MID, Vector2(-0.28, -0.62), Vector2(0.52, -0.74)],
		[R_MID, Vector2(-0.26, 0.0), Vector2(0.45, 0.0)],
		[R_MID, Vector2(-0.28, 0.62), Vector2(0.52, 0.74)],
		[R_FWD, Vector2(-0.1, 0.0), Vector2(0.74, 0.0)],
	],
}


static func default_for(per_side: int) -> String:
	if per_side <= 3:
		return "3"
	if per_side <= 5:
		return "5"
	if per_side <= 7:
		return "7"
	return "4-3-3"


static func get_slots(id: String, per_side: int) -> Array:
	if id == "" or not DATA.has(id) or DATA[id].size() != per_side:
		id = default_for(per_side)
	return DATA[id]


static func role_name(r: int) -> String:
	return ["GK", "DEF", "MID", "FWD"][r]

class_name Pitch
extends RefCounted
## Pitch geometry. Origin = centre spot, length along X (goals at x = ±length/2),
## width along Z, Y up. Team attacking +X shoots at the goal with side = +1.

enum Surface { GRASS, TURF }

var length := 105.0
var width := 68.0
var goal_width := 7.32
var goal_height := 2.44
var goal_depth := 2.2
var post_radius := 0.06
var line_half := 0.06            # half width of painted lines
var box_depth := 16.5
var box_width := 40.32
var six_depth := 5.5
var six_width := 18.32
var circle_radius := 9.15
var penalty_spot := 11.0
var walls := false               # arena: ball rebounds off the boundary
var wall_chamfer := 0.0          # arena: 45° corner walls of this leg length
var wall_restitution := 0.62
var runoff_x := 5.0              # distance from goal line to ad boards (no walls)
var runoff_z := 4.0
var surface := Surface.GRASS
var name := "stadium"


static func full() -> Pitch:
	var p := Pitch.new()
	return p


## Small-sided arena with walls (3v3 / 5v5), REMATCH-like rules.
static func arena(per_side: int) -> Pitch:
	var p := Pitch.new()
	p.name = "arena"
	p.walls = true
	p.surface = Surface.TURF
	if per_side <= 3:
		p.length = 36.0
		p.width = 22.0
		p.goal_width = 4.6
		p.goal_height = 2.0
		p.box_depth = 6.5
		p.box_width = 12.0
	elif per_side <= 5:
		p.length = 44.0
		p.width = 26.0
		p.goal_width = 5.2
		p.goal_height = 2.2
		p.box_depth = 8.0
		p.box_width = 14.0
	else:
		p.length = 64.0
		p.width = 40.0
		p.goal_width = 6.0
		p.goal_height = 2.2
		p.box_depth = 11.0
		p.box_width = 22.0
	p.goal_depth = 1.6
	p.six_depth = p.box_depth * 0.45
	p.six_width = p.goal_width + 3.0
	p.circle_radius = minf(5.0, p.width * 0.2)
	p.penalty_spot = p.box_depth * 0.75
	p.wall_chamfer = 2.5
	p.runoff_x = 0.0
	p.runoff_z = 0.0
	return p


func hl() -> float:
	return length * 0.5


func hw() -> float:
	return width * 0.5


## X of the goal line of the goal on `side` (+1 / -1).
func goal_x(side: int) -> float:
	return hl() * side


func goal_center(side: int) -> Vector3:
	return Vector3(hl() * side, 0.0, 0.0)


## Point inside the penalty area of goal `side` (horizontal test).
func in_box(p: Vector3, side: int) -> bool:
	var dx := (hl() - p.x * side)
	return dx >= -0.5 and dx <= box_depth and absf(p.z) <= box_width * 0.5


func in_six(p: Vector3, side: int) -> bool:
	var dx := (hl() - p.x * side)
	return dx >= -0.5 and dx <= six_depth and absf(p.z) <= six_width * 0.5


func in_field(p: Vector3, margin := 0.0) -> bool:
	return absf(p.x) <= hl() + margin and absf(p.z) <= hw() + margin


## Clamp a point to where a player can stand.
func clamp_player(p: Vector3) -> Vector3:
	var mx := hl() + (runoff_x - 0.6 if not walls else -0.45)
	var mz := hw() + (runoff_z - 0.6 if not walls else -0.45)
	p.x = clampf(p.x, -mx, mx)
	p.z = clampf(p.z, -mz, mz)
	if walls and wall_chamfer > 0.0:
		# keep players out of the chamfered corners
		var lim := hl() + hw() - wall_chamfer - 0.85
		var s := absf(p.x) + absf(p.z)
		if s > lim:
			var over := (s - lim) * 0.5
			p.x = signf(p.x) * (absf(p.x) - over)
			p.z = signf(p.z) * (absf(p.z) - over)
	return p


## Penalty spot of goal `side`.
func penalty_point(side: int) -> Vector3:
	return Vector3((hl() - penalty_spot) * side, 0.0, 0.0)

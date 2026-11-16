class_name Cmd
extends RefCounted
## One tick of intent for a footballer. Produced by AI or by the human
## controller (touch / keyboard / gamepad / network) — both use identical
## mechanics, so bots and players play by the same rules.

enum Act {
	NONE, PASS, THROUGH, LOB, CROSS, SHOT, CHIP, HEADER, TACKLE, SLIDE,
	GK_DIVE, GK_THROW, GK_KICK, THROW_IN, SKILL, CLEAR,
}

var move := Vector3.ZERO        # desired velocity direction × magnitude (0..1), world XZ
var sprint := false
var jockey := false             # face `look` while moving (defending stance)
var look := Vector3.INF         # optional point to face
var act := Act.NONE             # requested action (edge, consumed by the sim)
var target := Vector3.ZERO      # action target point (world)
var power := 0.0                # 0..1
var spin := Vector3.ZERO        # requested spin (rad/s) for curled shots/passes
var receiver := -1              # intended receiver id for passes
var skill := 0                  # skill move id (1 = step-over left, 2 = right, 3 = drag back)
var first_time := false         # queue the action for when the ball arrives


func clear_action() -> void:
	act = Act.NONE
	receiver = -1
	skill = 0
	first_time = false
	spin = Vector3.ZERO


func copy_from(o: Cmd) -> void:
	move = o.move
	sprint = o.sprint
	jockey = o.jockey
	look = o.look
	act = o.act
	target = o.target
	power = o.power
	spin = o.spin
	receiver = o.receiver
	skill = o.skill
	first_time = o.first_time

class_name CharacterLibrary
extends RefCounted
## Skinned character assets (generated MPFB humans + retargeted animations).

static var _checked := false
static var _ok := false


static func available() -> bool:
	if not _checked:
		_checked = true
		_ok = ResourceLoader.exists("res://assets/chars/player_base.tscn") and not OS.get_cmdline_user_args().has("--simple")
	return _ok

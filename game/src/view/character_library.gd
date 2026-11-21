class_name CharacterLibrary
extends RefCounted
## Skinned character assets (generated MPFB humans + retargeted animations).

static var _checked := false
static var _ok := false


static func available() -> bool:
	if not _checked:
		_checked = true
		_ok = not OS.get_cmdline_user_args().has("--simple") and CharacterView.load_shared()
	return _ok

class_name AiFace
extends Node
## Selfie → character parameters with Google Gemini (vision + JSON schema).
## Usage: var ai := AiFace.new(); add_child(ai); ai.done.connect(cb); ai.analyze(image)

signal done(ok: bool, data: Dictionary, err: String)

const SALT := "MAYDON-7f3k9q-football"
const MODELS := ["gemini-flash-latest", "gemini-2.5-flash", "gemini-3-flash-preview"]
const URL := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
const PROMPT := """You are the character-creator assistant of a realistic football video game.
Look at the person's face in the photo and choose game character parameters that make the in-game footballer resemble them.
Return JSON only. Rules:
- skin_tone: 0.0 = very fair/European, 0.5 = olive / Central Asian, 1.0 = very dark/African.
- skin_warmth: -1 (pink/cool) .. 1 (golden/warm).
- face morphs: each 0.0..1.0, 0 = average, 1 = strongly that trait. Opposite pairs (e.g. jaw_wide vs jaw_narrow) must not both be > 0. Use 0 for average features; typical faces have most values between 0 and 0.6.
- hair_style: the closest from the list; hair_color and beard_color as #rrggbb natural colours.
- beard: closest facial hair from the list ("none" if clean shaven).
- brows: thin | normal | thick. eye_color #rrggbb.
- age: estimated years. build: slim | average | muscular | heavy (judge from face/neck).
- If there is no clear single human face, return {"error": "no_face"}."""

var _http: HTTPRequest
var _model_i := 0
var _body := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 45.0
	add_child(_http)
	_http.request_completed.connect(_on_done)


static func api_key() -> String:
	var p := "res://assets/secret/k.bin"
	if FileAccess.file_exists(p):
		var b := FileAccess.get_file_as_bytes(p)
		var s := SALT.to_utf8_buffer()
		var out := PackedByteArray()
		out.resize(b.size())
		for i in b.size():
			out[i] = b[i] ^ s[i % s.size()]
		return out.get_string_from_utf8()
	if not OS.has_feature("mobile"):
		var dev := OS.get_environment("HOME") + "/maydon/.secrets/gemini_key"
		if FileAccess.file_exists(dev):
			return FileAccess.get_file_as_string(dev).strip_edges()
	return ""


func _schema() -> Dictionary:
	var face := {}
	for m in Look.MORPHS:
		face[m] = {"type": "NUMBER"}
	return {"type": "OBJECT", "properties": {
		"error": {"type": "STRING"},
		"skin_tone": {"type": "NUMBER"}, "skin_warmth": {"type": "NUMBER"},
		"hair_style": {"type": "STRING", "enum": Look.HAIR}, "hair_color": {"type": "STRING"},
		"beard": {"type": "STRING", "enum": Look.BEARD}, "beard_color": {"type": "STRING"},
		"brows": {"type": "STRING", "enum": ["thin", "normal", "thick"]}, "eye_color": {"type": "STRING"},
		"age": {"type": "INTEGER"}, "build": {"type": "STRING", "enum": ["slim", "average", "muscular", "heavy"]},
		"face": {"type": "OBJECT", "properties": face}}}


## Prepare (downscale + JPEG) and send.
func analyze(img: Image) -> void:
	var im := img.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	var m := maxi(im.get_width(), im.get_height())
	if m > 768:
		var k := 768.0 / m
		im.resize(int(im.get_width() * k), int(im.get_height() * k), Image.INTERPOLATE_LANCZOS)
	im.convert(Image.FORMAT_RGB8)
	var jpg := im.save_jpg_to_buffer(0.85)
	var body := {"contents": [{"parts": [{"text": PROMPT},
		{"inlineData": {"mimeType": "image/jpeg", "data": Marshalls.raw_to_base64(jpg)}}]}],
		"generationConfig": {"responseMimeType": "application/json", "responseSchema": _schema(), "temperature": 0.2}}
	_body = JSON.stringify(body)
	_model_i = 0
	_send()


func _send() -> void:
	var key := api_key()
	if key == "":
		done.emit(false, {}, "no_key")
		return
	var headers := ["Content-Type: application/json", "x-goog-api-key: " + key]
	var err := _http.request(URL % MODELS[_model_i], headers, HTTPClient.METHOD_POST, _body)
	if err != OK:
		done.emit(false, {}, "net")


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		if _retry():
			return
		done.emit(false, {}, "net")
		return
	if code != 200:
		if _retry():
			return
		done.emit(false, {}, "http_%d" % code)
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY:
		done.emit(false, {}, "parse")
		return
	var txt := ""
	var cands: Array = d.get("candidates", [])
	if not cands.is_empty():
		var parts: Array = cands[0].get("content", {}).get("parts", [])
		if not parts.is_empty():
			txt = str(parts[0].get("text", ""))
	var out = JSON.parse_string(txt)
	if typeof(out) != TYPE_DICTIONARY:
		done.emit(false, {}, "parse")
		return
	if out.has("error") and str(out["error"]) != "":
		done.emit(false, out, str(out["error"]))
		return
	done.emit(true, out, "")


func _retry() -> bool:
	_model_i += 1
	if _model_i < MODELS.size():
		_send()
		return true
	return false

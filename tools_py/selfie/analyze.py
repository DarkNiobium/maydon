#!/usr/bin/env python3
"""Selfie -> MAYDON character parameters via Gemini (prompt prototype; the game uses the same prompt)."""
import json, base64, sys, urllib.request, os, time
KEY = open(os.path.expanduser("~/maydon/.secrets/gemini_key")).read().strip()
MODEL = os.environ.get("MODEL", "gemini-3.8-flash")
MORPHS = ["head_round","head_square","head_long","jaw_wide","jaw_narrow","chin_out","chin_in","chin_wide","cheekbones_high","cheeks_full","cheeks_hollow","nose_wide","nose_narrow","nose_long","nose_short","nose_hump","nose_flat","eyes_big","eyes_small","eyes_wide","eyes_close","eyes_slant_up","eyes_monolid","brow_heavy","brow_high","lips_full","lips_thin","mouth_wide","ears_big","ears_out","forehead_high","face_mature"]
HAIR = ["bald","hair_buzz","hair_short_fade","hair_crop","hair_side_part","hair_slick_back","hair_quiff","hair_curly","hair_afro","hair_mohawk","hair_man_bun","hair_long","hair_braids"]
BEARD = ["none","beard_stubble","beard_short","beard_full","beard_goatee","beard_mustache","beard_chinstrap"]
PROMPT = """You are the character-creator assistant of a realistic football video game.
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
SCHEMA = {"type": "OBJECT", "properties": {
    "error": {"type": "STRING"},
    "skin_tone": {"type": "NUMBER"}, "skin_warmth": {"type": "NUMBER"},
    "hair_style": {"type": "STRING", "enum": HAIR}, "hair_color": {"type": "STRING"},
    "beard": {"type": "STRING", "enum": BEARD}, "beard_color": {"type": "STRING"},
    "brows": {"type": "STRING", "enum": ["thin", "normal", "thick"]}, "eye_color": {"type": "STRING"},
    "age": {"type": "INTEGER"}, "build": {"type": "STRING", "enum": ["slim", "average", "muscular", "heavy"]},
    "face": {"type": "OBJECT", "properties": {m: {"type": "NUMBER"} for m in MORPHS}},
}}
def analyze(path):
    img = base64.b64encode(open(path, "rb").read()).decode()
    body = {"contents": [{"parts": [{"text": PROMPT}, {"inlineData": {"mimeType": "image/jpeg", "data": img}}]}],
            "generationConfig": {"responseMimeType": "application/json", "responseSchema": SCHEMA, "temperature": 0.2}}
    req = urllib.request.Request(f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent",
        data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "x-goog-api-key": KEY})
    t = time.time()
    r = json.load(urllib.request.urlopen(req, timeout=90))
    txt = r["candidates"][0]["content"]["parts"][0]["text"]
    return json.loads(txt), time.time() - t
if __name__ == "__main__":
    for f in sys.argv[1:]:
        d, dt = analyze(f)
        face = {k: round(v, 2) for k, v in d.get("face", {}).items() if v > 0.05}
        print(f, f"{dt:.1f}s", {k: d.get(k) for k in ["skin_tone", "skin_warmth", "hair_style", "hair_color", "beard", "brows", "eye_color", "age", "build", "error"]}, face)
